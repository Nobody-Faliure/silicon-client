struct SectionPosition: Hashable {
	  let chunkX: Int
	  let chunkZ: Int
	  let sectionIndex: Int
}

final class ClientWorld {
	var chunks: [Chunk] = []
	
	var dirtySections: Set<SectionPosition> = []

	init() {
	}
	
	func chunk(atX x: Int, z: Int) -> Chunk? {
		return chunks.first { $0.chunkX == x && $0.chunkZ == z }
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
		block: BlockState
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
				
				dirtySections.insert(SectionPosition(
						chunkX: chunkX,
						chunkZ: chunkZ,
						sectionIndex: chunks[i].locate(y).section
				))

				return
			}
		}
	}
	
	func unloadChunk(chunkX: Int, chunkZ: Int) {
		chunks.removeAll {
			$0.chunkX == chunkX && $0.chunkZ == chunkZ
		}
	}
}
