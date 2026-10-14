import Foundation

struct TextureRef: Decodable {
	let sprite: String
	
	init(from decoder: Decoder) throws {
		if let plain = try? decoder.singleValueContainer().decode(String.self) {
			sprite = plain
			return
		}
		let container = try decoder.container(keyedBy: CodingKeys.self)
		sprite = try container.decode(String.self, forKey: .sprite)
	}
	
	enum CodingKeys: String, CodingKey {
		case sprite
	}
}

// One models/block/*.json file.
// Every field is optional because a file may inherit instead of declaring:
// anvil.json has only a parent and one texture, and gets its shape from
// template_anvil.json further up the chain.
struct MinecraftModel: Decodable {
	let parent: String?                      // the file this one inherits from
	let textures: [String: TextureRef]?          // nickname -> picture, e.g. "body" -> "block/anvil"
	let elements: [MinecraftModelElement]?   // the boxes making up the shape
}

// One box in a shape. A plain cube has a single element spanning the whole
// block; an anvil has four stacked boxes of different sizes.
struct MinecraftModelElement: Decodable {
	let from: [Float]                        // one corner of the box, 0–16 model space
	let to: [Float]                          // opposite corner
	let rotation: MinecraftElementRotation?  // optional tilt of this box
	let faces: [String: MinecraftModelFace]?
}

// One side of one box. A box may leave sides out entirely - the anvil's
// middle boxes have no "down" face, because nothing could ever see it.
struct MinecraftModelFace: Decodable {
	let texture: String    // "#top" — which image
	let uv: [Float]?       // [x1,y1,x2,y2] slice of the texture; absent → whole texture
	let rotation: Int?     // 0/90/180/270 spin; absent → 0
	let cullface: String?  // side name; only cull this face if set
	let tintindex: Int?    // biome tint flag; absent → none
}

// An angled box, used by torches, levers and buttons.
// Read from the file but not used yet - nothing that tilts is drawn.
struct MinecraftElementRotation: Decodable {
	let origin: [Float]    // pivot point [x,y,z]
	let axis: String       // "x" | "y" | "z"
	let angle: Float       // -45,-22.5,0,22.5,45
	let rescale: Bool?     // absent → false
}

// The finished answer for one block, after the whole inheritance chain has
// been collapsed into a single shape plus a single picture lookup.
// This is what the triangle-building code actually reads.
struct ResolvedModel {
	let textures: [String: String]     // nicknames fully merged, child wins
	let elements: [MinecraftModelElement]   // the winning shape
}

// One blockstates/*.json file: every placement a block can have.
// The keys are property lists, so anvil.json has four entries keyed
// "facing=north", "facing=east", "facing=south", "facing=west".
struct MinecraftBlockState: Decodable {
	let variants: [String: VariantOptions]
}

// A variant entry is either one model, or a list Minecraft picks from so
// large areas of stone don't look tiled. Keep them all; picking comes later.
struct VariantOptions: Decodable {
	let options: [MinecraftBlockStateVariant]
	
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		
		if let single = try? container.decode(MinecraftBlockStateVariant.self) {
			options = [single]
			return
		}
		
		options = try container.decode([MinecraftBlockStateVariant].self)
	}
}

// What one placement resolves to: which drawing, and how far it is spun.
struct MinecraftBlockStateVariant: Decodable {
	let model: String   // e.g. "minecraft:block/anvil"
	let x: Int?         // tilt in degrees, absent means 0
	let y: Int?         // spin in degrees, absent means 0
}
