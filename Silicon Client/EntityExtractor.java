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
import java.lang.reflect.*;
import sun.reflect.ReflectionFactory;
import net.minecraft.client.model.geom.EntityModelSet;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import java.util.Map;
import net.minecraft.client.renderer.entity.EntityRenderers;
import net.minecraft.client.renderer.entity.EntityRenderer;
import java.util.List;
import java.util.ArrayList;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.entity.LivingEntityRenderer;
import net.minecraft.client.renderer.entity.AbstractBoatRenderer;
import net.minecraft.resources.Identifier;
import net.minecraft.client.renderer.entity.state.LivingEntityRenderState;

public class EntityExtractor {
	public static void main(String[] arguments) throws Exception {
		SharedConstants.tryDetectVersion();
		Bootstrap.bootStrap();
		Constructor<?> blankMaker = ReflectionFactory.getReflectionFactory()
			.newConstructorForSerialization(EntityRendererProvider.Context.class, Object.class.getDeclaredConstructor());
		EntityRendererProvider.Context context = (EntityRendererProvider.Context) blankMaker.newInstance();
		Field modelSetField = EntityRendererProvider.Context.class.getDeclaredField("modelSet");
		modelSetField.setAccessible(true);
		modelSetField.set(context, EntityModelSet.vanilla());
		Field providersField = EntityRenderers.class.getDeclaredField("PROVIDERS");
		providersField.setAccessible(true);
		Map<EntityType<?>, EntityRendererProvider<?>> providers = (Map<EntityType<?>, EntityRendererProvider<?>>) providersField.get(null);
		StringBuilder json = new StringBuilder("{\n  \"types\": [\n");
		for (int id = 0; id < BuiltInRegistries.ENTITY_TYPE.size(); id++) {
			EntityType<?> type = BuiltInRegistries.ENTITY_TYPE.byId(id);
			String name = BuiltInRegistries.ENTITY_TYPE.getKey(type).getPath();
			json.append("    {\"name\": \"" + name + "\", \"width\": " + number(type.getWidth())
				+ ", \"height\": " + number(type.getHeight()) + "},\n");
		}
		json.setLength(json.length() - 2);
		json.append("\n  ],\n  \"models\": [\n");
		for (EntityType<?> type : providers.keySet()) {
			String name = BuiltInRegistries.ENTITY_TYPE.getKey(type).getPath();
			EntityRenderer<?, ?> renderer;
			try {
				renderer = providers.get(type).create(context);
			} catch (Throwable error) {
				continue;
			}
			String texture = "";
			try {
				LivingEntityRenderer living = (LivingEntityRenderer) renderer;
				texture = living.getTextureLocation((LivingEntityRenderState) living.createRenderState()).getPath();
			} catch (Throwable error) {
			}
			if (renderer instanceof AbstractBoatRenderer boat) {
				Field textureField = AbstractBoatRenderer.class.getDeclaredField("texture");
				textureField.setAccessible(true);
				texture = ((Identifier) textureField.get(boat)).getPath();
			}
			for (Class<?> kind = renderer.getClass(); kind != null && texture.isEmpty(); kind = kind.getSuperclass()) {
				for (Field field : kind.getDeclaredFields()) {
					if (field.getType() == Identifier.class && Modifier.isStatic(field.getModifiers())) {
						field.setAccessible(true);
						texture = ((Identifier) field.get(null)).getPath();
					}
				}
			}
			List<Model<?>> models = new ArrayList<>();
			findModels(renderer, models);
			for (Model<?> model : models) {
				json.append("    {\"entity\": \"" + name + "\", \"kind\": \"" + model.getClass().getSimpleName() + "\", \"texture\": \"" + texture + "\", \"parts\": [\n");
				writePart(json, "root", model.root(), -1, new ArrayList<>());
				json.setLength(json.length() - 2);
				json.append("\n    ]},\n");
			}
		}
		json.setLength(json.length() - 2);
		json.append("\n  ]\n}\n");
		Files.writeString(Path.of(arguments[0]), json.toString());
	}

	static String number(double value) {
		if (Double.isNaN(value) || Double.isInfinite(value)) {
			value = 0;
		}
		return String.format(Locale.ROOT, "%.4f", value);
	}

	static void findModels(Object thing, List<Model<?>> models) throws Exception {
		if (thing instanceof Model<?> model) {
			if (!models.contains(model)) {
				models.add(model);
			}
		}
		if (thing instanceof Map<?, ?> map) {
			for (Object value : map.values()) {
				findModels(value, models);
			}
		}
		if (thing instanceof EntityRenderer<?, ?> || thing instanceof Record) {
			for (Class<?> kind = thing.getClass(); kind != null; kind = kind.getSuperclass()) {
				for (Field field : kind.getDeclaredFields()) {
					if (!Modifier.isStatic(field.getModifiers()) && !field.getType().isPrimitive()) {
						field.setAccessible(true);
						findModels(field.get(thing), models);
					}
				}
			}
		}
	}

	static void writePart(StringBuilder json, String name, ModelPart part, int parent, List<ModelPart> written) throws Exception {
		int index = written.size();
		written.add(part);
		json.append("      {\"name\": \"" + name + "\", \"parent\": " + parent
			+ ", \"x\": " + number(part.x) + ", \"y\": " + number(part.y) + ", \"z\": " + number(part.z)
			+ ", \"xRot\": " + number(part.xRot) + ", \"yRot\": " + number(part.yRot) + ", \"zRot\": " + number(part.zRot) + ", \"faces\": [");
		Field cubesField = ModelPart.class.getDeclaredField("cubes");
		cubesField.setAccessible(true);
		List<ModelPart.Cube> cubes = (List<ModelPart.Cube>) cubesField.get(part);
		for (ModelPart.Cube cube : cubes) {
			for (ModelPart.Polygon polygon : cube.polygons) {
				writeFace(json, polygon);
			}
		}
		if (json.charAt(json.length() - 1) == ',') {
			json.setLength(json.length() - 1);
		}
		json.append("]},\n");
		Field childrenField = ModelPart.class.getDeclaredField("children");
		childrenField.setAccessible(true);
		Map<String, ModelPart> children = (Map<String, ModelPart>) childrenField.get(part);
		for (String childName : children.keySet()) {
			writePart(json, childName, children.get(childName), index, written);
		}
	}

	static void writeFace(StringBuilder json, ModelPart.Polygon polygon) {
		json.append("[");
		for (ModelPart.Vertex corner : polygon.vertices()) {
			json.append(number(corner.x()) + "," + number(corner.y()) + "," + number(corner.z()) + "," + number(corner.u()) + "," + number(corner.v()) + ",");
		}
		json.setLength(json.length() - 1);
		json.append("],");
	}
}
