import Foundation

struct MinecraftModel: Decodable {
	let parent: String?
	let textures: [String: String]?
	let elements: [MinecraftModelElement]?
}

struct MinecraftModelElement: Decodable {
	let faces: [String: MinecraftModelFace]?
}

struct MinecraftModelFace: Decodable {
	let texture: String

}

struct ChunkMesher {
	static func modelName(for blockState: BlockState) -> String {
		return blockState.block.id
	}
	
	static func loadModel(
		named modelName: String,
		modelFolder: URL
	) -> MinecraftModel {
		let cleanName = modelName
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")
		
		let modelURL = modelFolder
			.appendingPathComponent("block")
			.appendingPathComponent(cleanName)
			.appendingPathExtension("json")
		
		let data = try! Data(contentsOf: modelURL)
		
		return try! JSONDecoder().decode(
			MinecraftModel.self,
			from: data
		)
	}
	
	static func modelChain(
		startingWith model: MinecraftModel,
		modelFolder: URL
	) -> [MinecraftModel] {
		var chain = [model]
		var currentModel = model

		while let parentName = currentModel.parent {
			let parentModel = loadModel(
				named: parentName,
				modelFolder: modelFolder
			)

			chain.append(parentModel)
			currentModel = parentModel
		}

		return chain
	}
	
	static func textureName(
		for face: BlockFace,
		blockState: BlockState,
		modelFolder: URL
	) -> String {
		let model = loadModel(
			named: modelName(for: blockState),
			modelFolder: modelFolder
		)
		
		let chain = modelChain(
			startingWith: model,
			modelFolder: modelFolder
		)
		
		let faceKey: String

		switch face {
		case .north: faceKey = "north"
		case .south: faceKey = "south"
		case .west: faceKey = "west"
		case .east: faceKey = "east"
		case .up: faceKey = "up"
		case .down: faceKey = "down"
		}
		
		var textureReference: String?

		for model in chain {
			if let elements = model.elements,
			   let firstElement = elements.first,
			   let face = firstElement.faces?[faceKey] {
				textureReference = face.texture
				break
			}
		}
		
		guard var reference = textureReference else {
			fatalError("No texture reference found for face \(faceKey)")
		}
		
		while reference.hasPrefix("#") {
			let key = String(reference.dropFirst())
			var nextReference: String?
			for model in chain {
				if let value = model.textures?[key] {
					nextReference = value
					break
				}
			}
			guard let foundReference = nextReference else {
				fatalError("No texture found for key \(key)")
			}
			reference = foundReference
		}
		return reference
	}
	
	static func buildMesh(
		from chunk: Chunk,
		modelFolder: URL
	) -> [String: [Vertex]] {
		var verticesByTexture: [String: [Vertex]] = [:]

		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {

					let blockState = chunk.getBlockState(x: x, y: y, z: z)
					let block = blockState.block

					if block != .air {
						let bx = Float(x + chunk.chunkX * Chunk.width)
						let by = Float(y)
						let bz = Float(z + chunk.chunkZ * Chunk.depth)

						// Front (-Z)
						if z == Chunk.depth - 1 ||
							chunk.getBlock(x: x, y: y, z: z + 1) == .air {

							verticesByTexture[textureName(for : .north, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Back (+Z)
						if z == 0 ||
							chunk.getBlock(x: x, y: y, z: z - 1) == .air {

							verticesByTexture[textureName(for : .south, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
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

							verticesByTexture[textureName(for : .west, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
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

							verticesByTexture[textureName(for : .east, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
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

							verticesByTexture[textureName(for : .up, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
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

							verticesByTexture[textureName(for : .down, blockState: blockState, modelFolder: modelFolder), default: []].append(contentsOf: [
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
