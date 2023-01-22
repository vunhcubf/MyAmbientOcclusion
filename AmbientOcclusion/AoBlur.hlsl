#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#if defined FULL_PRECISION_AO
#define half float
#define half2 float2
#define half3 float3
#define half4 float4
#define half4x4 float4x4
#define half3x3 float3x3
#endif

int Kernel_Radius;
float BlurSharpness;
            
TEXTURE2D(RT_Spatial_In_X);
SAMPLER(sampler_RT_Spatial_In_X);
TEXTURE2D(RT_Spatial_In_Y);
SAMPLER(sampler_RT_Spatial_In_Y);

TEXTURE2D(AO_CameraTexture);
SAMPLER(sampler_AO_CameraTexture);
TEXTURE2D(AmbientOcclusion);
SAMPLER(sampler_AmbientOcclusion);

TEXTURE2D_X_FLOAT(_MotionVectorTexture);
SAMPLER(sampler_MotionVectorTexture);
sampler2D RT_Temporal_In;
sampler2D _AO_Previous_RT;

float TemporalFilterIntensity;

float4 RT_Temporal_In_TexelSize;
float4 _CameraDepthTexture_TexelSize;

struct VertexInput{
    float4 positionOS:POSITION;
    float2 uv:TEXCOORD0;
};

struct VertexOutput{
   float4 position:SV_POSITION;
    float2 uv:TEXCOORD0;
};
float Pow2(float x){
    return x*x;
}
float GetEyeDepth(float2 uv){
    return LinearEyeDepth(SampleSceneDepth(uv),_ZBufferParams);
}
float Luminance(float3 rgb){
	return rgb.r*0.299 + rgb.g*0.587 + rgb.b*0.114;
}
float2 GetClosestUv(float2 uv){//要使用去除抖动的uv
	float2 Closest_Offset=float2(0,0);
	UNITY_UNROLL
	for(int i=-1;i<=1;i++){
		UNITY_UNROLL
		for(int j=-1;j<=1;j++){
			int flag=step(GetEyeDepth(uv),GetEyeDepth(uv+_CameraDepthTexture_TexelSize.xy*float2(i,j)));
			Closest_Offset=lerp(Closest_Offset,float2(i,j),flag);
		}
	}
	return _CameraDepthTexture_TexelSize.xy*Closest_Offset+uv;
}
void GetBoundedBox(out float3 cmin,out float3 cmax,float2 uv){
	float2 du=float2(1,0)*RT_Temporal_In_TexelSize.xy;
	float2 dv=float2(0,1)*RT_Temporal_In_TexelSize.xy;

	float3 ctl = tex2D(RT_Temporal_In, uv - dv - du).rgb;
	float3 ctc = tex2D(RT_Temporal_In, uv - dv).rgb;
	float3 ctr = tex2D(RT_Temporal_In, uv - dv + du).rgb;
	float3 cml = tex2D(RT_Temporal_In, uv - du).rgb;
	float3 cmc = tex2D(RT_Temporal_In, uv).rgb;
	float3 cmr = tex2D(RT_Temporal_In, uv + du).rgb;
	float3 cbl = tex2D(RT_Temporal_In, uv + dv - du).rgb;
	float3 cbc = tex2D(RT_Temporal_In, uv + dv).rgb;
	float3 cbr = tex2D(RT_Temporal_In, uv + dv + du).rgb;

	cmin = min(ctl, min(ctc, min(ctr, min(cml, min(cmc, min(cmr, min(cbl, min(cbc, cbr))))))));
	cmax = max(ctl, max(ctc, max(ctr, max(cml, max(cmc, max(cmr, max(cbl, max(cbc, cbr))))))));
}
void FetchAOAndDepth(float2 uv, inout float ao, inout float depth,bool Is_X){
	UNITY_BRANCH 
	if(Is_X){ao = SAMPLE_TEXTURE2D(RT_Spatial_In_X, sampler_RT_Spatial_In_X, uv).r;}
	else{ao = SAMPLE_TEXTURE2D(RT_Spatial_In_Y, sampler_RT_Spatial_In_Y, uv).r;}
	depth = SampleSceneDepth(uv);
	depth = Linear01Depth(depth, _ZBufferParams);
}
float CrossBilateralWeight(float r, float d, float d0){
	float blurSigma = Kernel_Radius * 0.5;
	float blurFalloff = 1.0 / (2.0 * blurSigma * blurSigma);

	float dz = (d0 - d) * _ProjectionParams.z * BlurSharpness;
	return exp2(-r * r * blurFalloff - dz * dz);
}

void ProcessSample(float ao, float d, float r, float d0, inout float totalAO, inout float totalW){
	float w = CrossBilateralWeight(r, d, d0);
	totalW += w;
	totalAO += w * ao;
}

void ProcessRadius(float2 uv0, float2 deltaUV, float d0, inout float totalAO, inout float totalW,bool Is_X){
	float ao;
	float d;
	float2 uv;
	UNITY_LOOP
	for (int r = 1; r <= Kernel_Radius; r++)
	{
		uv = uv0 + r * deltaUV;
		FetchAOAndDepth(uv, ao, d,Is_X);
		ProcessSample(ao, d, r, d0, totalAO, totalW);
	}
}
        
VertexOutput Vert_PostProcessDefault(VertexInput v){
    VertexOutput o;
	VertexPositionInputs positionInputs = GetVertexPositionInputs(v.positionOS.xyz);
    o.position = positionInputs.positionCS;
    o.uv = v.uv;
    return o;
}

float4 Frag_Bilateral_X(VertexOutput i):SV_Target{
    float2 deltaUV=float2(1,0)*RT_Temporal_In_TexelSize.xy;
    float totalAO;
	float depth;
	FetchAOAndDepth(i.uv, totalAO, depth,true);
	float totalW = 1.0;

	ProcessRadius(i.uv, -deltaUV, depth, totalAO, totalW,true);
	ProcessRadius(i.uv, +deltaUV, depth, totalAO, totalW,true);

	totalAO /= totalW;
	return totalAO;
}
float4 Frag_Bilateral_Y(VertexOutput i):SV_Target{
    float2 deltaUV=float2(0,1)*RT_Temporal_In_TexelSize.xy;
    float totalAO;
	float depth;
	FetchAOAndDepth(i.uv, totalAO, depth,false);
	float totalW = 1.0;

	ProcessRadius(i.uv, -deltaUV, depth, totalAO, totalW,false);
	ProcessRadius(i.uv, +deltaUV, depth, totalAO, totalW,false);

	totalAO /= totalW;
	return totalAO;//*SAMPLE_TEXTURE2D(AO_CameraTexture, sampler_AO_CameraTexture, i.uv).rgba;
}
float4 Frag_TemporalFilter(VertexOutput i):SV_Target{
	float2 Closest_uv=GetClosestUv(i.uv);
    float2 Velocity=SAMPLE_TEXTURE2D_X(_MotionVectorTexture,sampler_MotionVectorTexture,Closest_uv).rg;
	float ViewDistance=SampleSceneDepth(Closest_uv);
	ViewDistance=LinearEyeDepth(ViewDistance,_ZBufferParams);
	//灰度的包围盒
	float3 AABBMin,AABBMax;
	GetBoundedBox(AABBMin,AABBMax,i.uv);
	float3 AO_Pre=tex2D(_AO_Previous_RT,i.uv-Velocity).rgb;
	float3 AO_Cur=tex2D(RT_Temporal_In,i.uv).rgb;
	AO_Pre=clamp(AO_Pre,AABBMin,AABBMax);
	float lum0 = Luminance(AO_Cur.rgb);
	float lum1 = Luminance(AO_Pre.rgb);
	float unbiased_diff = abs(lum0 - lum1) / max(lum0, max(lum1, 0.2));
	float unbiased_weight=saturate(1-unbiased_diff);
	float BlendFactor=saturate(pow(unbiased_weight,1.1-TemporalFilterIntensity))*saturate(rcp(0.8*Pow2(length(Velocity))+0.8));
	float3 AO=lerp(AO_Cur,AO_Pre,BlendFactor);
	return float4(AO,1);
}
float4 Frag_BlendToScreen(VertexOutput i):SV_Target{
	#if defined DEBUG_AO_ONLY
	float3 Ao=SAMPLE_TEXTURE2D(AmbientOcclusion,sampler_AmbientOcclusion,i.uv).xxx;
	return float4(Ao,1);
	#else
	float3 result=SAMPLE_TEXTURE2D(AO_CameraTexture,sampler_AO_CameraTexture,i.uv).rgb;
	float3 Ao=SAMPLE_TEXTURE2D(AmbientOcclusion,sampler_AmbientOcclusion,i.uv).xxx;
	return float4(Ao*result,1);
	#endif
}
float4 Frag_CopyDepth(VertexOutput i):SV_Target{
	return SampleSceneDepth(i.uv);
}