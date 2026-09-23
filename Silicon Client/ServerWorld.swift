final class ServerWorld {
	var chunks: [Chunk] = []

	init() {
		var chunk = Chunk(chunkX: 0, chunkZ: 0)

		// Crafting table
		chunk.setBlock(
			x: 0,
			y: 0,
			z: 5,
			block: BlockState(
				block: Block(id: "minecraft:crafting_table"),
				properties: [:]
			)
		)

		chunk.setBlock(
			x: 1,
			y: 0,
			z: 5,
			block: BlockState(
				block: Block(id: "minecraft:stone"),
				properties: ["axis": "z"]
			)
		)
		chunk.setBlock(
			x: 1,
			y: 0,
			z: 4,
			block: BlockState(
				block: Block(id: "minecraft:stone"),
				properties: ["axis": "z"]
			)
		)
		chunk.setBlock(
			x: 1,
			y: 0,
			z: 3,
			block: BlockState(
				block: Block(id: "minecraft:stone"),
				properties: ["axis": "z"]
			)
		)

		// Furnace
		chunk.setBlock(
			x: 2,
			y: 0,
			z: 2,
			block: BlockState(
				block: Block(id: "minecraft:furnace"),
				properties: [
					"facing": "north",
					"lit": "true"
				]
			)
		)
		// Anvils, one per facing
		let facings = ["north", "east", "south", "west"]

		for (offset, facing) in facings.enumerated() {
			chunk.setBlock(
				x: offset,
				y: 0,
				z: 7,
				block: BlockState(
					block: Block(id: "minecraft:anvil"),
					properties: ["facing": facing]
				)
			)
		}

		// Damaged variants share the anvil model
		chunk.setBlock(
			x: 0,
			y: 0,
			z: 9,
			block: BlockState(
				block: Block(id: "minecraft:chipped_anvil"),
				properties: ["facing": "south"]
			)
		)

		chunk.setBlock(
			x: 1,
			y: 0,
			z: 9,
			block: BlockState(
				block: Block(id: "minecraft:damaged_anvil"),
				properties: ["facing": "south"]
			)
		)

		chunks.append(chunk)
	}
}
