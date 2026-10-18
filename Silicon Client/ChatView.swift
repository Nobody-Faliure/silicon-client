import SwiftUI

struct ChatView: View {
	@ObservedObject var info: ChatInfo
	
	var body: some View {
		VStack {
			Spacer()
			Text(info.text + "_")
				.font(.system(size: 14, design: .monospaced))
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(6)
				.background(.black.opacity(0.5))
		}
		.padding(4)
		.allowsHitTesting(false)
	}
}
