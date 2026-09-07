import Metal
import MetalKit

struct Vertex {
	let position: SIMD3<Float>
	let uv: SIMD2<Float>
}

// MTKViewDelegate lets Renderer receive draw calls from MTKView
final class Renderer: NSObject, MTKViewDelegate {
	
	// Core Metal objects used to talk to the GPU
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	
	// GPU rendering resources
	let depthStencilState: MTLDepthStencilState
	let pipelineState: MTLRenderPipelineState
	
	// Keyboard and mouse input
	let input: Input
	
	// Camera matrices
	var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
	var viewMatrix: simd_float4x4 = matrix_identity_float4x4
	
	// Camera state
	var cameraPosition = SIMD3<Float>(0, 0, 0)
	var cameraYaw: Float = 0
	var cameraPitch: Float = 0
	
	// Client-side copy of the world
	var clientWorld: ClientWorld = ClientWorld()
	
	var chunkMeshes: [ChunkRenderMesh] = []
	
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
		
		super.init()
		
		// Start the integrated server and receive its world
		let server = IntegratedServer()
		server.sendWorld(to: clientWorld)
		
		// Build the first world mesh
		chunkMeshes = buildWorldMeshes(
			from: clientWorld,
			device: device
		)
	}
	
	// Called repeatedly by MTKView to draw each frame
	func draw(in view: MTKView) {
		
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
		
		let moveSpeed: Float = 0.01
		
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
		for mesh in chunkMeshes {
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
			nearZ: 0.001,
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
	
	func texture(named name: String) -> MTLTexture {
		let textureLoader = MTKTextureLoader(device: device)

		return try! textureLoader.newTexture(
			name: name,
			scaleFactor: 1.0,
			bundle: .main
		)
	}
}
