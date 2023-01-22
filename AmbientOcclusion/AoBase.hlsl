#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"

#if defined FULL_PRECISION_AO
#define half float
#define half2 float2
#define half3 float3
#define half4 float4
#define half4x4 float4x4
#define half3x3 float3x3
#endif

#define SKYBOX_MASK step(GetEyeDepth(uv),9986)
#define NOISEINPUTSCALE 1000.0f
#define RADIUSSCALE_GTAO 500.0f
#define RADIUSSCALE_HBAO 100.0f

int MAXDISTANCE;
half RADIUS;//RADIUS_PIXEL
int STEPCOUNT;
int DIRECTIONCOUNT;
half AngleBias;
half AoDistanceAttenuation;
half Intensity;

////参数
half4x4 World2View_Matrix;
half4x4 View2World_Matrix;
half4x4 InvProjection_Matrix;
half fov;
//纹素大小
half4 _CameraDepthTexture_TexelSize;

////函数
half Pow2(half x){
    return x*x;
}
half Noise2D(half2 p)
{
    p*=NOISEINPUTSCALE;
    #if defined USE_TEMPORALNOISE
    p*=1+_SinTime.y*0.5;
    #endif
    half3 p3  = frac(half3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}
half GetEyeDepth(half2 uv){
    return LinearEyeDepth(SampleSceneDepth(uv),_ZBufferParams);
}
half3 GetPositionVs(half NDCDepth,half2 uv){//不支持reversed-z
    half3 Vec;
    half tangent=tan(fov*3.1415926/360.0);
    Vec.xy=uv*2-1;
    Vec.xy*=half2(_ScreenParams.x/_ScreenParams.y,1);
    Vec.z=-1/tangent;
    return Vec*LinearEyeDepth(NDCDepth,_ZBufferParams)*tangent;
}
half3 GetPositionVs(half2 uv,half EyeDepth){//不支持reversed-z
    half3 Vec;
    half tangent=tan(fov*3.1415926/360.0);
    Vec.xy=uv*2-1;
    Vec.xy*=half2(_ScreenParams.x/_ScreenParams.y,1);
    Vec.z=-1/tangent;
    return Vec*EyeDepth*tangent;
}
half3 GetPositionVs(half2 uv){
    // half4 WorldPos= mul(View2World_Matrix,half4(GetPositionVs(SampleSceneDepth(uv),uv),1));
    // return WorldPos.xyz/WorldPos.w;
    return GetPositionVs(SampleSceneDepth(uv),uv);
}
half3 GetNormalVs(half2 uv){
    half3 Norm=SampleSceneNormals(uv);
    Norm=mul((half3x3)World2View_Matrix,Norm);
    return normalize(Norm)*SKYBOX_MASK;
}
//左下角原点的屏幕uv
half2 GetScreenUv(half3 ViewPos){
    half2 Vec;
    half Aspect=_ScreenParams.x/_ScreenParams.y;
    half cot=1/tan(fov*3.1415926/360.0);
    Vec.x=ViewPos.x*cot/Aspect;
    Vec.y=ViewPos.y*cot;
    return (Vec.xy/ViewPos.z)*0.5+0.5;
}
half2 RotateDirection(half2 Vec,half x){
    return half2(Vec.x*cos(x)-Vec.y*sin(x),Vec.x*sin(x)+Vec.y*cos(x));
}
half FallOff(half Distance){
    return saturate(1-Distance*AoDistanceAttenuation*20.0);
}  
half2 FallOff(half2 Distance){
    return half2(FallOff(Distance.x),FallOff(Distance.y));
}        
half Noise2D(half2 value,half a ,half2 b)//1000,1000可以得到良好的噪声
{		
    #if defined USE_TEMPORALNOISE
    a*=1+_SinTime.y*0.1;
    #endif
    //avaoid artifacts
    half2 smallValue = sin(value);
    //get scalar value from 2d vector	
    half  random = dot(smallValue,b);
    random = frac(sin(random) * a);
    return random;
}
half GetUniformRadiusScale(half2 uv){
    return 1/length(GetPositionVs(uv));
}
//正确的世界坐标
// half3 BuildViewPos(half2 uv){
//     half3 Vec;
//     Vec.xy=uv*2-1;
//     Vec.xy*=half2(_ScreenParams.x/_ScreenParams.y,1)*tan(fov*3.1415926/360);
//     Vec.z=-1;
//     return Vec*LinearEyeDepth(SampleSceneDepth(uv),_ZBufferParams);
// }

struct VertexInput{
    half4 positionOS:POSITION;
    half2 uv:TEXCOORD0;
};

struct VertexOutput{
    half4 position:SV_POSITION;
    half2 uv:TEXCOORD0;
};

half ComputeHBAO(half3 P,half3 N,half3 S){
    half3 V=S-P;
    half VdotV=dot(V,V);
    half NdotV=dot(N,V)*rsqrt(VdotV);
    return saturate(NdotV-AngleBias)*FallOff(VdotV);//使用距离衰减
}
half ComputeGTAO(half h1,half h2,half n){
    return 0.25*(-cos(2*h2-n)+cos(n)+2*h2*sin(n))+0.25*(-cos(2*h1-n)+cos(n)+2*h1*sin(n));
}
void AccumulateHBAO(inout half Ao,
inout half RayPixels,
half StepSizePixels,
half2 Direction,
half2 FullResUv,
half3 PositionVs,
half3 NormalVs){
    half2 SnappedUv=round(RayPixels*Direction)*_CameraDepthTexture_TexelSize.xy+FullResUv;
    half3 S=GetPositionVs(SnappedUv);
    RayPixels+=StepSizePixels;
    Ao+=ComputeHBAO(PositionVs,NormalVs,S);
}
half GetHBAO(half2 FullResUv,half3 PositionVs,half3 NormalVs){
    half4 Rand=half4(1,0,1,1);
    Rand.xy=RotateDirection(Rand.xy,Noise2D(FullResUv));
    Rand.w=Noise2D(FullResUv);
    half StepSizePixels = max(1.0,lerp(0.8,1.2,Noise2D(FullResUv))*GetUniformRadiusScale(FullResUv)*RADIUSSCALE_HBAO*RADIUS / (STEPCOUNT + 1.0));
    half AngDelta=2.0*PI/DIRECTIONCOUNT;
    half Ao=0;
    UNITY_LOOP
    for(int i=0;i<DIRECTIONCOUNT;i++){
        half Angle=i*AngDelta;
        half2 Direction=RotateDirection(Rand.xy,Angle);
        half RayPixels=(Rand.z*StepSizePixels+1.0);//引入随机
        UNITY_LOOP
        for(int j=0;j<STEPCOUNT;j++){
            AccumulateHBAO(Ao,RayPixels,StepSizePixels,Direction,FullResUv,PositionVs,NormalVs);
        }
    }
    Ao/=STEPCOUNT*DIRECTIONCOUNT;
    return Ao;
}
half GetGTAO(half2 uv,half3 PositionVs,half3 NormalVs){
    half3 ViewDir=normalize(0-PositionVs);
    half AngleOffset=2*PI*Noise2D(uv);
    half AO,Angle,BentAngle,SliceLength,n,cos_n;
    half2 h,H,falloff,h1h2,h1h2Length,uvoffset;
    half3 SliceDir,h1,h2,PlaneNormal,PlaneTangent,SliceNormal,BentNormal;
    half4 uvSlice;
    BentNormal=0;
    AO=0;
    UNITY_LOOP
    for(int i=0;i<DIRECTIONCOUNT;i++){
        Angle=PI*i/DIRECTIONCOUNT+AngleOffset;
        SliceDir=half3(cos(Angle),sin(Angle),0);

        PlaneNormal=normalize(cross(SliceDir,ViewDir));
        PlaneTangent=cross(ViewDir,PlaneNormal);
        SliceNormal=NormalVs-PlaneNormal*dot(NormalVs,PlaneNormal);
        SliceLength=length(SliceNormal);

        cos_n=clamp(dot(normalize(SliceNormal),ViewDir),-1,1);
        n=-sign(dot(SliceNormal,PlaneTangent))*acos(cos_n);
        h=-1;

        half StepSize=max(1.0,lerp(0.9,1.1,Noise2D(uv))*GetUniformRadiusScale(uv)*RADIUSSCALE_GTAO*RADIUS / (STEPCOUNT + 1.0));
        UNITY_LOOP
        for(int j=0;j<STEPCOUNT;j++){
            uvoffset=SliceDir.xy*(1+j)*StepSize;
            uvoffset=round(uvoffset)*_CameraDepthTexture_TexelSize.xy;
            uvSlice=uv.xyxy+half4(uvoffset,-uvoffset);

            h1=GetPositionVs(uvSlice.xy)-PositionVs;
            h2=GetPositionVs(uvSlice.zw)-PositionVs;

            h1h2=half2(dot(h1,h1),dot(h2,h2));
            h1h2Length=rsqrt(h1h2);
            falloff=saturate(h1h2*(2/((Pow2(1.1-AoDistanceAttenuation)))));

            H=half2(dot(h1,ViewDir),dot(h2,ViewDir))*h1h2Length;
            h.xy=(H.xy>h.xy)?lerp(H,h,falloff):h;
        }
        h=acos(clamp(h,-1,1));
        h.x=n+max(-h.x-n,-PI/2);
        h.y=n+min(h.y-n,PI/2);

        BentAngle=(h.x+h.y)*0.5;
        BentNormal+=ViewDir*cos(BentAngle)-PlaneTangent*sin(BentAngle);
        AO+=SliceLength*ComputeGTAO(h.x,h.y,n);
    }
    BentNormal=normalize(normalize(BentNormal)-ViewDir*0.5);
    AO=saturate(AO/DIRECTIONCOUNT);
    //return half4(BentNormal,AO);
    return AO;
}
VertexOutput Vert_PostProcessDefault(VertexInput v)
{
    VertexOutput o;
    VertexPositionInputs positionInputs = GetVertexPositionInputs(v.positionOS.xyz);
    o.position = positionInputs.positionCS;
    o.uv = v.uv;
    return o;
}

half4 Frag_HBAO(VertexOutput i):SV_Target{
    //正确的世界坐标return mul(View2World_Matrix,half4(BuildViewPos(i.uv),1));
    half3 PositionVs = GetPositionVs(i.uv);
    //return half4(GetScreenUv(PositionVS),0,1);
    if (-PositionVs.z > MAXDISTANCE)
    {
        return 1;
    }
    half3 Norm=GetNormalVs(i.uv);
    half Ao=GetHBAO(i.uv,PositionVs,Norm);
    Ao=saturate(1.0-2.0*Ao);
    Ao=pow(Ao,Intensity);
    return half4(Ao,Ao,Ao,1);
}

half4 Frag_GTAO(VertexOutput i):SV_Target{
    half3 PositionVs = GetPositionVs(i.uv);
    if (-PositionVs.z > MAXDISTANCE)
    {
        return 1;
    }
    half3 Norm=GetNormalVs(i.uv);
    half AO=GetGTAO(i.uv,PositionVs,Norm);
    AO=pow(AO,Intensity);
    return half4(AO,AO,AO,1);
}