import Foundation

enum LightEngine {
	static func skyLight(at position: SIMD3<Int>, in world: ClientWorld) -> Int {
		guard let spot = world.locate(position) else { return 0 }
		return world.chunks[spot.chunk].sections[spot.section].skyLightLevel(at: spot.index)
	}
	
	static func blockLight(at position: SIMD3<Int>, in world: ClientWorld) -> Int {
		guard let spot = world.locate(position) else { return 0 }
		return world.chunks[spot.chunk].sections[spot.section].blockLightLevel(at: spot.index)
	}
	
	static func setSkyLight(at position: SIMD3<Int>, to value: Int, in world: ClientWorld) {
		guard let spot = world.locate(position) else { return }
		world.chunks[spot.chunk].sections[spot.section].setSkyLightLevel(at: spot.index, to: value)
		world.markForRedraw(position)
	}
	
	static func setBlockLight(at position: SIMD3<Int>, to value: Int, in world: ClientWorld) {
		guard let spot = world.locate(position) else { return }
		world.chunks[spot.chunk].sections[spot.section].setBlockLightLevel(at: spot.index, to: value)
		world.markForRedraw(position)
	}
	
	static func light(at position: SIMD3<Int>, sky: Bool, in world: ClientWorld) -> Int {
		sky ? skyLight(at: position, in: world) : blockLight(at: position, in: world)
	}
	
	static func setLight(at position: SIMD3<Int>, sky: Bool, to value: Int, in world: ClientWorld) {
		if sky {
			setSkyLight(at: position, to: value, in: world)
		} else {
			setBlockLight(at: position, to: value, in: world)
		}
	}
	
	static func glow(at position: SIMD3<Int>, in world: ClientWorld) -> Int {
		guard let id = world.blockID(worldX: position.x, y: position.y, worldZ: position.z),
			  Int(id) < BlockData.states.count else { return 0 }
		return BlockData.states[Int(id)].lightEmission
	}
	
	static func removeLight(sky: Bool, from start: SIMD3<Int>, oldLevel: Int, in world: ClientWorld) -> [SIMD3<Int>] {
		var queue = [(position: start, level: oldLevel)]
		var front = 0
		var edges: [SIMD3<Int>] = []
		while front < queue.count {
			let (position, level) = queue[front]
			front += 1
			for direction: SIMD3<Int> in [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]] {
				let neighbour = position &+ direction
				let neighbourLevel = light(at: neighbour, sky: sky, in: world)
				if neighbourLevel == 0 { continue }
				let straightDown = sky && direction.y == -1 && level == 15 && neighbourLevel == 15
				if neighbourLevel < level || straightDown {
					let ownGlow = sky ? 0 : glow(at: neighbour, in: world)
					setLight(at: neighbour, sky: sky, to: ownGlow, in: world)
					if ownGlow > 0 { edges.append(neighbour) }
					queue.append((neighbour, neighbourLevel))
				} else {
					edges.append(neighbour)
				}
			}
		}
		return edges
	}
	
	static func spreadLight(from starts: [SIMD3<Int>], in world: ClientWorld) {
		var queue = starts
		var front = 0                       // position of the next block to take from the queue
		while front < queue.count {
			let position = queue[front]
			front += 1
			let sky = skyLight(at: position, in: world)
			let block = blockLight(at: position, in: world)
			for direction: SIMD3<Int> in [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]] {
				let neighbour = position &+ direction
				guard let id = world.blockID(worldX: neighbour.x, y: neighbour.y, worldZ: neighbour.z),
					  Int(id) < BlockData.states.count else { continue }
				let values = BlockData.states[Int(id)]
				if values.lightDampening >= 15 { continue }   // solid: light can't get in
				let cost = max(1, values.lightDampening)
				let newSky = direction.y == -1 && sky == 15 && values.skylightDown ? 15 : sky - cost
				if newSky > skyLight(at: neighbour, in: world) {
					setSkyLight(at: neighbour, to: newSky, in: world)
					queue.append(neighbour)
				}
				let newBlock = block - cost
				if newBlock > blockLight(at: neighbour, in: world) {
					setBlockLight(at: neighbour, to: newBlock, in: world)
					queue.append(neighbour)
				}
			}
		}
	}
	
	static func relightAfterChange(at position: SIMD3<Int>, in world: ClientWorld) {
		let oldSky = skyLight(at: position, in: world)
		let oldBlock = blockLight(at: position, in: world)
		setSkyLight(at: position, to: 0, in: world)
		setBlockLight(at: position, to: glow(at: position, in: world), in: world)
		var edges = removeLight(sky: true, from: position, oldLevel: oldSky, in: world)
		edges += removeLight(sky: false, from: position, oldLevel: oldBlock, in: world)
		var starts = edges + [position]
		for direction: SIMD3<Int> in [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]] {
			starts.append(position &+ direction)
		}
		spreadLight(from: starts, in: world)
	}
}

extension Section {
	func skyLightLevel(at index: Int) -> Int {
		skyLight.isEmpty ? 15 : nibble(skyLight, index)
	}
	func blockLightLevel(at index: Int) -> Int {
		blockLight.isEmpty ? 0 : nibble(blockLight, index)
	}
	
	func lightLevel(at index: Int) -> Int {
		max(skyLightLevel(at: index), blockLightLevel(at: index))
	}
	
	// Two blocks share a byte: the even one is the low half, the odd one the high half.
	private func nibble(_ light: Data, _ index: Int) -> Int {
		let byteIndex = index >> 1
		
		guard byteIndex < light.count else { return 0 }
		
		let byte = light[light.startIndex + byteIndex]
		
		return index & 1 == 0 ? Int(byte & 0xF) : Int(byte >> 4)
	}
	
	private static func setNibble(_ light: inout Data, _ index: Int, to value: Int) {
		let byteIndex = light.startIndex + (index >> 1)
		let byte = light[byteIndex]
		light[byteIndex] = index & 1 == 0
		? (byte & 0xF0) | UInt8(value)
		: (byte & 0x0F) | UInt8(value << 4)
	}
	
	mutating func setSkyLightLevel(at index: Int, to value: Int) {
		if skyLight.isEmpty { skyLight = Data(repeating: 0xFF, count: 2048) }
		Section.setNibble(&skyLight, index, to: value)
	}
	
	mutating func setBlockLightLevel(at index: Int, to value: Int) {
		if blockLight.isEmpty { blockLight = Data(count: 2048) }
		Section.setNibble(&blockLight, index, to: value)
	}
}
