import SwiftUI

struct ContentView: View {

	@State private var isPlaying = false

	var body: some View {
		if isPlaying {
			GameView()
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
