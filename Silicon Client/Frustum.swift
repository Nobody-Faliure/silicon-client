import simd

// Could any part of this box be on screen?
func isBoxOnScreen(_ corners: [SIMD3<Float>], _ viewProjection: simd_float4x4) -> Bool {
	var points: [SIMD4<Float>] = []
	for corner in corners {
		points.append(viewProjection * SIMD4<Float>(corner, 1))
	}
	
	if points.allSatisfy({ $0.x >  $0.w }) { return false }   // all off the right
	if points.allSatisfy({ $0.x < -$0.w }) { return false }   // all off the left
	if points.allSatisfy({ $0.y >  $0.w }) { return false }   // all above
	if points.allSatisfy({ $0.y < -$0.w }) { return false }   // all below
	if points.allSatisfy({ $0.z >  $0.w }) { return false }   // all past the fog
	if points.allSatisfy({ $0.z <  0    }) { return false }   // all behind you
	
	return true
}
