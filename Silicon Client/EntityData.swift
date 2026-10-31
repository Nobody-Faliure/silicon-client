import Foundation

// One kind of entity (pig, zombie…). Every pig in the world shares this one.
struct EntityType: Decodable {
	let name: String
	let width: Double
	let height: Double
}

// The whole entities.json file. models, walks and keyframes get added here later.
struct EntitiesFile: Decodable {
	let types: [EntityType]
}

enum EntityData {
	static var types: [EntityType] = []

	static func file(jar: URL) -> URL {
		let folder = jar.deletingLastPathComponent()
		return folder.appendingPathComponent("GeneratedData/silicon/entities-\(SiliconVersion.current).json")
	}

	static func load(jar: URL) {
		guard let data = try? Data(contentsOf: file(jar: jar)) else {
			print("[entities] could not read \(file(jar: jar).path)")
			return
		}
		guard let entitiesFile = try? JSONDecoder().decode(EntitiesFile.self, from: data) else {
			print("[entities] could not understand \(file(jar: jar).path)")
			return
		}
		types = entitiesFile.types
	}
}
