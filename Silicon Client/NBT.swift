import Foundation

enum NBTTag {
	case byte(Int)
	case short(Int)
	case int(Int)
	case long(Int)
	case float(Float)
	case double(Double)
	case string(String)
	case byteArray([Int])
	case intArray([Int])
	case longArray([Int])
	case list([NBTTag])
	case compound([String: NBTTag])
}

struct NBTReader {
	let data: Data
	var index: Int = 0
	var remaining: Int { data.count - index }
	
	mutating func readByte() -> UInt8 {
		guard index < data.count else { return 0 }
		let byte = data[data.startIndex + index]
		index += 1
		return byte
	}
	
	mutating func readInteger(byteCount: Int) -> Int {
		var result = 0
		
		for _ in 0..<byteCount {
			result = result << 8 | Int(readByte())
		}
		
		let bitCount = byteCount * 8
		
		if byteCount < 8 && result >= 1 << (bitCount - 1) {
			result -= 1 << bitCount
		}
		
		return result
	}
	
	mutating func readShort() -> Int { readInteger(byteCount: 2) }
	mutating func readInt()   -> Int { readInteger(byteCount: 4) }
	mutating func readLong()  -> Int { readInteger(byteCount: 8) }
	
	mutating func readString() -> String {
		let length = min(max(readInteger(byteCount: 2), 0), remaining)
		
		let start = data.startIndex + index
		let bytes = data[start ..< start + length]
		index += length
		
		return String(decoding: bytes, as: UTF8.self)
	}
	
	mutating func readFloat() -> Float {
		var bits: UInt32 = 0
		for _ in 0..<4 { bits = bits << 8 | UInt32(readByte()) }
		return Float(bitPattern: bits)
	}
	
	mutating func readDouble() -> Double {
		var bits: UInt64 = 0
		for _ in 0..<8 { bits = bits << 8 | UInt64(readByte()) }
		return Double(bitPattern: bits)
	}
	
	mutating func readArray(byteCount: Int) -> [Int] {
		let count = readInt()
		var values: [Int] = []
		values.reserveCapacity(min(count, remaining))
		
		for _ in 0..<count {
			guard remaining >= byteCount else { break }
			values.append(readInteger(byteCount: byteCount))
		}
		
		return values
	}
	
	mutating func readList() -> [NBTTag] {
		let type = readByte()
		let count = readInt()
		var values: [NBTTag] = []
		values.reserveCapacity(min(count, remaining))
		
		for _ in 0..<count {
			guard remaining > 0, let value = readValue(type: type) else { break }
			values.append(value)
		}
		
		return values
	}
	
	mutating func readCompound() -> [String: NBTTag] {
		var fields: [String: NBTTag] = [:]
		
		while true {
			let type = readByte()
			if type == 0 { return fields }
			
			let name = readString()
			guard let value = readValue(type: type) else { return fields }
			fields[name] = value
		}
	}
	
	mutating func readValue(type: UInt8) -> NBTTag? {
		switch type {
		case 1:  return .byte(readInteger(byteCount: 1))
		case 2:  return .short(readShort())
		case 3:  return .int(readInt())
		case 4:  return .long(readLong())
		case 5:  return .float(readFloat())
		case 6:  return .double(readDouble())
		case 7:  return .byteArray(readArray(byteCount: 1))
		case 8:  return .string(readString())
		case 9:  return .list(readList())
		case 10: return .compound(readCompound())
		case 11: return .intArray(readArray(byteCount: 4))
		case 12: return .longArray(readArray(byteCount: 8))
		default: return nil
		}
	}
	
	mutating func readRoot() -> NBTTag? {
		guard readByte() == 10 else { return nil }
		_ = readString()
		return .compound(readCompound())
	}
	
	mutating func readVarInt() -> Int {
		return VarInt.read(from: data, at: &index) ?? 0
	}
}
