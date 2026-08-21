import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
	func makeNSView(context: Context) -> MTKView {
		MTKView()
	}
	
	func updateNSView(_ nsView: MTKView, context: Context) {
		
	}
}
