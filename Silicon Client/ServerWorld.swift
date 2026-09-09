final class ServerWorld {
	var chunks: [Chunk] = []

	init() {
		var chunk = Chunk(chunkX: 0, chunkZ: 0)
		
		chunk.setBlock(
			x: 1,
			y: 0,
			z: 1,
			block: BlockState(block: .oak_log, properties: [:])
		)
		chunk.setBlock(
			x: 1,
			y: 0,
			z: 2,
			block: BlockState(block: .crafting_table, properties: [:])
		)

		chunks.append(chunk)
	}
}
