import MetalKit
import CoreGraphics

final class SiliconMTKView: MTKView {
	let input: Input
	
	
	init(input: Input) {
		self.input = input
		super.init(frame: .zero, device: nil)
		
		colorPixelFormat = .bgra8Unorm
		depthStencilPixelFormat = .depth32Float
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override var acceptsFirstResponder: Bool { true }
	
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		window?.makeFirstResponder(self)
		window?.acceptsMouseMovedEvents = true
		CGAssociateMouseAndMouseCursorPosition(0)
		NSCursor.hide()
	}
	
	override func keyDown(with event: NSEvent) {
		if event.keyCode == 13 { input.wPressed = true }
		if event.keyCode == 0 { input.aPressed = true }
		if event.keyCode == 1 { input.sPressed = true }
		if event.keyCode == 2 { input.dPressed = true }
		if event.keyCode == 49 { input.spacePressed = true }
	}
	
	override func keyUp(with event: NSEvent) {
		if event.keyCode == 13 { input.wPressed = false }
		if event.keyCode == 0 { input.aPressed = false }
		if event.keyCode == 1 { input.sPressed = false }
		if event.keyCode == 2 { input.dPressed = false }
		if event.keyCode == 49 { input.spacePressed = false }
	}
	
	override func flagsChanged(with event: NSEvent) {
		input.shiftPressed = event.modifierFlags.contains(.shift)
	}
	
	override func mouseMoved(with event: NSEvent) {
		input.mouseDeltaX += Float(event.deltaX)
		input.mouseDeltaY += Float(event.deltaY)
	}
}
