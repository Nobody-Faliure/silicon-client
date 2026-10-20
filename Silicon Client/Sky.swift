import simd

enum Sky {
	// Vanilla's sun fan on the horizon: east for sunrise, west for sunset.
	// xyz = where, w = strength (1 middle, 0 edge).
	static func sunFan(east: Bool, strength: Float) -> [SIMD4<Float>] {
		let side: Float = east ? 1 : -1                          // +x is east, -x is west
		let center = SIMD4<Float>(100 * side, 0, 0, 1)
		
		var ring: [SIMD4<Float>] = []
		for i in 0...16 {
			let a = Float(i) * 2 * .pi / 16
			ring.append(SIMD4(120 * side * cos(a), 40 * strength * cos(a), 120 * sin(a), 0))
		}
		
		var triangles: [SIMD4<Float>] = []
		for i in 0..<16 {
			triangles += [center, ring[i], ring[i + 1]]
		}
		return triangles
	}
}
