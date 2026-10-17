import simd

struct Hitbox {
	let boxes: [Box]
	
	func collides(_ other: Hitbox) -> Bool {
		for box in boxes {
			for otherBox in other.boxes {
				if (box.overlaps(otherBox)) {return true}
			}
		}
		return false
	}
	
	func collidesIn(_ other: Hitbox, _ relativeMovement: SIMD3<Double>) -> SIMD3<Double> {
		var allowedMovement = relativeMovement
		var moved = SIMD3<Double>(0, 0, 0)       // how far we've already gone
		
		for axis in [1, 0, 2] {                  // y, then x, then z
			for box in boxes {
				let shifted = Box(min: box.min + moved, max: box.max + moved)
				for otherBox in other.boxes {
					allowedMovement[axis] = shifted.allowedMoventOnAxis(
						against: otherBox, axis: axis,
						relativeMovement: allowedMovement[axis])
				}
			}
			moved[axis] = allowedMovement[axis]  // lock in this axis before the next
		}
		return allowedMovement
	}
}

struct Box {
	let min: SIMD3<Double>
	let max: SIMD3<Double>
	
	func overlaps(_ other: Box) -> Bool {
		return min.x < other.max.x && other.min.x < max.x
		&& min.y < other.max.y && other.min.y < max.y
		&& min.z < other.max.z && other.min.z < max.z
	}
	
	func allowedMoventOnAxis(against other: Box, axis: Int, relativeMovement: Double) -> Double{
		//check if already in other hitbox
		for a in 0..<3 where a != axis {
			if Swift.min(max[a], other.max[a]) <= Swift.max(min[a], other.min[a]) {
				return relativeMovement
			}
		}
		
		let epsilon = 1e-7
		
		// Moving +: block's near side must be at or past my front edge
		if relativeMovement > 0 && other.min[axis] >= max[axis] - epsilon {
			return Swift.min(relativeMovement, other.min[axis] - max[axis])
		}
		
		// Moving -: block's near side must be at or before my back edge
		if relativeMovement < 0 && other.max[axis] <= min[axis] + epsilon {
			return Swift.max(relativeMovement, other.max[axis] - min[axis])
		}
		
		// Block is behind me (or I'm inside it), so it can't stop me
		return relativeMovement
	}
}
