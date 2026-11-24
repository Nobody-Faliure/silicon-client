// Runs once per version, on first launch (started by Swift, see MinecraftServer.swift).
// Asks Minecraft's own code about every entity: its size now; its model, texture and
// animations in later stages. Writes them to one JSON file.
//
// Usage: java -cp <client jar>:<libraries> EntityExtractor.java <output.json>

import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.EntityTypes;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.lang.reflect.*;
import sun.reflect.ReflectionFactory;
import net.minecraft.client.model.geom.EntityModelSet;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import java.util.Map;
import java.util.LinkedHashMap;
import net.minecraft.client.renderer.entity.EntityRenderers;
import net.minecraft.client.renderer.entity.EntityRenderer;
import java.util.List;
import java.util.ArrayList;
import java.util.Set;
import java.util.Collections;
import java.util.IdentityHashMap;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.entity.LivingEntityRenderer;
import net.minecraft.client.renderer.entity.AbstractBoatRenderer;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.client.renderer.entity.state.LivingEntityRenderState;
import net.minecraft.network.syncher.EntityDataSerializer;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.client.renderer.entity.layers.RenderLayer;
import org.objectweb.asm.tree.MethodNode;

public class EntityExtractor {
	public static void main(String[] arguments) throws Exception {
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		Constructor<?> blankMaker = ReflectionFactory.getReflectionFactory()
			.newConstructorForSerialization(EntityRendererProvider.Context.class, Object.class.getDeclaredConstructor());
		EntityRendererProvider.Context context = (EntityRendererProvider.Context) blankMaker.newInstance();
		Field modelSetField = EntityRendererProvider.Context.class.getDeclaredField("modelSet");
		modelSetField.setAccessible(true);
		modelSetField.set(context, EntityModelSet.vanilla());
		Field providersField = EntityRenderers.class.getDeclaredField("PROVIDERS");
		providersField.setAccessible(true);
		Map<EntityType<?>, EntityRendererProvider<?>> providers = (Map<EntityType<?>, EntityRendererProvider<?>>) providersField.get(null);
		StringBuilder json = new StringBuilder("{\n  \"types\": [\n");
		for (int id = 0; id < BuiltInRegistries.ENTITY_TYPE.size(); id++) {
			EntityType<?> type = BuiltInRegistries.ENTITY_TYPE.byId(id);
			String name = BuiltInRegistries.ENTITY_TYPE.getKey(type).getPath();
			json.append("    {\"name\": \"" + name + "\", \"width\": " + number(type.getWidth())
				+ ", \"height\": " + number(type.getHeight()) + "},\n");
		}
		json.setLength(json.length() - 2);
		json.append("\n  ],\n  \"models\": [\n");
		for (EntityType<?> type : providers.keySet()) {
			String name = BuiltInRegistries.ENTITY_TYPE.getKey(type).getPath();
			EntityRenderer<?, ?> renderer;
			try {
				renderer = providers.get(type).create(context);
			} catch (Throwable error) {
				continue;
			}
			String texture = "";
			try {
				LivingEntityRenderer living = (LivingEntityRenderer) renderer;
				texture = living.getTextureLocation((LivingEntityRenderState) living.createRenderState()).getPath();
			} catch (Throwable error) {
			}
			if (renderer instanceof AbstractBoatRenderer boat) {
				Field textureField = AbstractBoatRenderer.class.getDeclaredField("texture");
				textureField.setAccessible(true);
				texture = ((Identifier) textureField.get(boat)).getPath();
			}
			for (Class<?> kind = renderer.getClass(); kind != null && texture.isEmpty(); kind = kind.getSuperclass()) {
				for (Field field : kind.getDeclaredFields()) {
					if (field.getType() == Identifier.class && Modifier.isStatic(field.getModifiers())) {
						field.setAccessible(true);
						texture = ((Identifier) field.get(null)).getPath();
					}
				}
			}
			String babyTexture = texture;
			try {
				LivingEntityRenderState babyState = (LivingEntityRenderState) renderer.createRenderState();
				babyState.isBaby = true;
				babyTexture = ((LivingEntityRenderer) renderer).getTextureLocation(babyState).getPath();
			} catch (Throwable error) {
			}
			LinkedHashMap<String, Model<?>> models = new LinkedHashMap<>();
			layerTextures.clear();
			findModels(renderer, "", models);
			for (String choicePath : models.keySet()) {
				Model<?> model = models.get(choicePath);
				String modelTexture = layerTextures.getOrDefault(choicePath, "");
				if (modelTexture.isEmpty()) {
					modelTexture = choicePath.contains("babyModel") ? babyTexture : texture;
				}
				json.append("    {\"entity\": \"" + name + "\", \"choice\": \"" + choicePath + "\", \"kind\": \""+ model.getClass().getSimpleName() + "\", \"texture\": \"" + modelTexture + "\", \"parts\": [\n");
				List<ModelPart> parts = new ArrayList<>();
				StringBuilder headYaw = new StringBuilder();
				StringBuilder headPitch = new StringBuilder();
				writePart(json, "root", model.root(), -1, parts);
				LinkedHashMap<EntityAnimationTranslator.PartField, Object> partValues = new LinkedHashMap<>();
				try {
					Object state = renderer.createRenderState();
					MethodNode setupAnim = EntityAnimationTranslator.findSetupAnim(model.getClass());
					EntityAnimationTranslator.translateFunction(setupAnim, new Object[] {model, state}, state, partValues);
				} catch (Throwable error) {
				}
				// Turns the hash map into JSON, e.g. [2, "xRot", ["fmul", …]] means "part 2's xRot = this formula".
				StringBuilder movesJson = new StringBuilder();
				IdentityHashMap<Object, Integer> pieceNumbers = new IdentityHashMap<>();
				ArrayList<String> pieces = new ArrayList<>();
				for (EntityAnimationTranslator.PartField partAndField : partValues.keySet()) {
					int partNumber = parts.indexOf(partAndField.part());
					String formulaText = EntityAnimationTranslator.formulaJson(partValues.get(partAndField), pieceNumbers, pieces);
					movesJson.append("[" + partNumber + ", \"" + partAndField.field() + "\", " + formulaText + "], ");
				}
				if (renderer.createRenderState() instanceof LivingEntityRenderState state) {
					for (int angle = -90; angle <= 90; angle += 10) {
						state.yRot = angle;
						try {
							((Model) model).setupAnim(state);
						} catch (Throwable error) {
						}
						writePose(headYaw, parts);
					}
					state.yRot = 0;
					for (int angle = -90; angle <= 90; angle += 10) {
						state.xRot = angle;
						try {
							((Model) model).setupAnim(state);
						} catch (Throwable error) {
						}
						writePose(headPitch, parts);
					}
				}
				json.setLength(json.length() - 2);
				if (movesJson.length() > 0) {
					movesJson.setLength(movesJson.length() - 2);
				}
				String piecesJson = String.join(", ", pieces);
				json.append("\n    ], \"headYaw\": [" + headYaw + "], \"headPitch\": [" + headPitch + "], \"pieces\": [" + piecesJson + "], \"animation\": [" + movesJson + "]},\n");
			}
		}
		json.setLength(json.length() - 2);
		json.append("\n  ],\n  \"dataTypes\": {\n");
		for (Field field : EntityDataSerializers.class.getFields()) {
			if (field.getType() == EntityDataSerializer.class) {
				int typeNumber = EntityDataSerializers.getSerializedId((EntityDataSerializer<?>) field.get(null));
				json.append("    \"" + field.getName() + "\": " + typeNumber + ",\n");
			}
		}
		json.setLength(json.length() - 2);
		json.append("\n  },\n  \"variantDefaults\": {\n");
		for (Field field : EntityDataSerializers.class.getFields()) {
			try {
				json.append("    \"" + field.getName() + "\": \"" + defaultVariant(field) + "\",\n");
			} catch (Exception noDefault) {
			}
		}
		json.setLength(json.length() - 2);
		json.append("\n  },\n  \"slots\": {\n");
		for (Field typeField : EntityTypes.class.getFields()) {
			if (typeField.getType() == EntityType.class) {
				String declaredType = typeField.getGenericType().getTypeName();	// "…EntityType<…sheep.Sheep>"
				String mobClassName = declaredType.substring(declaredType.indexOf('<') + 1, declaredType.lastIndexOf('>'));
				String name = BuiltInRegistries.ENTITY_TYPE.getKey((EntityType<?>) typeField.get(null)).getPath();
				String slots = slotNames(Class.forName(mobClassName));
				json.append("    \"" + name + "\": {" + slots.substring(0, slots.length() - 2) + "},\n");
			}
		}
		json.setLength(json.length() - 2);
		json.append("\n  }\n}\n");
		Files.writeString(Path.of(arguments[0]), json.toString());
	}

	static String number(double value) {
		if (Double.isNaN(value) || Double.isInfinite(value)) {
			value = 0;
		}
		return String.format(Locale.ROOT, "%.4f", value);
	}

	// Each layer model's own texture, e.g. "layers.1.adultModel" → "textures/entity/sheep/sheep_wool.png".
	static LinkedHashMap<String, String> layerTextures = new LinkedHashMap<>();
	static Set<Object> alreadySearched = Collections.newSetFromMap(new IdentityHashMap<>());

	static void findModels(Object thing, String choicePath, LinkedHashMap<String, Model<?>> models) throws Exception {
		if (!alreadySearched.add(thing)) {
			return;
		}
		if (thing instanceof Model<?> model) {
			if (!models.containsValue(model)) {
				models.putIfAbsent(choicePath, model);
			}
		}
		if (thing instanceof Map<?, ?> map) {
			for (Map.Entry<?, ?> entry : map.entrySet()) {
				String entryKey = entry.getKey().toString().toLowerCase(Locale.ROOT);
				findModels(entry.getValue(), joinKey(choicePath, entryKey), models);
			}
		}
		if (thing instanceof List<?> list) {
			for (int index = 0; index < list.size(); index++) {
				findModels(list.get(index), joinKey(choicePath, String.valueOf(index)), models);
			}
		}
		if (thing instanceof EntityRenderer<?, ?> || thing instanceof Record || thing instanceof RenderLayer<?, ?>) {
			for (Class<?> kind = thing.getClass(); kind != null; kind = kind.getSuperclass()) {
				for (Field field : kind.getDeclaredFields()) {
					if (!Modifier.isStatic(field.getModifiers()) && !field.getType().isPrimitive()) {
						field.setAccessible(true);
						findModels(field.get(thing), joinKey(choicePath, field.getName()), models);
						if (thing instanceof RenderLayer<?, ?> && field.get(thing) instanceof Model<?>) {
							layerTextures.put(joinKey(choicePath, field.getName()), layerTexture(thing, field.getName()));
						}
					}
				}
			}
		}
	}

	// Adds one more choice to the path, e.g. "cold" + "babyModel" gives "cold.babyModel".
	static String joinKey(String choicePath, String nextChoice) {
		if (choicePath.isEmpty()) {
			return nextChoice;
		}
		return choicePath + "." + nextChoice;
	}

	// One model's texture inside a layer, e.g. SheepWoolLayer + "adultModel" gives "textures/entity/sheep/sheep_wool.png". "" if it has none.
	static String layerTexture(Object layer, String modelFieldName) throws Exception {
		for (Field field : layer.getClass().getDeclaredFields()) {
			boolean isBabyTexture = field.getName().contains("BABY");
			boolean isBabyModel = modelFieldName.contains("baby");
			if (field.getType() == Identifier.class && Modifier.isStatic(field.getModifiers()) && isBabyTexture == isBabyModel) {
				field.setAccessible(true);
				return ((Identifier) field.get(null)).getPath();
			}
		}
		return "";
	}

	// Every slot of one mob class and the classes above it, e.g. Sheep gives "16": "DATA_BABY_ID", "18": "DATA_WOOL_ID", …
	static String slotNames(Class<?> mobClass) throws Exception {
		StringBuilder slots = new StringBuilder();
		for (Class<?> kind = mobClass; kind != null; kind = kind.getSuperclass()) {
			for (Field field : kind.getDeclaredFields()) {
				if (field.getType() == EntityDataAccessor.class && Modifier.isStatic(field.getModifiers())) {
					field.setAccessible(true);
					int slot = ((EntityDataAccessor<?>) field.get(null)).id();
					slots.append("\"" + slot + "\": \"" + field.getName() + "\", ");
				}
			}
		}
		return slots.toString();
	}

	// The default variant of one type, e.g. PIG_VARIANT gives "minecraft:temperate".
	static String defaultVariant(Field typeField) throws Exception {
		String declaredType = typeField.getGenericType().getTypeName();	// "…EntityDataSerializer<…Holder<…pig.PigVariant>>"
		String variantClassName = declaredType.substring(declaredType.lastIndexOf('<') + 1, declaredType.indexOf('>'));
		Class<?> variantsClass = Class.forName(variantClassName + "s");
		ResourceKey<?> defaultKey;
		try {
			defaultKey = (ResourceKey<?>) variantsClass.getField("DEFAULT").get(null);
		} catch (NoSuchFieldException notInVariantsClass) {
			Class<?> mobClass = Class.forName(variantClassName.replace("Variant", ""));
			Field mobDefaultField = mobClass.getDeclaredField("DEFAULT_VARIANT");
			mobDefaultField.setAccessible(true);
			defaultKey = (ResourceKey<?>) mobDefaultField.get(null);
		}
		return defaultKey.identifier().toString();
	}

	static void writePart(StringBuilder json, String name, ModelPart part, int parent, List<ModelPart> written) throws Exception {
		int index = written.size();
		written.add(part);
		json.append("      {\"name\": \"" + name + "\", \"parent\": " + parent
			+ ", \"x\": " + number(part.x) + ", \"y\": " + number(part.y) + ", \"z\": " + number(part.z)
			+ ", \"xRot\": " + number(part.xRot) + ", \"yRot\": " + number(part.yRot) + ", \"zRot\": " + number(part.zRot) + ", \"faces\": [");
		Field cubesField = ModelPart.class.getDeclaredField("cubes");
		cubesField.setAccessible(true);
		List<ModelPart.Cube> cubes = (List<ModelPart.Cube>) cubesField.get(part);
		for (ModelPart.Cube cube : cubes) {
			for (ModelPart.Polygon polygon : cube.polygons) {
				writeFace(json, polygon);
			}
		}
		if (json.charAt(json.length() - 1) == ',') {
			json.setLength(json.length() - 1);
		}
		json.append("]},\n");
		Field childrenField = ModelPart.class.getDeclaredField("children");
		childrenField.setAccessible(true);
		Map<String, ModelPart> children = (Map<String, ModelPart>) childrenField.get(part);
		for (String childName : children.keySet()) {
			writePart(json, childName, children.get(childName), index, written);
		}
	}

	static void writeFace(StringBuilder json, ModelPart.Polygon polygon) {
		json.append("[");
		for (ModelPart.Vertex corner : polygon.vertices()) {
			json.append(number(corner.x()) + "," + number(corner.y()) + "," + number(corner.z()) + "," + number(corner.u()) + "," + number(corner.v()) + ",");
		}
		json.setLength(json.length() - 1);
		json.append("],");
	}

	static void writePose(StringBuilder table, List<ModelPart> parts) {
		if (!table.isEmpty()) {
			table.append(",");
		}
		table.append("[");
		for (ModelPart part : parts) {
			table.append(number(part.xRot) + "," + number(part.yRot) + "," + number(part.zRot) + ",");
		}
		table.setLength(table.length() - 1);
		table.append("]");
	}
}
