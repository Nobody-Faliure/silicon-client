enum Block {
	case air
	case stone
}

struct Chunk {
	var blocks: [Block]
	
	static let width = 16
	static let depth = 16
	static let height = 16
	
	init() {
		self.blocks = Array(
			repeating: .air,
			count: Chunk.width * Chunk.height * Chunk.depth
		)
	}
	
	// Converts 3D chunk coordinates into one position in the flat block array.
	func index(x: Int, y: Int, z: Int) -> Int {
		return x + z * Chunk.width + y * Chunk.width * Chunk.depth
	}
	
	func getBlock(x: Int, y: Int, z: Int) -> Block {
		return blocks[index(x: x, y: y, z: z)]
	}
	
	mutating func setBlock(x: Int, y: Int, z: Int, block: Block) {
		blocks[index(x: x, y: y, z: z)] = block
	}
}
