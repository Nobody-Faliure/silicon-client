#include <metal_stdlib>
using namespace metal;

struct Vertex {
	float3 position;
	float2 uv;
};

struct VertexOut {
	float4 position [[position]];
	float2 uv;
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
	return out;
}

fragment float4 fragmentShader(
	VertexOut in [[stage_in]],
	texture2d<float> texture [[texture(0)]]
) {
	constexpr sampler textureSampler(
		mag_filter::nearest,
		min_filter::nearest
	);

	return texture.sample(textureSampler, in.uv);
}

