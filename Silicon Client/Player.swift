import Foundation

struct Player {
	var x: Double = 0
	var y: Double = 0
	var z: Double = 0
	
	var yaw: Float = 0
	var pitch: Float = 0
}

enum PositionDecoder {
	static func decode(packet: Data) -> (teleportID: Int, player: Player)? {
		var reader = NBTReader(data: packet)
		
		guard reader.readVarInt() == 0x48 else { return nil }
		
		let teleportID = reader.readVarInt()
		
		var player = Player()
		
		player.x = reader.readDouble()
		player.y = reader.readDouble()
		player.z = reader.readDouble()
		
		reader.index += 24          // velocity x, y, z — unused
		
		player.yaw = reader.readFloat()
		player.pitch = reader.readFloat()
		
		return (teleportID, player)
	}
}
