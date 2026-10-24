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
	private let log: PacketLog? = nil
	
	var onChunk: ((Chunk) -> Void)?
	var onPosition: ((Player) -> Void)?
	var onForgetChunk: ((Int, Int) -> Void)?
	var onLight: ((Int, Int, [Int: Data], [Int: Data]) -> Void)?
	var onGameMode: ((GameMode) -> Void)?
	var onAbilities: ((_ isFlying: Bool, _ mayFly: Bool, _ flyingSpeed: Double) -> Void)?
	var onEntityID: ((Int) -> Void)?
	var onRespawn: (() -> Void)?
	var onAttributes: ((_ entityID: Int, _ stats: [Int: (base: Double, modifiers: [AttributeModifier])]) -> Void)?
	var onTime: ((_ ticks: Int, _ rate: Double) -> Void)?
	var onBlockState: ((_ blockStateId: Int, _ x: Int, _ y: Int, _ z: Int) -> Void)?
	var onSystemChat: ((_ text: String) -> Void)?
	
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
			
		case (.play, 0x83):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                // packet id
			let entityID = reader.readVarInt()     // whose stats these are
			var stats: [Int: (base: Double, modifiers: [AttributeModifier])] = [:]
			
			for _ in 0..<reader.readVarInt() {     // each stat
				let attribute = reader.readVarInt()    // 26 = walking speed, 19 = jump
				let base = reader.readDouble()
				var modifiers: [AttributeModifier] = []
				
				for _ in 0..<reader.readVarInt() {     // each sticker
					let id = reader.readIdentifier()
					let amount = reader.readDouble()
					let operation = reader.readVarInt()
					modifiers.append(AttributeModifier(id: id, amount: amount, operation: operation))
				}
				
				stats[attribute] = (base, modifiers)
			}
			
			DispatchQueue.main.async { self.onAttributes?(entityID, stats) }
			
		case (.play, 0x08):							// set block state
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()					// packet id
			let position = reader.readLong()
			let x = position >> 38
			let z = (position << 26) >> 38
			let y = (position << 52) >> 52
			let blockStateId = reader.readVarInt()
			
			DispatchQueue.main.async {
				self.onBlockState?(blockStateId, x, y, z)
			}
			
		case (.play, 0x54):							// block sections update
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()					// packet id
			
			let sectionPosition = reader.readLong()
			let sectionX = sectionPosition >> 42
			let sectionZ = (sectionPosition << 22) >> 42
			let sectionY = (sectionPosition << 44) >> 44
			
			let count = reader.readVarInt()
			for _ in 0..<count {
				let packed = reader.readVarLong()
				let blockStateId = packed >> 12
				let localX = (packed >> 8) & 15
				let localZ = (packed >> 4) & 15
				let localY = packed & 15
				
				DispatchQueue.main.async {
					self.onBlockState?(blockStateId, sectionX * 16 + localX, sectionY * 16 + localY, sectionZ * 16 + localZ)
				}
			}
			
		case (.play, 0x79):                                                   // system chat
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                                 // packet id
			guard let tag = reader.readNetworkRoot() else { break }
			let text = Language.plainText(tag)
			DispatchQueue.main.async { self.onSystemChat?(text) }
			
		case (.play, 0x71):
			var reader = NBTReader(data: packet)
			_ = reader.readVarInt()                		// packet id
			_ = reader.readLong()                  		// world age, unused
			
			if reader.readVarInt() > 0 {           		// how many clocks (overworld has 1)
				_ = reader.readVarInt()            		// which clock
				let ticks = reader.readVarLong()   		// total ticks on that clock
				_ = reader.readFloat()             		// part of a tick, unused
				let rate = Double(reader.readFloat())  	// 1 = time moving, 0 = frozen
				
				DispatchQueue.main.async { self.onTime?(ticks, rate) }
			}
			
		default:
			break
		}
	}
	
	func send(_ payload: Data) {
		var packet = Data()
		VarInt.write(payload.count, to: &packet)
		packet.append(payload)
		connection?.send(content: packet, completion: .contentProcessed { _ in })
	}
	
	private var blockSequence = 0
	func sendPlayerAction(status: Int, block: SIMD3<Int>, face: Int) {
		var payload = Data(); VarInt.write(0x29, to: &payload); VarInt.write(status, to: &payload); VarInt.writePosition(block, to: &payload)
		payload.append(UInt8(face)); blockSequence += 1; VarInt.write(blockSequence, to: &payload)
		send(payload)
	}
	
	func sendSwing() {
		var payload = Data(); VarInt.write(0x3f, to: &payload); VarInt.write(0, to: &payload); send(payload)
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
