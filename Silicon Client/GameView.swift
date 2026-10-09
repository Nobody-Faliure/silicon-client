import SwiftUI

struct GameView: View {
	  let status: LoadingStatus
	  let debug: DebugInfo

	  var body: some View {
			  MetalView(status: status, debug: debug)
	  }
}
