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
	
}
