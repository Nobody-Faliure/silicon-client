import Foundation

struct SectionPosition: Hashable {
	let chunkX: Int
	let chunkZ: Int
	let sectionIndex: Int
}

final class ClientWorld {
	var chunks: [Chunk] = []
	
	var dirtySections: Set<SectionPosition> = []
	
	static let noCollision: Set<String> = [
		"minecraft:air"
		,"minecraft:water", "minecraft:lava", "minecraft:bubble_column",
		"minecraft:cave_air", "minecraft:void_air",
		"minecraft:seagrass", "minecraft:tall_seagrass",
		"minecraft:kelp", "minecraft:kelp_plant",
		"minecraft:short_grass", "minecraft:tall_grass", "minecraft:fern", "minecraft:large_fern",
	]
	
	init() {
	}
	
	func chunk(atX x: Int, z: Int) -> Chunk? {
		return chunks.first { $0.chunkX == x && $0.chunkZ == z }
	}
	
	func getBlockState(worldX: Int, y: Int, worldZ: Int) -> BlockState? {
		guard y >= Chunk.minY, y < Chunk.minY + Chunk.sectionCount * Section.height else {
			return nil
		}
		
		guard let chunk = chunk(atX: worldX >> 4, z: worldZ >> 4) else {
			return nil
		}
		
		return chunk.getBlockState(x: worldX & 15, y: y, z: worldZ & 15)
	}
	
	// Boxes of the block at this spot, placed in the world
	func hitbox(at position: SIMD3<Double>) -> Hitbox {
		let x = Int(floor(position.x))
		let y = Int(floor(position.y))
		let z = Int(floor(position.z))
		let corner = SIMD3<Double>(Double(x), Double(y), Double(z))
		
		// Not loaded yet: treat as solid so you don't fall into the void
		guard let id = blockID(worldX: x, y: y, worldZ: z) else {
			return Hitbox(boxes: [Box(min: corner, max: corner + [1, 1, 1])])
		}
		
		let name = BlockRegistry.statesByID[Int(id)].block.id
		// Air has no boxes
		if ClientWorld.noCollision.contains(name) { return Hitbox(boxes: []) }
		
		// For now, every other block is a full cube
		return Hitbox(boxes: [Box(min: corner, max: corner + [1, 1, 1])])
	}
	
	func blockID(worldX: Int, y: Int, worldZ: Int) -> UInt16? {
		guard y >= Chunk.minY, y < Chunk.minY + Chunk.sectionCount * Section.height else {
			return nil
		}
		
		guard let chunk = chunk(atX: worldX >> 4, z: worldZ >> 4) else {
			return nil
		}
		
		return chunk.blockID(x: worldX & 15, y: y, z: worldZ & 15)
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
		id: UInt16
	) {
		for i in 0..<chunks.count {
			if chunks[i].chunkX == chunkX &&
				chunks[i].chunkZ == chunkZ {
				
				chunks[i].setBlock(
					x: x,
					y: y,
					z: z,
					id: id
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
	
	func receiveLight(chunkX: Int, chunkZ: Int, sky: [Int: Data], block: [Int: Data]) {
		for i in 0..<chunks.count where chunks[i].chunkX == chunkX && chunks[i].chunkZ == chunkZ {
			for (section, light) in sky where section >= 0 && section < Chunk.sectionCount {
				chunks[i].sections[section].skyLight = light
				dirtySections.insert(SectionPosition(chunkX: chunkX, chunkZ: chunkZ, sectionIndex: section))
			}
			
			for (section, light) in block where section >= 0 && section < Chunk.sectionCount {
				chunks[i].sections[section].blockLight = light
				dirtySections.insert(SectionPosition(chunkX: chunkX, chunkZ: chunkZ, sectionIndex: section))
			}
			
			return
		}
	}
	
	func unloadChunk(chunkX: Int, chunkZ: Int) {
		chunks.removeAll {
			$0.chunkX == chunkX && $0.chunkZ == chunkZ
		}
	}
}
