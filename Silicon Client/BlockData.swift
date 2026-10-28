import Foundation

enum BlockData {
	struct Values: Decodable {
		let hardness: Float       // 0 = breaks instantly, -1 = unbreakable (bedrock)
		let needsTool: Bool       // true = digs slowly without the right tool
		let lightDampening: Int   // 0-15: how much light drops going into this block (stone 15, leaves 1, air 0)
		let lightEmission: Int    // 0-15: how bright it glows (torch 14, glowstone 15)
		let skylightDown: Bool    // true = sunlight passes straight down at full strength (air, glass)
	}
	
	static var states: [Values] = []   // states[id] = the values for block state number id

	static func load(jar: URL) {
		let file = jar.deletingLastPathComponent()
			.appendingPathComponent("GeneratedData/silicon/block-data.json")
		guard let data = try? Data(contentsOf: file),
			  let values = try? JSONDecoder().decode([Values].self, from: data) else {
			print("[block data] could not read \(file.path)")
			return
		}
		states = values
	}
	
	static func miningProgressPerTick(for stateID: UInt16) -> Float {
		guard Int(stateID) < states.count else { return 0.01 }   // not loaded yet: slow, so the server never says no
		let values = states[Int(stateID)]
		if values.hardness < 0 { return 0 }                          // unbreakable (bedrock)
		if values.hardness == 0 { return 1 }                         // breaks on the first tick
		return 1 / values.hardness / (values.needsTool ? 100 : 30)
	}
}
