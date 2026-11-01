import Foundation

// One kind of entity (pig, zombie…). Every pig in the world shares this one.
struct EntityType: Decodable {
	let name: String
	let width: Double
	let height: Double
}

// One piece of a model (head, a leg…). Each face is 20 numbers: 4 corners × x y z u v.
struct EntityPart: Decodable {
	let name: String
	let parent: Int
	let x: Float
	let y: Float
	let z: Float
	let xRot: Float
	let yRot: Float
	let zRot: Float
	let faces: [[Float]]
}

// One model of one entity (the pig has PigModel, BabyPigModel, ColdPigModel…).
struct EntityModel: Decodable {
	let entity: String
	let kind: String
	let texture: String
	let parts: [EntityPart]
}

// The whole entities.json file. models, walks and keyframes get added here later.
struct EntitiesFile: Decodable {
	let types: [EntityType]
	let models: [EntityModel]
}

enum EntityData {
	static var types: [EntityType] = []
	static var models: [EntityModel] = []

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
		models = entitiesFile.models
	}
}
