import Foundation

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

struct Section {
	var blocks: [BlockState]
	
	var skyLight = Data()
	var blockLight = Data()
	
	static let width = 16
	static let depth = 16
	static let height = 16
	
	init() {
		self.blocks = Array(
			repeating: BlockState(block: Block(id: "minecraft:air"), properties: [:]),
			count: Section.width * Section.height * Section.depth
		)
	}
	
	func index(x: Int, y: Int, z: Int) -> Int {
		return x + z * Section.width + y * Section.width * Section.depth
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
	
	func lightLevel(at index: Int) -> Int {
		let sky = skyLight.isEmpty ? 15 : nibble(skyLight, index)
		let block = blockLight.isEmpty ? 0 : nibble(blockLight, index)
		
		return max(sky, block)
	}
	
	// Two blocks share a byte: the even one is the low half, the odd one the high half.
	private func nibble(_ light: Data, _ index: Int) -> Int {
		let byteIndex = index >> 1
		
		guard byteIndex < light.count else { return 0 }
		
		let byte = light[light.startIndex + byteIndex]
		
		return index & 1 == 0 ? Int(byte & 0xF) : Int(byte >> 4)
	}
}

struct Chunk {
	var sections: [Section]
	
	var chunkX: Int
	var chunkZ: Int
	
	static let sectionCount = 24     // -64 to 319
	static let minY = -64

	var height: Int { sections.count * Section.height }

	init(chunkX: Int, chunkZ: Int) {
		self.sections = (0..<Chunk.sectionCount).map { _ in Section() }
		self.chunkX = chunkX
		self.chunkZ = chunkZ
	}
	
	func locate(_ y: Int) -> (section: Int, localY: Int) {
		return ((y + 64) / Section.height, (y + 64) % Section.height)
	}
	
	func getBlock(x: Int, y: Int, z: Int) -> Block {
		let location = locate(y)
		return sections[location.0].getBlock(x: x, y: location.1, z: z)
	}
	
	func getBlockState(x: Int, y: Int, z: Int) -> BlockState {
		let location = locate(y)
		return sections[location.0].getBlockState(x: x, y: location.1, z: z)
	}
	
	mutating func setBlock(x: Int, y: Int, z: Int, block: BlockState) {
		let location = locate(y)
		return sections[location.0].setBlock(x: x, y: location.1, z: z, block: block)
	}
}
