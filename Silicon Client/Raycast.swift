import Foundation

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
	
	func handleClick() {
		guard input.leftClicked else { return }; input.leftClicked = false
		guard player.gameMode == .creative || player.gameMode == .survival, let target = raycast() else { return }
		serverConnection.sendPlayerAction(status: 0, block: target.hit, face: Renderer.face(from: target.placeAt &- target.hit)); serverConnection.sendSwing()
	}
}
