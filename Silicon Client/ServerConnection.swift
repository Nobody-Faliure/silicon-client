import Foundation
import Network

enum ProtocolState {
	case handshaking
	case status
	case login
	case configuration
	case play
}

final class ServerConnection {
	private var connection: NWConnection?
	private var incoming = Data()
	private var protocolState: ProtocolState = .handshaking
	private let log = PacketLog(fileName: "packets.bin")
	
	var onChunk: ((Chunk) -> Void)?
	var onPosition: ((Player) -> Void)?
	var onForgetChunk: ((Int, Int) -> Void)?
	var onLight: ((Int, Int, [Int: Data], [Int: Data]) -> Void)?
	var onGameMode: ((GameMode) -> Void)?
	var onAbilities: ((_ isFlying: Bool, _ mayFly: Bool, _ flyingSpeed: Double) -> Void)?
	var onEntityID: ((Int) -> Void)?
	var onRespawn: (() -> Void)?
	
	func connect(host: String, port: UInt16) {
		let endpoint = NWEndpoint.hostPort(
			host: NWEndpoint.Host(host),
			port: NWEndpoint.Port(rawValue: port)!
		)
		
		let connection = NWConnection(to: endpoint, using: .tcp)
		
		connection.stateUpdateHandler = { state in
			switch state {
			case .ready:
				print("[net] connected to \(host):\(port)")
				self.receive()
				self.sendHandshake(host: host, port: port, nextState: 2)
				self.protocolState = .login
				self.sendLoginStart(username: "wreckStoner")
			case .failed(let error):
				print("[net] failed: \(error)")
			case .waiting(let error):
				print("[net] waiting: \(error)")
			default:
				break
			}
		}
		
		connection.start(queue: .global())
		self.connection = connection
	}
	
	func sendHandshake(host: String, port: UInt16, nextState: Int) {
		var payload = Data()
		
		VarInt.write(0, to: &payload)
		VarInt.write(776, to: &payload)
		
		VarInt.writeString(host, to: &payload)
		
		payload.append(UInt8(port >> 8))
		payload.append(UInt8(port & 0xFF))
		
		VarInt.write(nextState, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { error in
			if let error {
				print("[net] send failed: \(error)")
			} else {
				print("[net] sent handshake, \(packet.count) bytes")
			}
		})
	}
	
	func sendStatusRequest() {
		var packet = Data()
		
		VarInt.write(1, to: &packet)
		VarInt.write(0, to: &packet)
		
		connection?.send(content: packet, completion: .contentProcessed { error in
			if let error {
				print("[net] send failed: \(error)")
			} else {
				print("[net] sent status request")
			}
		})
	}
	
	
	func receive() {
		connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
			if let data, !data.isEmpty {
				self.incoming.append(data)
				self.processPackets()
			}
			
			if let error {
				print("[net] receive error: \(error)")
				return
			}
			
			if isComplete {
				print("[net] connection closed")
				return
			}
			
			self.receive()
		}
	}
	
	private func processPackets() {
		while true {
			var index = 0
			
			guard let length = VarInt.read(from: incoming, at: &index) else {
				return
			}
			
			let total = index + length
			
			guard incoming.count >= total else {
				return
			}
			
			let packet = incoming.subdata(in: index ..< total)
			incoming = Data(incoming.dropFirst(total))
			
			handle(packet)
		}
	}
	
	private func handle(_ packet: Data) {
		log?.append(packet)
		
		var index = 0
		guard let id = VarInt.read(from: packet, at: &index) else { return }
		
		switch (protocolState, id) {
		case (.login, 0x02):
			sendLoginAcknowledged()
			protocolState = .configuration
			
		case (.configuration, 0x0e):
			sendKnownPacks()
			
		case (.configuration, 0x07):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()
			let registry = reader.readIdentifier()
			let count = reader.readVarInt()
			
			guard registry == "minecraft:worldgen/biome" else { break }
			
			var biomes: [Biome] = []
			
			for _ in 0..<count {
				_ = reader.readIdentifier()                 // the name; we only need the order
				let hasData = reader.readByte() == 1
				let tag = hasData ? reader.readNetworkRoot() : nil
				
				biomes.append(tag.flatMap(BiomeRegistry.biome(from:)) ?? .unknown)
			}
			
			BiomeRegistry.biomes = biomes
			if let folder = BiomeRegistry.colormapFolder {
				BiomeRegistry.applyColormaps(in: folder)
			}
			
		case (.configuration, 0x03):
			sendFinishConfiguration()
			protocolState = .play
			sendClientInformation()
			
		case (.play, 0x2c):
			sendKeepAlive(packet.dropFirst(index))
			
		case (.play, 0x2d):
			if let chunk = ChunkDecoder.decode(packet: packet) {
				DispatchQueue.main.async {
					self.onChunk?(chunk)
				}
			}
			
		case (.play, 0x48):
			if let result = PositionDecoder.decode(packet: packet) {
				
				DispatchQueue.main.async {
					self.onPosition?(result.player)
					self.sendConfirmTeleport(result.teleportID)
				}
			}
			
		case (.play, 0x0b):
			sendChunkBatchReceived(chunksPerTick: 16)
			
		case (.play, 0x30):
			var reader = NBTReader(data: packet)
			
			_ = reader.readVarInt()
			
			let chunkX = reader.readVarInt()
			let chunkZ = reader.readVarInt()
			
			let light = LightDecoder.decode(from: &reader)
			
			DispatchQueue.main.async {
				self.onLight?(chunkX, chunkZ, light.sky, light.block)
			}
			
		case (.play, 0x25):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()
			
			let chunkZ = reader.readInteger(byteCount: 4)
			let chunkX = reader.readInteger(byteCount: 4)
			
			DispatchQueue.main.async {
				self.onForgetChunk?(chunkX, chunkZ)
			}
			
		case (.play, 0x31):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                // packet id
			let entityID = reader.readInt()        // your entity id
			DispatchQueue.main.async { self.onEntityID?(entityID) }
			_ = reader.readByte()                  // hardcore
			let dimensionCount = reader.readVarInt()
			for _ in 0..<dimensionCount { _ = reader.readIdentifier() }  // world names
			_ = reader.readVarInt()                // max players
			_ = reader.readVarInt()                // view distance
			_ = reader.readVarInt()                // simulation distance
			_ = reader.readByte()                  // reduced debug info
			_ = reader.readByte()                  // respawn screen
			_ = reader.readByte()                  // limited crafting
			_ = reader.readVarInt()                // dimension type
			_ = reader.readIdentifier()            // dimension name
			_ = reader.readLong()                  // hashed seed
			
			if let mode = GameMode(rawValue: reader.readByte()) {
				DispatchQueue.main.async { self.onGameMode?(mode) }
			}
			
		case (.play, 0x26):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                // packet id
			let event = reader.readByte()          // which kind of message
			let value = reader.readFloat()         // the message's number
			
			if event == 3, let mode = GameMode(rawValue: UInt8(value)) {
				DispatchQueue.main.async { self.onGameMode?(mode) }
			}
			
		case (.play, 0x40):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                // packet id
			let flags = reader.readByte()
			let flyingSpeed = Double(reader.readFloat())
			_ = reader.readFloat()                 // walking speed (zoom), unused for now
			
			let isFlying = flags & 0x02 != 0       // flying right now
			let mayFly   = flags & 0x04 != 0       // allowed to fly
			
			DispatchQueue.main.async {
				self.onAbilities?(isFlying, mayFly, flyingSpeed)
			}
			
		case (.play, 0x68):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                // packet id
			let health = reader.readFloat()        // 20 = full hearts, 0 = dead
			
			if health <= 0 {
				sendRespawn()
				DispatchQueue.main.async { self.onRespawn?() }
			}
			
		default:
			break
		}
	}
	
	func sendLoginStart(username: String) {
		var payload = Data()
		
		VarInt.write(0, to: &payload)
		VarInt.writeString(username, to: &payload)
		
		let uuid = UUID()
		withUnsafeBytes(of: uuid.uuid) { payload.append(contentsOf: $0) }
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { error in
			if let error {
				print("[net] send failed: \(error)")
			} else {
				print("[net] sent login start")
			}
		})
	}
	
	func sendLoginAcknowledged() {
		var packet = Data()
		
		VarInt.write(1, to: &packet)
		VarInt.write(3, to: &packet)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in
			print("[net] sent login acknowledged")
		})
	}
	
	func sendKnownPacks() {
		var payload = Data()
		
		VarInt.write(0x07, to: &payload)
		VarInt.write(0, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in
			print("[net] sent known packs (none)")
		})
	}
	
	func sendFinishConfiguration() {
		var packet = Data()
		
		VarInt.write(1, to: &packet)
		VarInt.write(3, to: &packet)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in
			print("[net] sent finish configuration")
		})
	}
	
	func sendKeepAlive(_ payload: Data) {
		var body = Data()
		
		VarInt.write(0x1c, to: &body)
		body.append(payload)
		
		var packet = Data()
		VarInt.write(body.count, to: &packet)
		packet.append(body)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendPlayerPosition(_ player: Player, onGround: Bool) {
		var payload = Data()
		
		VarInt.write(0x1f, to: &payload)
		
		VarInt.writeDouble(player.position.x, to: &payload)
		VarInt.writeDouble(player.position.y, to: &payload)
		VarInt.writeDouble(player.position.z, to: &payload)
		
		VarInt.writeFloat(player.yaw, to: &payload)
		VarInt.writeFloat(player.pitch, to: &payload)
		
		payload.append(onGround ? 1 : 0)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendConfirmTeleport(_ teleportID: Int) {
		var payload = Data()
		
		VarInt.write(0x00, to: &payload)
		VarInt.write(teleportID, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		print("[net] confirming teleport \(teleportID)")
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendClientInformation() {
		var payload = Data()
		
		VarInt.write(0x0e, to: &payload)
		
		VarInt.writeString("en_us", to: &payload)
		payload.append(17)                   		// view distance, in chunks
		VarInt.write(0, to: &payload)       		// chat mode: 0 = enabled
		payload.append(1)                   		// chat colors: true
		payload.append(0x7f)                		// skin parts: all shown
		VarInt.write(1, to: &payload)				// main hand: 1 = right
		payload.append(0)                          	// text filtering: false
		payload.append(1)                          	// server listings: true
		VarInt.write(0, to: &payload)              	// particle status: 0 = all
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in
			print("[net] sent client information, view distance 16")
		})
	}
	
	func sendChunkBatchReceived(chunksPerTick: Float) {
		var payload = Data()
		
		VarInt.write(0x0b, to: &payload)
		VarInt.writeFloat(chunksPerTick, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendClientTickEnd() {
		var payload = Data()
		
		VarInt.write(0x0d, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendFlying(_ isFlying: Bool) {
		var payload = Data()
		
		VarInt.write(0x28, to: &payload)
		payload.append(isFlying ? 0x02 : 0x00)   // only the flying bit counts
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendSprinting(_ isSprinting: Bool, entityID: Int) {
		var payload = Data()
		
		VarInt.write(0x2a, to: &payload)
		VarInt.write(entityID, to: &payload)
		VarInt.write(isSprinting ? 1 : 2, to: &payload)   // 1 start, 2 stop
		VarInt.write(0, to: &payload)                     // horse jump, unused
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendCommand(_ command: String) {
		var payload = Data()
		
		VarInt.write(0x07, to: &payload)
		VarInt.writeString(command, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendRespawn() {
		var payload = Data()
		
		VarInt.write(0x0c, to: &payload)
		VarInt.write(0, to: &payload)                     // 0 = respawn, 1 = open stats
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	func sendPlayerLoaded() {
		var payload = Data()
		
		VarInt.write(0x2c, to: &payload)
		
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
}
