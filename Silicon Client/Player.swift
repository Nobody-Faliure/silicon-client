import Foundation

enum GameMode: UInt8 {
	case survival = 0, creative = 1, adventure = 2, spectator = 3
}

struct Player {
	var position = SIMD3<Double>(0, 0, 0)
	
	var yaw: Float = 0
	var pitch: Float = 0
	
	// Speed in blocks per tick. Kept between ticks, so movement has momentum.
	var velocity = SIMD3<Double>(0, 0, 0)
	
	var onGround = false
	
	var isFlying = false
	var mayFly = false
	
	var isSprinting = false
	
	var gameMode: GameMode = .survival
	
	var hitBox: Hitbox {
		Hitbox(boxes: [Box(min: position - [0.3, 0, 0.3], max: position + [0.3, 1.8, 0.3])])
	}
	
	var movementSpeed: Double = 0.1
	var flyingSpeed: Double = 0
	
	var jumpStrength: Double = 0.42
	
	// Where the player was one tick ago. The camera slides from here to now.
	var previousTickPosition = SIMD3<Double>(0, 0, 0)
	
	mutating func updatePosition(input: Input, deltaTime: Double, world: ClientWorld) {
		if input.spaceDoubleTapped {
			input.spaceDoubleTapped = false
			if mayFly && gameMode != .spectator { isFlying.toggle() }
		}
		
		if gameMode == .spectator && input.scrollDelta != 0 {
			if input.scrollDelta != 0 {
				input.flyStep = min(4, max(1, input.flyStep + Double(input.scrollDelta) * 0.1))
				input.scrollDelta = 0
			}
		}
		
		if input.ctrlPressed && input.wPressed { isSprinting = true }
		if !input.wPressed { isSprinting = false }
		
		// How hard the keys push this tick (vanilla creative flight: 0.05)
		let push: Double
		
		if isFlying {
			push = flyingSpeed * (gameMode == .spectator ? input.flyStep : 1) * (isSprinting ? 2 : 1)
		} else if onGround {
			push = movementSpeed * (isSprinting ? 1.3 : 1)
		} else {
			push = isSprinting ? 0.026 : 0.02
		}
		
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
		var flat = SIMD2<Double>(wish.x, wish.z) * 0.98
		let length = (flat.x * flat.x + flat.y * flat.y).squareRoot()
		if length > 1 { flat /= length }
		
		velocity.x += flat.x * push
		velocity.z += flat.y * push
		
		if isFlying {
			velocity.y += wish.y * push * 3    // vanilla: 3× the flying speed, so 0.15
		} else if input.spacePressed && onGround {
			velocity.y = jumpStrength
			if isSprinting {
				velocity.x += sinYaw * 0.2     // sprint-jump: extra kick forward
				velocity.z += cosYaw * 0.2
			}
		}
		
		let allowed: SIMD3<Double>
		
		if gameMode != .spectator {
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
			allowed = hitBox.collidesIn(Hitbox(boxes: nearby), velocity)
		} else {
			allowed = velocity
		}
		
		let wasOnGround = onGround             // vanilla picks drag from before the move
		
		position += allowed
		
		// Was falling and the floor cut it short
		onGround = velocity.y < 0 && allowed.y != velocity.y

		// Creative: touching the ground while flying ends flying
		if onGround && isFlying && gameMode != .spectator { isFlying = false }
		
		// A wall cut this direction short, so stop moving that way
		for axis in 0..<3 where allowed[axis] != velocity[axis] {
			velocity[axis] = 0
		}
		
		let drag = wasOnGround && !isFlying ? 0.546 : 0.91
		velocity.x *= drag
		velocity.z *= drag
		
		if isFlying {
			velocity.y *= 0.6                      // up/down: stops almost at once
		} else {
			velocity.y = (velocity.y - 0.08) * 0.98   // gravity, then air drag
		}
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
