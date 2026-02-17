cbuffer ConstantBuffer : register(b0)
{
    matrix world;
    matrix view;
    matrix projection;
}

struct VS_INPUT
{
    float4 Pos : POSITION;
    float2 Tex : TEXCOORD0;
    float3 Normal : NORMAL;
};

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 Tex : TEXCOORD0;
    float3 Normal : NORMAL;
};

Texture2D txDiffuse : register(t0);
SamplerState samLinear : register(s0);

PS_INPUT VS(VS_INPUT input)
{
    PS_INPUT output = (PS_INPUT)0;
    output.Pos = mul(input.Pos, world);
    output.Pos = mul(output.Pos, view);
    output.Pos = mul(output.Pos, projection);
    output.Tex = input.Tex;
    output.Normal = mul(input.Normal, (float3x3)world);
    return output;
}

float4 PS(PS_INPUT input) : SV_Target
{
    float4 col = txDiffuse.Sample(samLinear, input.Tex);
    float3 lightDir = normalize(float3(1, 1, -1));
    float lightIntensity = saturate(dot(input.Normal, lightDir)) * 0.8 + 0.2;
    return col * lightIntensity;
}
