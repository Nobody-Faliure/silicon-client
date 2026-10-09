import Foundation

enum ChunkDecoder {
	static func decode(packet: Data) -> Chunk? {
		BlockRegistry.load(version: "26.2")
		
		var reader = NBTReader(data: packet)
		
		guard reader.readVarInt() == 0x2d else { return nil }
		
		let chunkX = reader.readInteger(byteCount: 4)
		let chunkZ = reader.readInteger(byteCount: 4)
		
		let heightmapCount = reader.readVarInt()
		
		for _ in 0..<heightmapCount {
			_ = reader.readVarInt()                  // which heightmap it is
			let longCount = reader.readVarInt()      // how many longs
			reader.index += longCount * 8            // skip them
		}
		
		_ = reader.readVarInt()                 // blob size, 20192 — we don't need it
		
		var chunk = Chunk(chunkX: chunkX, chunkZ: chunkZ)
		
		for sectionIndex in 0..<Chunk.sectionCount {
			reader.index += 4                    // non-air count + the unidentified short
			
			let blocks = PaletteContainer(reading: &reader, entryCount: 4096)
			_ = PaletteContainer(reading: &reader, entryCount: 64)   // biomes
			
			
			for i in 0..<4096 {
				let stateID = blocks.value(at: i)
				
				guard stateID != 0 else { continue }
				
				guard let state = BlockRegistry.statesByID[stateID] else { continue }
				
				chunk.sections[sectionIndex].blocks[i] = state
			}
		}
		
		let blockEntityCount = reader.readVarInt()
		
		for _ in 0..<blockEntityCount {
			reader.index += 3        // packed x/z in one byte, then y as a short
			_ = reader.readVarInt()  // which kind of block entity
			_ = reader.readNetworkRoot()    // its NBT
		}
		
		let light = LightDecoder.decode(from: &reader)
		
		for (section, bytes) in light.sky where section >= 0 && section < Chunk.sectionCount {
			chunk.sections[section].skyLight = bytes
		}
		
		for (section, bytes) in light.block where section >= 0 && section < Chunk.sectionCount {
			chunk.sections[section].blockLight = bytes
		}
		
		return chunk
	}
}
