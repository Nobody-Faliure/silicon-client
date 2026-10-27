import Foundation

extension Renderer {
	func blockModel(at block: SIMD3<Int>) -> (variant: MinecraftBlockStateVariant, model: ResolvedModel)? {
		guard let modelFolder, let blockStateFolder,
			  let blockID = clientWorld.blockID(worldX: block.x, y: block.y, worldZ: block.z)
				else { return nil }
		let info = BlockInfoTable.info(
			blockID,
			blockStateFolder: blockStateFolder,
			modelFolder: modelFolder
		)
		guard let options = info.variants?.options else { return nil }
		
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
		
		return (variant, model)
	}
	
	func outlineBoxes(at block: SIMD3<Int>) -> [(min: SIMD3<Float>, size: SIMD3<Float>)] {
		guard let shape = blockModel(at: block) else { return [] }
		let origin = SIMD3<Float>(block)
		let turnX = shape.variant.x ?? 0
		let turnY = shape.variant.y ?? 0
		
		let center = origin + 0.5
		return shape.model.elements.map { element in
			let from = origin + SIMD3<Float>(element.from) / 16
			let to = origin + SIMD3<Float>(element.to) / 16
			let turnedFrom = ChunkMesher.rotate(turnX, turnY, around: center, from)
			let turnedTo = ChunkMesher.rotate(turnX, turnY, around: center, to)
			let boxMin = pointwiseMin(turnedFrom, turnedTo)
			return (boxMin, pointwiseMax(turnedFrom, turnedTo) - boxMin)
		}
	}
	
	func breakingOverlayVertices(at block: SIMD3<Int>) -> [Vertex] {
		guard let shape = blockModel(at: block) else { return [] }
		let variant = shape.variant
		let model = shape.model
		
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
