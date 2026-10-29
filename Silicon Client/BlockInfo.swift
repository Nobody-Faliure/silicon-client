import Foundation

// Everything the mesher asks about a block state, worked out once.
struct BlockInfo {
	let isAir: Bool
	let fluidHeight: Float?          // nil means not a fluid
	let isWater: Bool
	let isLeaves: Bool
	let parts: [VariantOptions]      // the pieces to draw; empty means nothing to draw
	let hidesNeighbours: Bool
}

enum BlockInfoTable {
	// One slot per block state ID, filled the first time that ID is meshed.
	static var table: [BlockInfo?] = []
	
	static func info(
		_ id: UInt16,
		blockStateFolder: URL,
		modelFolder: URL
	) -> BlockInfo {
		if table.isEmpty {
			table = Array(repeating: nil, count: BlockRegistry.statesByID.count)
		}
		
		if let known = table[Int(id)] { return known }
		
		let state = BlockRegistry.statesByID[Int(id)]
		let name = state.block.id
		let parts = ChunkMesher.variantOptions(for: state, blockStateFolder: blockStateFolder)
		
		// Same rule as neighbourHides: the first option must be one full solid box.
		var hides = false
		if parts.count == 1, let first = parts[0].options.first {
			hides = ChunkMesher.hidesNeighbours(
				ChunkMesher.resolvedModel(modelName: first.model, modelFolder: modelFolder)
			)
		}
		
		let info = BlockInfo(
			isAir: name == "minecraft:air",
			fluidHeight: ChunkMesher.fluidHeight(of: state),
			isWater: ChunkMesher.fluidHeight(of: state) != nil && name != "minecraft:lava",
			isLeaves: name.contains("leaves"),
			parts: parts,
			hidesNeighbours: hides
		)
		
		table[Int(id)] = info
		return info
	}
}
