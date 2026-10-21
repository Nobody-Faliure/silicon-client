import Metal
import Foundation
import simd

struct SectionMaterialMesh {
	let textureName: String
	let vertexBuffer: MTLBuffer
	let vertexCount: Int
	var texture: MTLTexture? = nil
}

struct SectionRenderMesh {
	let chunkX: Int
	let chunkZ: Int
	let sectionIndex: Int
	var materials: [SectionMaterialMesh]
	var translucentMaterials: [SectionMaterialMesh]
	let corners: [SIMD3<Float>]
	
	// The 8 corners of this section, in world coordinates.
	static func cornersOf(chunkX: Int, chunkZ: Int, sectionIndex: Int) -> [SIMD3<Float>] {
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
	let mesh = ChunkMesher.buildSectionMesh(
		from: chunk,
		sectionIndex: sectionIndex,
		modelFolder: modelFolder,
		blockStateFolder: blockStateFolder,
		clientWorld: clientWorld
	)
	
	if mesh.opaque.isEmpty && mesh.translucent.isEmpty {
		return nil
	}
	
	func materials(from verticesByTexture: [String: [Vertex]]) -> [SectionMaterialMesh] {
		var result: [SectionMaterialMesh] = []
		
		for (textureName, textureVertices) in verticesByTexture {
			let vertexBuffer = device.makeBuffer(
				bytes: textureVertices,
				length: textureVertices.count * MemoryLayout<Vertex>.stride
			)!
			
			result.append(SectionMaterialMesh(
				textureName: textureName,
				vertexBuffer: vertexBuffer,
				vertexCount: textureVertices.count
			))
		}
		
		return result.sorted { !$0.textureName.contains("overlay") && $1.textureName.contains("overlay") }
	}
	
	return SectionRenderMesh(
		chunkX: chunk.chunkX,
		chunkZ: chunk.chunkZ,
		sectionIndex: sectionIndex,
		materials: materials(from: mesh.opaque),
		translucentMaterials: materials(from: mesh.translucent),
		corners: SectionRenderMesh.cornersOf(chunkX: chunk.chunkX, chunkZ: chunk.chunkZ, sectionIndex: sectionIndex)
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
