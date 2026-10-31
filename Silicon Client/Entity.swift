import Foundation

// One live mob (or arrow, item…) the server told us about.
struct Entity {
      let id: Int                          // the server's number for it; packets refer to it by this
      let typeID: Int                      // what kind: pig, zombie… (looked up in EntityData later)
      var position: SIMD3<Double>          // where it is now (feet, centre)
      var previousPosition: SIMD3<Double>  // where it was one tick ago; drawing slides between the two
	var walkPosition: Float = 0          // how far it has walked, in steps; drives the leg swing (like vanilla)
	var walkSpeed: Float = 0             // 0 standing … 1 running; how big the leg swing is
	var age: Int = 0                     // ticks since we first saw it; drives idle motion and keyframe timing
}
