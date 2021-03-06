#if !defined(ITE)
#define ITE 32
#endif

float EPS = 0.003;
float mindist<float uistep = .0001;> = .0001;

float emit <string uiname = "Emission Stlength";> = 1.0;
float stepLength<string uiname = "StepLength";> = 1.0;

SamplerState linearSampler : IMMUTABLE
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Wrap;
	AddressV = Wrap;
};

cbuffer cbPerDraw : register( b0 )
{
	float4x4 tVP : VIEWPROJECTION;	
	float4x4 tVPI : VIEWPROJECTIONINVERSE;
	float4x4 tV : VIEW;
	float4x4 tP : PROJECTION;
	float4x4 tPI : PROJECTIONINVERSE;
	float4x4 tVI : VIEWINVERSE;
	float4x4 ptVP : PREVIOUSVIEWPROJECTION;
	float4x4 ptVPI : PREVIOUSVIEWPROJECTIONINVERSE;
};

cbuffer cbPerObj : register( b1 )
{
	float4x4 tW : WORLD;
	float4x4 tWI : WORLDINVERSE;
	float4x4 ptW;
};

struct VS_IN
{
	float4 PosO : POSITION;
	float4 TexCd : TEXCOORD0;
};
struct vs2ps
{
	float4 Pos: SV_Position;
	float2 uv: TEXCOORD0;
};

struct PSout{
	float4 color : SV_Target0;
	float4 normal : SV_Target1;
	float4 MRVel : SV_Target2;
	float3 position : SV_Target3;
	float depth : SV_Depth;
};


float3 getNormal(float3 p) {
    float2 e = float2(1.0, -1.0) * EPS;
	float d = 0;
    return normalize(
        e.xyy * DistanceFunction(p + e.xyy, d) +
        e.yxy * DistanceFunction(p + e.yxy, d) +
        e.yyx * DistanceFunction(p + e.yyx, d) +
        e.xxx * DistanceFunction(p + e.xxx, d)
    );
}

vs2ps VS(VS_IN input)
{
	vs2ps output;
	output.Pos  = input.PosO;
	output.uv = input.TexCd.xy;
	return output;
}

PSout PS(vs2ps In){
	PSout gbuffer;
	Info info = (Info)0;
	OutputData o = (OutputData)0;

	float2 u = mul(float4(In.uv, 1, 1), texW).xy;
	
	float2 rayDir = (In.uv * 2 - 1) * float2(1, -1);
	
	info.rayDir = normalize(mul(float4(mul(float4(rayDir, 0, 0), tPI).xy, 1, 0), tVI).xyz);
	float3 ray = normalize(mul(info.rayDir, (float3x3)tWI));
	
	float3 rayPos = mul(float4(tVI[3].xyz, 1), tWI).xyz;
	info.camPos = tVI[3].xyz;

	float maxdist = -(tP[3].z / (tP[2].z - 1));

	float near = -tP[3].z / tP[2].z;
	rayPos += ray * near;
	float3 normal = 0;
	bool hit = false;
	float dist = 0;
	float total = near;
	float m = 0;
	for(int i = 0; i < ITE; i++){
		dist = DistanceFunction(rayPos, m);
		
		if(dist < mindist * max(total, 1)){ 
			normal = normalize(max(min(getNormal(rayPos), 1), -1));
			normal = normalize(mul(normal, (float3x3)tW));
			hit = true;

			break;
		}
		rayPos += ray * dist * stepLength;
		total += dist * stepLength;
		if(total > maxdist) break;
	}
	
	info.maxLoop = ITE;
	info.loop = i;
	info.totalDistance = total;
	info.Normal = normal;
	info.Material = m;

	float3 endPos = mul(float4(rayPos, 1), tW).xyz;
	info.Pos = endPos;
	float4 possc = mul(float4(endPos, 1), tVP);
	gbuffer.depth = 
	info.Depth = possc.z / possc.w;

	gbuffer.depth = lerp(maxdist, gbuffer.depth, hit);
	
	PostFunction(info, o);

	float3 bNorm = normal;
	if(IsBump){
		float3 bumpy = o.BumpNormal;
		bNorm = BumpsTNB(bNorm, bumpy, info.Pos, o.uv);
	}
	
	gbuffer.color = float4((o.Albedo + o.Emission * emit) * hit, hit);
	gbuffer.normal = float4(bNorm, o.Reflectance) * hit;
	gbuffer.position = endPos * hit;

	float4 prevPosVP = mul(float4(mul(float4(rayPos, 1), ptW).xyz, 1), ptVP);
	float2 prevpossc = prevPosVP.xy / prevPosVP.w;
	float2 velxy = (possc.xy / possc.w) - prevpossc;
	
	velxy *= .5;
	velxy += .5;
	
	gbuffer.MRVel = float4(o.Metalness, o.Roughness, velxy) * hit;
	gbuffer.normal = float4(bNorm, o.Reflectance);
	
	return gbuffer;
}

technique10 GBuffer
{
	pass P0
	{
		SetVertexShader( CompileShader( vs_4_0, VS() ) );
		SetPixelShader( CompileShader( ps_4_0, PS() ) );
	}
}




