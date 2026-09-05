import Metal
import MetalKit

// MTKViewDelegate lets Renderer receive draw calls from MTKView
final class Renderer: NSObject, MTKViewDelegate {
	
	// Core Metal objects and data used by the renderer
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	
	// 3D positions of the triangle's three vertices
	let vertices: [SIMD3<Float>] = [
		SIMD3<Float>(0.0, 0.0, 3.1), SIMD3<Float>(0.1, 0.0, 3.1), SIMD3<Float>(0.1, 0.1, 3.1),
		SIMD3<Float>(0.1, 0.1, 3.1), SIMD3<Float>(0.0, 0.1, 3.1), SIMD3<Float>(0.0, 0.0, 3.1),
		SIMD3<Float>(0.1, 0.0, 3.0), SIMD3<Float>(0.0, 0.0, 3.0), SIMD3<Float>(0.0, 0.1, 3.0),
		SIMD3<Float>(0.0, 0.1, 3.0), SIMD3<Float>(0.1, 0.1, 3.0), SIMD3<Float>(0.1, 0.0, 3.0),
		SIMD3<Float>(0.0, 0.0, 3.0), SIMD3<Float>(0.0, 0.0, 3.1), SIMD3<Float>(0.0, 0.1, 3.1),
		SIMD3<Float>(0.0, 0.1, 3.1), SIMD3<Float>(0.0, 0.1, 3.0), SIMD3<Float>(0.0, 0.0, 3.0),
		SIMD3<Float>(0.1, 0.0, 3.1), SIMD3<Float>(0.1, 0.0, 3.0), SIMD3<Float>(0.1, 0.1, 3.0),
		SIMD3<Float>(0.1, 0.1, 3.0), SIMD3<Float>(0.1, 0.1, 3.1), SIMD3<Float>(0.1, 0.0, 3.1),
		SIMD3<Float>(0.0, 0.1, 3.1), SIMD3<Float>(0.1, 0.1, 3.1), SIMD3<Float>(0.1, 0.1, 3.0),
		SIMD3<Float>(0.1, 0.1, 3.0), SIMD3<Float>(0.0, 0.1, 3.0), SIMD3<Float>(0.0, 0.1, 3.1),
		SIMD3<Float>(0.0, 0.0, 3.0), SIMD3<Float>(0.1, 0.0, 3.0), SIMD3<Float>(0.1, 0.0, 3.1),
		SIMD3<Float>(0.1, 0.0, 3.1), SIMD3<Float>(0.0, 0.0, 3.1), SIMD3<Float>(0.0, 0.0, 3.0)
	]
	
	// GPU vertex storage and the compiled shader pipeline
	let vertexBuffer: MTLBuffer
	let pipelineState: MTLRenderPipelineState
	
	// The input
	let input: Input
	
	// Projection adds perspective; viewMatrix will later represent the camera
	var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
	var viewMatrix: simd_float4x4 = matrix_identity_float4x4
	var cameraPosition = SIMD3<Float>(0, 0, 0)
	var cameraYaw: Float = 0
	var cameraPitch: Float = 0
	
	// Creates the renderer's Metal resources when the object is initialized
	init(input: Input) {
		self.device = MTLCreateSystemDefaultDevice()!
		
		// Load the Metal shaders compiled from Shaders.metal
		let library = device.makeDefaultLibrary()!
		let vertexFunction = library.makeFunction(name: "vertexShader")!
		let fragmentFunction = library.makeFunction(name: "fragmentShader")!
		
		// Configure which shaders and pixel format the GPU pipeline uses
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		self.pipelineState = try! device.makeRenderPipelineState(
			descriptor: pipelineDescriptor
		)
		
		// Create the GPU command queue and copy vertex data into a Metal buffer
		self.commandQueue = device.makeCommandQueue()!
		self.vertexBuffer = device.makeBuffer(
			bytes: vertices,
			length: vertices.count * MemoryLayout<SIMD3<Float>>.stride
		)!
		
		self.input = input
		
		// Run NSObject's initializer after our stored properties are ready
		super.init()
	}
	
	func draw(in view: MTKView) {
		let forward = SIMD3<Float>(
			sin(cameraYaw),
			0,
			cos(cameraYaw)
		)
		
		let right = SIMD3<Float>(
			cos(cameraYaw),
			0,
			-sin(cameraYaw)
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
		
		// Get this frame's render target and set the background clear color
		guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
		renderPassDescriptor.colorAttachments[0].clearColor =
			MTLClearColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 1.0)
		
		// Start recording the GPU commands needed for this frame
		let commandBuffer = commandQueue.makeCommandBuffer()!
		let renderEncoder = commandBuffer.makeRenderCommandEncoder(
			descriptor: renderPassDescriptor
		)!
		
		// Bind the shader pipeline and triangle vertex data
		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
		
		// Send the projection matrix to buffer(1) in the vertex shader
		var matrix = projectionMatrix
		renderEncoder.setVertexBytes(
									&matrix,
									length: MemoryLayout<simd_float4x4>.stride,
									index: 1
		)
		
		// Send the camera matrix to buffer(2) in the vertex shader
		// Turn horizontal mouse movement into left/right camera rotation
		cameraYaw += input.mouseDeltaX * 0.002
		input.mouseDeltaX = 0
		
		// Turn vertical mouse movement into up/down camera rotation
		cameraPitch += input.mouseDeltaY * 0.002
		cameraPitch = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, cameraPitch))
		input.mouseDeltaY = 0

		// Calculate the rotation values for the view matrix
		// The negative yaw is used because the view matrix moves the world
		// opposite to the direction the camera is facing
		let cosYaw = cos(-cameraYaw)
		let sinYaw = sin(-cameraYaw)
		let cosPitch = cos(-cameraPitch)
		let sinPitch = sin(-cameraPitch)

		// These two columns rotate the world around the X and Y axis
		viewMatrix.columns.0 = SIMD4<Float>(cosYaw, sinPitch * sinYaw, -cosPitch * sinYaw, 0)
		viewMatrix.columns.1 = SIMD4<Float>(0, cosPitch, sinPitch, 0)
		viewMatrix.columns.2 = SIMD4<Float>(sinYaw, -sinPitch * cosYaw, cosPitch * cosYaw, 0)

		// Convert the camera's X, Y, and Z position into the rotated coordinate system
		// Then negate them so moving the camera right makes the world move left, etc.
		let translatedX = -(cameraPosition.x * cosYaw + cameraPosition.z * sinYaw)

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

		// Column 3 stores the translation part of the view matrix
		// This moves the entire world opposite to the camera's position
		viewMatrix.columns.3 = SIMD4<Float>(
			translatedX,
			translatedY,
			translatedZ,
			1
		)
		var cameraMatrix = viewMatrix
		renderEncoder.setVertexBytes(&cameraMatrix,
									 length: MemoryLayout<simd_float4x4>.stride,
									 index: 2
		)
		
		// Tell the GPU to draw one triangle from the three vertices
		renderEncoder.drawPrimitives(
			type: .triangle,
			vertexStart: 0,
			vertexCount: 24
		)
		
		// Finish encoding, display the frame, and submit the work to the GPU
		renderEncoder.endEncoding()
		commandBuffer.present(view.currentDrawable!)
		commandBuffer.commit()
	}
	
	func mtkView(
		_ view: MTKView,
		drawableSizeWillChange size: CGSize
	) {
		
		// Recalculate perspective whenever the Metal view changes size
		let aspect = Float(size.width / size.height)
		projectionMatrix = makePerspectiveMatrix(
			fovY: 60 * .pi / 180,
			aspect: aspect,
			nearZ: 0.001,
			farZ: 1000
		)
	}
	
	func makePerspectiveMatrix(
		fovY: Float,
		aspect: Float,
		nearZ: Float,
		farZ: Float
	) -> simd_float4x4 {
		
		// Convert FOV, aspect ratio, and depth range into perspective scale values
		let yScale = 1 / tan(fovY / 2)
		let xScale = yScale / aspect
		let zRange = farZ - nearZ
		let zScale = farZ / zRange
		let wzScale = -(farZ * nearZ) / zRange
		
		// Convert 3D camera-space positions into Metal clip-space coordinates
		return simd_float4x4(
			SIMD4<Float>(xScale, 0, 0, 0),
			SIMD4<Float>(0, yScale, 0, 0),
			SIMD4<Float>(0, 0, zScale, 1),
			SIMD4<Float>(0, 0, wzScale, 0)
		)
	}
}
