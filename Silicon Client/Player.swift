import Foundation

struct Player {
	var position = SIMD3<Double>(0, 0, 0)
	
	var yaw: Float = 0
	var pitch: Float = 0
	
	static let spectatorFlySpeed: Double = 10.9
	
	// Where the player was one tick ago. The camera slides from here to now.
	var previousTickPosition = SIMD3<Double>(0, 0, 0)
	
	mutating func spectatorFly(input: Input, deltaTime: Double) {
		if input.scrollDelta != 0 {
			input.flyStep = min(4, max(1, input.flyStep + Double(input.scrollDelta) * 0.1))
			input.scrollDelta = 0
		}

		let distance = Player.spectatorFlySpeed * input.flyStep * deltaTime
		
		let sinYaw = Double(sin(yaw))
		let cosYaw = Double(cos(yaw))
		
		if input.wPressed     { position.x += sinYaw * distance; position.z += cosYaw * distance }
		if input.sPressed     { position.x -= sinYaw * distance; position.z -= cosYaw * distance }
		if input.aPressed     { position.x -= cosYaw * distance; position.z += sinYaw * distance }
		if input.dPressed     { position.x += cosYaw * distance; position.z -= sinYaw * distance }
		if input.spacePressed { position.y += distance }
		if input.shiftPressed { position.y -= distance }
	}
	
	mutating func updateLookDirection(input: Input) {
		self.yaw += input.mouseDeltaX * 0.002
		input.mouseDeltaX = 0
		
		// Mouse pitch
		self.pitch += input.mouseDeltaY * 0.002
		
		self.pitch = max(
			-.pi / 2 + 0.01,
			 min(.pi / 2 - 0.01, self.pitch)
		)
		
		input.mouseDeltaY = 0
	}
}

enum PositionDecoder {
	static func decode(packet: Data) -> (teleportID: Int, player: Player)? {
		var reader = NBTReader(data: packet)
		
		guard reader.readVarInt() == 0x48 else { return nil }
		
		let teleportID = reader.readVarInt()
		
		var player = Player()
		
		player.position.x = reader.readDouble()
		player.position.y = reader.readDouble()
		player.position.z = reader.readDouble()
		
		player.previousTickPosition = player.position
		
		reader.index += 24          // velocity x, y, z — unused
		
		player.yaw = -reader.readFloat() * .pi / 180
		player.pitch = reader.readFloat() * .pi / 180
		
		return (teleportID, player)
	}
}
