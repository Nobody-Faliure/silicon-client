import Foundation

// How one tinted part of a block gets its colour. Read from block-tints.json.
enum Tint {
	case grass, foliage, dryFoliage, water   // the biome's colour of that kind
	case fixed(SIMD3<Float>)                 // always this colour (birch leaves, redstone…)
	
	// The actual colour of this tint in a given biome. White means "no change".
	func color(in biome: Biome) -> SIMD3<Float> {
		let white = SIMD3<Float>(1, 1, 1)
		switch self {
		case .grass:            return biome.grassColor ?? white
		case .foliage:          return biome.foliageColor ?? white
		case .dryFoliage:       return biome.dryFoliageColor ?? white
		case .water:            return biome.waterColor ?? white
		case .fixed(let color): return color
		}
	}
}

extension Tint: Decodable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let label = try? container.decode(String.self) {
			switch label {
			case "grass": self = .grass
			case "foliage": self = .foliage
			case "dry_foliage": self = .dryFoliage
			default: self = .water
			}
		} else {
			let hex = try container.decode([String: String].self)["fixed"] ?? "#ffffff"
			self = .fixed(BiomeRegistry.color(fromHex: hex) ?? SIMD3<Float>(1, 1, 1))
		}
	}
}

enum BlockTints {
	static var states: [[Tint]] = []   // states[id] = that block state's tints, one per tintindex
	
	static func load(jar: URL) {
		let file = jar.deletingLastPathComponent().appendingPathComponent("GeneratedData/silicon/block-tints.json")
		guard let data = try? Data(contentsOf: file),
			  let values = try? JSONDecoder().decode([[Tint]].self, from: data) else {
			print("[bitlock tints] could not read \(file.path)")
			return
		}
		states = values
	}
}
