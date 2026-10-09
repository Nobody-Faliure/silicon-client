import Foundation

// The light half of a packet: four masks, then the arrays they describe.
// Both level_chunk_with_light (0x2d) and light_update (0x30) end with
// exactly these fields, so both read them through here.
enum LightDecoder {
	
	// Takes the reader mid-packet and leaves it just past the light, so the
	// caller can carry on. Returns section number -> that section's 2048
	// bytes, for sky and for block separately.
	static func decode(from reader: inout NBTReader) -> (sky: [Int: Data], block: [Int: Data]) {
		let skyMask = reader.readMask()
		let blockMask = reader.readMask()
		let emptySkyMask = reader.readMask()
		let emptyBlockMask = reader.readMask()
		
		var sky: [Int: Data] = [:]
		var block: [Int: Data] = [:]
		
		// Sections the server says are pitch black. Storing real zeros rather
		// than leaving them out matters: a section with no data at all is
		// treated as "not told yet" and drawn fully bright.
		let dark = Data(count: 2048)
		
		for bit in emptySkyMask { sky[bit - 1] = dark }
		for bit in emptyBlockMask { block[bit - 1] = dark }
		
		let skyCount = min(reader.readVarInt(), skyMask.count)
		
		for n in 0..<skyCount where n < skyMask.count {
			let length = reader.readVarInt()
			sky[skyMask[n] - 1] = reader.readBytes(length)
		}
		
		let blockCount = min(reader.readVarInt(), blockMask.count)
		
		for n in 0..<blockCount where n < blockMask.count {
			let length = reader.readVarInt()
			block[blockMask[n] - 1] = reader.readBytes(length)
		}
		
		return (sky, block)
	}
}
