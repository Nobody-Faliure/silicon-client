import SwiftUI

struct ContentView: View {

	@State private var isPlaying = false
	@StateObject private var status = LoadingStatus()
	@StateObject private var debug = DebugInfo()
	@StateObject private var chat = ChatInfo()

	var body: some View {
		if isPlaying {
			ZStack {
				// Always built, even while hidden — creating it is what
				// makes the Renderer, which starts the download.
				GameView(status: status, debug: debug, chat: chat)

				if !status.isReady {
					LoadingView(status: status)
				}
				
				if debug.isVisible {
					DebugView(info: debug)
				}
				
				if chat.isOpen {
					ChatView(info: chat)
				}
			}
		} else {
			VStack {
				Text("Silicon Client")
				Text(SiliconVersion.current)

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
