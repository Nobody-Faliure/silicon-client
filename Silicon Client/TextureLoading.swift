import Metal
import ImageIO

extension Renderer {
	// Finds a downloaded Minecraft texture by its resource name
	func texture(named name: String) -> MTLTexture {
		// Convert "minecraft:block/stone" or "block/stone" into "stone.png"
		let textureName = name
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")
		
		if let cached = textureCache[textureName] {
			return cached
		}
		
		let texturesFolder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
			.appendingPathComponent("Silicon Client")
			.appendingPathComponent("assets/minecraft/textures/block")
		
		let textureURL = texturesFolder
			.appendingPathComponent(textureName)
			.appendingPathExtension("png")
		
		let loaded = loadMinecraftTexture(from: textureURL, named: textureName)
		textureCache[textureName] = loaded
		return loaded
	}
	
	// Decodes a Minecraft PNG into raw pixels and creates a Metal texture
	func loadMinecraftTexture(from textureURL: URL, named name: String, canAnimate: Bool = true) -> MTLTexture {
		do {
			let data = try Data(contentsOf: textureURL)
			
			// Create an ImageIO source from the PNG data
			guard let source = CGImageSourceCreateWithData(
				data as CFData,
				nil
			) else {
				fatalError("Could not create image source: \(textureURL.path)")
			}
			
			let cgImage = CGImageSourceCreateImageAtIndex(
				source,
				0,
				nil
			)!
			
			let width = cgImage.width
			let height = cgImage.height
			
			let frameHeight = canAnimate && height > width ? width : height
			
			// Allocate enough memory for RGBA pixels
			let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
			let bytesPerRow = width * 4
			let byteCount = bytesPerRow * height
			
			let pixelData = UnsafeMutableRawPointer.allocate(
				byteCount: byteCount,
				alignment: 64
			)
			
			memset(pixelData, 0, byteCount)
			
			defer {
				pixelData.deallocate()
			}
			
			// Decode the image into a predictable 4-byte-per-pixel format
			let context = CGContext(
				data: pixelData,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: bytesPerRow,
				space: colorSpace,
				bitmapInfo:  CGImageAlphaInfo.premultipliedLast.rawValue
			)!
			
			context.draw(
				cgImage,
				in: CGRect(
					x: 0,
					y: 0,
					width: width,
					height: height
				)
			)
			
			// Create the GPU texture that will hold those pixels
			let descriptor = MTLTextureDescriptor.texture2DDescriptor(
				pixelFormat: .rgba8Unorm_srgb,
				width: width,
				height: frameHeight,
				mipmapped: true
			)
			
			let texture = device.makeTexture(
				descriptor: descriptor
			)!
			
			// Copy the decoded pixels into Metal's texture memory
			texture.replace(
				region: MTLRegionMake2D(
					0,
					0,
					width,
					frameHeight
				),
				mipmapLevel: 0,
				withBytes: pixelData,
				bytesPerRow: bytesPerRow
			)
			
			let mipmapCommands = commandQueue.makeCommandBuffer()!
			let shrinker = mipmapCommands.makeBlitCommandEncoder()!
			shrinker.generateMipmaps(for: texture)
			shrinker.endEncoding()
			mipmapCommands.commit()
			
			// A strip: remember every frame so draw() can swap them later.
			if canAnimate && height > width {
				let folder = textureURL.deletingLastPathComponent()
				
				animatedTextures[name] = AnimatedTexture(
					texture: texture,
					frames: Data(bytes: pixelData, count: byteCount),
					size: width,
					animation: TextureAnimation.load(
						name: name,
						frameCount: height / width,
						in: folder
					)
				)
			}
			
			return texture
		} catch {
			fatalError(
				"Failed texture: \(textureURL.path) — \(error)"
			)
		}
	}
	
	func advanceAnimations(now: CFTimeInterval) {
		let tick = Int(now * 20)
		
		guard tick != lastAnimationTick else { return }
		
		lastAnimationTick = tick
		
		let mipmapCommands = commandQueue.makeCommandBuffer()!
		let shrinker = mipmapCommands.makeBlitCommandEncoder()!
		
		for animated in animatedTextures.values {
			let order = animated.animation.frameOrder
			
			guard !order.isEmpty else { continue }
			
			let step = (tick / animated.animation.ticksPerFrame) % order.count
			let frame = order[step]
			
			let bytesPerFrame = animated.size * animated.size * 4
			let start = frame * bytesPerFrame
			
			guard start + bytesPerFrame <= animated.frames.count else { continue }
			
			animated.frames.withUnsafeBytes { raw in
				animated.texture.replace(
					region: MTLRegionMake2D(0, 0, animated.size, animated.size),
					mipmapLevel: 0,
					withBytes: raw.baseAddress! + start,
					bytesPerRow: animated.size * 4
				)
			}
			
			shrinker.generateMipmaps(for: animated.texture)
		}
		
		shrinker.endEncoding()
		mipmapCommands.commit()
	}

	// Minecraft's "missing texture": magenta and black squares, for pictures that can't be found.
	func makeMissingTexture() -> MTLTexture? {
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 2, height: 2, mipmapped: false)
		let texture = device.makeTexture(descriptor: descriptor)
		let pixels: [UInt8] = [248, 0, 248, 255,   0, 0, 0, 255,   0, 0, 0, 255,   248, 0, 248, 255]
		texture?.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
		return texture
	}

	// An entity's picture, like "textures/entity/zombie/zombie.png". Not found → checkerboard.
	func entityTexture(path: String) -> MTLTexture? {
		if let cached = textureCache[path] {
			return cached
		}
		let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let file = applicationSupport.appendingPathComponent("Silicon Client/assets/minecraft/" + path)
		let found = path.hasSuffix(".png") && FileManager.default.fileExists(atPath: file.path)
		let picture = found ? loadMinecraftTexture(from: file, named: path, canAnimate: false) : makeMissingTexture()
		textureCache[path] = picture
		return picture
	}
}
