import Metal
import MetalKit
import ImageIO

struct Vertex {
	let x: Float
	let y: Float
	let z: Float
	let u: Float
	let v: Float
	let tintIndex: Int32
	let shade: Float
	let depthBias: Float
	
	init(position: SIMD3<Float>, uv: SIMD2<Float>, tintIndex: Int32, shade: Float, depthBias: Float) {
		x = position.x
		y = position.y
		z = position.z
		u = uv.x
		v = uv.y
		self.tintIndex = tintIndex
		self.shade = shade
		self.depthBias = depthBias
	}
}

// MTKViewDelegate lets Renderer receive draw calls from MTKView
final class Renderer: NSObject, MTKViewDelegate {
	
	// Core Metal objects used to talk to the GPU
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	
	// GPU rendering resources
	let depthStencilState: MTLDepthStencilState
	let pipelineState: MTLRenderPipelineState
	
	let minecraftServer = MinecraftServer()
	let serverConnection = ServerConnection()
	
	// Keyboard and mouse input
	let input: Input
	
	// Camera matrices
	var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
	var viewMatrix: simd_float4x4 = matrix_identity_float4x4
	
	// Camera state
	var cameraPosition = SIMD3<Float>(0, 200, 0)
	var cameraYaw: Float = 0
	var cameraPitch: Float = 0
	
	private var lastFrameTime: CFTimeInterval?
	
	private var player = Player()
	
	static let eyeHeight: Float = 1.62
	
	let status: LoadingStatus
	let debug: DebugInfo
	
	private var hasSpawned = false
	
	private var hasSentPlayerLoaded = false
	private var lastPositionSend: CFTimeInterval = 0
	// Readings — position, counts — refresh four times a second, which is
	// fast enough to follow while flying.
	private var lastReadingUpdate: CFTimeInterval = 0
	
	// Rates only exist over a window. These collect one second's worth,
	// then publish and start again.
	private var secondStarted: CFTimeInterval = 0
	private var framesThisSecond = 0
	private var meshMillisecondsThisSecond = 0.0
	private var sectionsMeshedThisSecond = 0
	
	private let meshQueue = DispatchQueue(
		label: "dev.jasper.Silicon-Client.mesh",
		qos: .userInitiated
	)
	
	var lookDirection: SIMD3<Float> {
		SIMD3<Float>(
			sin(cameraYaw) * cos(cameraPitch),
			-sin(cameraPitch),
			cos(cameraYaw) * cos(cameraPitch)
		)
	}
	
	// Client-side copy of the world
	var clientWorld: ClientWorld = ClientWorld()
	
	var sectionMeshes: [SectionRenderMesh] = []
	
	var modelFolder: URL?
	var blockStateFolder: URL?
	
	private var textureCache: [String: MTLTexture] = [:]
	
	private struct AnimatedTexture {
		let texture: MTLTexture
		let frames: Data
		let size: Int
		let animation: TextureAnimation
	}
	
	private var animatedTextures: [String: AnimatedTexture] = [:]
	private var lastAnimationTick = -1
	
	// Creates all Metal resources when Renderer starts
	init(input: Input, status: LoadingStatus, debug: DebugInfo) {
		
		// Get the Mac's Metal GPU
		self.device = MTLCreateSystemDefaultDevice()!
		
		// Load Metal shaders
		let library = device.makeDefaultLibrary()!
		let vertexFunction = library.makeFunction(name: "vertexShader")!
		let fragmentFunction = library.makeFunction(name: "fragmentShader")!
		
		// Set up render pipeline
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		
		pipelineDescriptor.colorAttachments[0].pixelFormat =
			.bgra8Unorm_srgb
		
		pipelineDescriptor.depthAttachmentPixelFormat =
			.depth32Float
		
		self.pipelineState = try! device.makeRenderPipelineState(
			descriptor: pipelineDescriptor
		)
		
		// Create command queue
		self.commandQueue = device.makeCommandQueue()!
		
		// Set up depth testing
		let depthDescriptor = MTLDepthStencilDescriptor()
		depthDescriptor.depthCompareFunction = .less
		depthDescriptor.isDepthWriteEnabled = true
		
		self.depthStencilState = device.makeDepthStencilState(
			descriptor: depthDescriptor
		)!
		
		// Store input
		self.input = input
		
		self.status = status
		
		self.debug = debug
		
		let resourceDownloader = ResourceDownloader()
		
		super.init()
		
		serverConnection.onChunk = { [weak self] chunk in
			guard let self else { return }
			
			self.clientWorld.receiveChunk(chunk)
			
			for i in 0..<Chunk.sectionCount {
				self.clientWorld.dirtySections.insert(
					SectionPosition(
						chunkX: chunk.chunkX,
						chunkZ: chunk.chunkZ,
						sectionIndex: i
					)
				)
			}
		}
		
		serverConnection.onPosition = { [weak self] new_player in
			guard let self else { return }
			
			player = new_player
			self.hasSpawned = true
		}
		
		serverConnection.onLight = { [weak self] chunkX, chunkZ, sky, block in
			guard let self else { return }
			
			self.clientWorld.receiveLight(chunkX: chunkX, chunkZ: chunkZ, sky: sky, block: block)
		}
		
		serverConnection.onForgetChunk = { [weak self] chunkX, chunkZ in
			guard let self else { return }
			
			self.clientWorld.unloadChunk(chunkX: chunkX, chunkZ: chunkZ)
			
			self.sectionMeshes.removeAll {
				$0.chunkX == chunkX && $0.chunkZ == chunkZ
			}
			
			self.clientWorld.dirtySections = self.clientWorld.dirtySections.filter {
				$0.chunkX != chunkX || $0.chunkZ != chunkZ
			}
		}
		
		Task {
			do {
				status.show("Downloading textures")
				let textureFolder = try await resourceDownloader.downloadAllBlockAndItemTextures()
				ChunkMesher.textureFolder = textureFolder.appendingPathComponent("block")
				
				status.show("Downloading block models")
				let modelFolder = try await resourceDownloader.downloadAllModelJSONs()
				self.modelFolder = modelFolder
				
				status.show("Downloading block states")
				let blockStateFolder = try await resourceDownloader.downloadAllBlockStateJSONs()
				self.blockStateFolder = blockStateFolder
				
				sectionMeshes = buildWorldMeshes(
					from: clientWorld,
					device: device,
					modelFolder: modelFolder,
					blockStateFolder: blockStateFolder
				)
				
				let support = URL(fileURLWithPath: NSHomeDirectory())
					.appendingPathComponent("Library/Application Support/Silicon Client")
				
				status.show("Downloading the server")
				let serverJar = try await resourceDownloader.downloadServerJar()
				
				status.show("Reading block data")
				MinecraftServer.generateReports(jar: serverJar)
				
				status.show("Starting the server")
				minecraftServer.start(
					jar: serverJar,
					worldFolder: support.appendingPathComponent("Worlds/New World")
				) {
					self.status.show("Connecting")
					self.serverConnection.connect(host: "127.0.0.1", port: self.minecraftServer.serverPort())
				}
			} catch {
				status.show("Failed: \(error.localizedDescription)")
			}
		}
		AppDelegate.server = minecraftServer
	}
	
	private func updateDebug(now: CFTimeInterval, deltaTime: Double) {
		framesThisSecond += 1
		
		if debug.isVisible != input.showDebug {
			debug.isVisible = input.showDebug
		}
		
		// Rates: one whole second, then publish and reset.
		if now - secondStarted >= 1 {
			let elapsed = now - secondStarted
			
			debug.fps = Int((Double(framesThisSecond) / elapsed).rounded())
			debug.frameMilliseconds = elapsed / Double(max(framesThisSecond, 1)) * 1000
			
			if sectionsMeshedThisSecond > 0 {
				debug.meshMilliseconds = meshMillisecondsThisSecond / Double(sectionsMeshedThisSecond)
			}
			
			secondStarted = now
			framesThisSecond = 0
			meshMillisecondsThisSecond = 0
			sectionsMeshedThisSecond = 0
		}
		
		// Readings: just what things are right now.
		guard now - lastReadingUpdate >= 0.25 else { return }
		
		lastReadingUpdate = now
		
		debug.x = player.x
		debug.y = player.y
		debug.z = player.z
		debug.facing = Renderer.facingName(yaw: player.yaw, pitch: player.pitch)
		debug.yaw = Renderer.yawDegrees(player.yaw)
		debug.pitch = Double(player.pitch * 180 / .pi)
		debug.blocksPerSecond = Player.spectatorFlySpeed * input.flyStep
		
		debug.chunksLoaded = clientWorld.chunks.count
		debug.sectionMeshes = sectionMeshes.count
		debug.sectionsQueued = clientWorld.dirtySections.count
	}

	
	// Which way the camera points, in words. Eight compass directions, or
	// up and down once you are looking steeply enough that the compass
	// stops being what you want to know.
	private static func facingName(yaw: Float, pitch: Float) -> String {
		let pitchDegrees = pitch * 180 / .pi
		
		if pitchDegrees >  60 { return "down" }
		if pitchDegrees < -60 { return "up" }
		
		let names = [
			"south", "south-west", "west", "north-west",
			"north", "north-east", "east", "south-east"
		]
		
		let degrees = Renderer.yawDegrees(yaw)
		let sector = Int((degrees / 45).rounded()) % 8
		
		return names[sector]
	}
	
	// Yaw as the game writes it: degrees, 0 up to 360, sign flipped from ours.
	private static func yawDegrees(_ yaw: Float) -> Double {
		let raw = Double(-yaw * 180 / .pi)
		
		return (raw.truncatingRemainder(dividingBy: 360) + 360)
			.truncatingRemainder(dividingBy: 360)
	}
	
	private func advanceAnimations(now: CFTimeInterval) {
		let tick = Int(now * 20)
		
		guard tick != lastAnimationTick else { return }
		
		lastAnimationTick = tick
		
		for animated in animatedTextures.values {
			let order = animated.animation.frameOrder

			guard !order.isEmpty else { continue }
			
			let step = (tick / animated.animation.ticksPerFrame) % order.count
			let frame = order[step]
			
			let bytesPerFrame = animated.size * animated.size * 4
			let start = frame * bytesPerFrame
			
			guard start + bytesPerFrame <= animated.frames.count else { continue }
			
			animated.frames.withUnsafeBytes { raw in
				animated.texture.replace(
					region: MTLRegionMake2D(0, 0, animated.size, animated.size),
					mipmapLevel: 0,
					withBytes: raw.baseAddress! + start,
					bytesPerRow: animated.size * 4
				)
			}
		}
	}
	
	func rebuildDirtySections() {
		guard let modelFolder, let blockStateFolder else { return }
		
		let batch = Array(clientWorld.dirtySections.prefix(10000))
		
		for position in batch {
			
			guard let chunk = clientWorld.chunk(
				atX: position.chunkX,
				z: position.chunkZ
			), let world = snapshot(around: position),
				  world.chunks.count == 5 else { continue }
			clientWorld.dirtySections.remove(position)
			
			meshQueue.async {
				let started = CACurrentMediaTime()
				
				let mesh = buildSectionRenderMesh(
					from: chunk,
					sectionIndex: position.sectionIndex,
					device: self.device,
					modelFolder: modelFolder,
					blockStateFolder: blockStateFolder,
					clientWorld: world
				)
				
				let took = (CACurrentMediaTime() - started) * 1000
				self.meshMillisecondsThisSecond += took
				self.sectionsMeshedThisSecond += 1
				
				DispatchQueue.main.async {
					guard self.clientWorld.chunk(atX: position.chunkX, z: position.chunkZ) != nil else { return }
					self.sectionMeshes.removeAll {
						$0.chunkX == position.chunkX
						&& $0.chunkZ == position.chunkZ
						&& $0.sectionIndex == position.sectionIndex
					}
					
					if let mesh {
						self.sectionMeshes.append(mesh)
					}
				}
			}
		}
	}
	
	private func snapshot(around position: SectionPosition) -> ClientWorld? {
		guard let chunk = clientWorld.chunk(
			atX: position.chunkX,
			z: position.chunkZ
		) else { return nil }
		
		let copy = ClientWorld()
		copy.receiveChunk(chunk)
		
		for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
			if let neighbour = clientWorld.chunk(
				atX: position.chunkX + dx,
				z: position.chunkZ + dz
			) {
				copy.receiveChunk(neighbour)
			}
		}
		
		return copy
	}
	
	func raycast() -> (hit: SIMD3<Int>, placeAt: SIMD3<Int>)? {
		let reach: Float = 4.5
		let stepSize: Float = 0.05
		let direction = lookDirection
		
		var previous = SIMD3<Int>(cameraPosition.rounded(.down))
		
		for step in 0...Int(reach / stepSize) {
			let point = cameraPosition + direction * (Float(step) * stepSize)
			let block = SIMD3<Int>(point.rounded(.down))
			if block == previous { continue }
			if let state = clientWorld.getBlockState(worldX: block.x, y: block.y, worldZ: block.z),
			   state.block != Block(id: "minecraft:air") {
				return (block, previous)
			}
			previous = block
		}
		return nil
	}
	
	private var standingOnLoadedChunk: Bool {
		let chunkX = Int(player.x.rounded(.down)) >> 4
		let chunkZ = Int(player.z.rounded(.down)) >> 4
		
		return sectionMeshes.contains {
			$0.chunkX == chunkX && $0.chunkZ == chunkZ
		}
	}
	
	// Called repeatedly by MTKView to draw each frame
	func draw(in view: MTKView) {
		if !clientWorld.dirtySections.isEmpty {
			rebuildDirtySections()
		}
		
		let now = CACurrentMediaTime()
		let deltaTime = min(now - (lastFrameTime ?? now), 0.1)
		lastFrameTime = now
		
		// The loading screen comes down only once the server has placed us
		// and at least one chunk is on screen — otherwise it reveals a void.
		if !hasSentPlayerLoaded, hasSpawned, standingOnLoadedChunk {
			hasSentPlayerLoaded = true
			serverConnection.sendPlayerLoaded()
			status.ready()
		}
		
		player.spectatorFly(input: input, deltaTime: deltaTime)
		
		updateDebug(now: now, deltaTime: deltaTime)
		
		advanceAnimations(now: now)
		
		if hasSpawned, now - lastPositionSend >= 0.05 {
			lastPositionSend = now
			
			var player = self.player
			player.yaw = -player.yaw * 180 / .pi
			player.pitch = player.pitch * 180 / .pi
			
			serverConnection.sendPlayerPosition(player, onGround: false)
			serverConnection.sendClientTickEnd()
		}
		
		cameraPosition = SIMD3<Float>(
			Float(player.x),
			Float(player.y) + Renderer.eyeHeight,
			Float(player.z)
		)
		
		guard let renderPassDescriptor =
				view.currentRenderPassDescriptor else {
			return
		}
		
		// Clear depth buffer
		renderPassDescriptor.depthAttachment.clearDepth = 1.0
		renderPassDescriptor.depthAttachment.loadAction = .clear
		
		// Sky color
		renderPassDescriptor.colorAttachments[0].clearColor =
		MTLClearColor(
			red: 0.45,
			green: 0.70,
			blue: 1.0,
			alpha: 1.0
		)
		
		// Begin GPU commands
		let commandBuffer = commandQueue.makeCommandBuffer()!
		
		let renderEncoder = commandBuffer.makeRenderCommandEncoder(
			descriptor: renderPassDescriptor
		)!
		
		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setDepthStencilState(depthStencilState)
		
		// Cull triangle backs
		renderEncoder.setCullMode(.back)
		
		// Send projection matrix
		var matrix = projectionMatrix
		
		renderEncoder.setVertexBytes(
			&matrix,
			length: MemoryLayout<simd_float4x4>.stride,
			index: 1
		)
		
		player.updateLookDirection(input: input)
		
		cameraYaw = player.yaw
		cameraPitch = player.pitch
		
		// Camera rotation
		let cosYaw = cos(-cameraYaw)
		let sinYaw = sin(-cameraYaw)
		let cosPitch = cos(-cameraPitch)
		let sinPitch = sin(-cameraPitch)
		
		viewMatrix.columns.0 = SIMD4<Float>(
			cosYaw,
			sinPitch * sinYaw,
			-cosPitch * sinYaw,
			0
		)
		
		viewMatrix.columns.1 = SIMD4<Float>(
			0,
			cosPitch,
			sinPitch,
			0
		)
		
		viewMatrix.columns.2 = SIMD4<Float>(
			sinYaw,
			-sinPitch * cosYaw,
			cosPitch * cosYaw,
			0
		)
		
		// Camera translation
		let translatedX = -(
			cameraPosition.x * cosYaw
			+ cameraPosition.z * sinYaw
		)
		
		let translatedY = -(
			cameraPosition.x * sinPitch * sinYaw
			+ cameraPosition.y * cosPitch
			- cameraPosition.z * sinPitch * cosYaw
		)
		
		let translatedZ = -(
			-cameraPosition.x * cosPitch * sinYaw
			 + cameraPosition.y * sinPitch
			 + cameraPosition.z * cosPitch * cosYaw
		)
		
		viewMatrix.columns.3 = SIMD4<Float>(
			translatedX,
			translatedY,
			translatedZ,
			1
		)
		
		// Send camera matrix
		var cameraMatrix = viewMatrix
		
		renderEncoder.setVertexBytes(
			&cameraMatrix,
			length: MemoryLayout<simd_float4x4>.stride,
			index: 2
		)
		
		// Draw current mesh
		for mesh in sectionMeshes {
			for material in mesh.materials {
				let materialTexture = texture(named: material.textureName)
				
				// Send texture to fragment shader
				renderEncoder.setFragmentTexture(
					materialTexture,
					index: 0
				)
				
				renderEncoder.setVertexBuffer(
					material.vertexBuffer,
					offset: 0,
					index: 0
				)
				
				renderEncoder.drawPrimitives(
					type: .triangle,
					vertexStart: 0,
					vertexCount: material.vertexCount
				)
			}
		}
		
		renderEncoder.endEncoding()
		
		// Display completed frame
		commandBuffer.present(view.currentDrawable!)
		
		// Send commands to GPU
		commandBuffer.commit()
	}
	
	// Called whenever the Metal view changes size
	func mtkView(
		_ view: MTKView,
		drawableSizeWillChange size: CGSize
	) {
		
		let aspect = Float(size.width / size.height)
		
		projectionMatrix = makePerspectiveMatrix(
			fovY: 60 * .pi / 180,
			aspect: aspect,
			nearZ: 0.1,
			farZ: 1000
		)
	}
	
	// Builds a perspective projection matrix
	func makePerspectiveMatrix(
		fovY: Float,
		aspect: Float,
		nearZ: Float,
		farZ: Float
	) -> simd_float4x4 {
		
		let yScale = 1 / tan(fovY / 2)
		let xScale = yScale / aspect
		
		let zRange = farZ - nearZ
		
		let zScale = farZ / zRange
		let wzScale = -(farZ * nearZ) / zRange
		
		return simd_float4x4(
			SIMD4<Float>(xScale, 0, 0, 0),
			SIMD4<Float>(0, yScale, 0, 0),
			SIMD4<Float>(0, 0, zScale, 1),
			SIMD4<Float>(0, 0, wzScale, 0)
		)
	}
	
	// Finds a downloaded Minecraft texture by its resource name
	func texture(named name: String) -> MTLTexture {
		if let cached = textureCache[name] {
			return cached
		}
		let texturesFolder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
			.appendingPathComponent("Silicon Client")
			.appendingPathComponent("assets/minecraft/textures/block")
		
		// Convert "minecraft:block/stone" or "block/stone" into "stone.png"
		let textureName = name
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")
		
		let textureURL = texturesFolder
			.appendingPathComponent(textureName)
			.appendingPathExtension("png")
		
		let loaded = loadMinecraftTexture(from: textureURL, named: textureName)
		textureCache[name] = loaded
		return loaded
	}
	
	// Decodes a Minecraft PNG into raw pixels and creates a Metal texture
	func loadMinecraftTexture(from textureURL: URL, named name: String) -> MTLTexture {
		do {
			let data = try Data(contentsOf: textureURL)
			
			// Create an ImageIO source from the PNG data
			guard let source = CGImageSourceCreateWithData(
				data as CFData,
				nil
			) else {
				fatalError("Could not create image source: \(textureURL.path)")
			}
			
			let cgImage = CGImageSourceCreateImageAtIndex(
				source,
				0,
				nil
			)!
			
			let width = cgImage.width
			let height = cgImage.height
			
			let frameHeight = height > width ? width : height
			
			// Allocate enough memory for RGBA pixels
			let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
			let bytesPerRow = width * 4
			let byteCount = bytesPerRow * height
			
			let pixelData = UnsafeMutableRawPointer.allocate(
				byteCount: byteCount,
				alignment: 64
			)
			
			defer {
				pixelData.deallocate()
			}
			
			// Decode the image into a predictable 4-byte-per-pixel format
			let context = CGContext(
				data: pixelData,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: bytesPerRow,
				space: colorSpace,
				bitmapInfo:  CGImageAlphaInfo.premultipliedLast.rawValue
			)!
			
			context.draw(
				cgImage,
				in: CGRect(
					x: 0,
					y: 0,
					width: width,
					height: height
				)
			)
			
			// Create the GPU texture that will hold those pixels
			let descriptor = MTLTextureDescriptor.texture2DDescriptor(
				pixelFormat: .rgba8Unorm_srgb,
				width: width,
				height: frameHeight,
				mipmapped: false
			)
			
			let texture = device.makeTexture(
				descriptor: descriptor
			)!
			
			// Copy the decoded pixels into Metal's texture memory
			texture.replace(
				region: MTLRegionMake2D(
					0,
					0,
					width,
					frameHeight
				),
				mipmapLevel: 0,
				withBytes: pixelData,
				bytesPerRow: bytesPerRow
			)
			
			// A strip: remember every frame so draw() can swap them later.
			if height > width {
				let folder = textureURL.deletingLastPathComponent()
				
				animatedTextures[name] = AnimatedTexture(
					texture: texture,
					frames: Data(bytes: pixelData, count: byteCount),
					size: width,
					animation: TextureAnimation.load(
						name: name,
						frameCount: height / width,
						in: folder
					)
				)
			}
			
			return texture
		} catch {
			fatalError(
				"Failed texture: \(textureURL.path) — \(error)"
			)
		}
	}
}
