import Foundation

// Turns the blocks in a chunk into triangles the GPU can draw.
//
// Minecraft describes a block across several JSON files, and this file walks
// that trail and flattens it into vertices:
//
//   blockstates/anvil.json   which drawing to use, and how it is turned
//         |                  ("facing=north" -> model "anvil", turned 180)
//         v
//   models/block/anvil.json  the drawing - but it mostly just says
//         |                  "I am a template_anvil with a different top"
//         v
//   models/block/template_anvil.json   the real shape: four boxes
//         |
//         v
//   models/block/block.json            the root; nothing more to inherit
//
// The structs below mirror those files one-for-one so JSONDecoder can read
// them. The functions further down do the walking, merging and triangle
// building.

// One models/block/*.json file.
// Every field is optional because a file may inherit instead of declaring:
// anvil.json has only a parent and one texture, and gets its shape from
// template_anvil.json further up the chain.
struct MinecraftModel: Decodable {
	let parent: String?                      // the file this one inherits from
	let textures: [String: String]?          // nickname -> picture, e.g. "body" -> "block/anvil"
	let elements: [MinecraftModelElement]?   // the boxes making up the shape
}

// One box in a shape. A plain cube has a single element spanning the whole
// block; an anvil has four stacked boxes of different sizes.
struct MinecraftModelElement: Decodable {
	let from: [Float]                        // one corner of the box, 0–16 model space
	let to: [Float]                          // opposite corner
	let rotation: MinecraftElementRotation?  // optional tilt of this box
	let faces: [String: MinecraftModelFace]?
}

// One side of one box. A box may leave sides out entirely - the anvil's
// middle boxes have no "down" face, because nothing could ever see it.
struct MinecraftModelFace: Decodable {
	let texture: String    // "#top" — which image
	let uv: [Float]?       // [x1,y1,x2,y2] slice of the texture; absent → whole texture
	let rotation: Int?     // 0/90/180/270 spin; absent → 0
	let cullface: String?  // side name; only cull this face if set
	let tintindex: Int?    // biome tint flag; absent → none
}

// An angled box, used by torches, levers and buttons.
// Read from the file but not used yet - nothing that tilts is drawn.
struct MinecraftElementRotation: Decodable {
	let origin: [Float]    // pivot point [x,y,z]
	let axis: String       // "x" | "y" | "z"
	let angle: Float       // -45,-22.5,0,22.5,45
	let rescale: Bool?     // absent → false
}

// The finished answer for one block, after the whole inheritance chain has
// been collapsed into a single shape plus a single picture lookup.
// This is what the triangle-building code actually reads.
struct ResolvedModel {
	let textures: [String: String]     // nicknames fully merged, child wins
	let elements: [MinecraftModelElement]   // the winning shape
}

// One blockstates/*.json file: every placement a block can have.
// The keys are property lists, so anvil.json has four entries keyed
// "facing=north", "facing=east", "facing=south", "facing=west".
struct MinecraftBlockState: Decodable {
	  let variants: [String: VariantChoice]
}

// A variant entry is either one model, or a list Minecraft picks from so
// large areas of stone don't look tiled. Keep them all; picking comes later.
struct VariantChoice: Decodable {
	  let options: [MinecraftBlockStateVariant]

	  init(from decoder: Decoder) throws {
			  let container = try decoder.singleValueContainer()

			  if let single = try? container.decode(MinecraftBlockStateVariant.self) {
					  options = [single]
					  return
			  }

			  options = try container.decode([MinecraftBlockStateVariant].self)
	  }
}

// What one placement resolves to: which drawing, and how far it is spun.
struct MinecraftBlockStateVariant: Decodable {
	let model: String   // e.g. "minecraft:block/anvil"
	let x: Int?         // tilt in degrees, absent means 0
	let y: Int?         // spin in degrees, absent means 0
}

struct ChunkMesher {
	// It needs a type and a starting value, e.g.
	static var modelCache: [String: ResolvedModel] = [:]
	static var variantCache: [URL: MinecraftBlockState] = [:]
	
	// Same position always picks the same option, so stone never reshuffles
	  static func variantIndex(x: Int, y: Int, z: Int, count: Int) -> Int {
		  if count == 1 { return 0 }

		  var h = UInt64(bitPattern: Int64(x &* 3129871))
			  ^ UInt64(bitPattern: Int64(z &* 116129781))
			  ^ UInt64(bitPattern: Int64(y))

		  h = h &* h &* 42317861 &+ h &* 11

		  return Int((h >> 16) % UInt64(count))
	  }
	
	// Reads a blockstates/*.json file and picks the entry matching this
	// block's properties.
	//
	// For an anvil with ["facing": "north"] it scans the four entries and
	// returns the one keyed "facing=north" - model "anvil", spun 180.
	//
	// Gets the model name from the block ID
	static func variant(
		for blockState: BlockState,
		x: Int, y: Int, z: Int,
		blockStateFolder: URL
	) -> MinecraftBlockStateVariant {
		let blockName = blockState.block.id
			.replacingOccurrences(of: "minecraft:", with: "")
		
		let blockStateURL = blockStateFolder
			.appendingPathComponent(blockName)
			.appendingPathExtension("json")
		
		let blockStateJSON: MinecraftBlockState
		
		if let cached = variantCache[blockStateURL] {
			blockStateJSON = cached
		} else {
			blockStateJSON = loadJSON(
				from: blockStateURL,
				as: MinecraftBlockState.self
			)
			variantCache[blockStateURL] = blockStateJSON
		}
		
		let properties = blockState.properties
		let variants = blockStateJSON.variants
		
		// Check each entry until one matches every property we were given.
		// A key can list several, e.g. "facing=north,lit=true", and all of
		// them have to agree before the entry counts as a match.
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
				return variant.options[variantIndex(x: x, y: y, z: z, count: variant.options.count)]
			}
		}
		fatalError("No matching blockstate variant found for \(blockState.block.id)")
	}
	
	// Reads a file off the disk and turns its text into Swift values.
	//
	// This is the slow line in the whole file - opening and decoding takes
	// roughly 25 microseconds, and the mesher calls it thousands of times
	// per chunk unless results are remembered.
	//
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
	
	// Walks the inheritance trail and collects every file along it.
	//
	// Starting at anvil.json this returns
	//   [anvil, template_anvil, block]
	// in child-first order. Each step is another disk read.
	//
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
	
	// Squashes a chain collected above into one ResolvedModel.
	// Pure bookkeeping - reads nothing from disk.
	//
	// Not to be confused with resolvedModel(for:) below, which is the one
	// that does the loading. This one only merges what was already loaded.
	static func resolveModel(chain: [MinecraftModel]) -> ResolvedModel {
		// elements (shape): first model that has any wins, then stop
		// Shape: walk child-first and take the first file that declares one.
		// anvil.json declares none, template_anvil.json declares four boxes,
		// so those win and block.json is never consulted.
		var elements: [MinecraftModelElement] = []
		for model in chain {
			if let e = model.elements {
				elements = e
				break
			}
		}

		// textures (lookup table): merge every model's, child wins
		// Pictures: walk backwards, furthest ancestor first, letting each
		// file overwrite what came before. Because the child is written
		// last it wins - which is how the anvil keeps template_anvil's body
		// picture but swaps in its own anvil_top.
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
	
	// The full lookup for one block: find the drawing, load it, follow its
	// parents, merge them, hand back the finished shape and pictures.
	//
	// Every disk read for a block happens underneath this call, which makes
	// it the place worth remembering answers in.
	//
	// Loads and resolves the whole model for one block state
	static func resolvedModel(
		modelName: String,
		modelFolder: URL
	) -> ResolvedModel {
		if let cached = modelCache[modelName] {
			return cached
		}
		
		let cleanName = modelName
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
		
		let resolved = resolveModel(
				chain: modelChain(
						startingWith: model,
						modelFolder: modelFolder
			 )
		)

	 modelCache[modelName] = resolved
	 return resolved
	}
	
	// Turns a reference like "#body" into a real texture name
	// Follows nicknames until a real picture name falls out.
	// A face says "#body", the lookup says body -> "block/anvil", so that
	// is the answer. Loops because a nickname may point at another nickname.
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
	// Only a single box filling the block edge to edge can hide the face
	// behind it. An anvil cannot, which is why the ground under one still
	// draws its top face instead of leaving a hole.
	static func isFullCube(_ resolved: ResolvedModel) -> Bool {
		guard resolved.elements.count == 1,
			  let element = resolved.elements.first else {
			return false
		}
		
		return element.from == [0, 0, 0]
			&& element.to == [16, 16, 16]
			&& element.rotation == nil
	}
	
	// Turns a face name into the direction it points, used to find the
	// neighbouring block sitting against it.
	//
	// Careful: north is +Z here, the opposite of real Minecraft. The whole
	// file is consistent about it, so everything lines up, but it means this
	// world is a mirror image of the real game's.
	//
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
	
	// The four corners of one face, built from the box's two opposite
	// corners f and t.
	//
	// Order matters twice over: faceUVs() below hands back texture
	// coordinates in this same order, and buildMesh() relies on the
	// direction the corners travel to keep faces pointing outward.
	//
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
	// Which patch of the picture goes on this face, and which way up.
	//
	// The anvil leans on this heavily - nearly every one of its faces takes
	// a different slice of the same anvil.png, several of them turned. A
	// backwards slice like [4,2,0,14], where the first number is larger,
	// mirrors the picture, and that falls out of the arithmetic for free.
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
	
	// Walks every block in the chunk and produces the triangles for it.
	//
	// The returned dictionary is grouped by picture name because the
	// renderer can only bind one picture at a time - every face using
	// anvil.png is collected together so it can be drawn in one go.
	//
	// Builds visible chunk faces grouped by texture
	static func buildSectionMesh(
		from chunk: Chunk,
		sectionIndex: Int,
		modelFolder: URL,
		blockStateFolder: URL,
		clientWorld: ClientWorld
	) -> [String: [Vertex]] {
		
		// texture name -> vertices using that texture
		var verticesByTexture: [String: [Vertex]] = [:]
		
		let air = Block(id: "minecraft:air")
		
		// Decides whether a face can be skipped because something solid is
		// pressed against it. Skipping faces nobody can see is most of what
		// keeps the triangle count down.
		//
		// Off the edge of the chunk counts as not hidden, so boundary faces
		// are always drawn rather than being wrongly cut away.
		//
		// A face is only hidden when a full-size solid block sits against it
		func hidden(_ x: Int, _ y: Int, _ z: Int, _ dir: SIMD3<Float>) -> Bool {
			let nx = x + Int(dir.x), ny = y + Int(dir.y), nz = z + Int(dir.z)
			
			let neighbourChunkX = chunk.chunkX + (nx >> 4)
			let neighbourChunkZ = chunk.chunkZ + (nz >> 4)
			
			guard ny >= -64, ny < -64 + chunk.height else {
				return false        // outside the world - draw the face
			}
			
			guard let neighbourChunk = clientWorld.chunk(atX: neighbourChunkX, z: neighbourChunkZ) else {
				return false        // not loaded - draw the face
			}

			let neighbour = neighbourChunk.getBlockState(x: nx & 15, y: ny, z: nz & 15)
			
			if neighbour.block == air {
				return false
			}
			
			let nv = variant(for: neighbour, x: nx, y: ny, z: nz, blockStateFolder: blockStateFolder)
			return isFullCube(resolvedModel(modelName: nv.model, modelFolder: modelFolder))
		}
		
		// Visit every position in the section, one block at a time.
		let bottomY = -64 + sectionIndex * Section.height
		for y in bottomY..<bottomY + Section.height {
			for z in 0..<Section.depth {
				for x in 0..<Section.width {
					
					let blockState = chunk.getBlockState(x: x, y: y, z: z)
					
					if blockState.block == air {
						continue
					}
					
					// Two separate lookups: the spin comes from the blockstate
					// entry, the shape from the model files. Both read the
					// disk, and both repeat for every block in the chunk.
					let v = variant(for: blockState, x: x, y: y, z: z, blockStateFolder: blockStateFolder)
					let xRot = v.x ?? 0
					let yRot = v.y ?? 0
					
					let resolved = resolvedModel(modelName: v.model, modelFolder: modelFolder)
					
					// Block position in world coordinates
					let bx = Float(x + chunk.chunkX * Section.width)
					let by = Float(y)
					let bz = Float(z + chunk.chunkZ * Section.depth)
					
					// origin is the block's near-bottom-left corner, which the
					// box measurements are added onto. center is its middle,
					// which any spin turns around.
					let origin = SIMD3<Float>(bx, by, bz)
					let center = SIMD3<Float>(bx + 0.5, by + 0.5, bz + 0.5)
					
					// One pass per box. A cube has a single box; the anvil has
					// four, so a single anvil runs this four times.
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
						
						// Only the sides the box actually declares. A missing
						// side is simply absent here and never drawn.
						for (faceKey, face) in element.faces ?? [:] {
							
							// A face is a candidate for skipping only if the file
							// marked it as such. Most anvil faces are not marked,
							// because its boxes sit inside the block where a
							// neighbour could never cover them.
							//
							// The direction is spun first, so a block turned 180
							// checks the neighbour it is really facing.
							//
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
							
							// Matching lists: corner 0 pairs with uv 0, and so on.
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
	
	// Spins a point around a centre by whole quarter turns.
	//
	// Used two ways: on corners, to turn the shape itself, and on direction
	// vectors with a centre of zero, to work out which neighbour a turned
	// face ends up looking at.
	//
	// Whole quarter turns only, so no trigonometry is needed - the
	// coordinates just swap places and change sign.
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
