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
	let choice: String     // which model this is, e.g. "models.cold.babyModel"
	let kind: String
	let texture: String
	let parts: [EntityPart]
	let headYaw: [[Float]]
	let headPitch: [[Float]]
}

// One variant JSON file, e.g. pig_variant/cold.json or wolf_variant/ashen.json. Any field can be missing.
struct EntityVariant: Decodable {
	let assetId: String?                  // adult texture, e.g. "minecraft:entity/pig/pig_cold"
	let babyAssetId: String?              // baby texture, e.g. "minecraft:entity/pig/pig_cold_baby"
	let model: String?                    // word for wantedChoices, e.g. "cold"
	let assets: [String: String]?         // wolf only: mood → adult texture, e.g. "tame" → "minecraft:entity/wolf/wolf_ashen_tame"
	let babyAssets: [String: String]?     // wolf only: mood → baby texture
}

// The whole entities.json file. models, walks and keyframes get added here later.
struct EntitiesFile: Decodable {
	let types: [EntityType]
	let models: [EntityModel]
	let dataTypes: [String: Int]   // type name → its number in this version, e.g. "PIG_VARIANT": 28
	let variantDefaults: [String: String]   // type name → default variant, e.g. "PIG_VARIANT": "minecraft:temperate"
	let slots: [String: [String: String]]   // mob → slot → name, e.g. "sheep" → "16" → "DATA_BABY_ID"
}

enum EntityData {
	static var types: [EntityType] = []
	static var models: [EntityModel] = []
	static var dataTypes: [String: Int] = [:]   // e.g. "PIG_VARIANT": 28; filled by load
	static var variantDefaults: [String: String] = [:]   // filled by load
	static var slots: [String: [String: String]] = [:]   // filled by load
	static var loadedVariants: [String: EntityVariant] = [:]   // "pig/warm" → that file, so each file is read once
	// This version's folder, e.g. ".../Versions/26.2". Set when load runs.
	static var versionFolder: URL? = nil
	// Each variant list the server sends when we join, in the server's order.
	// e.g. "minecraft:pig_variant" → ["minecraft:cold", "minecraft:temperate", "minecraft:warm"]
	static var variantNames: [String: [String]] = [:]

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
		versionFolder = jar.deletingLastPathComponent()
		models = entitiesFile.models
		dataTypes = entitiesFile.dataTypes
		variantDefaults = entitiesFile.variantDefaults
		slots = entitiesFile.slots
	}

	// Reads one variant JSON file, e.g. mob "pig" + variantName "temperate" reads pig_variant/temperate.json.
	// Gives nil if the file is missing or can't be read.
	static func variant(mob: String, variantName: String) -> EntityVariant? {
		if let alreadyRead = loadedVariants["\(mob)/\(variantName)"] {
			return alreadyRead
		}
		let file = versionFolder?.appendingPathComponent("GeneratedData/data/minecraft/\(mob)_variant/\(variantName).json")
		guard let file, let data = try? Data(contentsOf: file) else {
			return nil
		}
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		let readVariant = try? decoder.decode(EntityVariant.self, from: data)
		loadedVariants["\(mob)/\(variantName)"] = readVariant
		return readVariant
	}

	// Which variant this mob is, e.g. mob "pig" + variantNumber 2 gives "minecraft:warm".
	// Uses the game's default when the server sent no number.
	static func variantName(mob: String, variantNumber: Int?) -> String? {
		let names = variantNames["minecraft:\(mob)_variant"] ?? []
		if let variantNumber, variantNumber < names.count {
			return names[variantNumber]
		}
		return variantDefaults[mob.uppercased() + "_VARIANT"]
	}

	// The texture file for this mob's variant, e.g. "textures/entity/pig/pig_warm.png". Nil for mobs without variants.
	static func variantTexturePath(mob: String, variantNumber: Int?, isBaby: Bool) -> String? {
		guard let variantName = variantName(mob: mob, variantNumber: variantNumber) else {
			return nil
		}
		let shortName = variantName.replacingOccurrences(of: "minecraft:", with: "")
		let foundVariant = variant(mob: mob, variantName: shortName)
		let babyOrAdultId = isBaby ? foundVariant?.babyAssetId : foundVariant?.assetId
		guard let assetId = babyOrAdultId ?? foundVariant?.assetId else {
			return nil
		}
		return "textures/" + assetId.replacingOccurrences(of: "minecraft:", with: "") + ".png"
	}

	// The model word for this mob's variant, e.g. "cold" for a cold pig. Nil when there is none.
	static func variantModelWord(mob: String, variantNumber: Int?) -> String? {
		guard let variantName = variantName(mob: mob, variantNumber: variantNumber) else {
			return nil
		}
		let shortName = variantName.replacingOccurrences(of: "minecraft:", with: "")
		return variant(mob: mob, variantName: shortName)?.model
	}

	// A number this mob got from the server, found by its name, e.g. "DATA_BABY_ID" gives 1 for a baby. Nil if never sent.
	static func dataNumber(entity: Entity, mob: String, name: String) -> Int? {
		let slotText = slots[mob]?.first { $0.value == name }?.key
		guard let slotText, let slot = Int(slotText) else {
			return nil
		}
		return entity.data[slot]
	}
}
