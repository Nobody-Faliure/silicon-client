import Metal
import MetalKit
import ImageIO

struct Vertex {
	let px, py, pz: Int16      // position inside the section, in 1/256 of a block
	let flags: Int16           // 1 = grass overlay, gets the depth nudge
	let u, v: UInt16           // 0...65535 means 0...1 across the texture
	let r, g, b: UInt8         // biome tint, 0...255
	let shade: UInt8           // face brightness, 0...255
	
	init(position: SIMD3<Float>, origin: SIMD3<Float>, uv: SIMD2<Float>,
		 tint: SIMD3<Float>, shade: Float, depthBias: Float) {
		let local = (position - origin) * 256
		px = Int16(local.x.rounded())
		py = Int16(local.y.rounded())
		pz = Int16(local.z.rounded())
		flags = depthBias > 0 ? 1 : 0
		u = UInt16((min(max(uv.x, 0), 1) * 65535).rounded())
		v = UInt16((min(max(uv.y, 0), 1) * 65535).rounded())
		r = UInt8((min(max(tint.x, 0), 1) * 255).rounded())
		g = UInt8((min(max(tint.y, 0), 1) * 255).rounded())
		b = UInt8((min(max(tint.z, 0), 1) * 255).rounded())
		self.shade = UInt8((min(max(shade, 0), 1) * 255).rounded())
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
	
	let translucentPipelineState: MTLRenderPipelineState
	let translucentDepthState: MTLDepthStencilState
	
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
	
	// Time that has passed but not yet been turned into ticks. 20 ticks a second.
	private var unspentTickTime: Double = 0
	static let tickLength: Double = 0.05
	
	private var player = Player()
	
	static let eyeHeight: Float = 1.62
	
	let status: LoadingStatus
	let debug: DebugInfo
	let chat: ChatInfo
	
	private var hasSpawned = false
	
	private var hasSentPlayerLoaded = false
	
	private var dayTime: Int = 0          // ticks on the world clock
	private var timeRate: Double = 1      // 1 = moving, 0 = frozen
	
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
	
	var textureCache: [String: MTLTexture] = [:]
	
	struct AnimatedTexture {
		let texture: MTLTexture
		let frames: Data
		let size: Int
		let animation: TextureAnimation
	}
	
	var animatedTextures: [String: AnimatedTexture] = [:]
	var lastAnimationTick = -1
	
	// Creates all Metal resources when Renderer starts
	init(input: Input, status: LoadingStatus, debug: DebugInfo, chat: ChatInfo) {
		
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
		
		// Water has to mix with whatever is already on screen, so it needs a
		// pipeline with blending turned on. The opaque one above was already
		// built, so reusing the descriptor is safe.
		pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
		pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
		pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
		pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
		pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
		pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
		pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
		
		self.translucentPipelineState = try! device.makeRenderPipelineState(
			descriptor: pipelineDescriptor
		)
		
		// Depth writes off: one water surface must not hide another behind it,
		// or a lake loses all sense of depth.
		let translucentDepthDescriptor = MTLDepthStencilDescriptor()
		translucentDepthDescriptor.depthCompareFunction = .less
		translucentDepthDescriptor.isDepthWriteEnabled = false
		
		self.translucentDepthState = device.makeDepthStencilState(
			descriptor: translucentDepthDescriptor
		)!
		
		// Store input
		self.input = input
		
		self.status = status
		
		self.debug = debug
		
		self.chat = chat
		
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
			
			player.position = new_player.position
			player.previousTickPosition = new_player.position
			player.yaw = new_player.yaw
			player.pitch = new_player.pitch
			player.velocity = [0, 0, 0]
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
		
		serverConnection.onGameMode = { [weak self] mode in
			guard let self else { return }

			self.player.gameMode = mode
			print("[game] gamemode \(mode)")
		}
		
		serverConnection.onAbilities = { [weak self] isFlying, mayFly, flyingSpeed in
			guard let self else { return }

			self.player.isFlying = isFlying
			self.player.mayFly = mayFly
			self.player.flyingSpeed = flyingSpeed
			print("[game] flying \(isFlying), may fly \(mayFly), speed \(flyingSpeed)")
		}
		
		serverConnection.onEntityID = { [weak self] id in
			self?.player.entityID = id
		}
		
		serverConnection.onRespawn = { [weak self] in
			guard let self else { return }
			
			self.clientWorld.unloadAll()
			self.sectionMeshes.removeAll()
			self.hasSentPlayerLoaded = false
		}
		
		serverConnection.onAttributes = { [weak self] entityID, stats in
			guard let self, entityID == self.player.entityID else { return }
			
			if let speed = stats[26] {
				self.player.speedBase = speed.base
				self.player.speedModifiers = speed.modifiers
			}
			if let jump = stats[19] {
				self.player.jumpStrength = Attributes.finalValue(base: jump.base, modifiers: jump.modifiers)
			}
		}
		
		serverConnection.onTime = { [weak self] ticks, rate in
			self?.dayTime = ticks
			self?.timeRate = rate
		}
		
		Task {
			do {
				status.show("Downloading/Preparing textures")
				let textureFolder = try await resourceDownloader.downloadAllBlockAndItemTextures()
				ChunkMesher.textureFolder = textureFolder.appendingPathComponent("block")
				BiomeRegistry.colormapFolder = textureFolder
				
				status.show("Downloading/Preparing block models")
				let modelFolder = try await resourceDownloader.downloadAllModelJSONs()
				self.modelFolder = modelFolder
				
				status.show("Downloading/Preparing block states")
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
	
	private func updateChat() {
		if chat.isOpen != input.chatOpen {
			chat.isOpen = input.chatOpen
		}
		if chat.text != input.chatText {
			chat.text = input.chatText
		}
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
		
		debug.x = player.position.x
		debug.y = player.position.y
		debug.z = player.position.z
		debug.facing = Renderer.facingName(yaw: player.yaw, pitch: player.pitch)
		debug.yaw = Renderer.yawDegrees(player.yaw)
		debug.pitch = Double(player.pitch * 180 / .pi)
		debug.blocksPerSecond = player.flyingSpeed * input.flyStep
		
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
	
	func rebuildDirtySections() {
		guard let modelFolder, let blockStateFolder else { return }
		
		let batch = Array(clientWorld.dirtySections.prefix(10000))
		
		for position in batch {
			
			guard let chunk = clientWorld.chunk(
				atX: position.chunkX,
				z: position.chunkZ
			),
				  clientWorld.chunk(atX: position.chunkX + 1, z: position.chunkZ) != nil,
				  clientWorld.chunk(atX: position.chunkX - 1, z: position.chunkZ) != nil,
				  clientWorld.chunk(atX: position.chunkX, z: position.chunkZ + 1) != nil,
				  clientWorld.chunk(atX: position.chunkX, z: position.chunkZ - 1) != nil,
				  let world = snapshot(around: position) else { continue }
			
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
					
					if var mesh {
						for i in mesh.materials.indices {
							mesh.materials[i].texture = self.texture(named: mesh.materials[i].textureName)
						}
						for i in mesh.translucentMaterials.indices {
							mesh.translucentMaterials[i].texture = self.texture(named: mesh.translucentMaterials[i].textureName)
						}
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
		let chunkX = Int(player.position.x.rounded(.down)) >> 4
		let chunkZ = Int(player.position.z.rounded(.down)) >> 4
		
		return sectionMeshes.contains {
			$0.chunkX == chunkX && $0.chunkZ == chunkZ
		}
	}
	
	// One game tick: move the player, then tell the server where we are.
	private func tick() {
		if timeRate > 0 { dayTime += 1 }
		
		player.previousTickPosition = player.position
		
		let wasFlying = player.isFlying
		let wasSprinting = player.isSprinting
		player.updatePosition(input: input, deltaTime: Renderer.tickLength, world: clientWorld)
		if player.isFlying != wasFlying {
			serverConnection.sendFlying(player.isFlying)
		}
		if player.isSprinting != wasSprinting {
			serverConnection.sendSprinting(player.isSprinting, entityID: player.entityID)
		}
		
		guard hasSpawned else { return }
		
		if let command = input.pendingCommand {
			input.pendingCommand = nil
			serverConnection.sendCommand(command)
		}
		
		var player = self.player
		player.yaw = -player.yaw * 180 / .pi
		player.pitch = player.pitch * 180 / .pi
		
		serverConnection.sendPlayerPosition(player, onGround: player.onGround)
		serverConnection.sendClientTickEnd()
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
		
		unspentTickTime += deltaTime
		while unspentTickTime >= Renderer.tickLength {
			unspentTickTime -= Renderer.tickLength
			tick()
		}
		
		updateDebug(now: now, deltaTime: deltaTime)
		
		updateChat()
		
		advanceAnimations(now: now)
		
		let blend = unspentTickTime / Renderer.tickLength
		let current = player.position
		let smooth = player.previousTickPosition + (current - player.previousTickPosition) * blend
		
		cameraPosition = SIMD3<Float>(
			Float(smooth.x),
			Float(smooth.y) + Renderer.eyeHeight,
			Float(smooth.z)
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
		
		let viewProjection = projectionMatrix * viewMatrix
		
		// Draw current mesh
		for mesh in sectionMeshes {
			if !isBoxOnScreen(mesh.corners, viewProjection) {
				continue
			}
			
			var origin: [Float] = [
				Float(mesh.chunkX * Section.width),
				Float(-64 + mesh.sectionIndex * Section.height),
				Float(mesh.chunkZ * Section.depth)
			]
			renderEncoder.setVertexBytes(
				&origin,
				length: 3 * MemoryLayout<Float>.stride,
				index: 3
			)
			
			for material in mesh.materials {
				let materialTexture = material.texture
				
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
		
		// Second pass: water. Everything opaque is already on screen, so
		// there is something behind it to blend with.
		renderEncoder.setRenderPipelineState(translucentPipelineState)
		renderEncoder.setDepthStencilState(translucentDepthState)
		
		for mesh in sectionMeshes {
			if !isBoxOnScreen(mesh.corners, viewProjection) {
				continue
			}
			
			var origin: [Float] = [
				Float(mesh.chunkX * Section.width),
				Float(-64 + mesh.sectionIndex * Section.height),
				Float(mesh.chunkZ * Section.depth)
			]
			renderEncoder.setVertexBytes(
				&origin,
				length: 3 * MemoryLayout<Float>.stride,
				index: 3
			)
			
			for material in mesh.translucentMaterials {
				renderEncoder.setFragmentTexture(
					material.texture,
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
}
