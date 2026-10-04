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
	static var statesByID: [Int: BlockState] = [:]
	
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
