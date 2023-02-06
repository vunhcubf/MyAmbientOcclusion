#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#if defined FULL_PRECISION_AO
#define half float
#define half2 float2
#define half3 float3
#define half4 float4
#define half4x4 float4x4
#define half3x3 float3x3
#endif

//declaredepth这个库，指定lod等级
TEXTURE2D_X_FLOAT(_CameraDepthTexture);
SamplerState Point_Clamp;
SamplerState Linear_Clamp;
half SampleSceneDepth(half2 uv)
{
    return SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, Point_Clamp, UnityStereoTransformScreenSpaceTex(uv),0).r;
}
//*******************************
bool GetSkyBoxMask(half2 uv){
    return step(SampleSceneDepth(uv),0);
}
int Kernel_Radius;
half BlurSharpness;

TEXTURE2D(_GBuffer0);
SAMPLER(sampler_GBuffer0);
TEXTURE2D(_GBuffer1);
SAMPLER(sampler_GBuffer1);
TEXTURE2D(_GBuffer2);
SAMPLER(sampler_GBuffer2);
            
TEXTURE2D(RT_Spatial_In_X);
SAMPLER(sampler_RT_Spatial_In_X);
TEXTURE2D(RT_Spatial_In_Y);
SAMPLER(sampler_RT_Spatial_In_Y);
TEXTURE2D(RT_MultiBounce_In);
SAMPLER(sampler_RT_MultiBounce_In);

TEXTURE2D(AmbientOcclusion);
SAMPLER(sampler_AmbientOcclusion);

TEXTURE2D_X_FLOAT(_MotionVectorTexture);
SAMPLER(sampler_MotionVectorTexture);
sampler2D RT_Temporal_In;
sampler2D _AO_Previous_RT;

half TemporalFilterIntensity;

half4 RT_Temporal_In_TexelSize;
half4 _CameraDepthTexture_TexelSize;

struct VertexInput{
    half4 positionOS:POSITION;
    half2 uv:TEXCOORD0;
};

struct VertexOutput{
   half4 position:SV_POSITION;
    half2 uv:TEXCOORD0;
};
half3 AOMultiBounce( half3 BaseColor, half AO )
{
	half3 a =  2.0404 * BaseColor - 0.3324;
	half3 b = -4.7951 * BaseColor + 0.6417;
	half3 c =  2.7552 * BaseColor + 0.6903;
	return max( AO, ( ( AO * a + b ) * AO + c ) * AO );
}
half Pow2(half x){
    return x*x;
}
half GetEyeDepth(half2 uv){
    return LinearEyeDepth(SampleSceneDepth(uv),_ZBufferParams);
}
half Luminance(half3 rgb){
	return rgb.r*0.299 + rgb.g*0.587 + rgb.b*0.114;
}
half2 GetClosestUv(half2 uv){//要使用去除抖动的uv
	half2 Closest_Offset=half2(0,0);
	UNITY_UNROLL
	for(int i=-1;i<=1;i++){
		UNITY_UNROLL
		for(int j=-1;j<=1;j++){
			int flag=step(GetEyeDepth(uv),GetEyeDepth(uv+_CameraDepthTexture_TexelSize.xy*half2(i,j)));
			Closest_Offset=lerp(Closest_Offset,half2(i,j),flag);
		}
	}
	return _CameraDepthTexture_TexelSize.xy*Closest_Offset+uv;
}
void GetBoundingBox(out half cmin,out half cmax,half2 uv){
	half2 du=half2(1,0)*RT_Temporal_In_TexelSize.xy;
	half2 dv=half2(0,1)*RT_Temporal_In_TexelSize.xy;

	half ctl = tex2D(RT_Temporal_In, uv - dv - du).r;
	half ctc = tex2D(RT_Temporal_In, uv - dv).r;
	half ctr = tex2D(RT_Temporal_In, uv - dv + du).r;
	half cml = tex2D(RT_Temporal_In, uv - du).r;
	half cmc = tex2D(RT_Temporal_In, uv).r;
	half cmr = tex2D(RT_Temporal_In, uv + du).r;
	half cbl = tex2D(RT_Temporal_In, uv + dv - du).r;
	half cbc = tex2D(RT_Temporal_In, uv + dv).r;
	half cbr = tex2D(RT_Temporal_In, uv + dv + du).r;

	cmin = min(ctl, min(ctc, min(ctr, min(cml, min(cmc, min(cmr, min(cbl, min(cbc, cbr))))))));
	cmax = max(ctl, max(ctc, max(ctr, max(cml, max(cmc, max(cmr, max(cbl, max(cbc, cbr))))))));
}
void FetchAOAndDepth(half2 uv, inout half ao, inout half depth,bool Is_X){
	UNITY_BRANCH 
	if(Is_X){ao = SAMPLE_TEXTURE2D(RT_Spatial_In_X, sampler_RT_Spatial_In_X, uv).r;}
	else{ao = SAMPLE_TEXTURE2D(RT_Spatial_In_Y, sampler_RT_Spatial_In_Y, uv).r;}
	depth = SampleSceneDepth(uv);
	depth = Linear01Depth(depth, _ZBufferParams);
}
half CrossBilateralWeight(half r, half d, half d0){
	half blurSigma = Kernel_Radius * 0.5;
	half blurFalloff = 1.0 / (2.0 * blurSigma * blurSigma);

	half dz = (d0 - d) * _ProjectionParams.z * BlurSharpness;
	return exp2(-r * r * blurFalloff - dz * dz);
}

void ProcessSample(half ao, half d, half r, half d0, inout half totalAO, inout half totalW){
	half w = CrossBilateralWeight(r, d, d0);
	totalW += w;
	totalAO += w * ao;
}

void ProcessRadius(half2 uv0, half2 deltaUV, half d0, inout half totalAO, inout half totalW,bool Is_X){
	half ao;
	half d;
	half2 uv;
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

half Frag_Bilateral_X(VertexOutput i):SV_Target{
	[branch]
    if(GetSkyBoxMask(i.uv)){return 1.0;}
    half2 deltaUV=half2(1,0)*RT_Temporal_In_TexelSize.xy;
    half totalAO;
	half depth;
	FetchAOAndDepth(i.uv, totalAO, depth,true);
	half totalW = 1.0;

	ProcessRadius(i.uv, -deltaUV, depth, totalAO, totalW,true);
	ProcessRadius(i.uv, +deltaUV, depth, totalAO, totalW,true);

	totalAO /= totalW;
	return totalAO;
}
half Frag_Bilateral_Y(VertexOutput i):SV_Target{
	[branch]
    if(GetSkyBoxMask(i.uv)){return 1.0;}
    half2 deltaUV=half2(0,1)*RT_Temporal_In_TexelSize.xy;
    half totalAO;
	half depth;
	FetchAOAndDepth(i.uv, totalAO, depth,false);
	half totalW = 1.0;

	ProcessRadius(i.uv, -deltaUV, depth, totalAO, totalW,false);
	ProcessRadius(i.uv, +deltaUV, depth, totalAO, totalW,false);

	totalAO /= totalW;
	return totalAO;
}
half Frag_TemporalFilter(VertexOutput i):SV_Target{
	[branch]
    if(GetSkyBoxMask(i.uv)){return 1.0;}
	half2 Closest_uv=GetClosestUv(i.uv);
    half2 Velocity=SAMPLE_TEXTURE2D_X(_MotionVectorTexture,sampler_MotionVectorTexture,Closest_uv).rg;
	
	//灰度的包围盒
	half AABBMin,AABBMax;
	GetBoundingBox(AABBMin,AABBMax,i.uv);
	half AO_Pre=tex2D(_AO_Previous_RT,i.uv-Velocity).r;
	half AO_Cur=tex2D(RT_Temporal_In,i.uv).r;
	AO_Pre=clamp(AO_Pre,AABBMin,AABBMax);
	half lum0 = AO_Cur;
	half lum1 = AO_Pre;
	half unbiased_diff = abs(lum0 - lum1) / max(lum0, max(lum1, 0.2));
	half unbiased_weight=saturate(1-unbiased_diff);
	half BlendFactor=saturate(pow(unbiased_weight,1.1-TemporalFilterIntensity))*saturate(rcp(0.8*Pow2(length(Velocity))+0.8));
	half AO=lerp(AO_Cur,AO_Pre,BlendFactor);
	return AO;
}
half4 Frag_BlendToScreen(VertexOutput i):SV_Target{
	#if defined MULTI_BOUNCE_AO
	half3 Ao=SAMPLE_TEXTURE2D(AmbientOcclusion,sampler_AmbientOcclusion,i.uv).xyz;
	#else
	half3 Ao=SAMPLE_TEXTURE2D(AmbientOcclusion,sampler_AmbientOcclusion,i.uv).xxx;
	#endif
	return half4(Ao,1);
}
half4 Frag_MultiBounce(VertexOutput i):SV_Target{
	[branch]
    if(GetSkyBoxMask(i.uv)){return 1.0;}
	half3 BaseColor=SAMPLE_TEXTURE2D(_GBuffer0,sampler_GBuffer0,i.uv).xyz;
	half Ao=SAMPLE_TEXTURE2D(RT_MultiBounce_In,sampler_RT_MultiBounce_In,i.uv).x;
	return half4(AOMultiBounce(BaseColor,Ao),1);
}