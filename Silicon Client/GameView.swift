import SwiftUI

struct GameView: View {
	let status: LoadingStatus
	let debug: DebugInfo
	let chat: ChatInfo
		
		var body: some View {
			MetalView(status: status, debug: debug, chat: chat)
		}
}
