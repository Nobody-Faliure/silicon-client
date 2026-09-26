import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
	  static var server: MinecraftServer?

	  func applicationWillTerminate(_ notification: Notification) {
			  AppDelegate.server?.stop()
	  }
}

@main
struct Silicon_ClientApp: App {
	  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	  var body: some Scene {
			  WindowGroup {
					  ContentView()
			  }
	  }
}
