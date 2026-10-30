// Runs once per version, on first launch (started by Swift, see MinecraftServer.swift).
// Asks Minecraft's own colour rulebook which colour every block state is tinted with:
// a biome colour (grass, foliage, dry foliage, water) or a fixed colour.
//
// Usage: java -cp <client jar>:<libraries> BlockTintExtractor.java <output.json>

import net.minecraft.SharedConstants;
import net.minecraft.core.BlockPos;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.level.ColorResolver;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.client.color.block.BlockColors;
import net.minecraft.client.color.block.BlockTintSource;
import net.minecraft.client.renderer.BiomeColors;
import net.minecraft.client.renderer.block.BlockAndTintGetter;
import net.minecraft.world.level.CardinalLighting;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.lighting.LevelLightEngine;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.material.Fluids;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public class BlockTintExtractor {
	public static void main(String[] arguments) throws Exception {
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		BlockColors colors = BlockColors.createDefault();
		BlockAndTintGetter fakeWorld = new FakeWorld();
		String[] labelNames = {"", "grass", "foliage", "dry_foliage", "water"};
		StringBuilder json = new StringBuilder("[\n");
		for (int id = 0; id < Block.BLOCK_STATE_REGISTRY.size(); id++) {
			BlockState state = Block.BLOCK_STATE_REGISTRY.byId(id);
			List<BlockTintSource> rules = colors.getTintSources(state);
			json.append("  [");
			for (int index = 0; index < rules.size(); index++) {
				int answer = rules.get(index).colorInWorld(state, fakeWorld, BlockPos.ZERO);
				if (index > 0) json.append(", ");
				if (answer >= 1 && answer <= 4) json.append("\"" + labelNames[answer] + "\"");
				else json.append(String.format("{\"fixed\": \"#%06x\"}", answer & 0xFFFFFF));
			}
			json.append("],\n");
		}
		json.setLength(json.length() - 2);   // drop the last ",\n" (JSON forbids a trailing comma)
		json.append("\n]\n");
		Files.writeString(Path.of(arguments[0]), json);
	}

	// A pretend world. Rules ask it "which biome colour here?"; it answers with a label number
	// (1 grass, 2 foliage, 3 dry foliage, 4 water) so we can tell which colour each rule wants.
	// The other questions are never really used, so they get harmless answers.
	static class FakeWorld implements BlockAndTintGetter {
		public int getBlockTint(BlockPos position, ColorResolver asked) {
			if (asked == BiomeColors.GRASS_COLOR_RESOLVER) return 1;
			if (asked == BiomeColors.FOLIAGE_COLOR_RESOLVER) return 2;
			if (asked == BiomeColors.DRY_FOLIAGE_COLOR_RESOLVER) return 3;
			if (asked == BiomeColors.WATER_COLOR_RESOLVER) return 4;
			return 0;
		}
		public BlockState getBlockState(BlockPos position) { return Blocks.AIR.defaultBlockState(); }
		public FluidState getFluidState(BlockPos position) { return Fluids.EMPTY.defaultFluidState(); }
		public BlockEntity getBlockEntity(BlockPos position) { return null; }
		public CardinalLighting cardinalLighting() { return null; }
		public LevelLightEngine getLightEngine() { return null; }
		public int getMinY() { return -64; }
		public int getHeight() { return 384; }
	}
}
