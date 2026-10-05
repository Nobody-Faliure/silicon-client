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
		
		let hex = packet.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " ")
		print("[net] packet \(packet.count) bytes: \(hex)")
		
		var index = 0
		guard let id = VarInt.read(from: packet, at: &index) else { return }
		
		switch (protocolState, id) {
		case (.login, 0x02):
			sendLoginAcknowledged()
			protocolState = .configuration
		case (.configuration, 0x0e):
			sendKnownPacks()
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
				sendConfirmTeleport(result.teleportID)
				
				DispatchQueue.main.async {
					self.onPosition?(result.player)
				}
			}
		case (.play, 0x0b):
			sendChunkBatchReceived(chunksPerTick: 16)
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
		
		VarInt.writeDouble(player.x, to: &payload)
		VarInt.writeDouble(player.y, to: &payload)
		VarInt.writeDouble(player.z, to: &payload)
		
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
		payload.append(16)                   		// view distance, in chunks
		VarInt.write(0, to: &payload)       		// chat mode: 0 = enabled
		payload.append(1)                   		// chat colours: true
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
}
