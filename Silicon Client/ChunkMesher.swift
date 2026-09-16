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
	let x: Int?
	let y: Int?
}

struct ChunkMesher {
	// Gets the model name from the block ID
	static func variant(
		for blockState: BlockState,
		blockStateFolder: URL
	) -> MinecraftBlockStateVariant {
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
				return variant
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
		let cleanName = variant(for: blockState, blockStateFolder: blockStateFolder).model
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
		
		func exposed(_ x: Int, _ y: Int, _ z: Int, _ dir: SIMD3<Float>) -> Bool {
			let nx = x + Int(dir.x), ny = y + Int(dir.y), nz = z + Int(dir.z)
			guard nx >= 0, nx < Chunk.width, ny >= 0, ny < Chunk.height, nz >= 0, nz < Chunk.depth else {
				return true
			}
			return chunk.getBlock(x: nx, y: ny, z: nz) == Block(id: "minecraft:air")
		}

		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {

					let blockState = chunk.getBlockState(x: x, y: y, z: z)
					let block = blockState.block

					if block != Block(id: "minecraft:air") {
						let v = variant(for: blockState, blockStateFolder: blockStateFolder)
						let xRot = v.x ?? 0
						let yRot = v.y ?? 0
						
						// Block position in world coordinates
						let bx = Float(x + chunk.chunkX * Chunk.width)
						let by = Float(y)
						let bz = Float(z + chunk.chunkZ * Chunk.depth)
						
						let center = SIMD3<Float>(bx + 0.5, by + 0.5, bz + 0.5)

						// North face
						if z == Chunk.depth - 1 ||
							exposed(x, y, z, rotate(xRot, yRot,around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 1))) {

							verticesByTexture[
								textureName(
									for: .north,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz + 1)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz + 1)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz + 1)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz + 1)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz + 1)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz + 1)), uv: SIMD2<Float>(0, 1))
							])
						}

						// South face
						if z == 0 ||
							exposed(x, y, z, rotate(xRot, yRot,around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, -1))) {

							verticesByTexture[
								textureName(
									for: .south,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz)), uv: SIMD2<Float>(0, 1))
							])
						}

						// West face
						if x == 0 ||
							exposed(x, y, z, rotate(xRot, yRot,around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(-1, 0, 0))) {

							verticesByTexture[
								textureName(
									for: .west,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz + 1)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz + 1)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz + 1)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz)), uv: SIMD2<Float>(0, 1))
							])
						}

						// East face
						if x == Chunk.width - 1 ||
							exposed(x, y, z, rotate(xRot, yRot,around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0))) {

							verticesByTexture[
								textureName(
									for: .east,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz + 1)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz + 1)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz + 1)), uv: SIMD2<Float>(0, 1))
							])
							
						}

						// Top face
						if y == Chunk.height - 1 ||
							exposed(x, y, z, rotate(xRot, yRot,around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 1, 0))) {

							verticesByTexture[
								textureName(
									for: .up,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot, around: center, SIMD3<Float>(bx, by + 1, bz + 1)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz + 1)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by + 1, bz)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by + 1, bz + 1)), uv: SIMD2<Float>(0, 1))
							])
						}

						// Bottom face
						if y == 0 ||
							exposed(x, y, z, rotate(xRot, yRot, around: SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, -1, 0))) {

							verticesByTexture[
								textureName(
									for: .down,
									blockState: blockState, blockStateFolder: blockStateFolder,
									modelFolder: modelFolder
								),
								default: []
							].append(contentsOf: [
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz)), uv: SIMD2<Float>(0, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz)), uv: SIMD2<Float>(1, 1)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz + 1)), uv: SIMD2<Float>(1, 0)),

								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx + 1, by, bz + 1)), uv: SIMD2<Float>(1, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz + 1)), uv: SIMD2<Float>(0, 0)),
								Vertex(position: rotate(xRot, yRot,around: center, SIMD3<Float>(bx, by, bz)), uv: SIMD2<Float>(0, 1))
							])
						}
					}
				}
			}
		}

		return verticesByTexture
	}
	static func rotate(_ xRot: Int, _ yRot: Int, around c: SIMD3<Float>, _ pos: SIMD3<Float>) -> SIMD3<Float> {
		var d = pos - c
		switch xRot {                                  // tilt around X axis (leaves d.x alone)
		case 90:  d = SIMD3<Float>(d.x, -d.z,  d.y)
		case 180: d = SIMD3<Float>(d.x, -d.y, -d.z)
		case 270: d = SIMD3<Float>(d.x,  d.z, -d.y)
		default:  break
		}
		switch yRot {                                  // spin around Y axis (leaves d.y alone)
		case 90:  d = SIMD3<Float>( d.z, d.y, -d.x)
		case 180: d = SIMD3<Float>(-d.x, d.y, -d.z)
		case 270: d = SIMD3<Float>(-d.z, d.y,  d.x)
		default:  break
		}
		return c + d
	}
}
