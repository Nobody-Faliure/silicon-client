import Combine

final class ChatInfo: ObservableObject {
    @Published var isOpen = false
    @Published var text = ""
}
