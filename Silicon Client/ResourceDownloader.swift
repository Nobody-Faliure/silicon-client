import Foundation
import ZIPFoundation
import AppKit

final class ResourceDownloader {
	let minecraftVersion = "26.2"
	
	let versionManifestURL = URL(
		string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
	)!
	
	func fetchVersionManifest() async throws -> Data {
		let (data, _) = try await URLSession.shared.data(from: versionManifestURL)
		return data
	}
	
	struct VersionManifest: Decodable {
		let versions: [MinecraftVersion]
	}

	struct MinecraftVersion: Decodable {
		let id: String
		let url: URL
	}
	
	func decodeVersionManifest(from data: Data) throws -> VersionManifest {
		return try JSONDecoder().decode(VersionManifest.self, from: data)
	}
	
	func findMinecraftVersion(in manifest: VersionManifest) -> MinecraftVersion? {
		return manifest.versions.first {
			$0.id == minecraftVersion
		}
	}
	
	func fetchVersionMetadata(for version: MinecraftVersion) async throws -> Data {
		let (data, _) = try await URLSession.shared.data(from: version.url)
		return data
	}
	
	func decodeVersionMetadata(from data: Data) throws -> VersionMetadata {
		return try JSONDecoder().decode(VersionMetadata.self, from: data)
	}
	
	struct VersionMetadata: Decodable {
		let downloads: Downloads
	}

	struct Downloads: Decodable {
		let client: ClientDownload
	}

	struct ClientDownload: Decodable {
		let url: URL
	}
	
	func fetchClientJar(from metadata: VersionMetadata) async throws -> Data {
		let url = metadata.downloads.client.url
		let (data, _) = try await URLSession.shared.data(from: url)
		return data
	}
	
	func saveClientJar(_ data: Data) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("minecraft-client.jar")
		
		try data.write(to: url)
		return url
	}
	
	func downloadAllBlockAndItemTextures() async throws -> URL {
		let manifestData = try await fetchVersionManifest()
		let manifest = try decodeVersionManifest(from: manifestData)

		guard let version = findMinecraftVersion(in: manifest) else {
			throw NSError(domain: "TextureDownloader", code: 10)
		}

		let metadataData = try await fetchVersionMetadata(for: version)
		let metadata = try decodeVersionMetadata(from: metadataData)

		let jarData = try await fetchClientJar(from: metadata)
		let jarURL = try saveClientJar(jarData)

		let archive = try Archive(url: jarURL, accessMode: .read)

		let textureFolder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
		.appendingPathComponent("Silicon Client")
		.appendingPathComponent("assets/minecraft/textures")
		
		print("Texture folder:", textureFolder.path)

		try FileManager.default.createDirectory(
			at: textureFolder,
			withIntermediateDirectories: true
		)

		for entry in archive {
			let path = entry.path

			let isBlockTexture =
				path.hasPrefix("assets/minecraft/textures/block/")

			let isItemTexture =
				path.hasPrefix("assets/minecraft/textures/item/")

			guard
				(isBlockTexture || isItemTexture),
				path.hasSuffix(".png")
			else {
				continue
			}

			let relativePath = path.replacingOccurrences(
				of: "assets/minecraft/textures/",
				with: ""
			)

			let destinationURL =
				textureFolder.appendingPathComponent(relativePath)

			let destinationFolder =
				destinationURL.deletingLastPathComponent()

			try FileManager.default.createDirectory(
				at: destinationFolder,
				withIntermediateDirectories: true
			)

			var textureData = Data()

			_ = try archive.extract(entry) { chunk in
				textureData.append(chunk)
			}

			if let image = NSImage(data: textureData),
			   let tiffData = image.tiffRepresentation,
			   let bitmap = NSBitmapImageRep(data: tiffData),
			   let pngData = bitmap.representation(using: .png, properties: [:]) {
				try pngData.write(to: destinationURL)
			} else {
				try textureData.write(to: destinationURL)
			}
			
		}

		return textureFolder
	}
	
	func downloadAllModelJSONs() async throws -> URL {
		let manifestData = try await fetchVersionManifest()
		let manifest = try decodeVersionManifest(from: manifestData)
		
		guard let version = findMinecraftVersion(in: manifest) else {
			throw NSError(domain: "ResourceDownloader", code: 20)
		}
		
		let metadataData = try await fetchVersionMetadata(for: version)
		let metadata = try decodeVersionMetadata(from: metadataData)
		
		let jarData = try await fetchClientJar(from: metadata)
		let jarURL = try saveClientJar(jarData)
		let archive = try Archive(url: jarURL, accessMode: .read)
		
		let modelFolder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
		.appendingPathComponent("Silicon Client")
		.appendingPathComponent("assets/minecraft/models")
		
		try FileManager.default.createDirectory(
			at: modelFolder,
			withIntermediateDirectories: true
		)
		
		for entry in archive {
			let path = entry.path
			guard
				path.hasPrefix("assets/minecraft/models/"),
				path.hasSuffix(".json")
					else {
				continue
			}
			
			let relativePath = path.replacingOccurrences(
				of: "assets/minecraft/models/",
				with: ""
			)
			
			let destinationURL =
				modelFolder.appendingPathComponent(relativePath)
			
			let destinationFolder =
				destinationURL.deletingLastPathComponent()
			
			try FileManager.default.createDirectory(
				at: destinationFolder,
				withIntermediateDirectories: true
			)
			
			var modelData = Data()
			
			_ = try archive.extract(entry) { chunk in
				modelData.append(chunk)
			}
			
			try modelData.write(to: destinationURL)
		}
		
		return modelFolder
	}
}
