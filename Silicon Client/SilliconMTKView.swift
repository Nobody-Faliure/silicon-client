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
		input.ctrlPressed = false
	}
	
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		window?.makeFirstResponder(self)
		window?.acceptsMouseMovedEvents = true
		captureMouse()
	}
	
	override func keyDown(with event: NSEvent) {
		if input.chatOpen {
			switch event.keyCode {
			case 53:                                   // Esc: cancel
				input.chatOpen = false
				captureMouse()
			case 36:                                   // Enter: send if it's a command
				if input.chatText.hasPrefix("/") && input.chatText.count > 1 {
					input.pendingCommand = String(input.chatText.dropFirst())
				}
				input.chatOpen = false
				captureMouse()
			case 51:                                   // Backspace
				if !input.chatText.isEmpty { input.chatText.removeLast() }
			default:                                   // any other key: add its letter
				if let typed = event.characters,
				   typed.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
					input.chatText += typed
				}
			}
			return
		}
		
		if event.keyCode == 53 {
			if mouseIsCaptured {
				releaseMouse()
			} else {
				captureMouse()
			}
			
			return
		}
		
		if event.keyCode == 44 {                       // "/" opens chat
			input.chatText = "/"
			input.chatOpen = true
			releaseMouse()
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
		if event.keyCode == 49 && !event.isARepeat { input.spaceTapped(at: event.timestamp) }
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
		input.ctrlPressed = mouseIsCaptured && event.modifierFlags.contains(.control)
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
