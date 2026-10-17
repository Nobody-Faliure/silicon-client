import Foundation

struct Player {
	var position = SIMD3<Double>(0, 0, 0)
	
	var yaw: Float = 0
	var pitch: Float = 0
	
	// Speed in blocks per tick. Kept between ticks, so movement has momentum.
	var velocity = SIMD3<Double>(0, 0, 0)
	
	var onGround = false
	
	var hitBox: Hitbox {
		Hitbox(boxes: [Box(min: position - [0.3, 0, 0.3], max: position + [0.3, 1.8, 0.3])])
	}
	
	static let spectatorFlySpeed: Double = 10.9
	
	// Where the player was one tick ago. The camera slides from here to now.
	var previousTickPosition = SIMD3<Double>(0, 0, 0)
	
	mutating func updatePosition(input: Input, deltaTime: Double, world: ClientWorld) {
		if input.scrollDelta != 0 {
			input.flyStep = min(4, max(1, input.flyStep + Double(input.scrollDelta) * 0.1))
			input.scrollDelta = 0
		}
		
		// How hard the keys push this tick (vanilla creative flight: 0.05)
		let push = 0.05 * input.flyStep
		
		var wish = SIMD3<Double>(0, 0, 0)
		
		let sinYaw = Double(sin(yaw))
		let cosYaw = Double(cos(yaw))
		
		if input.wPressed     { wish.x += sinYaw; wish.z += cosYaw }
		if input.sPressed     { wish.x -= sinYaw; wish.z -= cosYaw }
		if input.aPressed     { wish.x -= cosYaw; wish.z += sinYaw }
		if input.dPressed     { wish.x += cosYaw; wish.z -= sinYaw }
		if input.spacePressed { wish.y += 1 }
		if input.shiftPressed { wish.y -= 1 }
		
		// Diagonal keys shouldn't be faster: cap the sideways wish at length 1
		var flat = SIMD2<Double>(wish.x, wish.z)
		let length = (flat.x * flat.x + flat.y * flat.y).squareRoot()
		if length > 1 { flat /= length }
		
		velocity.x += flat.x * push * 0.98
		velocity.z += flat.y * push * 0.98
		velocity.y += wish.y * push * 3       // vanilla: 3× the flying speed, so 0.15
		
		let box = hitBox.boxes[0]
		let areaMin = box.min + pointwiseMin(velocity, [0, 0, 0])
		let areaMax = box.max + pointwiseMax(velocity, [0, 0, 0])
		
		var nearby: [Box] = []
		for x in Int(floor(areaMin.x))...Int(floor(areaMax.x)) {
			for y in Int(floor(areaMin.y))...Int(floor(areaMax.y)) {
				for z in Int(floor(areaMin.z))...Int(floor(areaMax.z)) {
					nearby += world.hitbox(at: [Double(x), Double(y), Double(z)]).boxes
				}
			}
		}
		
		// How far I can really go, after walls cut it short
		let allowed = hitBox.collidesIn(Hitbox(boxes: nearby), velocity)
		
		position += allowed
		
		// A wall cut this direction short, so stop moving that way
		for axis in 0..<3 where allowed[axis] != velocity[axis] {
			velocity[axis] = 0
		}
		
		velocity.x *= 0.91   // sideways: air drag
		velocity.z *= 0.91
		velocity.y *= 0.6    // up/down: stops almost at once
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
