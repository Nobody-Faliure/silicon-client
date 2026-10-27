import Metal

extension Renderer {
	static let notTargetable: Set<String> = ["minecraft:air", "minecraft:cave_air", "minecraft:void_air", "minecraft:water", "minecraft:lava", "minecraft:bubble_column"]
	
	func raycast() -> (hit: SIMD3<Int>, placeAt: SIMD3<Int>)? {
		let reach: Float = player.gameMode == .creative ? 5 : 4.5
		let stepSize: Float = 0.05
		let direction = lookDirection
		
		var previous = SIMD3<Int>(cameraPosition.rounded(.down))
		
		for step in 0...Int(reach / stepSize) {
			let point = cameraPosition + direction * (Float(step) * stepSize)
			let block = SIMD3<Int>(point.rounded(.down))
			if block == previous { continue }
			if let state = clientWorld.getBlockState(worldX: block.x, y: block.y, worldZ: block.z),
			   !Renderer.notTargetable.contains(state.block.id) {
				return (block, previous)
			}
			previous = block
		}
		return nil
	}
	
	static func face(from side: SIMD3<Int>) -> Int {
		if side.y != 0 { return side.y < 0 ? 0 : 1 }
		if side.z != 0 { return side.z < 0 ? 2 : 3 }
		return side.x < 0 ? 4 : 5
	}

	func updateDigging() {
		if player.digDelay > 0 {
			player.digDelay -= 1
			return
		}
		let canBreak = player.gameMode == .creative || player.gameMode == .survival
		let target = input.leftHeld && canBreak ? raycast() : nil
		if let oldBlock = player.diggingBlock, oldBlock != target?.hit {
			serverConnection.sendPlayerAction(status: 1, block: oldBlock, face: 0)
			player.diggingBlock = nil
		}
		guard let target else { return }
		let face = Renderer.face(from: target.placeAt &- target.hit)
		guard let state = clientWorld.getBlockState(worldX: target.hit.x, y: target.hit.y, worldZ: target.hit.z) else { return }
		let progressPerTick = player.gameMode == .creative ? 1 : BlockHardness.progressPerTick(for: state.block.id)
		
		if player.diggingBlock == nil {
			serverConnection.sendPlayerAction(status: 0, block: target.hit, face: face)
			player.diggingBlock = target.hit
			player.digProgress = 0
			let vertices = breakingOverlayVertices(at: target.hit)
			breakingOverlay = vertices.isEmpty ? nil : device.makeBuffer(
				bytes: vertices,
				length: MemoryLayout<Vertex>.stride * vertices.count
			)
		}

		serverConnection.sendSwing()
		player.digProgress += progressPerTick
		guard player.digProgress >= 1 else { return }
		player.diggingBlock = nil
		player.digDelay = 5
		if progressPerTick < 1 {
			serverConnection.sendPlayerAction(status: 2, block: target.hit, face: face)
		}
	}
}
