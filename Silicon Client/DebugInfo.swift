import SwiftUI
import Combine

// What the F3 screen shows. Renderer fills this in a few times a second
// rather than every frame — the numbers are unreadable faster than that,
// and every change redraws the view.
final class DebugInfo: ObservableObject {
	@Published var isVisible = false
	
	@Published var fps = 0
	@Published var frameMilliseconds = 0.0
	
	@Published var x = 0.0
	@Published var y = 0.0
	@Published var z = 0.0
	@Published var facing = ""
	@Published var yaw = 0.0
	@Published var pitch = 0.0
	
	@Published var chunksLoaded = 0
	@Published var sectionMeshes = 0
	@Published var sectionsQueued = 0
	
	@Published var meshMilliseconds = 0.0
	@Published var blocksPerSecond = 0.0
}
