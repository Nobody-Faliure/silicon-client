import SwiftUI

struct ContentView: View {

	@State private var isPlaying = false
	@StateObject private var status = LoadingStatus()
	@StateObject private var debug = DebugInfo()

	var body: some View {
		if isPlaying {
			ZStack {
				// Always built, even while hidden — creating it is what
				// makes the Renderer, which starts the download.
				GameView(status: status, debug: debug)

				if !status.isReady {
					LoadingView(status: status)
				}
				
				if debug.isVisible {
					DebugView(info: debug)
				}
			}
		} else {
			VStack {
				Text("Silicon Client")
				Text("0.0.1-dev.1")

				Button("Singleplayer") {
					isPlaying = true
				}
			}
			.padding()
		}
	}
}

#Preview {
	ContentView()
}
