import SwiftUI

struct LoadingView: View {
    @ObservedObject var status: LoadingStatus

    var body: some View {
        VStack(spacing: 18) {
            Text("Silicon Client")
                .font(.system(size: 34, weight: .semibold, design: .rounded))

            ProgressView()
                .controlSize(.small)

            Text(status.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
