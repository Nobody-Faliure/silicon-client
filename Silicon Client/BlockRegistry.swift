struct BlockDefinition {
	let id: String
	let textureName: String
	let isSolid: Bool
}

struct BlockRegistry {
	private var definitions: [String: BlockDefinition] = [:]

	mutating func register(_ definition: BlockDefinition) {
		definitions[definition.id] = definition
	}

	func definition(for block: Block) -> BlockDefinition? {
		definitions[block.id]
	}
	
	static func vanilla() -> BlockRegistry {
		var registry = BlockRegistry()

		registry.register(BlockDefinition(
			id: "minecraft:air",
			textureName: "",
			isSolid: false
		))

		registry.register(BlockDefinition(
			id: "minecraft:stone",
			textureName: "stone",
			isSolid: true
		))

		return registry
	}
}

 
