final class IntegratedServer {
	var world: ServerWorld

	init() {
		self.world = ServerWorld()
	}
	
	func sendWorld(to clientWorld: ClientWorld) {
		for chunk in world.chunks {
			sendChunk(chunk, to: clientWorld)
		}
	}
	
	func sendChunk(_ chunk: Chunk, to clientWorld: ClientWorld) {
		clientWorld.receiveChunk(chunk)
	}
	
	func sendBlock(
		chunkX: Int,
		chunkZ: Int,
		x: Int,
		y: Int,
		z: Int,
		block: Block,
		to clientWorld: ClientWorld
	) {
		clientWorld.receiveBlockUpdate(
			chunkX: chunkX,
			chunkZ: chunkZ,
			x: x,
			y: y,
			z: z,
			block: block
		)
	}
	
	func unloadChunk(
		chunkX: Int,
		chunkZ: Int,
		from clientWorld: ClientWorld
	) {
		clientWorld.unloadChunk(
			chunkX: chunkX,
			chunkZ: chunkZ
		)
	}
}
