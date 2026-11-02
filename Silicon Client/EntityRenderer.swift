import Metal
import simd

extension Renderer {
	// Draws every entity as a white box at its hitbox size, like F3+B. Models replace this in stage D.
	func drawEntities(with renderEncoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4, screenSize: SIMD2<Float>, blend: Double) {
		var viewProjection = viewProjection
		var screenSize = screenSize
		renderEncoder.setCullMode(.none)
		for entity in clientWorld.entities.values {
			guard entity.typeID < EntityData.types.count else { continue }
			let type = EntityData.types[entity.typeID]
			let smooth = entity.previousPosition + (entity.position - entity.previousPosition) * blend
			var turn = entity.yaw - entity.previousYaw
			turn -= 360 * (turn / 360).rounded()
			let smoothYaw = entity.previousYaw + turn * Float(blend)
			if let number = modelNumber(typeName: type.name) {
				drawEntityModel(entity: entity, modelNumber: number, smooth: smooth, yaw: smoothYaw, with: renderEncoder, viewProjection: viewProjection)
				continue
			}
			renderEncoder.setRenderPipelineState(entityPipelineState)
			renderEncoder.setDepthStencilState(translucentDepthState)
			renderEncoder.setVertexBytes(&viewProjection, length: MemoryLayout<simd_float4x4>.stride, index: 0)
			renderEncoder.setVertexBytes(&screenSize, length: 8, index: 2)
			var boxMin = SIMD3<Float>(smooth - SIMD3(type.width / 2, 0, type.width / 2))
			var boxSize = SIMD3<Float>(Float(type.width), Float(type.height), Float(type.width))
			renderEncoder.setVertexBytes(&boxMin, length: 12, index: 1)
			renderEncoder.setVertexBytes(&boxSize, length: 12, index: 3)
			renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 72)
		}
	}

	// The GPU corners of one model. Built the first time it's asked for, then reused.
	func entityMesh(modelNumber: Int) -> MTLBuffer? {
		if let mesh = entityMeshes[modelNumber] {
			return mesh
		}
		let vertices = EntityMesher.buildMesh(model: EntityData.models[modelNumber])
		if vertices.isEmpty {
			return nil
		}
		let mesh = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<EntityVertex>.stride)
		entityMeshes[modelNumber] = mesh
		return mesh
	}

	// One matrix per part, in seat order. Each part starts from its parent's matrix.
	func partMatrices(model: EntityModel, base: simd_float4x4, headYaw: Float, headPitch: Float) -> [simd_float4x4] {
		var matrices: [simd_float4x4] = []
		for partNumber in 0..<model.parts.count {
			let part = model.parts[partNumber]
			let hasParent = part.parent >= 0 && part.parent < matrices.count
			let parentMatrix = hasParent ? matrices[part.parent] : base
			let joint = moveMatrix(x: part.x, y: part.y, z: part.z)
			var partRotation = SIMD3<Float>(part.xRot, part.yRot, part.zRot)
			if model.headYaw.count == 19 && model.headPitch.count == 19 {
				let restingRotation = tableRotation(headTable: model.headYaw, headDegrees: 0, partNumber: partNumber)
				let changeFromHeadTurn = tableRotation(headTable: model.headYaw, headDegrees: headYaw, partNumber: partNumber) - restingRotation
				let changeFromHeadTilt = tableRotation(headTable: model.headPitch, headDegrees: headPitch, partNumber: partNumber) - restingRotation
				partRotation = restingRotation + changeFromHeadTurn + changeFromHeadTilt
			}
			let turnZ = turnMatrix(angle: partRotation.z, axis: SIMD3<Float>(0, 0, 1))
			let turnY = turnMatrix(angle: partRotation.y, axis: SIMD3<Float>(0, 1, 0))
			matrices.append(parentMatrix * joint * turnZ * turnY * turnMatrix(angle: partRotation.x, axis: SIMD3<Float>(1, 0, 0)))
		}
		return matrices
	}

	func tableRotation(headTable: [[Float]], headDegrees: Float, partNumber: Int) -> SIMD3<Float> {
		let rowPosition = min(max((headDegrees + 90) / 10, 0), 18)
		let rowBelow = Int(rowPosition)
		let rowAbove = min(rowBelow + 1, 18)
		let blendTowardRowAbove = rowPosition - Float(rowBelow)
		let firstNumber = partNumber * 3
		let rotationBelow = SIMD3<Float>(headTable[rowBelow][firstNumber], headTable[rowBelow][firstNumber + 1], headTable[rowBelow][firstNumber + 2])
		let rotationAbove = SIMD3<Float>(headTable[rowAbove][firstNumber], headTable[rowAbove][firstNumber + 1], headTable[rowAbove][firstNumber + 2])
		return rotationBelow + (rotationAbove - rotationBelow) * blendTowardRowAbove
	}

	// The first model made for this entity type, or nil if it has none (items, paintings…).
	func modelNumber(typeName: String) -> Int? {
		for number in 0..<EntityData.models.count {
			if EntityData.models[number].entity == typeName {
				return number
			}
		}
		return nil
	}

	// Draws one entity with its real model and picture.
	func drawEntityModel(entity: Entity, modelNumber: Int, smooth: SIMD3<Double>, yaw: Float, with renderEncoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4) {
		guard let mesh = entityMesh(modelNumber: modelNumber) else {
			return
		}
		let model = EntityData.models[modelNumber]
		let picture = entityTexture(path: model.texture)
		let place = moveMatrix(x: Float(smooth.x), y: Float(smooth.y), z: Float(smooth.z))
		let facing = turnMatrix(angle: (180 - yaw) * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
		let flip = scaleMatrix(x: -1, y: -1, z: 1)
		let down = moveMatrix(x: 0, y: -1.501, z: 0)
		let pixels = scaleMatrix(x: 1.0 / 16, y: 1.0 / 16, z: 1.0 / 16)
		let base = place * facing * flip * down * pixels
		var headTurnFromBody = entity.headYaw - yaw
		headTurnFromBody -= 360 * (headTurnFromBody / 360).rounded()
		var matrices = partMatrices(model: model, base: base, headYaw: headTurnFromBody, headPitch: entity.pitch)
		var camera = viewProjection
		renderEncoder.setRenderPipelineState(entityModelPipelineState)
		renderEncoder.setDepthStencilState(depthStencilState)
		renderEncoder.setVertexBuffer(mesh, offset: 0, index: 0)
		renderEncoder.setVertexBytes(&camera, length: MemoryLayout<simd_float4x4>.stride, index: 1)
		renderEncoder.setVertexBytes(&matrices, length: matrices.count * MemoryLayout<simd_float4x4>.stride, index: 2)
		renderEncoder.setFragmentTexture(picture, index: 0)
		renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.length / MemoryLayout<EntityVertex>.stride)
	}
}
