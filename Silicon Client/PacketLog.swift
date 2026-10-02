import Foundation

final class PacketLog {
	private let handle: FileHandle
	private(set) var count = 0
	
	init?(fileName: String) {
		let url = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
			.appendingPathComponent("Silicon Client")
			.appendingPathComponent(fileName)
		
		FileManager.default.createFile(atPath: url.path, contents: nil)
		
		guard let handle = try? FileHandle(forWritingTo: url) else {
			return nil
		}
		
		self.handle = handle
		
		print("[log] recording packets to \(url.path)")
	}
	
	func append(_ packet: Data) {
		var record = Data()
		var length = UInt32(packet.count).bigEndian
		withUnsafeBytes(of: &length) { record.append(contentsOf: $0) }
		record.append(packet)
		
		try? handle.write(contentsOf: record)
		count += 1
	}
	
	deinit {
		try? handle.close()
	}
}
