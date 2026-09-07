struct Block: Equatable {
	let id: String

	static let air = Block(id: "minecraft:air")
	static let stone = Block(id: "minecraft:stone")
}

struct Chunk {
	var blocks: [Block]
	
	var chunkX: Int
	var chunkZ: Int
	
	static let width = 16
	static let depth = 16
	static let height = 16
	
	init(chunkX: Int, chunkZ: Int) {
		self.blocks = Array(
			repeating: .air,
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
		return blocks[index(x: x, y: y, z: z)]
	}
	
	mutating func setBlock(x: Int, y: Int, z: Int, block: Block) {
		blocks[index(x: x, y: y, z: z)] = block
	}
}
