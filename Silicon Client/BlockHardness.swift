import Foundation

enum BlockHardness {
	struct Values: Decodable {
		let hardness: Float    // 0 = breaks instantly, -1 = unbreakable (bedrock)
		let needsTool: Bool    // true = digs slowly without the right tool
	}

	static var blocks: [String: Values] = [:]

	static func load(jar: URL) {
		let file = jar.deletingLastPathComponent()
			.appendingPathComponent("GeneratedData/silicon/block-hardness.json")
		guard let data = try? Data(contentsOf: file),
			  let values = try? JSONDecoder().decode([String: Values].self, from: data) else {
			print("[hardness] could not read \(file.path)")
			return
		}
		blocks = values
	}
}
