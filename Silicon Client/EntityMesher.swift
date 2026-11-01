import simd

// One corner, ready for the GPU. Must match EntityVertex in Shaders.metal.
struct EntityVertex {
	var position: SIMD3<Float>
	var uv: SIMD2<Float>
	var part: UInt32
}

enum EntityMesher {
	// Turns one model into GPU corners: every face becomes 2 triangles.
	static func buildMesh(model: EntityModel) -> [EntityVertex] {
		var vertices: [EntityVertex] = []
		for partNumber in 0..<model.parts.count {
			for face in model.parts[partNumber].faces {
				for corner in [0, 1, 2, 0, 2, 3] {
					let start = corner * 5
					let position = SIMD3<Float>(face[start], face[start + 1], face[start + 2])
					let uv = SIMD2<Float>(face[start + 3], face[start + 4])
					vertices.append(EntityVertex(position: position, uv: uv, part: UInt32(partNumber)))
				}
			}
		}
		return vertices
	}
}
