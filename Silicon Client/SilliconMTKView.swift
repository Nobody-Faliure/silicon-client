import MetalKit
import CoreGraphics

final class SiliconMTKView: MTKView {
	let input: Input
	
	init(input: Input) {
		self.input = input
		super.init(frame: .zero, device: nil)
		
		colorPixelFormat = .bgra8Unorm_srgb
		depthStencilPixelFormat = .depth32Float
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override var acceptsFirstResponder: Bool { true }
	
	// While captured the pointer is hidden and locked to the window, and its
	// movement turns the camera. Escape toggles it, so later a menu can sit
	// here and its buttons stay clickable.
	private var mouseIsCaptured = false
	
	private func captureMouse() {
		guard !mouseIsCaptured else { return }
		
		mouseIsCaptured = true
		CGAssociateMouseAndMouseCursorPosition(0)
		NSCursor.hide()
	}
	
	private func releaseMouse() {
		guard mouseIsCaptured else { return }
		
		mouseIsCaptured = false
		CGAssociateMouseAndMouseCursorPosition(1)
		NSCursor.unhide()
		
		// Anything held down stays held forever otherwise, and you fly away
		// while typing somewhere else.
		input.wPressed = false
		input.aPressed = false
		input.sPressed = false
		input.dPressed = false
		input.spacePressed = false
		input.shiftPressed = false
	}
	
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		window?.makeFirstResponder(self)
		window?.acceptsMouseMovedEvents = true
		captureMouse()
	}
	
	override func keyDown(with event: NSEvent) {
		if event.keyCode == 53 {
			if mouseIsCaptured {
				releaseMouse()
			} else {
				captureMouse()
			}
			
			return
		}
		
		guard mouseIsCaptured else { return }
		
		if event.keyCode == 99 {
			input.showDebug.toggle()
			return
		}
		
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
		input.shiftPressed = mouseIsCaptured && event.modifierFlags.contains(.shift)
	}
	
	override func mouseMoved(with event: NSEvent) {
		guard mouseIsCaptured else { return }
		
		input.mouseDeltaX += Float(event.deltaX)
		input.mouseDeltaY += Float(event.deltaY)
	}
	
	override func scrollWheel(with event: NSEvent) {
		guard mouseIsCaptured else { return }
		
		input.scrollDelta += Float(event.scrollingDeltaY)
	}
}
