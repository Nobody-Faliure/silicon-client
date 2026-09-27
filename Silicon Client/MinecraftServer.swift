import Foundation

final class MinecraftServer {
	private var process: Process?
	private var worldFolder: URL?
	
	deinit {
		stop()
	}
	
	private var pidFile: URL? {
		worldFolder?.appendingPathComponent("silicon-server.pid")
	}
	
	private func killOrphan() {
		guard let pidFile,
			  let text = try? String(contentsOf: pidFile, encoding: .utf8),
			  let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
			return
		}
		
		guard kill(pid, 0) == 0 else {
			try? FileManager.default.removeItem(at: pidFile)
			return
		}
		
		print("Killing orphaned server \(pid) from a previous run")
		kill(pid, SIGTERM)
		
		for _ in 0..<50 {
			if kill(pid, 0) != 0 {
				break
			}
			usleep(100_000)
		}
		
		try? FileManager.default.removeItem(at: pidFile)
	}
	
	func start(jar: URL, worldFolder: URL, onReady: @escaping () -> Void) {
		self.worldFolder = worldFolder
		killOrphan()
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
		
		if let pidFile {
			try? "\(process.processIdentifier)".write(
				to: pidFile,
				atomically: true,
				encoding: .utf8
			)
		}
	}
	
	func stop() {
		process?.terminate()
		process = nil
	}
}
