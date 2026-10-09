import SwiftUI
import Combine

final class LoadingStatus: ObservableObject {
    @Published var message = "Starting up"
    @Published var isReady = false

    // Safe to call from any thread. Renderer talks to this from its
    // download Task and from the server's ready callback, neither of
    // which is the main thread, and SwiftUI must be told from main.
    func show(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            self.message = message
        }
    }

    func ready() {
        DispatchQueue.main.async {
            self.isReady = true
        }
    }
}
