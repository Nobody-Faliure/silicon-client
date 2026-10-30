// Runs once per version, on first launch (started by Swift, see MinecraftServer.swift).
// Lets Minecraft's own code build its list of blocks, then writes each block's
// hardness to a JSON file so the dig timer matches the server exactly.
//
// Usage: java -cp <server jar>:<libraries> HardnessExtractor.java <output.json>

import net.minecraft.SharedConstants;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.level.EmptyBlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import java.nio.file.Files;
import java.nio.file.Path;

public class BlockDataExtractor {
	public static void main(String[] arguments) throws Exception {
		// 1. Bootstrap: let the game build its lists of blocks, items, entities
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		
		// 2. Ask every block for its values
		StringBuilder json = new StringBuilder("[\n");
		for (int id = 0; id < Block.BLOCK_STATE_REGISTRY.size(); id++) {
			BlockState state = Block.BLOCK_STATE_REGISTRY.byId(id);
			float hardness = state.getDestroySpeed(EmptyBlockGetter.INSTANCE, BlockPos.ZERO);
			boolean needsTool = state.requiresCorrectToolForDrops();
			StringBuilder collision = new StringBuilder("[");
			for (AABB box : state.getCollisionShape(EmptyBlockGetter.INSTANCE, BlockPos.ZERO).toAabbs()) {
				if (collision.length() > 1) collision.append(", ");
				collision.append("[" + box.minX + ", " + box.minY + ", " + box.minZ + ", " + box.maxX + ", " + box.maxY + ", " + box.maxZ + "]");
			}
			collision.append("]");
			json.append("  {\"hardness\": " + hardness + ", \"needsTool\": " + needsTool
						+ ", \"lightDampening\": " + state.getLightDampening()
						+ ", \"lightEmission\": " + state.getLightEmission()
						+ ", \"skylightDown\": " + state.propagatesSkylightDown()
						+ ", \"collision\": " + collision + "},\n");
		}
		json.setLength(json.length() - 2);  // drop the last ",\n" (JSON forbids a trailing comma)
		json.append("\n]\n");

		// 3. Spit it out
		Files.writeString(Path.of(arguments[0]), json);
	}
}
