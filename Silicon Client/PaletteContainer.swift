import Foundation

struct PaletteContainer {
	let bitsPerEntry: Int
	let palette: [Int]
	let data: [Int]
	
	init(reading reader: inout NBTReader, entryCount: Int) {
		bitsPerEntry = Int(reader.readByte())
		
		if bitsPerEntry == 0 {
			palette = [reader.readVarInt()]
			data = []
			return
		}
		
		if bitsPerEntry <= 8 {
			let count = reader.readVarInt()
			var entries: [Int] = []
			entries.reserveCapacity(count)
			
			for _ in 0..<count {
				entries.append(reader.readVarInt())
			}
			
			palette = entries
		} else {
			palette = []
		}
		
		let entriesPerLong = 64 / bitsPerEntry
		let longCount = Int(ceil(Double(entryCount) / Double(entriesPerLong)))
		
		var longs: [Int] = []
		longs.reserveCapacity(longCount)
		
		for _ in 0..<longCount {
			longs.append(reader.readInteger(byteCount: 8))
		}
		
		data = longs
	}
	
	func value(at index: Int) -> Int {
		if bitsPerEntry == 0 {
			return palette[0]
		}
		
		let entriesPerLong = 64 / bitsPerEntry
		let longIndex = index / entriesPerLong
		let offset = (index % entriesPerLong) * bitsPerEntry
		
		let mask = (1 << bitsPerEntry) - 1
		
		guard longIndex < data.count else { return 0 }
		
		let raw = (data[longIndex] >> offset) & mask
		
		if palette.isEmpty { return raw }
		return raw < palette.count ? palette[raw] : 0
	}
}
