import Foundation
import Network

final class ServerConnection {
	private var connection: NWConnection?
	
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
				self.sendHandshake(host: host, port: port, nextState: 1)
				self.sendStatusRequest()
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
		VarInt.write(-1, to: &payload)
		
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
				print("[net] received \(data.count) bytes")
				print(data.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " "))
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
}
