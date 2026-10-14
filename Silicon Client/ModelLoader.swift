import Foundation

extension ChunkMesher {
	// Same position always picks the same option, so stone never reshuffles
	static func variantIndex(x: Int, y: Int, z: Int, count: Int) -> Int {
		if count == 1 { return 0 }
		
		var h = UInt64(bitPattern: Int64(x &* 3129871))
		^ UInt64(bitPattern: Int64(z &* 116129781))
		^ UInt64(bitPattern: Int64(y))
		
		h = h &* h &* 42317861 &+ h &* 11
		
		return Int((h >> 16) % UInt64(count))
	}
	
	// The blockstate entry matching this block's properties, with all its
	// options. nil when the file is missing or nothing matches.
	static func variantOptions(
		for blockState: BlockState,
		blockStateFolder: URL
	) -> VariantOptions? {
		if let cached = variantCache[blockState] { return cached }
		
		let blockName = blockState.block.id
			.replacingOccurrences(of: "minecraft:", with: "")
		
		let blockStateURL = blockStateFolder
			.appendingPathComponent(blockName)
			.appendingPathExtension("json")
		
		guard let blockStateJSON = loadJSONIfPossible(
			from: blockStateURL,
			as: MinecraftBlockState.self
		) else {
			return nil
		}
		
		for (variantKey, variant) in blockStateJSON.variants {
			var matches = true
			
			for property in variantKey.split(separator: ",") {
				let parts = property.split(separator: "=", maxSplits: 1)
				
				if parts.count == 2,
				   blockState.properties[String(parts[0])] != String(parts[1]) {
					matches = false
					break
				}
			}
			
			if matches {
				variantCache[blockState] = variant
				return variant
			}
		}
		
		return nil
	}
	
	
	// Reads a file off the disk and turns its text into Swift values.
	//
	// This is the slow line in the whole file - opening and decoding takes
	// roughly 25 microseconds, and the mesher calls it thousands of times
	// per chunk unless results are remembered.
	//
	// Loads and decodes any JSON file
	static func loadJSON<T: Decodable>(
		from url: URL,
		as type: T.Type
	) -> T {
		let data = try! Data(contentsOf: url)
		
		return try! JSONDecoder().decode(
			T.self,
			from: data
		)
	}
	
	static func loadJSONIfPossible<T: Decodable>(
		from url: URL,
		as type: T.Type
	) -> T? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		return try? JSONDecoder().decode(T.self, from: data)
	}
	
	// Walks the inheritance trail and collects every file along it.
	//
	// Starting at anvil.json this returns
	//   [anvil, template_anvil, block]
	// in child-first order. Each step is another disk read.
	//
	// Follows parent models and stores the whole chain
	static func modelChain(
		startingWith model: MinecraftModel,
		modelFolder: URL
	) -> [MinecraftModel] {
		var chain = [model]
		var currentModel = model
		
		while let parentName = currentModel.parent {
			let cleanName = parentName
				.replacingOccurrences(of: "minecraft:", with: "")
				.replacingOccurrences(of: "block/", with: "")
			
			let modelURL = modelFolder
				.appendingPathComponent("block")
				.appendingPathComponent(cleanName)
				.appendingPathExtension("json")
			
			let parentModel: MinecraftModel = loadJSON(
				from: modelURL,
				as: MinecraftModel.self
			)
			
			chain.append(parentModel)
			currentModel = parentModel
		}
		
		return chain
	}
	
	// Squashes a chain collected above into one ResolvedModel.
	// Pure bookkeeping - reads nothing from disk.
	//
	// Not to be confused with resolvedModel(for:) below, which is the one
	// that does the loading. This one only merges what was already loaded.
	static func resolveModel(chain: [MinecraftModel]) -> ResolvedModel {
		// elements (shape): first model that has any wins, then stop
		// Shape: walk child-first and take the first file that declares one.
		// anvil.json declares none, template_anvil.json declares four boxes,
		// so those win and block.json is never consulted.
		var elements: [MinecraftModelElement] = []
		for model in chain {
			if let e = model.elements {
				elements = e
				break
			}
		}
		
		// textures (lookup table): merge every model's, child wins
		// Pictures: walk backwards, furthest ancestor first, letting each
		// file overwrite what came before. Because the child is written
		// last it wins - which is how the anvil keeps template_anvil's body
		// picture but swaps in its own anvil_top.
		var textures: [String: String] = [:]
		for model in chain.reversed() {
			if let t = model.textures {
				for (key, value) in t {
					textures[key] = value.sprite
				}
			}
		}
		
		return ResolvedModel(textures: textures, elements: elements)
	}
	
	// The full lookup for one block: find the drawing, load it, follow its
	// parents, merge them, hand back the finished shape and pictures.
	//
	// Every disk read for a block happens underneath this call, which makes
	// it the place worth remembering answers in.
	//
	// Loads and resolves the whole model for one block state
	static func resolvedModel(
		modelName: String,
		modelFolder: URL
	) -> ResolvedModel {
		if let cached = modelCache[modelName] {
			return cached
		}
		
		let cleanName = modelName
			.replacingOccurrences(of: "minecraft:", with: "")
			.replacingOccurrences(of: "block/", with: "")
		
		let modelURL = modelFolder
			.appendingPathComponent("block")
			.appendingPathComponent(cleanName)
			.appendingPathExtension("json")
		
		let model: MinecraftModel = loadJSON(
			from: modelURL,
			as: MinecraftModel.self
		)
		
		let resolved = resolveModel(
			chain: modelChain(
				startingWith: model,
				modelFolder: modelFolder
			)
		)
		
		modelCache[modelName] = resolved
		return resolved
	}
	
	// Turns a reference like "#body" into a real texture name
	// Follows nicknames until a real picture name falls out.
	// A face says "#body", the lookup says body -> "block/anvil", so that
	// is the answer. Loops because a nickname may point at another nickname.
	static func resolveTexture(
		_ reference: String,
		in resolved: ResolvedModel
	) -> String {
		var reference = reference
		
		while reference.hasPrefix("#") {
			let key = String(reference.dropFirst())
			
			guard let next = resolved.textures[key] else {
				fatalError("No texture found for key \(key)")
			}
			
			reference = next
		}
		
		return reference
	}
	
}
