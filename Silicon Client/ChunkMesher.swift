struct ChunkMesher {
	static func buildMesh(
		from chunk: Chunk,
		registry: BlockRegistry
	) -> [String: [Vertex]] {
		var verticesByTexture: [String: [Vertex]] = [:]

		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {

					let block = chunk.getBlock(x: x, y: y, z: z)

					if block != .air,
					   let definition = registry.definition(for: block){
						let bx = Float(x + chunk.chunkX * Chunk.width)
						let by = Float(y)
						let bz = Float(z + chunk.chunkZ * Chunk.depth)

						// Front (+Z)
						if z == Chunk.depth - 1 ||
							chunk.getBlock(x: x, y: y, z: z + 1) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Back (-Z)
						if z == 0 ||
							chunk.getBlock(x: x, y: y, z: z - 1) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1))
							])
						}

						// Left (-X)
						if x == 0 ||
							chunk.getBlock(x: x - 1, y: y, z: z) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1))
							])
						}

						// Right (+X)
						if x == Chunk.width - 1 ||
							chunk.getBlock(x: x + 1, y: y, z: z) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Top (+Y)
						if y == Chunk.height - 1 ||
							chunk.getBlock(x: x, y: y + 1, z: z) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Bottom (-Y)
						if y == 0 ||
							chunk.getBlock(x: x, y: y - 1, z: z) == .air {

							verticesByTexture[definition.textureName, default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1))
							])
						}
					}
				}
			}
		}

		return verticesByTexture
	}
}
