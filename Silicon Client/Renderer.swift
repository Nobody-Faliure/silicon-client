import Metal
import MetalKit

// MTKViewDelegate lets Renderer receive draw calls from MTKView
final class Renderer: NSObject, MTKViewDelegate {
	
	// Core Metal objects used to talk to the GPU
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	
	// 36 vertices make a 1 x 1 x 1 cube.
	// The cube goes from:
	// X: 0 -> 1
	// Y: 0 -> 1
	// Z: 1 -> 2
	let vertices: [SIMD3<Float>] = [
		
		// Front face: Z = 1 — points toward -Z
		SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, 0, 1),
		SIMD3<Float>(1, 1, 1), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 1, 1),

		// Back face: Z = 2 — points toward +Z
		SIMD3<Float>(1, 0, 2), SIMD3<Float>(0, 1, 2), SIMD3<Float>(0, 0, 2),
		SIMD3<Float>(0, 1, 2), SIMD3<Float>(1, 0, 2), SIMD3<Float>(1, 1, 2),

		// Left face: X = 0 — points toward -X
		SIMD3<Float>(0, 0, 2), SIMD3<Float>(0, 1, 1), SIMD3<Float>(0, 0, 1),
		SIMD3<Float>(0, 1, 1), SIMD3<Float>(0, 0, 2), SIMD3<Float>(0, 1, 2),

		// Right face: X = 1 — points toward +X
		SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 1, 2), SIMD3<Float>(1, 0, 2),
		SIMD3<Float>(1, 1, 2), SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 1, 1),

		// Top face: Y = 1 — points toward +Y
		SIMD3<Float>(0, 1, 1), SIMD3<Float>(1, 1, 2), SIMD3<Float>(1, 1, 1),
		SIMD3<Float>(1, 1, 2), SIMD3<Float>(0, 1, 1), SIMD3<Float>(0, 1, 2),

		// Bottom face: Y = 0 — points toward -Y
		SIMD3<Float>(0, 0, 2), SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 0, 2),
		SIMD3<Float>(1, 0, 1), SIMD3<Float>(0, 0, 2), SIMD3<Float>(0, 0, 1)
	]
	
	// vertexBuffer stores the cube vertices in GPU-readable memory.
	// pipelineState contains the compiled vertex + fragment shader setup.
	let vertexBuffer: MTLBuffer
	let depthStencilState: MTLDepthStencilState
	let pipelineState: MTLRenderPipelineState
	
	// Stores the keyboard and mouse input state
	let input: Input
	
	// projectionMatrix gives the scene perspective/FOV.
	// viewMatrix represents the camera's position and rotation.
	var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
	var viewMatrix: simd_float4x4 = matrix_identity_float4x4
	
	// Camera location and rotation
	var cameraPosition = SIMD3<Float>(0, 0, 0)
	var cameraYaw: Float = 0
	var cameraPitch: Float = 0
	
	// Creates all the Metal resources when Renderer starts
	init(input: Input) {
		
		// Get the Mac's Metal GPU
		self.device = MTLCreateSystemDefaultDevice()!
		
		// Load the Metal shaders compiled from Shaders.metal
		let library = device.makeDefaultLibrary()!
		let vertexFunction = library.makeFunction(name: "vertexShader")!
		let fragmentFunction = library.makeFunction(name: "fragmentShader")!
		
		// Describe how our rendering pipeline should work
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		
		// The window's color texture uses BGRA pixels
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
		
		// Compile the pipeline description into something the GPU can use
		self.pipelineState = try! device.makeRenderPipelineState(
			descriptor: pipelineDescriptor
		)
		
		// The command queue is where we submit work to the GPU
		self.commandQueue = device.makeCommandQueue()!
		
		// Copy all 36 cube vertices into GPU-accessible memory
		self.vertexBuffer = device.makeBuffer(
			bytes: vertices,
			length: vertices.count * MemoryLayout<SIMD3<Float>>.stride
		)!
		
		// Make depth rules so Metal knows what goes in front of what
		let depthDescriptor = MTLDepthStencilDescriptor()
		depthDescriptor.depthCompareFunction = .less
		depthDescriptor.isDepthWriteEnabled = true
		
		self.depthStencilState = device.makeDepthStencilState(
			descriptor: depthDescriptor
		)!
		
		// Keep the Input object so Renderer can check keys/mouse
		self.input = input
		
		// Initialize NSObject after our properties are ready
		super.init()
	}
	
	// Called repeatedly by MTKView to draw each frame
	func draw(in view: MTKView) {
		
		// Forward points in the direction the camera is facing horizontally.
		// Y stays 0 so W/S do not fly upward when looking up.
		let forward = SIMD3<Float>(
			sin(cameraYaw),
			0,
			cos(cameraYaw)
		)
		
		// Right is 90 degrees sideways from forward.
		// This lets A/D follow the camera's yaw.
		let right = SIMD3<Float>(
			cos(cameraYaw),
			0,
			-sin(cameraYaw)
		)
		
		// World-up always points directly along +Y.
		// This is used for Space/Shift flying.
		let up = SIMD3<Float>(
			0,
			1,
			0
		)
		
		// Camera movement amount per frame
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
		
		// Get the textures used for this frame
		guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
			return
		}
		
		// Start every depth pixel at the farthest possible depth
		renderPassDescriptor.depthAttachment.clearDepth = 1.0
		renderPassDescriptor.depthAttachment.loadAction = .clear
		
		// Clear the previous frame with sky blue
		renderPassDescriptor.colorAttachments[0].clearColor =
			MTLClearColor(
				red: 0.45,
				green: 0.70,
				blue: 1.0,
				alpha: 1.0
			)
		
		// Create a package of GPU commands
		let commandBuffer = commandQueue.makeCommandBuffer()!
		
		// Record rendering instructions
		let renderEncoder = commandBuffer.makeRenderCommandEncoder(
			descriptor: renderPassDescriptor
		)!
		
		// Tell Metal which rendering rules to use
		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setDepthStencilState(depthStencilState)
		
		// Don't draw triangle backs
		renderEncoder.setCullMode(.back)
		
		// Give buffer(0) our cube vertices
		renderEncoder.setVertexBuffer(
			vertexBuffer,
			offset: 0,
			index: 0
		)
		
		// Projection matrix sent to vertex shader buffer(1)
		var matrix = projectionMatrix
		
		renderEncoder.setVertexBytes(
			&matrix,
			length: MemoryLayout<simd_float4x4>.stride,
			index: 1
		)
		
		// Mouse X changes yaw
		cameraYaw += input.mouseDeltaX * 0.002
		input.mouseDeltaX = 0
		
		// Mouse Y changes pitch
		cameraPitch += input.mouseDeltaY * 0.002
		
		// Prevent camera from flipping upside down
		cameraPitch = max(
			-.pi / 2 + 0.01,
			min(.pi / 2 - 0.01, cameraPitch)
		)
		
		input.mouseDeltaY = 0

		// Calculate camera rotation
		let cosYaw = cos(-cameraYaw)
		let sinYaw = sin(-cameraYaw)
		let cosPitch = cos(-cameraPitch)
		let sinPitch = sin(-cameraPitch)

		// Rotation part of the view matrix
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

		// Camera translation after accounting for rotation
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

		// Translation part of the view matrix
		viewMatrix.columns.3 = SIMD4<Float>(
			translatedX,
			translatedY,
			translatedZ,
			1
		)
		
		// Send camera/view matrix into vertex shader buffer(2)
		var cameraMatrix = viewMatrix
		
		renderEncoder.setVertexBytes(
			&cameraMatrix,
			length: MemoryLayout<simd_float4x4>.stride,
			index: 2
		)
		
		// Draw 12 triangles = 6 cube faces
		renderEncoder.drawPrimitives(
			type: .triangle,
			vertexStart: 0,
			vertexCount: 36
		)
		
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
}
