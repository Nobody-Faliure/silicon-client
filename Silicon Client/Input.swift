import AppKit

final class Input {
	var wPressed = false
	var aPressed = false
	var sPressed = false
	var dPressed = false
	
	var mouseDeltaX: Float = 0
	var mouseDeltaY: Float = 0
	
	var spacePressed = false
	var shiftPressed = false
	
	var ctrlPressed = false
	
	var spaceDoubleTapped = false          // Player reads this, then resets it
	
	var leftClicked = false                // Renderer reads this, then resets it
	
	private var lastSpaceTap: TimeInterval = 0

	func spaceTapped(at time: TimeInterval) {
		if time - lastSpaceTap < 0.35 {
			spaceDoubleTapped = true
			lastSpaceTap = 0               // so a third tap starts fresh
		} else {
			lastSpaceTap = time
		}
	}
	
	var scrollDelta: Float = 0
	
	var flyStep: Double = 1
	
	var showDebug = false
	
	var chatOpen = false
	var chatText = ""
	var pendingCommand: String?   // Enter puts it here; Renderer sends it and clears it
}
