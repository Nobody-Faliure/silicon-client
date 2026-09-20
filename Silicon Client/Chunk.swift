struct Block: Hashable {
	let id: String
}

enum BlockFace: String {
	case up
	case down
	case north
	case south
	case east
	case west
}

struct BlockState: Hashable {
	let block: Block
	let properties: [String: String]
}

struct Chunk {
	var blocks: [BlockState]
	
	var chunkX: Int
	var chunkZ: Int
	
	static let width = 16
	static let depth = 16
	static let height = 16
	
	init(chunkX: Int, chunkZ: Int) {
		self.blocks = Array(
			repeating: BlockState(block: Block(id: "minecraft:air"), properties: [:]),
			count: Chunk.width * Chunk.height * Chunk.depth
		)
		self.chunkX = chunkX
		self.chunkZ = chunkZ
	}
	
	// Converts 3D chunk coordinates into one position in the flat block array.
	func index(x: Int, y: Int, z: Int) -> Int {
		return x + z * Chunk.width + y * Chunk.width * Chunk.depth
	}
	
	func getBlock(x: Int, y: Int, z: Int) -> Block {
		return blocks[index(x: x, y: y, z: z)].block
	}
	
	func getBlockState(x: Int, y: Int, z: Int) -> BlockState {
		return blocks[index(x: x, y: y, z: z)]
	}
	
	mutating func setBlock(x: Int, y: Int, z: Int, block: BlockState) {
		blocks[index(x: x, y: y, z: z)] = block
	}
}
