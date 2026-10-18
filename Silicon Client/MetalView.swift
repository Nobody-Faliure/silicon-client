import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
	let status: LoadingStatus
	let debug: DebugInfo
	let chat: ChatInfo
	
	// Keeps the renderer alive
	class Coordinator {
		let renderer:  Renderer
		let input = Input()
		
		init(status: LoadingStatus, debug: DebugInfo, chat: ChatInfo) {
			renderer = Renderer(input: input, status: status, debug: debug, chat: chat)
		}
	}
	
	// Teaches swift how to use a coordinator
	func makeCoordinator() -> Coordinator {
		Coordinator(status: status, debug: debug, chat: chat)
	}
	
	// Creates the Metal view
	func makeNSView(context: Context) -> MTKView {
		let view = SiliconMTKView(input: context.coordinator.input)
		let renderer = context.coordinator.renderer // gets the renderer stored in the coordinator
		view.device = renderer.device
		view.delegate = renderer
		view.preferredFramesPerSecond = 500
		(view.layer as? CAMetalLayer)?.displaySyncEnabled = false
		return view
	}
	
	func updateNSView(_ nsView: MTKView, context: Context) {
		
	}
}
