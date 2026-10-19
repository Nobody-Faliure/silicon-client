struct AttributeModifier {
	let id: String        // e.g. "minecraft:effect.speed"
	let amount: Double    // e.g. 0.4
	let operation: Int    // 0 add, 1 percent of base, 2 percent of everything
}

enum Attributes {
	static func finalValue(base: Double, modifiers: [AttributeModifier]) -> Double {
		var value = base
		for m in modifiers where m.operation == 0 { value += m.amount }
		
		var result = value
		for m in modifiers where m.operation == 1 { result += value * m.amount }
		for m in modifiers where m.operation == 2 { result *= 1 + m.amount }
		
		return result
	}
}
