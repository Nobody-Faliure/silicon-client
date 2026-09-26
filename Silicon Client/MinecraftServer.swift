import Foundation

final class MinecraftServer {
	private var process: Process?
	
	deinit {
		stop()
	}
	
	func start(jar: URL, worldFolder: URL, onReady: @escaping () -> Void) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/java")
		process.arguments = ["-Xmx2G", "-jar", jar.path, "nogui"]
		process.currentDirectoryURL = worldFolder
		let output = Pipe()
		process.standardOutput = output
		process.standardError = output
		
		output.fileHandleForReading.readabilityHandler = { handle in
			guard let line = String(data: handle.availableData, encoding: .utf8),
				!line.isEmpty else { return }

			print("[server] \(line)", terminator: "")

			if line.contains("Done (") {
			DispatchQueue.main.async {
					  onReady()
				}
			}
		}
		
		try? process.run()
		self.process = process
	}
	
	func stop() {
		process?.terminate()
		process = nil
	}
}
