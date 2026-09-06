struct ChunkMesher {
	static func buildMesh(from chunk: Chunk) -> [Vertex] {
		var vertices: [Vertex] = []
		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {
					let block = chunk.getBlock(x: x, y: y, z: z)
					if (block == .stone) {
						let bx = Float(x)
						let by = Float(y)
						let bz = Float(z)

						// Front
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1))
						])

						// Back
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1))
						])

						// Left
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1))
						])

						// Right
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1))
						])

						// Top
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1))
						])

						// Bottom
						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(1, 1)),
							Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 0))
						])

						vertices.append(contentsOf: [
							Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 0)),
							Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 0)),
							Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1))
						])
					}
				}
			}
		}
		return vertices
	}
}


