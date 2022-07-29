cbuffer constants : register(b0) {
	float4x4 transform;
	float4x4 projection;
}

struct vs_in {
	float3 position : POS;
	float3 color    : COL;
};

struct vs_out {
	float4 position : SV_POSITION;
	float4 color    : COL;
};

vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(projection, mul(transform, float4(input.position, 1.0f)));
	//output.position = float4(0,0,0,0);
	output.color = float4(input.color.rgb, 1);
	return output;
}

float4 ps_main(vs_out input) : SV_TARGET {
	return float4(1, 1, 0, 1);
}