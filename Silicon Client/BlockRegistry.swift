import Foundation

// One entry in blocks.json: "minecraft:oak_stairs": { "states": [...] }
struct BlockReportEntry: Decodable {
	let states: [BlockReportState]
}

// One state: { "id": 3907, "properties": { "facing": "north", ... } }
struct BlockReportState: Decodable {
	let id: Int
	let properties: [String: String]?
}

enum BlockRegistry {
	static var statesByID: [BlockState] = []
	
	static func reportURL(version: String) -> URL {
		FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
			.appendingPathComponent("Silicon Client")
			.appendingPathComponent("Versions")
			.appendingPathComponent(version)
			.appendingPathComponent("GeneratedData")
			.appendingPathComponent("reports")
			.appendingPathComponent("blocks.json")
	}
	
	static func load(version: String) {
		guard statesByID.isEmpty else { return }
		
		guard let data = try? Data(contentsOf: reportURL(version: version)),
			  let report = try? JSONDecoder().decode(
				[String: BlockReportEntry].self, from: data) else {
			print("[registry] could not read blocks.json")
			return
		}
		
		// IDs run 0...max with no gaps, so an array indexed by ID works.
		let maxID = report.values.flatMap { $0.states }.map(\.id).max() ?? 0
		let air = BlockState(block: Block(id: "minecraft:air"), properties: [:])
		statesByID = Array(repeating: air, count: maxID + 1)
		
		for (name, entry) in report {
			for state in entry.states {
				statesByID[state.id] = BlockState(
					block: Block(id: name),
					properties: state.properties ?? [:]
				)
			}
		}

	}
}
