import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Objects;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.IincInsnNode;
import org.objectweb.asm.tree.IntInsnNode;
import org.objectweb.asm.tree.JumpInsnNode;
import org.objectweb.asm.tree.LabelNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.LookupSwitchInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.TableSwitchInsnNode;
import org.objectweb.asm.tree.VarInsnNode;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.util.Mth;

// Turns a model's posing code (setupAnim) into formulas, by walking Minecraft's compiled code.
public class EntityAnimationTranslator {
	// One piece of a formula, e.g. multiply with inputs [walkAnimationPos, 0.6662].
	// Each input is a number, a state value, or another Operation.
	static final class Operation {
		final String name;
		final Object[] inputs;
		Operation(String name, Object... inputs) {
			this.name = name;
			this.inputs = inputs;
		}
	}

	// The scratch paper for one function being read: its variables, and its formula pieces in progress.
	static final class FunctionBeingRead {
		final Object[] variableSlots;
		final ArrayList<Object> formulaPieces = new ArrayList<>();
		int instructionNumber = 0;
		// When this paper's path happens, e.g. "isBaby is true". TRUE means always (no if on a state value yet).
		Object pathCondition = Boolean.TRUE;
		// Every part number this paper has written so far, e.g. head "zRot" = 0.4.
		final LinkedHashMap<PartField, Object> partValues = new LinkedHashMap<>();
		// What this paper's function gave back when it reached return. null until then, or if it gives back nothing.
		Object returnedValue = null;
		FunctionBeingRead(MethodNode function) {
			this.variableSlots = new Object[function.maxLocals];
		}

		// Makes a copy of this scratch paper, so the other side of an if can be read on its own.
		FunctionBeingRead(FunctionBeingRead original) {
			this.variableSlots = original.variableSlots.clone();
			this.formulaPieces.addAll(original.formulaPieces);
			this.instructionNumber = original.instructionNumber;
			this.pathCondition = original.pathCondition;
			this.partValues.putAll(original.partValues);
		}
	}

	// One formula written into a part, e.g. rightHindLeg's xRot = cos(walkAnimationPos × 0.6662) × 1.4.
	record PartWrite(ModelPart part, String field, Object formula) {
	}

	// Which part, and which of its numbers, e.g. head and "zRot".
	record PartField(ModelPart part, String field) {
	}

	// Java's two-input math instructions, in their numbered order (IADD is 96, DREM is 115).
	static final String[] twoInputMathNames = {
		"iadd", "ladd", "fadd", "dadd",
		"isub", "lsub", "fsub", "dsub",
		"imul", "lmul", "fmul", "dmul",
		"idiv", "ldiv", "fdiv", "ddiv",
		"irem", "lrem", "frem", "drem",
	};

	// The numbers Java's shortcut instructions stand for, in their numbered order (ICONST_M1 is 2, DCONST_1 is 15).
	static final Object[] shortcutNumbers = {
		-1, 0, 1, 2, 3, 4, 5,
		0L, 1L,
		0.0f, 1.0f, 2.0f,
		0.0, 1.0,
	};

	// What each "compare against 0" if checks, in their numbered order (IFEQ is 153, IFLE is 158).
	static final String[] ifTestNames = {
		"isZero", "isNotZero", "isBelowZero", "isZeroOrAbove", "isAboveZero", "isZeroOrBelow",
	};

	// Joins two conditions: "both must be true". TRUE means "always", so it can be left out.
	static Object and(Object firstCondition, Object secondCondition) {
		if (firstCondition == Boolean.TRUE) {
			return secondCondition;
		}
		return new Operation("and", firstCondition, secondCondition);
	}

	// Joins two conditions: "at least one is true". TRUE means "always", so the result is always too.
	static Object or(Object firstCondition, Object secondCondition) {
		if (firstCondition == Boolean.TRUE || secondCondition == Boolean.TRUE) {
			return Boolean.TRUE;
		}
		return new Operation("or", firstCondition, secondCondition);
	}

	// Makes "whenTrue if condition, else whenFalse". If both papers have the same value, no choice is needed.
	static Object choose(Object condition, Object whenTrue, Object whenFalse) {
		if (Objects.equals(whenTrue, whenFalse)) {
			return whenTrue;
		}
		return new Operation("choose", condition, whenTrue, whenFalse);
	}

	// A part number on one paper: what the paper wrote, or if it wrote nothing, the number the part already has.
	static Object partValueOnPaper(FunctionBeingRead paper, PartField partField) throws Exception {
		if (paper.partValues.containsKey(partField)) {
			return paper.partValues.get(partField);
		}
		Field partNumber = ModelPart.class.getDeclaredField(partField.field());
		partNumber.setAccessible(true);
		return partNumber.get(partField.part());
	}

	// Makes one paper out of two papers at the same instruction number: every slot whose value differs becomes a choose.
	static FunctionBeingRead mergePapers(FunctionBeingRead firstPaper, FunctionBeingRead secondPaper) throws Exception {
		FunctionBeingRead mergedPaper = new FunctionBeingRead(firstPaper);
		for (int slotNumber = 0; slotNumber < mergedPaper.variableSlots.length; slotNumber++) {
			mergedPaper.variableSlots[slotNumber] = choose(firstPaper.pathCondition, firstPaper.variableSlots[slotNumber], secondPaper.variableSlots[slotNumber]);
		}
		for (int pieceNumber = 0; pieceNumber < mergedPaper.formulaPieces.size(); pieceNumber++) {
			Object mergedPiece = choose(firstPaper.pathCondition, firstPaper.formulaPieces.get(pieceNumber), secondPaper.formulaPieces.get(pieceNumber));
			mergedPaper.formulaPieces.set(pieceNumber, mergedPiece);
		}
		LinkedHashSet<PartField> partFieldsOnEitherPaper = new LinkedHashSet<>(firstPaper.partValues.keySet());
		partFieldsOnEitherPaper.addAll(secondPaper.partValues.keySet());
		// For each part number either paper wrote: choose between the two papers' values.
		for (PartField partField : partFieldsOnEitherPaper) {
			Object mergedValue = choose(firstPaper.pathCondition, partValueOnPaper(firstPaper, partField), partValueOnPaper(secondPaper, partField));
			mergedPaper.partValues.put(partField, mergedValue);
		}
		mergedPaper.returnedValue = choose(firstPaper.pathCondition, firstPaper.returnedValue, secondPaper.returnedValue);
		mergedPaper.pathCondition = or(firstPaper.pathCondition, secondPaper.pathCondition);
		return mergedPaper;
	}

	// Compares two whole numbers: −1, 0 or 1 if both are fixed, or a compare formula if one is a state value.
	static Object compareNow(Object leftSide, Object rightSide) {
		if (leftSide instanceof Operation || rightSide instanceof Operation) {
			return new Operation("compare", leftSide, rightSide);
		}
		return Integer.compare(((Number) leftSide).intValue(), ((Number) rightSide).intValue());
	}

	// Finds a field by its name in a class, or in its parent, or the parent's parent…
	static Field findField(String className, String fieldName) throws Exception {
		Class<?> searchedClass = Class.forName(className.replace('/', '.'));
		while (searchedClass != null) {
			for (Field field : searchedClass.getDeclaredFields()) {
				if (field.getName().equals(fieldName)) {
					field.setAccessible(true);
					return field;
				}
			}
			searchedClass = searchedClass.getSuperclass();
		}
		throw new NoSuchFieldException(fieldName);
	}

	// Opens one class's compiled code from client.jar, e.g. PigModel → its functions and instructions.
	static ClassNode readClassCode(Class<?> codeClass) throws Exception {
		ClassNode classCode = new ClassNode();
		new ClassReader(codeClass.getName()).accept(classCode, 0);
		return classCode;
	}

	// Finds setupAnim in one class's code, or null if that class doesn't have its own.
	static MethodNode findSetupAnimInClass(ClassNode classCode) {
		for (MethodNode function : classCode.methods) {
			boolean isCopyMadeByJava = (function.access & Opcodes.ACC_BRIDGE) != 0;
			if (function.name.equals("setupAnim") && !isCopyMadeByJava) {
				return function;
			}
		}
		return null;
	}

	// Finds the setupAnim a model really uses: its own, or the nearest parent's. Null if none.
	static MethodNode findSetupAnim(Class<?> modelClass) throws Exception {
		Class<?> searchedClass = modelClass;
		while (searchedClass != null) {
			MethodNode setupAnim = findSetupAnimInClass(readClassCode(searchedClass));
			if (setupAnim != null) {
				return setupAnim;
			}
			searchedClass = searchedClass.getSuperclass();
		}
		return null;
	}

	// Finds every instruction in a function that writes into a part, e.g. "rightHindLeg.xRot = …".
	static ArrayList<FieldInsnNode> findPartWrites(MethodNode function, HashSet<String> visitedFunctions) throws Exception {
		ArrayList<FieldInsnNode> partWrites = new ArrayList<>();
		for (AbstractInsnNode instruction : function.instructions) {
			if (instruction instanceof FieldInsnNode fieldInstruction) {
				boolean isWrite = fieldInstruction.getOpcode() == Opcodes.PUTFIELD;
				boolean isIntoPart = fieldInstruction.owner.equals(Type.getInternalName(ModelPart.class));
				if (isWrite && isIntoPart) {
					partWrites.add(fieldInstruction);
				}
			}
			if (instruction instanceof MethodInsnNode call) {
				String functionName = call.owner + "." + call.name + call.desc;
				if (visitedFunctions.add(functionName)) {
					MethodNode calledFunction = findCalledFunction(call);
					if (calledFunction != null) {
						partWrites.addAll(findPartWrites(calledFunction, visitedFunctions));
					}
				}
			}
		}
		return partWrites;
	}

	// Finds the code a call instruction runs, e.g. "AnimationUtils.animateZombieArms" → that function. Null if not found.
	static MethodNode findCalledFunction(MethodInsnNode call) throws Exception {
		if (!call.owner.startsWith("net/minecraft/")) {
			return null;
		}
		Class<?> searchedClass = Class.forName(call.owner.replace('/', '.'));
		while (searchedClass != null) {
			for (MethodNode function : readClassCode(searchedClass).methods) {
				if (function.name.equals(call.name) && function.desc.equals(call.desc)) {
					return function;
				}
			}
			searchedClass = searchedClass.getSuperclass();
		}
		return null;
	}

	// Finds the function a call means, in the form Java can run, e.g. "Model.root" → Java's handle on root(). Null if not found.
	static Method findRealFunction(MethodInsnNode call) throws Exception {
		Class<?> searchedClass = Class.forName(call.owner.replace('/', '.'));
		while (searchedClass != null) {
			for (Method function : searchedClass.getDeclaredMethods()) {
				if (function.getName().equals(call.name) && Type.getMethodDescriptor(function).equals(call.desc)) {
					return function;
				}
			}
			searchedClass = searchedClass.getSuperclass();
		}
		return null;
	}

	// Lets Java run a call for real (only when no state values go in), e.g. model.root() → the real root part.
	static Object runForReal(MethodInsnNode call, Object[] callInputs) throws Exception {
		Method function = findRealFunction(call);
		if (function == null) {
			throw new Exception("could not find " + call.owner + "." + call.name);
		}
		function.setAccessible(true);
		Type[] inputTypes = Type.getArgumentTypes(call.desc);
		int firstInputSpot = callInputs.length - inputTypes.length;
		for (int inputIndex = 0; inputIndex < inputTypes.length; inputIndex++) {
			boolean wantsTrueOrFalse = inputTypes[inputIndex] == Type.BOOLEAN_TYPE;
			int inputSpot = firstInputSpot + inputIndex;
			if (wantsTrueOrFalse && callInputs[inputSpot] instanceof Integer zeroOrOne) {
				callInputs[inputSpot] = zeroOrOne != 0;
			}
		}
		if (call.getOpcode() == Opcodes.INVOKESTATIC) {
			return function.invoke(null, callInputs);
		}
		Object objectCalledOn = callInputs[0];
		Object[] inputsAfterObject = Arrays.copyOfRange(callInputs, 1, callInputs.length);
		return function.invoke(objectCalledOn, inputsAfterObject);
	}

	// Gives back the waiting paper with the least instruction number, so the papers ahead wait for it.
	static FunctionBeingRead paperWithLeastInstructionNumber(ArrayList<FunctionBeingRead> waitingPapers) {
		FunctionBeingRead paperWithLeast = waitingPapers.getFirst();
		for (FunctionBeingRead waitingPaper : waitingPapers) {
			if (waitingPaper.instructionNumber < paperWithLeast.instructionNumber) {
				paperWithLeast = waitingPaper;
			}
		}
		return paperWithLeast;
	}

	// Gives back another waiting paper at the same instruction number as scratchPaper, or null if there is none.
	static FunctionBeingRead paperAtSameInstructionNumber(ArrayList<FunctionBeingRead> waitingPapers, FunctionBeingRead scratchPaper) {
		for (FunctionBeingRead waitingPaper : waitingPapers) {
			boolean isAnotherPaper = waitingPaper != scratchPaper;
			if (isAnotherPaper && waitingPaper.instructionNumber == scratchPaper.instructionNumber) {
				return waitingPaper;
			}
		}
		return null;
	}

	// At an if on a state value: a copy of the paper jumps to jumpTarget, this paper stays. Each gets its side of the condition.
	static FunctionBeingRead splitPaper(FunctionBeingRead scratchPaper, Object jumpCondition, int jumpTarget) {
		FunctionBeingRead jumpingPaper = new FunctionBeingRead(scratchPaper);
		jumpingPaper.instructionNumber = jumpTarget;
		jumpingPaper.pathCondition = and(scratchPaper.pathCondition, jumpCondition);
		scratchPaper.pathCondition = and(scratchPaper.pathCondition, new Operation("not", jumpCondition));
		return jumpingPaper;
	}

	// Reads a function top to bottom, turning its math into formulas. Its part moves get written into partValues.
	// Returns what the function returns (a formula, a real thing, or null if it returns nothing).
	static Object translateFunction(MethodNode function, Object[] functionInputs, Object entityRenderState, LinkedHashMap<PartField, Object> partValues) throws Exception {
		FunctionBeingRead scratchPaper = new FunctionBeingRead(function);
		scratchPaper.partValues.putAll(partValues);
		for (int inputNumber = 0; inputNumber < functionInputs.length; inputNumber++) {
			scratchPaper.variableSlots[inputNumber] = functionInputs[inputNumber];
		}
		// Papers still being read. An if on a state value adds a second paper here.
		ArrayList<FunctionBeingRead> waitingPapers = new ArrayList<>();
		waitingPapers.add(scratchPaper);
		// Papers that reached a return. They get merged into one at the very end.
		ArrayList<FunctionBeingRead> finishedPapers = new ArrayList<>();
		// Each turn reads one instruction on one paper.
		int instructionsRead = 0;
		while (!waitingPapers.isEmpty() && instructionsRead < 2000000) {
			instructionsRead = instructionsRead + 1;
			// Read the paper furthest behind, so a paper ahead waits for it at the end of the if.
			scratchPaper = paperWithLeastInstructionNumber(waitingPapers);
			// Two papers on the same instruction: both sides of an if are done, so make them one paper again.
			FunctionBeingRead paperAtSameInstruction = paperAtSameInstructionNumber(waitingPapers, scratchPaper);
			if (paperAtSameInstruction != null) {
				waitingPapers.remove(scratchPaper);
				waitingPapers.remove(paperAtSameInstruction);
				waitingPapers.add(mergePapers(scratchPaper, paperAtSameInstruction));
				continue;
			}
			boolean isPastTheEnd = scratchPaper.instructionNumber >= function.instructions.size();
			if (isPastTheEnd) {
				waitingPapers.remove(scratchPaper);
				continue;
			}
			AbstractInsnNode instruction = function.instructions.get(scratchPaper.instructionNumber);
			scratchPaper.instructionNumber = scratchPaper.instructionNumber + 1;
			if (instruction.getOpcode() == Opcodes.GOTO) {
				JumpInsnNode jumpInstruction = (JumpInsnNode) instruction;
				scratchPaper.instructionNumber = function.instructions.indexOf(jumpInstruction.label);
				continue;
			}
			if (instruction.getOpcode() == Opcodes.DUP) {
				Object lastPiece = scratchPaper.formulaPieces.getLast();
				scratchPaper.formulaPieces.add(lastPiece);
				continue;
			}
			if (instruction.getOpcode() == Opcodes.POP) {
				scratchPaper.formulaPieces.removeLast();
				continue;
			}
			boolean isSmallNumber = instruction.getOpcode() == Opcodes.BIPUSH || instruction.getOpcode() == Opcodes.SIPUSH;
			if (isSmallNumber) {
				IntInsnNode smallNumberInstruction = (IntInsnNode) instruction;
				scratchPaper.formulaPieces.add(smallNumberInstruction.operand);
				continue;
			}
			if (instruction.getOpcode() == Opcodes.CHECKCAST) {
				continue;
			}
			if (instruction.getOpcode() == Opcodes.ARRAYLENGTH) {
				Object list = scratchPaper.formulaPieces.removeLast();
				scratchPaper.formulaPieces.add(java.lang.reflect.Array.getLength(list));
				continue;
			}
			boolean isListRead = instruction.getOpcode() >= Opcodes.IALOAD && instruction.getOpcode() <= Opcodes.SALOAD;
			if (isListRead) {
				Object position = scratchPaper.formulaPieces.removeLast();
				Object list = scratchPaper.formulaPieces.removeLast();
				if (list instanceof Operation || position instanceof Operation) {
					throw new Exception("list read with a state value: not yet");
				}
				scratchPaper.formulaPieces.add(java.lang.reflect.Array.get(list, ((Number) position).intValue()));
				continue;
			}
			boolean isSwitch = instruction instanceof TableSwitchInsnNode || instruction instanceof LookupSwitchInsnNode;
			if (isSwitch) {
				ArrayList<Integer> caseNumbers = new ArrayList<>();
				ArrayList<LabelNode> caseJumpPlaces = new ArrayList<>();
				LabelNode defaultJumpPlace;
				if (instruction instanceof TableSwitchInsnNode rangeSwitch) {
					for (int caseNumber = rangeSwitch.min; caseNumber <= rangeSwitch.max; caseNumber++) {
						caseNumbers.add(caseNumber);
					}
					caseJumpPlaces.addAll(rangeSwitch.labels);
					defaultJumpPlace = rangeSwitch.dflt;
				} else {
					LookupSwitchInsnNode listedSwitch = (LookupSwitchInsnNode) instruction;
					caseNumbers.addAll(listedSwitch.keys);
					caseJumpPlaces.addAll(listedSwitch.labels);
					defaultJumpPlace = listedSwitch.dflt;
				}
				Object switchedValue = scratchPaper.formulaPieces.removeLast();
				if (switchedValue instanceof Operation) {
					for (int caseIndex = 0; caseIndex < caseNumbers.size(); caseIndex++) {
						Operation isThisCase = new Operation("isEqual", switchedValue, caseNumbers.get(caseIndex));
						int caseJumpTarget = function.instructions.indexOf(caseJumpPlaces.get(caseIndex));
						waitingPapers.add(splitPaper(scratchPaper, isThisCase, caseJumpTarget));
					}
					scratchPaper.instructionNumber = function.instructions.indexOf(defaultJumpPlace);
					continue;
				}
				int matchingCaseIndex = caseNumbers.indexOf(((Number) switchedValue).intValue());
				LabelNode jumpPlace = defaultJumpPlace;
				if (matchingCaseIndex >= 0) {
					jumpPlace = caseJumpPlaces.get(matchingCaseIndex);
				}
				scratchPaper.instructionNumber = function.instructions.indexOf(jumpPlace);
				continue;
			}
			if (instruction instanceof IincInsnNode addToSlotInstruction) {
				int slotNumber = addToSlotInstruction.var;
				Object oldValue = scratchPaper.variableSlots[slotNumber];
				scratchPaper.variableSlots[slotNumber] = ((Number) oldValue).intValue() + addToSlotInstruction.incr;
				continue;
			}
			if (instruction instanceof LdcInsnNode fixedNumberInstruction) {
				scratchPaper.formulaPieces.add(fixedNumberInstruction.cst);
				continue;
			}
			if (instruction instanceof VarInsnNode slotInstruction) {
				boolean isStoreIntoSlot = slotInstruction.getOpcode() >= Opcodes.ISTORE;
				if (isStoreIntoSlot) {
					scratchPaper.variableSlots[slotInstruction.var] = scratchPaper.formulaPieces.removeLast();
				} else {
					scratchPaper.formulaPieces.add(scratchPaper.variableSlots[slotInstruction.var]);
				}
				continue;
			}
			if (instruction.getOpcode() == Opcodes.GETSTATIC) {
				FieldInsnNode staticFieldReadInstruction = (FieldInsnNode) instruction;
				Field staticField = findField(staticFieldReadInstruction.owner, staticFieldReadInstruction.name);
				scratchPaper.formulaPieces.add(staticField.get(null));
				continue;
			}
			if (instruction.getOpcode() == Opcodes.GETFIELD) {
				FieldInsnNode fieldReadInstruction = (FieldInsnNode) instruction;
				Object objectWhoseFieldIsRead = scratchPaper.formulaPieces.removeLast();
				if (objectWhoseFieldIsRead instanceof ModelPart partBeingRead) {
					PartField partFieldBeingRead = new PartField(partBeingRead, fieldReadInstruction.name);
					if (scratchPaper.partValues.containsKey(partFieldBeingRead)) {
						scratchPaper.formulaPieces.add(scratchPaper.partValues.get(partFieldBeingRead));
						continue;
					}
				}
				boolean isFieldOfStateValue = objectWhoseFieldIsRead instanceof Operation outerOperation && outerOperation.name.equals("stateValue");
				if (isFieldOfStateValue) {
					String nestedStateValueName = ((Operation) objectWhoseFieldIsRead).inputs[0] + "." + fieldReadInstruction.name;
					scratchPaper.formulaPieces.add(new Operation("stateValue", nestedStateValueName));
					continue;
				}
				if (objectWhoseFieldIsRead == entityRenderState) {
					String stateValueName = fieldReadInstruction.name;
					scratchPaper.formulaPieces.add(new Operation("stateValue", stateValueName));
				} else {
					Field field = findField(fieldReadInstruction.owner, fieldReadInstruction.name);
					scratchPaper.formulaPieces.add(field.get(objectWhoseFieldIsRead));
				}
				continue;
			}
			boolean isTwoInputMath = instruction.getOpcode() >= Opcodes.IADD && instruction.getOpcode() <= Opcodes.DREM;
			if (isTwoInputMath) {
				Object rightSideOfMath = scratchPaper.formulaPieces.removeLast();
				Object leftSideOfMath = scratchPaper.formulaPieces.removeLast();
				String mathName = twoInputMathNames[instruction.getOpcode() - Opcodes.IADD];
				scratchPaper.formulaPieces.add(new Operation(mathName, leftSideOfMath, rightSideOfMath));
				continue;
			}
			boolean isNegate = instruction.getOpcode() >= Opcodes.INEG && instruction.getOpcode() <= Opcodes.DNEG;
			if (isNegate) {
				Object numberToNegate = scratchPaper.formulaPieces.removeLast();
				scratchPaper.formulaPieces.add(new Operation("neg", numberToNegate));
				continue;
			}
			int ifKind = instruction.getOpcode();
			boolean isIfCompareTwoInts = ifKind >= Opcodes.IF_ICMPEQ && ifKind <= Opcodes.IF_ICMPLE;
			if (isIfCompareTwoInts) {
				Object rightSideOfCompare = scratchPaper.formulaPieces.removeLast();
				Object leftSideOfCompare = scratchPaper.formulaPieces.removeLast();
				scratchPaper.formulaPieces.add(compareNow(leftSideOfCompare, rightSideOfCompare));
				ifKind = ifKind - (Opcodes.IF_ICMPEQ - Opcodes.IFEQ);
			}
			boolean isIfAgainstZero = ifKind >= Opcodes.IFEQ && ifKind <= Opcodes.IFLE;
			if (isIfAgainstZero) {
				JumpInsnNode jumpInstruction = (JumpInsnNode) instruction;
				Object valueBeingChecked = scratchPaper.formulaPieces.removeLast();
				// The if depends on a state value, so read both sides: a copy of the paper jumps, this paper doesn't.
				if (valueBeingChecked instanceof Operation) {
					Object jumpCondition = new Operation(ifTestNames[ifKind - Opcodes.IFEQ], valueBeingChecked);
					int jumpTarget = function.instructions.indexOf(jumpInstruction.label);
					waitingPapers.add(splitPaper(scratchPaper, jumpCondition, jumpTarget));
					continue;
				}
				// The if depends on a fixed number, so we can decide right now whether to jump.
				int checkedNumber = 0;
				if (valueBeingChecked instanceof Boolean isTrue && isTrue) {
					checkedNumber = 1;
				}
				if (valueBeingChecked instanceof Number number) {
					checkedNumber = number.intValue();
				}
				boolean shouldJump = switch (ifKind) {
					case Opcodes.IFEQ -> checkedNumber == 0;
					case Opcodes.IFNE -> checkedNumber != 0;
					case Opcodes.IFLT -> checkedNumber < 0;
					case Opcodes.IFGE -> checkedNumber >= 0;
					case Opcodes.IFGT -> checkedNumber > 0;
					default -> checkedNumber <= 0;
				};
				if (shouldJump) {
					scratchPaper.instructionNumber = function.instructions.indexOf(jumpInstruction.label);
				}
				continue;
			}
			boolean isIfSameObject = instruction.getOpcode() == Opcodes.IF_ACMPEQ || instruction.getOpcode() == Opcodes.IF_ACMPNE;
			if (isIfSameObject) {
				JumpInsnNode jumpInstruction = (JumpInsnNode) instruction;
				int jumpTarget = function.instructions.indexOf(jumpInstruction.label);
				Object rightSideOfSameCheck = scratchPaper.formulaPieces.removeLast();
				Object leftSideOfSameCheck = scratchPaper.formulaPieces.removeLast();
				boolean jumpsWhenSame = instruction.getOpcode() == Opcodes.IF_ACMPEQ;
				boolean checksAStateValue = leftSideOfSameCheck instanceof Operation || rightSideOfSameCheck instanceof Operation;
				if (checksAStateValue) {
					Object jumpCondition = new Operation("isSame", leftSideOfSameCheck, rightSideOfSameCheck);
					if (!jumpsWhenSame) {
						jumpCondition = new Operation("not", jumpCondition);
					}
					waitingPapers.add(splitPaper(scratchPaper, jumpCondition, jumpTarget));
					continue;
				}
				boolean isSame = leftSideOfSameCheck == rightSideOfSameCheck;
				if (isSame == jumpsWhenSame) {
					scratchPaper.instructionNumber = jumpTarget;
				}
				continue;
			}
			boolean isCompare = instruction.getOpcode() >= Opcodes.LCMP && instruction.getOpcode() <= Opcodes.DCMPG;
			if (isCompare) {
				Object rightSideOfCompare = scratchPaper.formulaPieces.removeLast();
				Object leftSideOfCompare = scratchPaper.formulaPieces.removeLast();
				boolean comparesAStateValue = leftSideOfCompare instanceof Operation || rightSideOfCompare instanceof Operation;
				if (comparesAStateValue) {
					scratchPaper.formulaPieces.add(new Operation("compare", leftSideOfCompare, rightSideOfCompare));
				} else {
					scratchPaper.formulaPieces.add(Double.compare(((Number) leftSideOfCompare).doubleValue(), ((Number) rightSideOfCompare).doubleValue()));
				}
				continue;
			}
			boolean isShortcutNumber = instruction.getOpcode() >= Opcodes.ICONST_M1 && instruction.getOpcode() <= Opcodes.DCONST_1;
			if (isShortcutNumber) {
				scratchPaper.formulaPieces.add(shortcutNumbers[instruction.getOpcode() - Opcodes.ICONST_M1]);
				continue;
			}
			boolean isConversion = instruction.getOpcode() >= Opcodes.I2L && instruction.getOpcode() <= Opcodes.I2S;
			if (isConversion) {
				int conversionKind = instruction.getOpcode();
				boolean cutsOffDecimals = conversionKind == Opcodes.F2I || conversionKind == Opcodes.F2L || conversionKind == Opcodes.D2I || conversionKind == Opcodes.D2L;
				if (cutsOffDecimals) {
					Object numberWithDecimals = scratchPaper.formulaPieces.removeLast();
					scratchPaper.formulaPieces.add(new Operation("cutDecimals", numberWithDecimals));
				}
				continue;
			}
			if (instruction instanceof MethodInsnNode callInstruction) {
				boolean isCalledOnAnObject = callInstruction.getOpcode() != Opcodes.INVOKESTATIC;
				int inputCount = Type.getArgumentTypes(callInstruction.desc).length;
				if (isCalledOnAnObject) {
					inputCount = inputCount + 1;
				}
				Object[] calledFunctionInputs = new Object[inputCount];
				for (int inputNumber = inputCount - 1; inputNumber >= 0; inputNumber--) {
					calledFunctionInputs[inputNumber] = scratchPaper.formulaPieces.removeLast();
				}
				boolean hasStateValueInput = false;
				for (Object calledFunctionInput : calledFunctionInputs) {
					if (calledFunctionInput instanceof Operation || calledFunctionInput == entityRenderState) {
						hasStateValueInput = true;
					}
				}
				Object returnedValue;
				boolean isStaticCall = callInstruction.getOpcode() == Opcodes.INVOKESTATIC;
				boolean onlyNumbersInAndOut = !callInstruction.desc.contains("L") && !callInstruction.desc.contains("[");
				if (hasStateValueInput && isStaticCall && onlyNumbersInAndOut) {
					String mathName = callInstruction.owner.substring(callInstruction.owner.lastIndexOf('/') + 1) + "." + callInstruction.name;
					returnedValue = new Operation(mathName, calledFunctionInputs);
				} else if (hasStateValueInput) {
					MethodNode calledFunction = findCalledFunction(callInstruction);
					if (calledFunction == null) {
						throw new Exception("don't know " + callInstruction.owner + "." + callInstruction.name + " yet");
					}
					returnedValue = translateFunction(calledFunction, calledFunctionInputs, entityRenderState, scratchPaper.partValues);
				} else {
					returnedValue = runForReal(callInstruction, calledFunctionInputs);
				}
				boolean callGivesBackSomething = Type.getReturnType(callInstruction.desc) != Type.VOID_TYPE;
				if (callGivesBackSomething) {
					scratchPaper.formulaPieces.add(returnedValue);
				}
				continue;
			}
			if (instruction.getOpcode() == Opcodes.PUTFIELD) {
				FieldInsnNode fieldWriteInstruction = (FieldInsnNode) instruction;
				Object formulaBeingWritten = scratchPaper.formulaPieces.removeLast();
				Object objectWhoseFieldIsWritten = scratchPaper.formulaPieces.removeLast();
				if (objectWhoseFieldIsWritten instanceof ModelPart partBeingWritten) {
					PartField partFieldBeingWritten = new PartField(partBeingWritten, fieldWriteInstruction.name);
					scratchPaper.partValues.put(partFieldBeingWritten, formulaBeingWritten);
				}
				continue;
			}
			int instructionKind = instruction.getOpcode();
			boolean isReturnWithValue = instructionKind >= Opcodes.IRETURN && instructionKind <= Opcodes.ARETURN;
			if (isReturnWithValue) {
				scratchPaper.returnedValue = scratchPaper.formulaPieces.removeLast();
			}
			// Any return: this paper is done reading, so it goes on the finished pile.
			if (isReturnWithValue || instructionKind == Opcodes.RETURN) {
				scratchPaper.formulaPieces.clear();
				waitingPapers.remove(scratchPaper);
				finishedPapers.add(scratchPaper);
				continue;
			}
			boolean isRealInstruction = instructionKind >= 0;
			if (isRealInstruction) {
				throw new Exception("don't know instruction number " + instructionKind + " yet");
			}
		}
		if (instructionsRead >= 2000000) throw new Exception("endless loop");
		// Every paper is done: merge the finished ones into one, then hand back its part moves and what it gave back.
		FunctionBeingRead lastPaper = finishedPapers.getFirst();
		for (int paperNumber = 1; paperNumber < finishedPapers.size(); paperNumber++) {
			lastPaper = mergePapers(lastPaper, finishedPapers.get(paperNumber));
		}
		partValues.putAll(lastPaper.partValues);
		return lastPaper.returnedValue;
	}
}
