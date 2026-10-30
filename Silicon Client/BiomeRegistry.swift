import simd
import CoreGraphics
import ImageIO
import Foundation

struct Biome {
	let grassColor: SIMD3<Float>?
	let foliageColor: SIMD3<Float>?
	let dryFoliageColor: SIMD3<Float>?
	let waterColor: SIMD3<Float>?
	
	let temperature: Float
	let downfall: Float
	
	static let unknown = Biome(
		grassColor: nil,
		foliageColor: nil,
		dryFoliageColor: nil,
		waterColor: nil,
		temperature: 0.5,
		downfall: 0.5
	)
}


enum BiomeRegistry {
	static var biomes: [Biome] = []
	static var colormapFolder: URL?
	
	static func applyColormaps(in folder: URL) {
		guard
			let grass = loadColormap(
				at: folder.appendingPathComponent("colormap/grass.png")),
			let foliage = loadColormap(
				at: folder.appendingPathComponent("colormap/foliage.png")),
			let dryFoliage = loadColormap(
				at: folder.appendingPathComponent("colormap/dry_foliage.png"))
				else { return }
		
		biomes = biomes.map { biome in
			Biome(
				grassColor: biome.grassColor ?? color(
					fromColormap: grass,
					temperature: biome.temperature,
					downfall: biome.downfall
				),
				foliageColor: biome.foliageColor ?? color(
					fromColormap: foliage,
					temperature: biome.temperature,
					downfall: biome.downfall
				),
				dryFoliageColor: biome.dryFoliageColor ?? color(
					fromColormap: dryFoliage,
					temperature: biome.temperature,
					downfall: biome.downfall
				),
				waterColor: biome.waterColor,
				temperature: biome.temperature,
				downfall: biome.downfall
			)
		}
	}
	
	static func color(fromHex hex: String) -> SIMD3<Float>? {
		guard let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
		
		return SIMD3<Float>(
			Float((value >> 16) & 0xff) / 255,
			Float((value >>  8) & 0xff) / 255,
			Float( value        & 0xff) / 255
		)
	}
	
	static func loadColormap(at url: URL) -> [UInt8]? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
				else { return nil }
		
		var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
		
		guard let context = CGContext(
			data: &pixels,
			width: 256,
			height: 256,
			bitsPerComponent: 8,
			bytesPerRow: 256 * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else { return nil }
		
		context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
		
		return pixels
	}
	
	static func color(
		fromColormap pixels: [UInt8],
		temperature: Float,
		downfall: Float
	) -> SIMD3<Float> {
		let t = min(max(temperature, 0), 1)
		let d = min(max(downfall, 0), 1)
		
		let x = Int((1 - t) * 255)
		let y = Int((1 - d * t) * 255)
		
		let offset = (y * 256 + x) * 4
		
		return SIMD3<Float>(
			Float(pixels[offset]    ) / 255,
			Float(pixels[offset + 1]) / 255,
			Float(pixels[offset + 2]) / 255
		)
	}
	
	private static func string(_ tag: NBTTag?) -> String? {
		if let tag, case .string(let value) = tag { return value }
		return nil
	}
	
	private static func float(_ tag: NBTTag?) -> Float? {
		if let tag, case .float(let value) = tag { return value }
		return nil
	}
	
	static func biome(from tag: NBTTag) -> Biome? {
		guard case .compound(let root) = tag else { return nil }
		
		var effects: [String: NBTTag] = [:]
		if let found = root["effects"], case .compound(let values) = found {
			effects = values
		}
		
		return Biome(
			grassColor: string(effects["grass_color"]).flatMap(color(fromHex:)),
			foliageColor: string(effects["foliage_color"]).flatMap(color(fromHex:)),
			dryFoliageColor: string(effects["dry_foliage_color"]).flatMap(color(fromHex:)),
			waterColor: string(effects["water_color"]).flatMap(color(fromHex:)),
			temperature: float(root["temperature"]) ?? 0.5,
			downfall: float(root["downfall"]) ?? 0.5
		)
	}
}
