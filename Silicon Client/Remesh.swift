import Metal
import Foundation

struct ChunkMaterialMesh {
	let textureName: String
	let vertexBuffer: MTLBuffer
	let vertexCount: Int
}

struct ChunkRenderMesh {
	let chunkX: Int
	let chunkZ: Int
	let materials: [ChunkMaterialMesh]
}

func buildChunkRenderMesh(
	from chunk: Chunk,
	device: MTLDevice,
	modelFolder: URL,
	blockStateFolder: URL
) -> ChunkRenderMesh? {
	let verticesByTexture = ChunkMesher.buildMesh(
		from: chunk,
		modelFolder: modelFolder,
		blockStateFolder: blockStateFolder
	)
	
	var materials: [ChunkMaterialMesh] = []

	if verticesByTexture.isEmpty {
		return nil
	}
	for (textureName, textureVertices) in verticesByTexture {
		let vertexBuffer = device.makeBuffer(
			bytes: textureVertices,
			length: textureVertices.count * MemoryLayout<Vertex>.stride
		)!
		materials.append(
			ChunkMaterialMesh(
				textureName: textureName,
				vertexBuffer: vertexBuffer,
				vertexCount: textureVertices.count
			)
		)
	}
	

	return ChunkRenderMesh(
		chunkX: chunk.chunkX,
		chunkZ: chunk.chunkZ,
		materials: materials
	)
}

func buildWorldMeshes(
	from clientWorld: ClientWorld,
	device: MTLDevice,
	modelFolder: URL,
	blockStateFolder: URL
) -> [ChunkRenderMesh] {
	var chunkMeshes: [ChunkRenderMesh] = []

	for chunk in clientWorld.chunks {
		if let mesh = buildChunkRenderMesh(
			from: chunk,
			device: device,
			modelFolder: modelFolder,
			blockStateFolder: blockStateFolder
		) {
			chunkMeshes.append(mesh)
		}
	}

	return chunkMeshes
}
