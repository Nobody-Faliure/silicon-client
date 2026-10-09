import Foundation

final class MinecraftServer {
	private var process: Process?
	private var worldFolder: URL?
	private let requiredProperties = [
		"server-ip": "127.0.0.1",            // never reachable from outside
		"online-mode": "false",              // local singleplayer
		"max-players": "1",
		"network-compression-threshold": "-1",   // no zlib on the packet path
		"pause-when-empty-seconds": "0",     // never pause the world
		"view-distance": "32",
		"simulation-distance": "8",
		"gamemode": "spectator",
		"allow-flight": "true",
	]
	
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
	
	// Reads server-port out of server.properties
	func serverPort() -> UInt16 {
		guard let worldFolder else {
			return 25565
		}
		
		let file = worldFolder.appendingPathComponent("server.properties")
		
		guard let text = try? String(contentsOf: file, encoding: .utf8) else {
			return 25565
		}
		
		for line in text.split(separator: "\n") {
			guard line.hasPrefix("server-port=") else {
				continue
			}
			
			return UInt16(line.dropFirst("server-port=".count)) ?? 25565
		}
		
		return 25565
	}
	
	func start(jar: URL, worldFolder: URL, onReady: @escaping () -> Void) {
		self.worldFolder = worldFolder
		
		// Makes the folder if it is not there. On a clean Mac it is not, and
		// starting Java inside a folder that does not exist crashes the app.
		try? FileManager.default.createDirectory(
			at: worldFolder,
			withIntermediateDirectories: true
		)
		
		// The server will not boot without this.
		try? "eula=true\n".write(
			to: worldFolder.appendingPathComponent("eula.txt"),
			atomically: true,
			encoding: .utf8
		)
		
		killOrphan()
		applyRequiredProperties(in: worldFolder)
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
	
	private func applyRequiredProperties(in worldFolder: URL) {
		let file = worldFolder.appendingPathComponent("server.properties")
		
		var settings: [String: String] = [:]
		
		if let text = try? String(contentsOf: file, encoding: .utf8) {
			for line in text.split(separator: "\n") {
				guard !line.hasPrefix("#"),
					  let equals = line.firstIndex(of: "=") else { continue }
				
				let key = String(line[line.startIndex ..< equals])
				let value = String(line[line.index(after: equals)...])
				settings[key] = value
			}
		}
		
		for (key, value) in requiredProperties {
			settings[key] = value
		}
		
		let text = settings
			.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: "\n")
		
		try? text.write(to: file, atomically: true, encoding: .utf8)
	}
	
	func stop() {
		if process?.isRunning == true {
			process?.terminate()
		}
		
		process = nil
	}
}
