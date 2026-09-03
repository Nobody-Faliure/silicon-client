import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
	// Keeps the renderer alive
	class Coordinator {
		let renderer:  Renderer
		let input = Input()
		
		init() {
				renderer = Renderer(input: input)
			}
	}
	
	// Teaches swift how to use a coordinator
	func makeCoordinator() -> Coordinator {
		Coordinator()
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
