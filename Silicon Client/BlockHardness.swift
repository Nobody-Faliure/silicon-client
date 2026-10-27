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

	static func progressPerTick(for blockName: String) -> Float {
		guard let values = blocks[blockName] else { return 0.01 }   // unknown block: slow, so the server never says no
		if values.hardness < 0 { return 0 }                          // unbreakable (bedrock)
		if values.hardness == 0 { return 1 }                         // breaks on the first tick
		return 1 / values.hardness / (values.needsTool ? 100 : 30)
	}
}
