import Foundation

// One track from timeline/day.json, like "minecraft:visual/sky_color":
// a list of (tick, color) points to fade between.
struct ColorTrack {
	let keyframes: [(ticks: Int, color: SIMD4<Double>)]
	
	static func load(version: String, track: String) -> ColorTrack? {
		let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Silicon Client/Versions/\(version)/GeneratedData/data/minecraft/timeline/day.json")
		
		guard let data = try? Data(contentsOf: url),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let tracks = json["tracks"] as? [String: Any],
			  let entry = tracks[track] as? [String: Any],
			  let points = entry["keyframes"] as? [[String: Any]] else { return nil }
		
		let keyframes = points.compactMap { point -> (ticks: Int, color: SIMD4<Double>)? in
			guard let ticks = point["ticks"] as? Int,
				  let hex = point["value"] as? String,
				  let rgb = Int(hex.dropFirst(), radix: 16) else { return nil }
			
			let red   = Double((rgb >> 16) & 0xFF)
			let green = Double((rgb >> 8) & 0xFF)
			let blue  = Double(rgb & 0xFF)
			let alpha = hex.count == 9 ? Double((rgb >> 24) & 0xFF) : 255   // "#AARRGGBB" has strength in front
			return (ticks, SIMD4(red, green, blue, alpha) / 255)
		}
		
		return ColorTrack(keyframes: keyframes)
	}
	
	func color(at time: Int) -> SIMD4<Double> {
		let t = time % 24000                                         // time of day
		
		let i = keyframes.firstIndex { $0.ticks > t } ?? 0           // next point
		let after = keyframes[i]
		let before = keyframes[(i + keyframes.count - 1) % keyframes.count]  // previous point
		
		let span = (after.ticks - before.ticks + 24000) % 24000      // ticks between them
		let gone = (t - before.ticks + 24000) % 24000                // ticks since the previous one
		let progress = span == 0 ? 0 : Double(gone) / Double(span)   // 0…1
		
		return before.color + (after.color - before.color) * progress
	}
}
