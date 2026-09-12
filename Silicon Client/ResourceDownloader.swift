import Foundation
import ZIPFoundation
import AppKit

final class ResourceDownloader {
	
	// Minecraft version this downloader looks for
	let minecraftVersion = "26.2"
	
	// Mojang's list of all Minecraft versions
	let versionManifestURL = URL(
		string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
	)!
	
	// Downloads the main version manifest
	func fetchVersionManifest() async throws -> Data {
		let (data, _) = try await URLSession.shared.data(from: versionManifestURL)
		return data
	}
	
	// Structure of the main version manifest JSON
	struct VersionManifest: Decodable {
		let versions: [MinecraftVersion]
	}

	// One Minecraft version inside the manifest
	struct MinecraftVersion: Decodable {
		let id: String
		let url: URL
	}
	
	// Converts downloaded manifest JSON into Swift structs
	func decodeVersionManifest(from data: Data) throws -> VersionManifest {
		return try JSONDecoder().decode(VersionManifest.self, from: data)
	}
	
	// Finds our chosen Minecraft version
	func findMinecraftVersion(in manifest: VersionManifest) -> MinecraftVersion? {
		return manifest.versions.first {
			$0.id == minecraftVersion
		}
	}
	
	// Downloads metadata for one specific Minecraft version
	func fetchVersionMetadata(for version: MinecraftVersion) async throws -> Data {
		let (data, _) = try await URLSession.shared.data(from: version.url)
		return data
	}
	
	// Converts version metadata JSON into Swift structs
	func decodeVersionMetadata(from data: Data) throws -> VersionMetadata {
		return try JSONDecoder().decode(VersionMetadata.self, from: data)
	}
	
	// Contains download information for this version
	struct VersionMetadata: Decodable {
		let downloads: Downloads
	}

	struct Downloads: Decodable {
		let client: ClientDownload
	}

	// Contains the URL of the official client JAR
	struct ClientDownload: Decodable {
		let url: URL
	}
	
	// Downloads the official Minecraft client JAR
	func fetchClientJar(from metadata: VersionMetadata) async throws -> Data {
		let url = metadata.downloads.client.url
		let (data, _) = try await URLSession.shared.data(from: url)
		return data
	}
	
	// Saves the downloaded JAR into the temporary folder
	func saveClientJar(_ data: Data) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("minecraft-client.jar")
		
		try data.write(to: url)
		return url
	}
	
	// Downloads the JAR and extracts all block/item textures
	func downloadAllBlockAndItemTextures() async throws -> URL {
		
		// Find Minecraft 26.2
		let manifestData = try await fetchVersionManifest()
		let manifest = try decodeVersionManifest(from: manifestData)

		guard let version = findMinecraftVersion(in: manifest) else {
			throw NSError(domain: "TextureDownloader", code: 10)
		}

		// Get the client JAR download URL
		let metadataData = try await fetchVersionMetadata(for: version)
		let metadata = try decodeVersionMetadata(from: metadataData)

		// Download and open the JAR as a ZIP archive
		let jarData = try await fetchClientJar(from: metadata)
		let jarURL = try saveClientJar(jarData)

		let archive = try Archive(url: jarURL, accessMode: .read)

		// Permanent folder where Silicon Client stores textures
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

		// Check every file inside the Minecraft JAR
		for entry in archive {
			let path = entry.path

			let isBlockTexture =
				path.hasPrefix("assets/minecraft/textures/block/")

			let isItemTexture =
				path.hasPrefix("assets/minecraft/textures/item/")

			// Ignore everything except block/item PNGs
			guard
				(isBlockTexture || isItemTexture),
				path.hasSuffix(".png")
			else {
				continue
			}

			// Remove the part of the JAR path we don't need
			// Example:
			// assets/minecraft/textures/block/stone.png
			// becomes block/stone.png
			let relativePath = path.replacingOccurrences(
				of: "assets/minecraft/textures/",
				with: ""
			)

			// Final location for this texture
			let destinationURL =
				textureFolder.appendingPathComponent(relativePath)

			let destinationFolder =
				destinationURL.deletingLastPathComponent()

			// Make folders such as block/ and item/ if needed
			try FileManager.default.createDirectory(
				at: destinationFolder,
				withIntermediateDirectories: true
			)

			// Extract the texture bytes from the JAR
			var textureData = Data()

			_ = try archive.extract(entry) { chunk in
				textureData.append(chunk)
			}

			// Re-encode the PNG through AppKit.
			// This avoids the image decoding issue we had with some textures.
			if let image = NSImage(data: textureData),
			   let tiffData = image.tiffRepresentation,
			   let bitmap = NSBitmapImageRep(data: tiffData),
			   let pngData = bitmap.representation(using: .png, properties: [:]) {
				
				try pngData.write(to: destinationURL)
				
			} else {
				
				// Fall back to the original bytes
				try textureData.write(to: destinationURL)
			}
		}

		return textureFolder
	}
	
	// Downloads the JAR and extracts all model JSON files
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
		
		// Permanent folder for model JSONs
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
		
		// Look through everything in the JAR
		for entry in archive {
			let path = entry.path
			
			// Only extract model JSON files
			guard
				path.hasPrefix("assets/minecraft/models/"),
				path.hasSuffix(".json")
			else {
				continue
			}
			
			// Keep the original folder structure
			// Example: block/stone.json
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
			
			// Extract the JSON bytes
			var modelData = Data()
			
			_ = try archive.extract(entry) { chunk in
				modelData.append(chunk)
			}
			
			try modelData.write(to: destinationURL)
		}
		
		return modelFolder
	}
	
	// Downloads the JAR and extracts all blockstate JSON files
	func downloadAllBlockStateJSONs() async throws -> URL {
		
		let manifestData = try await fetchVersionManifest()
		let manifest = try decodeVersionManifest(from: manifestData)
		
		guard let version = findMinecraftVersion(in: manifest) else {
			throw NSError(domain: "ResourceDownloader", code: 30)
		}
		
		let metadataData = try await fetchVersionMetadata(for: version)
		let metadata = try decodeVersionMetadata(from: metadataData)
		
		let jarData = try await fetchClientJar(from: metadata)
		let jarURL = try saveClientJar(jarData)
		let archive = try Archive(url: jarURL, accessMode: .read)
		
		// Permanent folder for blockstate JSONs
		let blockStateFolder = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0]
		.appendingPathComponent("Silicon Client")
		.appendingPathComponent("assets/minecraft/blockstates")
		
		try FileManager.default.createDirectory(
			at: blockStateFolder,
			withIntermediateDirectories: true
		)
		
		// Search every file in the client JAR
		for entry in archive {
			let path = entry.path
			
			// Only extract blockstate JSON files
			guard
				path.hasPrefix("assets/minecraft/blockstates/"),
				path.hasSuffix(".json")
			else {
				continue
			}
			
			// Example:
			// assets/minecraft/blockstates/furnace.json
			// becomes furnace.json
			let relativePath = path.replacingOccurrences(
				of: "assets/minecraft/blockstates/",
				with: ""
			)
			
			let destinationURL =
				blockStateFolder.appendingPathComponent(relativePath)
			
			// Extract the JSON bytes
			var blockStateData = Data()
			
			_ = try archive.extract(entry) { chunk in
				blockStateData.append(chunk)
			}
			
			try blockStateData.write(to: destinationURL)
		}
		
		return blockStateFolder
	}
}
