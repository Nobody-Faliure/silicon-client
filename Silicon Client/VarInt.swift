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
}
