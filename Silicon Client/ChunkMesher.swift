import Foundation

// Minecraft model JSON
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

// Minecraft blockstate JSON
struct MinecraftBlockState: Decodable {
	let variants: [String: MinecraftBlockStateVariant]
}

struct MinecraftBlockStateVariant: Decodable {
	let model: String
}

struct ChunkMesher {
	// Gets the model name from the block ID
	static func modelName(
		for blockState: BlockState,
		blockStateFolder: URL
	) -> String {
		let blockName = blockState.block.id
			.replacingOccurrences(of: "minecraft:", with: "")
		
		let blockStateURL = blockStateFolder
			.appendingPathComponent(blockName)
			.appendingPathExtension("json")
		
		let blockStateJSON: MinecraftBlockState = loadJSON(
			from: blockStateURL,
			as: MinecraftBlockState.self
		)
		
		let properties = blockState.properties
		let variants = blockStateJSON.variants
		
		for (variantKey, variant) in variants {
			var matches = true
			for property in variantKey.split(separator: ",") {
				let parts = property.split(separator: "=", maxSplits: 1)
				if parts.count == 2 {
					let key = String(parts[0])
					let value = String(parts[1])
					
					if properties[key] != value {
						matches = false
						break
					}
				}
			}
			if matches {
				return variant.model
			}
		}
		fatalError("No matching blockstate variant found for \(blockState.block.id)")
	}
	
	// Loads one model JSON file
	// Loads and decodes any JSON file
	static func loadJSON<T: Decodable>(
		from url: URL,
		as type: T.Type
	) -> T {
		let data = try! Data(contentsOf: url)
		
		return try! JSONDecoder().decode(
			T.self,
			from: data
		)
	}
	
	// Follows parent models and stores the whole chain
	static func modelChain(
		startingWith model: MinecraftModel,
		modelFolder: URL
	) -> [MinecraftModel] {
		var chain = [model]
		var currentModel = model

		while let parentName = currentModel.parent {
			let cleanName = parentName
				.replacingOccurrences(of: "minecraft:", with: "")
				.replacingOccurrences(of: "block/", with: "")

			let modelURL = modelFolder
				.appendingPathComponent("block")
				.appendingPathComponent(cleanName)
				.appendingPathExtension("json")

			let parentModel: MinecraftModel = loadJSON(
				from: modelURL,
				as: MinecraftModel.self
			)

			chain.append(parentModel)
			currentModel = parentModel
		}

		return chain
	}
	
	// Finds the texture used by one block face
	static func textureName(
		for face: BlockFace,
		blockState: BlockState,
		blockStateFolder: URL,
		modelFolder: URL
	) -> String {
		let cleanName = modelName(for: blockState, blockStateFolder: blockStateFolder)
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")

		let modelURL = modelFolder
			.appendingPathComponent("block")
			.appendingPathComponent(cleanName)
			.appendingPathExtension("json")
		
		let model: MinecraftModel = loadJSON(
			from: modelURL,
			as: MinecraftModel.self
		)
		
		let chain = modelChain(
			startingWith: model,
			modelFolder: modelFolder
		)
		
		// Converts BlockFace to the JSON face name
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

		// Finds this face in the model chain
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
		
		// Resolves things like #side into the real texture
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
	
	// Builds visible chunk faces grouped by texture
	static func buildMesh(
		from chunk: Chunk,
		modelFolder: URL,
		blockStateFolder: URL
	) -> [String: [Vertex]] {
		
		// texture name -> vertices using that texture
		var verticesByTexture: [String: [Vertex]] = [:]

		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {

					let blockState = chunk.getBlockState(x: x, y: y, z: z)
					let block = blockState.block

					if block != Block(id: "minecraft:air") {
						
						// Block position in world coordinates
						let bx = Float(x + chunk.chunkX * Chunk.width)
						let by = Float(y)
						let bz = Float(z + chunk.chunkZ * Chunk.depth)

						// North face
						if z == Chunk.depth - 1 ||
							chunk.getBlock(x: x, y: y, z: z + 1) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .north,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// South face
						if z == 0 ||
							chunk.getBlock(x: x, y: y, z: z - 1) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .south,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(0, 1))
							])
						}

						// West face
						if x == 0 ||
							chunk.getBlock(x: x - 1, y: y, z: z) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .west,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx, by, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by, bz), uv: SIMD2<Float>(0, 1))
							])
						}

						// East face
						if x == Chunk.width - 1 ||
							chunk.getBlock(x: x + 1, y: y, z: z) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .east,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx + 1, by, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Top face
						if y == Chunk.height - 1 ||
							chunk.getBlock(x: x, y: y + 1, z: z) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .up,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz + 1), uv: SIMD2<Float>(1, 1)),
								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),

								Vertex(position: SIMD3<Float>(bx + 1, by + 1, bz), uv: SIMD2<Float>(1, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz), uv: SIMD2<Float>(0, 0)),
								Vertex(position: SIMD3<Float>(bx, by + 1, bz + 1), uv: SIMD2<Float>(0, 1))
							])
						}

						// Bottom face
						if y == 0 ||
							chunk.getBlock(x: x, y: y - 1, z: z) == Block(id: "minecraft:air") {

							verticesByTexture[
								textureName(
									for: .down,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
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
