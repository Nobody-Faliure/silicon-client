import Foundation

struct TextureAnimation {
	let ticksPerFrame: Int
	let frameOrder: [Int]
	
	static func load(name: String, frameCount: Int, in folder: URL) -> TextureAnimation {
		let plain = TextureAnimation(
			ticksPerFrame: 1,
			frameOrder: Array(0..<frameCount)
		)
		
		let url = folder
			.appendingPathComponent(name)
			.appendingPathExtension("png")
			.appendingPathExtension("mcmeta")
		
		guard let data = try? Data(contentsOf: url),
			  let file = try? JSONDecoder().decode(File.self, from: data),
			  let animation = file.animation else {
			return plain
		}
		
		return TextureAnimation(
			ticksPerFrame: max(animation.frametime ?? 1, 1),
			frameOrder: animation.frames ?? Array(0..<frameCount)
		)
	}
	
	private struct File: Decodable {
		let animation: Animation?
		
		struct Animation: Decodable {
			let frametime: Int?
			let frames: [Int]?
		}
	}
}
