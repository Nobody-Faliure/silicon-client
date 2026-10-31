// Runs once per version, on first launch (started by Swift, see MinecraftServer.swift).
// Asks Minecraft's own code about every entity: its size now; its model, texture and
// animations in later stages. Writes them to one JSON file.
//
// Usage: java -cp <client jar>:<libraries> EntityExtractor.java <output.json>

import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.EntityType;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

public class EntityExtractor {
	public static void main(String[] arguments) throws Exception {
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		StringBuilder json = new StringBuilder("{\n  \"types\": [\n");
		for (int id = 0; id < BuiltInRegistries.ENTITY_TYPE.size(); id++) {
			EntityType<?> type = BuiltInRegistries.ENTITY_TYPE.byId(id);
			String name = BuiltInRegistries.ENTITY_TYPE.getKey(type).getPath();
			json.append("    {\"name\": \"" + name + "\", \"width\": " + number(type.getWidth())
				+ ", \"height\": " + number(type.getHeight()) + "},\n");
		}
		json.setLength(json.length() - 2);
		json.append("\n  ]\n}\n");
		Files.writeString(Path.of(arguments[0]), json.toString());
	}

	static String number(double value) {
		return String.format(Locale.ROOT, "%.4f", value);
	}
}
