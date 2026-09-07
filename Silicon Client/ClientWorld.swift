final class ClientWorld {
	var chunks: [Chunk] = []

	init() {
	}

	func receiveChunk(_ newChunk: Chunk) {
		for i in 0..<chunks.count {
			if chunks[i].chunkX == newChunk.chunkX &&
				chunks[i].chunkZ == newChunk.chunkZ {

				chunks[i] = newChunk
				return
			}
		}

		chunks.append(newChunk)
	}
	
	func receiveBlockUpdate(
		chunkX: Int,
		chunkZ: Int,
		x: Int,
		y: Int,
		z: Int,
		block: Block
	) {
		for i in 0..<chunks.count {
			if chunks[i].chunkX == chunkX &&
				chunks[i].chunkZ == chunkZ {

				chunks[i].setBlock(
					x: x,
					y: y,
					z: z,
					block: block
				)

				return
			}
		}
	}
}
