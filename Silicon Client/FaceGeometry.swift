import Foundation
import simd

extension ChunkMesher {
	// Spins a point around a centre by whole quarter turns.
	//
	// Used two ways: on corners, to turn the shape itself, and on direction
	// vectors with a centre of zero, to work out which neighbour a turned
	// face ends up looking at.
	//
	// Whole quarter turns only, so no trigonometry is needed - the
	// coordinates just swap places and change sign.
	static func rotate(_ xRot: Int, _ yRot: Int, around c: SIMD3<Float>, _ pos: SIMD3<Float>) -> SIMD3<Float> {
		var d = pos - c
		switch xRot {                                  // tilt around X axis (leaves d.x alone)
		case 90:  d = SIMD3<Float>(d.x, -d.z,  d.y)
		case 180: d = SIMD3<Float>(d.x, -d.y, -d.z)
		case 270: d = SIMD3<Float>(d.x,  d.z, -d.y)
		default:  break
		}
		switch yRot {                                  // spin around Y axis (leaves d.y alone)
		case 90:  d = SIMD3<Float>( d.z, d.y, -d.x)
		case 180: d = SIMD3<Float>(-d.x, d.y, -d.z)
		case 270: d = SIMD3<Float>(-d.z, d.y,  d.x)
		default:  break
		}
		return c + d
	}
	
	// Turns a face name into the direction it points, used to find the
	// neighbouring block sitting against it.
	//
	// Careful: north is +Z here, the opposite of real Minecraft. The whole
	// file is consistent about it, so everything lines up, but it means this
	// world is a mirror image of the real game's.
	//
	// Which way a named face points
	static func direction(of faceKey: String) -> SIMD3<Float> {
		switch faceKey {
		case "up":    return SIMD3<Float>(0, 1, 0)
		case "down":  return SIMD3<Float>(0, -1, 0)
		case "north": return SIMD3<Float>(0, 0, 1)
		case "south": return SIMD3<Float>(0, 0, -1)
		case "east":  return SIMD3<Float>(1, 0, 0)
		case "west":  return SIMD3<Float>(-1, 0, 0)
		default:      return SIMD3<Float>(0, 0, 0)
		}
	}
	
	// The four corners of one face, built from the box's two opposite
	// corners f and t.
	//
	// Order matters twice over: faceUVs() below hands back texture
	// coordinates in this same order, and buildMesh() relies on the
	// direction the corners travel to keep faces pointing outward.
	//
	// The four corners of one element face, ordered top-left, top-right,
	// bottom-right, bottom-left as seen from outside the block
	static func corners(
		faceKey: String,
		from f: SIMD3<Float>,
		to t: SIMD3<Float>
	) -> [SIMD3<Float>] {
		switch faceKey {
		case "north":
			return [
				SIMD3<Float>(f.x, t.y, t.z),
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(t.x, f.y, t.z),
				SIMD3<Float>(f.x, f.y, t.z)
			]
		case "south":
			return [
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(f.x, f.y, f.z),
				SIMD3<Float>(t.x, f.y, f.z)
			]
		case "west":
			return [
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(f.x, t.y, t.z),
				SIMD3<Float>(f.x, f.y, t.z),
				SIMD3<Float>(f.x, f.y, f.z)
			]
		case "east":
			return [
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(t.x, f.y, f.z),
				SIMD3<Float>(t.x, f.y, t.z)
			]
		case "up":
			return [
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(f.x, t.y, t.z)
			]
		case "down":
			return [
				SIMD3<Float>(f.x, f.y, t.z),
				SIMD3<Float>(t.x, f.y, t.z),
				SIMD3<Float>(t.x, f.y, f.z),
				SIMD3<Float>(f.x, f.y, f.z)
			]
		default:
			return []
		}
	}
	
	// The texture coordinates matching corners(), after the face's own rotation.
	// uv is [x1, y1, x2, y2] in 0-16 texture space; absent means the whole image.
	// Which patch of the picture goes on this face, and which way up.
	//
	// The anvil leans on this heavily - nearly every one of its faces takes
	// a different slice of the same anvil.png, several of them turned. A
	// backwards slice like [4,2,0,14], where the first number is larger,
	// mirrors the picture, and that falls out of the arithmetic for free.
	static func faceUVs(_ face: MinecraftModelFace) -> [SIMD2<Float>] {
		let uv = face.uv ?? [0, 0, 16, 16]
		
		let u1 = uv[0] / 16, v1 = uv[1] / 16
		let u2 = uv[2] / 16, v2 = uv[3] / 16
		
		let base = [
			SIMD2<Float>(u1, v1),   // top-left
			SIMD2<Float>(u2, v1),   // top-right
			SIMD2<Float>(u2, v2),   // bottom-right
			SIMD2<Float>(u1, v2)    // bottom-left
		]
		
		// Spinning the texture clockwise moves each corner's coordinate back one place
		let steps = (((face.rotation ?? 0) / 90) % 4 + 4) % 4
		let offset = (4 - steps) % 4
		
		return (0..<4).map { base[($0 + offset) % 4] }
	}
	
	static func shade(of faceKey: String) -> Float {
		switch faceKey {
		case "up":             return 1.0
		case "north", "south": return 0.8
		case "east",  "west":  return 0.6
		case "down":           return 0.5
		default:               return 1.0
		}
	}
}
