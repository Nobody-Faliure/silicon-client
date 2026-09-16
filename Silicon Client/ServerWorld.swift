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

		// Upright oak log
		chunk.setBlock(
			x: 1,
			y: 0,
			z: 5,
			block: BlockState(
				block: Block(id: "minecraft:oak_log"),
				properties: ["axis": "z"]
			)
		)

		// Furnace
		chunk.setBlock(
			x: 2,
			y: 0,
			z: 5,
			block: BlockState(
				block: Block(id: "minecraft:furnace"),
				properties: [
					"facing": "north",
					"lit": "true"
				]
			)
		)
		chunks.append(chunk)
	}
}
