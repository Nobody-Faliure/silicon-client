import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
	let status: LoadingStatus
	
	// Keeps the renderer alive
	class Coordinator {
		let renderer:  Renderer
		let input = Input()
		
		init(status: LoadingStatus) {
			renderer = Renderer(input: input, status: status)
			}
	}
	
	// Teaches swift how to use a coordinator
	func makeCoordinator() -> Coordinator {
		Coordinator(status: status)
	}
	
	// Creates the Metal view
	func makeNSView(context: Context) -> MTKView {
		let view = SiliconMTKView(input: context.coordinator.input)
		let renderer = context.coordinator.renderer // gets the renderer stored in the coordinator
		view.device = renderer.device
		view.delegate = renderer
		return view
	}
	
	func updateNSView(_ nsView: MTKView, context: Context) {
		
	}
}
