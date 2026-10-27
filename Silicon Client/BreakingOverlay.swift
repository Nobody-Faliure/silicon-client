import Foundation

extension Renderer {
	func breakingOverlayVertices(at block: SIMD3<Int>) -> [Vertex] {
		guard let modelFolder, let blockStateFolder,
			  let blockID = clientWorld.blockID(worldX: block.x, y: block.y, worldZ: block.z)
				else { return [] }
		let info = BlockInfoTable.info(
			blockID,
			blockStateFolder: blockStateFolder,
			modelFolder: modelFolder
		)
		guard let options = info.variants?.options else { return [] }
		
		let variant = options[ChunkMesher.variantIndex(
			x: block.x & 15,
			y: block.y,
			z: block.z & 15,
			count: options.count
		)]
		
		let model = ChunkMesher.resolvedModel(
			modelName: variant.model,
			modelFolder: modelFolder
		)
		let origin = SIMD3<Float>(block)
		let center = origin + 0.5
		
		var vertices: [Vertex] = []
		for element in model.elements {
			let from = origin + SIMD3<Float>(element.from) / 16
			let to = origin + SIMD3<Float>(element.to) / 16
			for faceKey in (element.faces ?? [:]).keys {
				let corners = ChunkMesher.corners(faceKey: faceKey, from: from, to: to).map {
					ChunkMesher.rotate(variant.x ?? 0, variant.y ?? 0, around: center, $0)
				}
				let flatAxis = corners[0].x == corners[2].x ? 0
					: corners[0].y == corners[2].y ? 1
					: 2
				for index in [0, 3, 2, 2, 1, 0] {
					let local = corners[index] - origin
					let picture = flatAxis == 0 ? SIMD2<Float>(local.z, 1 - local.y)
						: flatAxis == 1 ? SIMD2<Float>(local.x, local.z)
						: SIMD2<Float>(local.x, 1 - local.y)
					vertices.append(Vertex(
						position: corners[index], origin: origin, uv: picture,
						tint: SIMD3<Float>(1, 1, 1), shade: 1, depthBias: 0.0002
					))
				}
			}
		}
		return vertices
	}
}
