import Foundation

// One live mob (or arrow, item…) the server told us about.
struct Entity {
	let id: Int                          // the server's number for it; packets refer to it by this
	let typeID: Int                      // what kind: pig, zombie… (looked up in EntityData later)
	var position: SIMD3<Double>          // where it is now (feet, centre)
	var previousPosition: SIMD3<Double>  // where it was one tick ago; drawing slides between the two
	var yaw: Float = 0                     // which way the body faces, in degrees
	var previousYaw: Float = 0             // which way it faced one tick ago; drawing slides between the two
	var targetPosition: SIMD3<Double>? = nil   // where the server says it should end up; nil = not sliding
	var targetYaw: Float = 0                   // which way it should end up facing
	var targetPitch: Float = 0                 // how far it should end up looking up/down
	var stepsLeft: Int = 0                     // ticks left in the slide, 3 → 2 → 1 → 0 (done)
	var pitch: Float = 0                   // looking up/down, in degrees
	var headYaw: Float = 0                 // which way the head faces (can differ from the body)
	var walkPosition: Float = 0            // how far it has walked, in steps; drives the leg swing (like vanilla)
	var walkSpeed: Float = 0               // 0 standing … 1 running; how big the leg swing is
	var age: Int = 0                       // ticks since we first saw it; drives idle motion and keyframe timing
	var variantNumber: Int? = nil          // index in this mob's variant list, e.g. 1 = temperate pig; nil until the server says
	var data: [Int: Int] = [:]   // slot → number the server sent, e.g. 16 → 1 (baby), 18 → 0x1E (sheared, light blue)
}
