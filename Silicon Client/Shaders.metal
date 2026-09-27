#include <metal_stdlib>
using namespace metal;

struct Vertex {
	float3 position;
	float2 uv;
	int tintIndex;
};

struct VertexOut {
	float4 position [[position]];
	float2 uv;
	int tintIndex;
};

vertex VertexOut vertexShader(
						   const device Vertex* vertices [[buffer(0)]],
						   uint vertexID [[vertex_id]],
						   constant float4x4& projectionMatrix [[buffer(1)]],
						   constant float4x4& viewMatrix [[buffer(2)]]

) {
	VertexOut out;
	out.position = projectionMatrix * viewMatrix * float4(vertices[vertexID].position, 1.0);
	out.uv = vertices[vertexID].uv;
	out.tintIndex = vertices[vertexID].tintIndex;
	return out;
}

float3 tintColour(int index) {
	if (index < 0) {
		return float3(1.0);              // no tint
	}
	return float3(0.57, 0.74, 0.35);     // plains grass, until biomes arrive
}

fragment float4 fragmentShader(
	VertexOut in [[stage_in]],
	texture2d<float> texture [[texture(0)]]
) {
	constexpr sampler textureSampler(
		mag_filter::nearest,
		min_filter::nearest
	);

	float4 color = texture.sample(textureSampler, in.uv);
	
	if (color.a < 0.5) {
		discard_fragment();
	}

	if (color.g == 0.0 && color.b == 0.0) {
		color = float4(color.r, color.r, color.r, color.a);
	}
	
	color.rgb *= tintColour(in.tintIndex);

	return color;
}

