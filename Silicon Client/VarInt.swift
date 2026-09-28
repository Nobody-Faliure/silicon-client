import Foundation

struct VarInt {
	static func write(_ value: Int, to data: inout Data) {
		var remaining = UInt32(bitPattern: Int32(value))
		
		while true {
			if remaining & ~0x7F == 0 {
				data.append(UInt8(remaining))
				return
			}
			
			data.append(UInt8((remaining & 0x7F) | 0x80))
			remaining >>= 7
		}
	}
	
	static func writeString(_ value: String, to data: inout Data) {
		let bytes = Array(value.utf8)
		
		VarInt.write(bytes.count, to: &data)
		data.append(contentsOf: bytes)
	}
	
	static func read(from data: Data, at index: inout Int) -> Int? {
		var result: UInt32 = 0
		var shift = 0
		
		while shift < 35 {
			guard index < data.count else {
				return nil
			}
			
			let byte = data[data.startIndex + index]
			index += 1
			
			result |= UInt32(byte & 0x7F) << shift
			
			if byte & 0x80 == 0 {
				return Int(Int32(bitPattern: result))
			}
			
			shift += 7
		}
		
		return nil
	}
}
