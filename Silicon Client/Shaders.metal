#include <metal_stdlib>
using namespace metal;

vertex float4 vertexShader(
						   const device float3* vertices [[buffer(0)]],
						   uint vertexID [[vertex_id]],
						   constant float4x4& projectionMatrix [[buffer(1)]],
						   constant float4x4& viewMatrix [[buffer(2)]]

) {
	return projectionMatrix * viewMatrix * float4(vertices[vertexID], 1.0);
}

fragment float4 fragmentShader() {
	return float4(1.0, 1.0, 1.0, 1.0);
}

