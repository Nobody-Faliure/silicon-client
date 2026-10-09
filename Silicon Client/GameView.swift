import SwiftUI

struct GameView: View {
	let status: LoadingStatus
	var body: some View {
		MetalView(status: status)
	}
}
