import Foundation

// Minecraft model JSON
struct MinecraftModel: Decodable {
	let parent: String?
	let textures: [String: String]?
	let elements: [MinecraftModelElement]?
}

struct MinecraftModelElement: Decodable {
	let from: [Float]                        // one corner of the box, 0–16 model space
	let to: [Float]                          // opposite corner
	let rotation: MinecraftElementRotation?  // optional tilt of this box
	let faces: [String: MinecraftModelFace]?
}

struct MinecraftModelFace: Decodable {
	let texture: String    // "#top" — which image
	let uv: [Float]?       // [x1,y1,x2,y2] slice of the texture; absent → whole texture
	let rotation: Int?     // 0/90/180/270 spin; absent → 0
	let cullface: String?  // side name; only cull this face if set
	let tintindex: Int?    // biome tint flag; absent → none
}

struct MinecraftElementRotation: Decodable {
	let origin: [Float]    // pivot point [x,y,z]
	let axis: String       // "x" | "y" | "z"
	let angle: Float       // -45,-22.5,0,22.5,45
	let rescale: Bool?     // absent → false
}

struct ResolvedModel {
	let textures: [String: String]
	let elements: [MinecraftModelElement]
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
	
	static func resolveModel(chain: [MinecraftModel]) -> ResolvedModel {
		// elements (shape): first model that has any wins, then stop
		var elements: [MinecraftModelElement] = []
		for model in chain {
			if let e = model.elements {
				elements = e
				break
			}
		}

		// textures (lookup table): merge every model's, child wins
		var textures: [String: String] = [:]
		for model in chain.reversed() {
			if let t = model.textures {
				for (key, value) in t {
					textures[key] = value
				}
			}
		}

		return ResolvedModel(textures: textures, elements: elements)
	}
	
	// Loads and resolves the whole model for one block state
	static func resolvedModel(
		for blockState: BlockState,
		blockStateFolder: URL,
		modelFolder: URL
	) -> ResolvedModel {
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
		
		return resolveModel(
			chain: modelChain(
				startingWith: model,
				modelFolder: modelFolder
			)
		)
	}
	
	// Turns a reference like "#body" into a real texture name
	static func resolveTexture(
		_ reference: String,
		in resolved: ResolvedModel
	) -> String {
		var reference = reference
		
		while reference.hasPrefix("#") {
			let key = String(reference.dropFirst())
			
			guard let next = resolved.textures[key] else {
				fatalError("No texture found for key \(key)")
			}
			
			reference = next
		}
		
		return reference
	}
	
	// True when the model is a single full-size box, so it hides whatever is behind it
	static func isFullCube(_ resolved: ResolvedModel) -> Bool {
		guard resolved.elements.count == 1,
			  let element = resolved.elements.first else {
			return false
		}
		
		return element.from == [0, 0, 0]
			&& element.to == [16, 16, 16]
			&& element.rotation == nil
	}
	
	// Which way a named face points
	static func direction(of faceKey: String) -> SIMD3<Float> {
		switch faceKey {
		case "up":    return SIMD3<Float>(0, 1, 0)
		case "down":  return SIMD3<Float>(0, -1, 0)
		case "north": return SIMD3<Float>(0, 0, 1)
		case "south": return SIMD3<Float>(0, 0, -1)
		case "east":  return SIMD3<Float>(1, 0, 0)
		case "west":  return SIMD3<Float>(-1, 0, 0)
		default:      return SIMD3<Float>(0, 0, 0)
		}
	}
	
	// The four corners of one element face, ordered top-left, top-right,
	// bottom-right, bottom-left as seen from outside the block
	static func corners(
		faceKey: String,
		from f: SIMD3<Float>,
		to t: SIMD3<Float>
	) -> [SIMD3<Float>] {
		switch faceKey {
		case "north":
			return [
				SIMD3<Float>(f.x, t.y, t.z),
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(t.x, f.y, t.z),
				SIMD3<Float>(f.x, f.y, t.z)
			]
		case "south":
			return [
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(f.x, f.y, f.z),
				SIMD3<Float>(t.x, f.y, f.z)
			]
		case "west":
			return [
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(f.x, t.y, t.z),
				SIMD3<Float>(f.x, f.y, t.z),
				SIMD3<Float>(f.x, f.y, f.z)
			]
		case "east":
			return [
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(t.x, f.y, f.z),
				SIMD3<Float>(t.x, f.y, t.z)
			]
		case "up":
			return [
				SIMD3<Float>(f.x, t.y, f.z),
				SIMD3<Float>(t.x, t.y, f.z),
				SIMD3<Float>(t.x, t.y, t.z),
				SIMD3<Float>(f.x, t.y, t.z)
			]
		case "down":
			return [
				SIMD3<Float>(f.x, f.y, t.z),
				SIMD3<Float>(t.x, f.y, t.z),
				SIMD3<Float>(t.x, f.y, f.z),
				SIMD3<Float>(f.x, f.y, f.z)
			]
		default:
			return []
		}
	}
	
	// The texture coordinates matching corners(), after the face's own rotation.
	// uv is [x1, y1, x2, y2] in 0-16 texture space; absent means the whole image.
	static func faceUVs(_ face: MinecraftModelFace) -> [SIMD2<Float>] {
		let uv = face.uv ?? [0, 0, 16, 16]
		
		let u1 = uv[0] / 16, v1 = uv[1] / 16
		let u2 = uv[2] / 16, v2 = uv[3] / 16
		
		let base = [
			SIMD2<Float>(u1, v1),   // top-left
			SIMD2<Float>(u2, v1),   // top-right
			SIMD2<Float>(u2, v2),   // bottom-right
			SIMD2<Float>(u1, v2)    // bottom-left
		]
		
		// Spinning the texture clockwise moves each corner's coordinate back one place
		let steps = (((face.rotation ?? 0) / 90) % 4 + 4) % 4
		let offset = (4 - steps) % 4
		
		return (0..<4).map { base[($0 + offset) % 4] }
	}
	
	// Builds visible chunk faces grouped by texture
	static func buildMesh(
		from chunk: Chunk,
		modelFolder: URL,
		blockStateFolder: URL
	) -> [String: [Vertex]] {
		
		// texture name -> vertices using that texture
		var verticesByTexture: [String: [Vertex]] = [:]
		
		let air = Block(id: "minecraft:air")
		
		// A face is only hidden when a full-size solid block sits against it
		func hidden(_ x: Int, _ y: Int, _ z: Int, _ dir: SIMD3<Float>) -> Bool {
			let nx = x + Int(dir.x), ny = y + Int(dir.y), nz = z + Int(dir.z)
			
			guard nx >= 0, nx < Chunk.width,
				  ny >= 0, ny < Chunk.height,
				  nz >= 0, nz < Chunk.depth else {
				return false
			}
			
			let neighbour = chunk.getBlockState(x: nx, y: ny, z: nz)
			
			if neighbour.block == air {
				return false
			}
			
			return isFullCube(
				resolvedModel(
					for: neighbour,
					blockStateFolder: blockStateFolder,
					modelFolder: modelFolder
				)
			)
		}
		
		for y in 0..<Chunk.height {
			for z in 0..<Chunk.depth {
				for x in 0..<Chunk.width {
					
					let blockState = chunk.getBlockState(x: x, y: y, z: z)
					
					if blockState.block == air {
						continue
					}
					
					let v = variant(for: blockState, blockStateFolder: blockStateFolder)
					let xRot = v.x ?? 0
					let yRot = v.y ?? 0
					
					let resolved = resolvedModel(
						for: blockState,
						blockStateFolder: blockStateFolder,
						modelFolder: modelFolder
					)
					
					// Block position in world coordinates
					let bx = Float(x + chunk.chunkX * Chunk.width)
					let by = Float(y)
					let bz = Float(z + chunk.chunkZ * Chunk.depth)
					
					let origin = SIMD3<Float>(bx, by, bz)
					let center = SIMD3<Float>(bx + 0.5, by + 0.5, bz + 0.5)
					
					for element in resolved.elements {
						
						// Model space runs 0-16 across the block
						let f = origin + SIMD3<Float>(
							element.from[0],
							element.from[1],
							element.from[2]
						) / 16
						
						let t = origin + SIMD3<Float>(
							element.to[0],
							element.to[1],
							element.to[2]
						) / 16
						
						for (faceKey, face) in element.faces ?? [:] {
							
							// Only faces that ask to be culled are ever dropped
							if let cullface = face.cullface {
								let dir = rotate(
									xRot,
									yRot,
									around: SIMD3<Float>(0, 0, 0),
									direction(of: cullface)
								)
								
								if hidden(x, y, z, dir) {
									continue
								}
							}
							
							let positions = corners(faceKey: faceKey, from: f, to: t)
							
							if positions.isEmpty {
								continue
							}
							
							let uvs = faceUVs(face)
							let texture = resolveTexture(face.texture, in: resolved)
							
							// Two triangles covering the quad, wound so the
							// outside face survives setCullMode(.back)
							for i in [0, 3, 2, 2, 1, 0] {
								verticesByTexture[texture, default: []].append(
									Vertex(
										position: rotate(xRot, yRot, around: center, positions[i]),
										uv: uvs[i]
									)
								)
							}
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
