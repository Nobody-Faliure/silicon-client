import SwiftUI

struct DebugView: View {
	@ObservedObject var info: DebugInfo
	
	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			line("Silicon Client", "0.0.1-dev.1")
			line("fps", "\(info.fps)   \(fixed(info.frameMilliseconds, 1)) ms")
			
			Spacer().frame(height: 8)
			
			line("xyz", "\(fixed(info.x, 2)) / \(fixed(info.y, 2)) / \(fixed(info.z, 2))")
			line("chunk", "\(Int(info.x.rounded(.down)) >> 4), \(Int(info.z.rounded(.down)) >> 4)")
			line("facing", info.facing)
			line("angle", "yaw \(fixed(info.yaw, 1))   pitch \(fixed(info.pitch, 1))")
			line("speed", "\(fixed(info.blocksPerSecond, 1)) blocks/s")
			
			Spacer().frame(height: 8)
			
			line("chunks", "\(info.chunksLoaded) loaded")
			line("meshes", "\(info.sectionMeshes)   \(info.sectionsQueued) queued")
			line("meshing", "\(fixed(info.meshMilliseconds, 2)) ms / section")
		}
		.font(.system(size: 12, design: .monospaced))
		.foregroundStyle(.white)
		.shadow(color: .black.opacity(0.9), radius: 0, x: 1, y: 1)
		.padding(12)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.allowsHitTesting(false)
	}
	
	private func line(_ name: String, _ value: String) -> some View {
		HStack(spacing: 8) {
			Text(name)
				.foregroundStyle(.white.opacity(0.6))
				.frame(width: 70, alignment: .leading)
			
			Text(value)
		}
	}
	
	private func fixed(_ value: Double, _ places: Int) -> String {
		String(format: "%.\(places)f", value)
	}
}
