import simd

// A matrix that moves things by (x, y, z).
func moveMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
	var matrix = matrix_identity_float4x4
	matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
	return matrix
}

// A matrix that stretches things: 2 = twice as big, -1 = mirrored.
func scaleMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
	return simd_float4x4(diagonal: SIMD4<Float>(x, y, z, 1))
}

// A matrix that turns things by angle (radians) around axis, like (0, 1, 0) for turning left/right.
func turnMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
	return simd_float4x4(simd_quatf(angle: angle, axis: axis))
}
