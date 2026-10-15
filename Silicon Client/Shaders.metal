#include <metal_stdlib>
using namespace metal;

struct Vertex {
	short4 position;   // xyz in 1/256 of a block, w = 1 for the grass overlay nudge
	ushort2 uv;        // 0...65535 = 0...1
	uchar4 color;      // rgb = tint, a = shade
};

struct VertexOut {
	float4 position [[position]];
	float2 uv;
	float3 tint;
	float shade;
};

vertex VertexOut vertexShader(
							  const device Vertex* vertices [[buffer(0)]],
							  uint vertexID [[vertex_id]],
							  constant float4x4& projectionMatrix [[buffer(1)]],
							  constant float4x4& viewMatrix [[buffer(2)]],
							  constant packed_float3& sectionOrigin [[buffer(3)]]
							  ) {
	Vertex v = vertices[vertexID];
	float3 position = float3(v.position.xyz) / 256.0 + float3(sectionOrigin);
	
	VertexOut out;
	out.position = projectionMatrix * viewMatrix * float4(position, 1.0);
	if (v.position.w != 0) {
		out.position.z -= 0.0002 * out.position.w;
	}
	out.uv = float2(v.uv) / 65535.0;
	out.tint = float3(v.color.rgb) / 255.0;
	out.shade = float(v.color.a) / 255.0;
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
	
	float4 color = texture.sample(textureSampler, in.uv);
	
	if (color.a < 0.5) {
		discard_fragment();
	}
	
	if (color.g == 0.0 && color.b == 0.0) {
		color = float4(color.r, color.r, color.r, color.a);
	}
	
	color.rgb *= in.tint;
	color.rgb *= in.shade;
	
	return color;
}

