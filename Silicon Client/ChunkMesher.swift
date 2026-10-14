import Foundation
import ImageIO

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

struct ChunkMesher {
	// It needs a type and a starting value, e.g.
	static var modelCache: [String: ResolvedModel] = [:]
	static var variantCache: [BlockState: VariantOptions] = [:]
	static var textureIsSolid: [String: Bool] = [:]
	static var textureFolder: URL?
	
	// Water and lava carry a "level" property. 0 is a source block, 1-7 are
	// flowing and get shorter as the number rises, 8 and above are falling
	// and render full. Returns nil for anything that is not a fluid.
	static func fluidHeight(of blockState: BlockState) -> Float? {
		let id = blockState.block.id
		
		guard id == "minecraft:water" || id == "minecraft:lava" else {
			return nil
		}
		
		let level = Int(blockState.properties["level"] ?? "0") ?? 0
		let amount = (level == 0 || level >= 8) ? 8 : 8 - level
		
		return Float(amount) / 9
	}
	
	static func brightness(ofLight level: Int) -> Float {
		let f = Float(level) / 15
		
		return max(f / (4 - 3 * f), 0.05)
	}
	
	static func isSolid(texture name: String) -> Bool {
		let bare = name
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")
		
		if let known = textureIsSolid[bare] { return known }
		
		guard let folder = textureFolder else { return false }
		
		let url = folder.appendingPathComponent(bare).appendingPathExtension("png")
		
		var solid = false
		if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
		   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
			solid = (properties[kCGImagePropertyHasAlpha] as? Bool) != true
		}
		
		textureIsSolid[bare] = solid
		return solid
	}
	
	// True when the model is a single full-size box, so it hides whatever is behind it
	// Only a single box filling the block edge to edge can hide the face
	// behind it. An anvil cannot, which is why the ground under one still
	// draws its top face instead of leaving a hole.
	static func hidesNeighbours(_ resolved: ResolvedModel) -> Bool {
		for element in resolved.elements {
			guard element.from == [0, 0, 0],
				  element.to == [16, 16, 16],
				  element.rotation == nil,
				  let faces = element.faces,
				  faces.count == 6 else {
				continue
			}
			
			let allSolid = faces.values.allSatisfy {
				isSolid(texture: resolveTexture($0.texture, in: resolved))
			}
			
			if allSolid {
				return true
			}
		}
		
		return false
	}
	
	static var hidesCache: [BlockState: Bool] = [:]
	
	static func neighbourHides(
		_ blockState: BlockState,
		blockStateFolder: URL,
		modelFolder: URL
	) -> Bool {
		if let hit = hidesCache[blockState] { return hit }
		
		guard let v = variant(for: blockState, x: 0, y: 0, z: 0, blockStateFolder: blockStateFolder) else {
			hidesCache[blockState] = false
			return false
		}
		let value = hidesNeighbours(resolvedModel(modelName: v.model, modelFolder: modelFolder))
		
		hidesCache[blockState] = value
		return value
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
	) -> (opaque: [String: [Vertex]], translucent: [String: [Vertex]]) {
		
		// texture name -> vertices using that texture
		var verticesByTexture: [String: [Vertex]] = [:]
		var translucentByTexture: [String: [Vertex]] = [:]
		
		// Water is drawn in a second pass, after everything opaque, so it has
		// something behind it to blend with.
		func emit(_ texture: String, _ vertex: Vertex, translucent: Bool) {
			if translucent {
				translucentByTexture[texture, default: []].append(vertex)
			} else {
				verticesByTexture[texture, default: []].append(vertex)
			}
		}
		
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
				return true        // not loaded - don't the face
			}
			
			let neighbour = neighbourChunk.getBlockState(x: nx & 15, y: ny, z: nz & 15)
			
			if neighbour.block == air {
				return false
			}
			
			return neighbourHides(neighbour, blockStateFolder: blockStateFolder, modelFolder: modelFolder)
		}
		
		// The light level, 0 to 15, of the block this face points at. Light
		// lives in the air next to a face, never inside the solid block the
		// face belongs to, so this steps one block along dir first.
		//
		// 15 when we cannot tell — off the world, or a chunk we have not
		// loaded. Guessing bright means unknown ground is never darkened.
		func lightLevel(_ x: Int, _ y: Int, _ z: Int, _ dir: SIMD3<Float>) -> Int {
			let nx = x + Int(dir.x), ny = y + Int(dir.y), nz = z + Int(dir.z)
			
			guard ny >= -64, ny < -64 + chunk.height,
				  let containingChunk = clientWorld.chunk(
					atX: chunk.chunkX + (nx >> 4),
					z: chunk.chunkZ + (nz >> 4)
				  ) else {
				return 15
			}
			
			let location = containingChunk.locate(ny)
			let section = containingChunk.sections[location.section]
			
			return section.lightLevel(
				at: section.index(x: nx & 15, y: location.localY, z: nz & 15)
			)
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
					guard let v = variant(for: blockState, x: x, y: y, z: z, blockStateFolder: blockStateFolder) else {
						continue
					}
					
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
					
					// A top corner is shared by four columns. It sits at the average
					// height of whichever of them are the same fluid; the others are
					// ignored rather than counted as zero. Fluid directly above any of
					// them raises the corner to a full block, so a waterfall has no
					// notch at every boundary.
					func cornerHeight(
						_ x: Int, _ y: Int, _ z: Int,
						_ dx: Int, _ dz: Int,
						_ id: String
					) -> Float {
						var total: Float = 0
						var count: Float = 0
						
						for ox in (dx - 1)...dx {
							for oz in (dz - 1)...dz {
								let wx = x + chunk.chunkX * Section.width + ox
								let wz = z + chunk.chunkZ * Section.depth + oz
								
								if let above = clientWorld.getBlockState(worldX: wx, y: y + 1, worldZ: wz),
								   above.block.id == id {
									return 1
								}
								
								guard let state = clientWorld.getBlockState(worldX: wx, y: y, worldZ: wz),
									  state.block.id == id,
									  let height = fluidHeight(of: state) else { continue }
								
								total += height
								count += 1
							}
						}
						
						return count == 0 ? 0 : total / count
					}
					
					// Fluids have no model, so their surface is built here
					// instead of from elements.
					if fluidHeight(of: blockState) != nil {
						let id = blockState.block.id
						let wx = x + chunk.chunkX * Section.width
						let wz = z + chunk.chunkZ * Section.depth
						
						// More of the same fluid directly above means this
						// block is inside a body of water, not at its surface.
						let coveredAbove = clientWorld.getBlockState(
							worldX: wx, y: y + 1, worldZ: wz
						)?.block.id == id
						
						let fluidTint: SIMD3<Float> = {
							guard id == "minecraft:water" else {
								return SIMD3<Float>(1, 1, 1)
							}
							
							let biomeIndex = chunk.sections[sectionIndex]
								.biomeID(x: x, y: y - bottomY, z: z)
							
							guard biomeIndex < BiomeRegistry.biomes.count else {
								return SIMD3<Float>(1, 1, 1)
							}
							
							return BiomeRegistry.biomes[biomeIndex].waterColor
							?? SIMD3<Float>(1, 1, 1)
						}()
						
						let isWater = id == "minecraft:water"
						
						let h = [
							cornerHeight(x, y, z, 0, 0, id),
							cornerHeight(x, y, z, 1, 0, id),
							cornerHeight(x, y, z, 1, 1, id),
							cornerHeight(x, y, z, 0, 1, id)
						]
						
						// Comparing the two sides of the block gives the slope.
						// A flat surface has none and uses the still texture.
						let slopeX = (h[1] + h[2]) - (h[0] + h[3])
						let slopeZ = (h[2] + h[3]) - (h[0] + h[1])
						
						let isFlowing = abs(slopeX) > 0.0001 || abs(slopeZ) > 0.0001
						let flowAngle = atan2(-slopeX, -slopeZ)
						
						let positions = [
							SIMD3<Float>(bx,     by + h[0], bz),
							SIMD3<Float>(bx + 1, by + h[1], bz),
							SIMD3<Float>(bx + 1, by + h[2], bz + 1),
							SIMD3<Float>(bx,     by + h[3], bz + 1)
						]
						
						let uvs = [
							SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
							SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)
						]
						
						let texture = resolveTexture("#particle", in: resolved)
						
						// The flow texture sits beside the still one in the
						// pack, so derive its name rather than typing a path.
						let topTexture = isFlowing
						? texture.replacingOccurrences(of: "_still", with: "_flow")
						: texture
						
						var topUVs = uvs
						
						if isFlowing {
							let s = sin(flowAngle) * 0.25
							let c = cos(flowAngle) * 0.25
							
							// Same order as h and positions: (0,0) (1,0) (1,1) (0,1)
							let offsets: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
							
							topUVs = offsets.map { dx, dz in
								SIMD2<Float>(
									0.5 + dx * c - dz * s,
									0.5 + dx * s + dz * c
								)
							}
						}
						
						if (!coveredAbove) {
							let faceShade = shade(of: "up")
							* brightness(ofLight: lightLevel(x, y, z, SIMD3<Float>(0, 1, 0)))
							
							for i in [0, 3, 2, 2, 1, 0] {
								emit(topTexture, Vertex(
									position: positions[i],
									uv: topUVs[i],
									tint: fluidTint,
									shade: faceShade,
									depthBias: 0
								), translucent: isWater)
							}
						}
						
						for (faceKey, tops) in [
							("north", [h[3], h[2]]),
							("south", [h[1], h[0]]),
							("west",  [h[0], h[3]]),
							("east",  [h[2], h[1]])
						] {
							let dir = direction(of: faceKey)
							
							if clientWorld.getBlockState(
								worldX: wx + Int(dir.x),
								y: y,
								worldZ: wz + Int(dir.z)
							)?.block.id == id { continue }
							
							if hidden(x, y, z, dir) { continue }
							
							var side = corners(
								faceKey: faceKey,
								from: origin,
								to: origin + SIMD3<Float>(1, 1, 1)
							)
							
							side[0].y = by + tops[0]
							side[1].y = by + tops[1]
							
							let sideUVs = [
								SIMD2<Float>(0, 1 - tops[0]),
								SIMD2<Float>(1, 1 - tops[1]),
								SIMD2<Float>(1, 1),
								SIMD2<Float>(0, 1)
							]
							
							let sideShade = shade(of: faceKey)
							* brightness(ofLight: lightLevel(x, y, z, dir))
							
							for i in [0, 3, 2, 2, 1, 0] {
								emit(texture, Vertex(
									position: side[i],
									uv: sideUVs[i],
									tint: fluidTint,
									shade: sideShade,
									depthBias: 0
								), translucent: isWater)
							}
						}
						
						// The underside. Flat, full size — a fluid's botctom is
						// never sloped, however the top behaves.
						if clientWorld.getBlockState(worldX: wx, y: y - 1, worldZ: wz)?
							.block.id != id,
						   !hidden(x, y, z, SIMD3<Float>(0, -1, 0)) {
							
							let under = corners(
								faceKey: "down",
								from: origin,
								to: origin + SIMD3<Float>(1, 1, 1)
							)
							
							let underShade = shade(of: "down")
							* brightness(ofLight: lightLevel(x, y, z, SIMD3<Float>(0, -1, 0)))
							
							for i in [0, 3, 2, 2, 1, 0] {
								emit(texture, Vertex(
									position: under[i],
									uv: uvs[i],
									tint: fluidTint,
									shade: underShade,
									depthBias: 0
								), translucent: isWater)
							}
						}
					}
					
					// One pass per box. A cube has a single box; the anvil has
					// four, so a single anvil runs this four times.
					for (elementIndex, element) in resolved.elements.enumerated() {
						
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
							
							let overlaps = resolved.elements.prefix(elementIndex).contains {
								$0.from == element.from && $0.to == element.to
							}
							
							// An element painted on top of an identical one — grass's
							// green fringe over its dirt side. Both faces must draw, so
							// nudge the later one toward the camera in the shader rather
							// than moving it in the world: a fixed world-space offset
							// stops being enough as depth precision falls off.
							let depthBias: Float = overlaps ? 0.0002 : 0
							
							let positions = corners(faceKey: faceKey, from: f, to: t)
							
							// Matching lists: corner 0 pairs with uv 0, and so on.
							let uvs = faceUVs(face)
							let texture = resolveTexture(face.texture, in: resolved)
							
							// Two triangles covering the quad, wound so the
							// outside face survives setCullMode(.back)
							// Only faces lying on the block's boundary take their light
							// from next door. A face inside the block — a plant's
							// crossed panels, an anvil's sides — is lit by its own block.
							let lightDirection = face.cullface == nil
							? SIMD3<Float>(0, 0, 0)
							: rotate(
								xRot,
								yRot,
								around: SIMD3<Float>(0, 0, 0),
								direction(of: faceKey)
							)
							
							let faceShade = shade(of: faceKey)
							* brightness(ofLight: lightLevel(x, y, z, lightDirection))
							
							let faceTint: SIMD3<Float> = {
								guard face.tintindex != nil else {
									return SIMD3<Float>(1, 1, 1)
								}
								
								let id = chunk.sections[sectionIndex]
									.biomeID(x: x, y: y - bottomY, z: z)
								
								guard id < BiomeRegistry.biomes.count else {
									return SIMD3<Float>(1, 1, 1)
								}
								
								let biome = BiomeRegistry.biomes[id]
								let isLeaves = blockState.block.id.contains("leaves")
								
								return (isLeaves ? biome.foliageColor : biome.grassColor)
								?? SIMD3<Float>(1, 1, 1)
							}()
							
							for i in [0, 3, 2, 2, 1, 0] {
								verticesByTexture[texture, default: []].append(
									Vertex(
										position: rotate(xRot, yRot, around: center, positions[i]),
										uv: uvs[i],
										tint: faceTint,
										shade: faceShade,
										depthBias: depthBias
									)
								)
							}
						}
					}
				}
			}
		}
		
		return (verticesByTexture, translucentByTexture)
	}
}
