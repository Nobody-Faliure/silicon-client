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

func buildSectionRenderMesh(
	from chunk: Chunk,
	sectionIndex: Int,
	device: MTLDevice,
	modelFolder: URL,
	blockStateFolder: URL,
	clientWorld: ClientWorld
) -> ChunkRenderMesh? {
	let verticesByTexture = ChunkMesher.buildSectionMesh(
		from: chunk,
		sectionIndex: sectionIndex,
		modelFolder: modelFolder,
		blockStateFolder: blockStateFolder,
		clientWorld: clientWorld
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
		for sectionIndex in 0..<chunk.sections.count {
			if let mesh = buildSectionRenderMesh(
				from: chunk,
				sectionIndex: sectionIndex,
				device: device,
				modelFolder: modelFolder,
				blockStateFolder: blockStateFolder,
				clientWorld: clientWorld
			) {
				chunkMeshes.append(mesh)
			}
		}
	}

	return chunkMeshes
}
