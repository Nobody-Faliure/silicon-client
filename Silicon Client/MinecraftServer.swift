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
		"gamemode": "creative",
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
	
	static func generateReports(jar: URL) {
		let versionFolder = jar.deletingLastPathComponent()
		
		let blocks = versionFolder
			.appendingPathComponent("GeneratedData")
			.appendingPathComponent("reports")
			.appendingPathComponent("blocks.json")
		
		let dayTimeline = versionFolder
			.appendingPathComponent("GeneratedData/data/minecraft/timeline/day.json")
		
		if FileManager.default.fileExists(atPath: blocks.path),
		   FileManager.default.fileExists(atPath: dayTimeline.path) { return }
		
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/java")
		process.arguments = [
			"-DbundlerMainClass=net.minecraft.data.Main",
			"-jar", jar.path,
			"--reports",
			"--server",
			"--output", "GeneratedData"
		]
		
		process.currentDirectoryURL = versionFolder
		
		do {
			try process.run()
			process.waitUntilExit()
			print("[reports] generated blocks.json")
		} catch {
			print("[reports] could not run the data generator: \(error)")
		}
	}
	
	static func generateBlockData(jar: URL) {
		let versionFolder = jar.deletingLastPathComponent()
		let output = BlockData.file(jar: jar)
		if FileManager.default.fileExists(atPath: output.path) { return }
		let folder = output.deletingLastPathComponent()
		let oldFiles = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
		for name in oldFiles where name.hasPrefix("block-data") {
			try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
		}
		try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
		
		let jarFolders = ["libraries", "versions"].map { versionFolder.appendingPathComponent($0) }
		let jars = jarFolders.flatMap { folder in
			FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
		}
		let classpath = jars.filter { $0.pathExtension == "jar" }.map(\.path).joined(separator: ":")
		guard let extractor = Bundle.main.url(forResource: "BlockDataExtractor", withExtension: "java") else { return }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/java")
		process.arguments = ["-cp", classpath, extractor.path, output.path]
		
		do {
			try process.run()
			process.waitUntilExit()
		} catch {
			print("[block data] could not run the extractor: \(error)")
		}
	}
	
	static func generateBlockTints(jar: URL) {
		let versionFolder = jar.deletingLastPathComponent()
		let output = versionFolder.appendingPathComponent("GeneratedData/silicon/block-tints.json")
		if FileManager.default.fileExists(atPath: output.path) { return }
		try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
		
		var jarPaths = [versionFolder.appendingPathComponent("client.jar").path]
		let libraryWalker = FileManager.default.enumerator(at: versionFolder.appendingPathComponent("libraries"), includingPropertiesForKeys: nil)
		while let file = libraryWalker?.nextObject() as? URL {
			if file.pathExtension == "jar" { jarPaths.append(file.path) }
		}
		guard let extractor = Bundle.main.url(forResource: "BlockTintExtractor", withExtension: "java") else { return }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/java")
		process.arguments = ["-cp", jarPaths.joined(separator: ":"), extractor.path, output.path]
		do {
			try process.run()
			process.waitUntilExit()
		} catch {
			print("[block tints] could not run the extractor: \(error)")
		}
	}
	
	func stop() {
		if process?.isRunning == true {
			process?.terminate()
		}
		
		process = nil
	}
}
