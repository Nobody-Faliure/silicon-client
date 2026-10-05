import Metal
import MetalKit
import ImageIO

struct Vertex {
	let position: SIMD3<Float>
	let uv: SIMD2<Float>
	let tintIndex: Int32
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
	
	static let eyeHeight: Float = 1.62
	
	private var positionTimer: Timer?
	private var hasSpawned = false
	
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
	
	// Creates all Metal resources when Renderer starts
	init(input: Input) {
		
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
		
		let resourceDownloader = ResourceDownloader()
		
		super.init()
		
		serverConnection.onChunk = { [weak self] chunk in
			guard let self else { return }
			
			self.clientWorld.receiveChunk(chunk)
			
			for (dx, dz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
				for i in 0..<Chunk.sectionCount {
					self.clientWorld.dirtySections.insert(
						SectionPosition(
							chunkX: chunk.chunkX + dx,
							chunkZ: chunk.chunkZ + dz,
							sectionIndex: i
						)
					)
				}
			}
		}
		
		serverConnection.onPosition = { [weak self] player in
			guard let self else { return }
			
			self.cameraPosition = SIMD3<Float>(
				Float(player.x),
				Float(player.y) + Renderer.eyeHeight,
				Float(player.z)
			)
			
			self.cameraYaw = -player.yaw * .pi / 180
			self.cameraPitch = player.pitch * .pi / 180
			self.hasSpawned = true
		}
		
		positionTimer = Timer.scheduledTimer(
			withTimeInterval: 1.0 / 20.0,
			repeats: true
		) { [weak self] _ in
			guard let self, self.hasSpawned else { return }
			
			var player = Player()
			player.x = Double(self.cameraPosition.x)
			player.y = Double(self.cameraPosition.y - Renderer.eyeHeight)
			player.z = Double(self.cameraPosition.z)
			player.yaw = -self.cameraYaw * 180 / .pi
			player.pitch = self.cameraPitch * 180 / .pi
			
			self.serverConnection.sendPlayerPosition(player, onGround: false)
		}
		
		Task {
			do {
				_ = try await resourceDownloader.downloadAllBlockAndItemTextures()
				
				let modelFolder = try await resourceDownloader.downloadAllModelJSONs()
				self.modelFolder = modelFolder
				
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
				
				let serverJar = try await resourceDownloader.downloadServerJar()
				
				minecraftServer.start(
					jar: serverJar,
					worldFolder: support.appendingPathComponent("Worlds/New World")
				) {
					print("server is ready")
					self.serverConnection.connect(host: "127.0.0.1", port: self.minecraftServer.serverPort())
				}
			} catch {
				print("Resource download failed:", error)
			}
		}
		AppDelegate.server = minecraftServer
	}
	
	func rebuildDirtySections() {
		guard let modelFolder, let blockStateFolder else { return }
		
		let batch = Array(clientWorld.dirtySections.prefix(10000))
		
		for position in batch {
			clientWorld.dirtySections.remove(position)
			
			guard let chunk = clientWorld.chunk(
				atX: position.chunkX,
				z: position.chunkZ
			), let world = snapshot(around: position) else { continue }
			
			meshQueue.async {
				let mesh = buildSectionRenderMesh(
					from: chunk,
					sectionIndex: position.sectionIndex,
					device: self.device,
					modelFolder: modelFolder,
					blockStateFolder: blockStateFolder,
					clientWorld: world
				)
				
				DispatchQueue.main.async {
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
	
	// Called repeatedly by MTKView to draw each frame
	func draw(in view: MTKView) {
		if !clientWorld.dirtySections.isEmpty {
			rebuildDirtySections()
		}
		
		// Forward direction based on camera yaw
		let forward = SIMD3<Float>(
			sin(cameraYaw),
			0,
			cos(cameraYaw)
		)
		
		// Right direction based on camera yaw
		let right = SIMD3<Float>(
			cos(cameraYaw),
			0,
			-sin(cameraYaw)
		)
		
		let up = SIMD3<Float>(
			0,
			1,
			0
		)
		
		let moveSpeed: Float = 1
		
		if input.wPressed {
			cameraPosition += forward * moveSpeed
		}
		
		if input.sPressed {
			cameraPosition -= forward * moveSpeed
		}
		
		if input.aPressed {
			cameraPosition -= right * moveSpeed
		}
		
		if input.dPressed {
			cameraPosition += right * moveSpeed
		}
		
		if input.spacePressed {
			cameraPosition += up * moveSpeed
		}
		
		if input.shiftPressed {
			cameraPosition -= up * moveSpeed
		}
		
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
		
		// Mouse yaw
		cameraYaw += input.mouseDeltaX * 0.002
		input.mouseDeltaX = 0
		
		// Mouse pitch
		cameraPitch += input.mouseDeltaY * 0.002
		
		cameraPitch = max(
			-.pi / 2 + 0.01,
			 min(.pi / 2 - 0.01, cameraPitch)
		)
		
		input.mouseDeltaY = 0
		
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
		
		let loaded = loadMinecraftTexture(from: textureURL)
		textureCache[name] = loaded
		return loaded
	}
	
	// Decodes a Minecraft PNG into raw pixels and creates a Metal texture
	func loadMinecraftTexture(from textureURL: URL) -> MTLTexture {
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
				height: height,
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
					height
				),
				mipmapLevel: 0,
				withBytes: pixelData,
				bytesPerRow: bytesPerRow
			)
			
			return texture
		} catch {
			fatalError(
				"Failed texture: \(textureURL.path) — \(error)"
			)
		}
	}
}
