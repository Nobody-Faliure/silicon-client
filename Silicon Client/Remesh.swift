import Metal

struct ChunkRenderMesh {
	let chunkX: Int
	let chunkZ: Int

	let vertexBuffer: MTLBuffer
	let vertexCount: Int
}

func buildChunkRenderMesh(
	from chunk: Chunk,
	device: MTLDevice
) -> ChunkRenderMesh? {
	let vertices = ChunkMesher.buildMesh(from: chunk)

	if vertices.isEmpty {
		return nil
	}

	let vertexBuffer = device.makeBuffer(
		bytes: vertices,
		length: vertices.count * MemoryLayout<Vertex>.stride
	)!

	return ChunkRenderMesh(
		chunkX: chunk.chunkX,
		chunkZ: chunk.chunkZ,
		vertexBuffer: vertexBuffer,
		vertexCount: vertices.count
	)
}

func buildWorldMeshes(
	from clientWorld: ClientWorld,
	device: MTLDevice
) -> [ChunkRenderMesh] {
	var chunkMeshes: [ChunkRenderMesh] = []

	for chunk in clientWorld.chunks {
		if let mesh = buildChunkRenderMesh(
			from: chunk,
			device: device
		) {
			chunkMeshes.append(mesh)
		}
	}

	return chunkMeshes
}
