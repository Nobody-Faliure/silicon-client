final class ServerWorld {
	var chunks: [Chunk] = []

	init() {
		var chunk = Chunk(chunkX: 0, chunkZ: 0)

		// Crafting table
		chunk.setBlock(
			x: 2,
			y: 0,
			z: 1,
			block: BlockState(
				block: Block(id: "minecraft:crafting_table"),
				properties: [:]
			)
		)

		// Upright oak log
		chunk.setBlock(
			x: 3,
			y: 0,
			z: 1,
			block: BlockState(
				block: Block(id: "minecraft:oak_log"),
				properties: ["axis": "y"]
			)
		)

		// Blast furnace
		chunk.setBlock(
			x: 4,
			y: 0,
			z: 1,
			block: BlockState(
				block: Block(id: "minecraft:blast_furnace"),
				properties: [
					"facing": "east",
					"lit": "true"
				]
			)
		)

		chunks.append(chunk)
	}
}
