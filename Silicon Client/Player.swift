import Foundation

struct Player {
	var x: Double = 0
	var y: Double = 0
	var z: Double = 0
	
	var yaw: Float = 0
	var pitch: Float = 0
	
	static let spectatorFlySpeed: Double = 10.9
	
	var flyStep: Double = 1
	
	mutating func spectatorFly(input: Input, deltaTime: Double) {
		if input.scrollDelta != 0 {
			flyStep = min(4, max(1, flyStep + Double(input.scrollDelta) * 0.1))
			input.scrollDelta = 0
		}

		let distance = Player.spectatorFlySpeed * flyStep * deltaTime
		
		let sinYaw = Double(sin(yaw))
		let cosYaw = Double(cos(yaw))
		
		if input.wPressed     { x += sinYaw * distance; z += cosYaw * distance }
		if input.sPressed     { x -= sinYaw * distance; z -= cosYaw * distance }
		if input.aPressed     { x -= cosYaw * distance; z += sinYaw * distance }
		if input.dPressed     { x += cosYaw * distance; z -= sinYaw * distance }
		if input.spacePressed { y += distance }
		if input.shiftPressed { y -= distance }
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
		
		player.x = reader.readDouble()
		player.y = reader.readDouble()
		player.z = reader.readDouble()
		
		reader.index += 24          // velocity x, y, z — unused
		
		player.yaw = -reader.readFloat() * .pi / 180
		player.pitch = reader.readFloat() * .pi / 180
		
		return (teleportID, player)
	}
}
