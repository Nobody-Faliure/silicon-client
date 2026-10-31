import Metal
import simd

extension Renderer {
	// Draws every entity as a white box at its hitbox size, like F3+B. Models replace this in stage D.
	func drawEntities(with renderEncoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4, screenSize: SIMD2<Float>, blend: Double) {
		var viewProjection = viewProjection
		var screenSize = screenSize
		renderEncoder.setRenderPipelineState(entityPipelineState)
		renderEncoder.setDepthStencilState(translucentDepthState)
		renderEncoder.setCullMode(.none)
		renderEncoder.setVertexBytes(&viewProjection, length: MemoryLayout<simd_float4x4>.stride, index: 0)
		renderEncoder.setVertexBytes(&screenSize, length: 8, index: 2)
		for entity in clientWorld.entities.values {
			guard entity.typeID < EntityData.types.count else { continue }
			let type = EntityData.types[entity.typeID]
			let smooth = entity.previousPosition + (entity.position - entity.previousPosition) * blend
			var boxMin = SIMD3<Float>(smooth - SIMD3(type.width / 2, 0, type.width / 2))
			var boxSize = SIMD3<Float>(Float(type.width), Float(type.height), Float(type.width))
			renderEncoder.setVertexBytes(&boxMin, length: 12, index: 1)
			renderEncoder.setVertexBytes(&boxSize, length: 12, index: 3)
			renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 72)
		}
	}
}
