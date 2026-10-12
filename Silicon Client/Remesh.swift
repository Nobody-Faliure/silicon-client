import Metal
import Foundation
import simd

struct SectionMaterialMesh {
	let textureName: String
	let vertexBuffer: MTLBuffer
	let vertexCount: Int
}

struct SectionRenderMesh {
	let chunkX: Int
	let chunkZ: Int
	let sectionIndex: Int
	let materials: [SectionMaterialMesh]
	
	// The 8 corners of this section, in world coordinates.
	var corners: [SIMD3<Float>] {
		let minX = Float(chunkX * 16)
		let minY = Float(-64 + sectionIndex * 16)
		let minZ = Float(chunkZ * 16)
		
		var result: [SIMD3<Float>] = []
		for x in [minX, minX + 16] {
			for y in [minY, minY + 16] {
				for z in [minZ, minZ + 16] {
					result.append(SIMD3<Float>(x, y, z))
				}
			}
		}
		return result
	}
}

func buildSectionRenderMesh(
	from chunk: Chunk,
	sectionIndex: Int,
	device: MTLDevice,
	modelFolder: URL,
	blockStateFolder: URL,
	clientWorld: ClientWorld
) -> SectionRenderMesh? {
	let verticesByTexture = ChunkMesher.buildSectionMesh(
		from: chunk,
		sectionIndex: sectionIndex,
		modelFolder: modelFolder,
		blockStateFolder: blockStateFolder,
		clientWorld: clientWorld
	)
	
	var materials: [SectionMaterialMesh] = []

	if verticesByTexture.isEmpty {
		return nil
	}
	for (textureName, textureVertices) in verticesByTexture {
		let vertexBuffer = device.makeBuffer(
			bytes: textureVertices,
			length: textureVertices.count * MemoryLayout<Vertex>.stride
		)!
		materials.append(
			SectionMaterialMesh(
				textureName: textureName,
				vertexBuffer: vertexBuffer,
				vertexCount: textureVertices.count
			)
		)
	}
	

	return SectionRenderMesh(
		chunkX: chunk.chunkX,
		chunkZ: chunk.chunkZ,
		sectionIndex: sectionIndex,
		materials: materials
	)
}

func buildWorldMeshes(
	from clientWorld: ClientWorld,
	device: MTLDevice,
	modelFolder: URL,
	blockStateFolder: URL
) -> [SectionRenderMesh] {
	var sectionMeshes: [SectionRenderMesh] = []

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
				sectionMeshes.append(mesh)
			}
		}
	}

	return sectionMeshes
}
