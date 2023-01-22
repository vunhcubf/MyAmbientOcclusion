#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"

#define NOISEINPUTSCALE 1000.0f
#define RADIUSSCALE_GTAO 500.0f
#define RADIUSSCALE_HBAO 100.0f

int MAXDISTANCE;
float RADIUS;//RADIUS_PIXEL
int STEPCOUNT;
int DIRECTIONCOUNT;
float AngleBias;
float AoDistanceAttenuation;
float Intensity;

////参数
float4x4 World2View_Matrix;
float4x4 View2World_Matrix;
float4x4 InvProjection_Matrix;
float fov;
//纹素大小
float4 _CameraDepthTexture_TexelSize;

////函数
float Pow2(float x){
    return x*x;
}
float Noise2D(float2 p)
{
    p*=NOISEINPUTSCALE;
    #if defined USE_TEMPORALNOISE
    p*=1+_SinTime.y*0.5;
    #endif
    float3 p3  = frac(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}
float GetZBufferDepth(float2 uv){
    return SampleSceneDepth(uv);
}
float GetEyeDepth(float2 uv){
    return LinearEyeDepth(SampleSceneDepth(uv),_ZBufferParams);
}
float3 GetPositionVs(float NDCDepth,float2 uv){//不支持reversed-z
    float3 Vec;
    float tangent=tan(fov*3.1415926/360.0);
    Vec.xy=uv*2-1;
    Vec.xy*=float2(_ScreenParams.x/_ScreenParams.y,1);
    Vec.z=-1/tangent;
    return Vec*LinearEyeDepth(NDCDepth,_ZBufferParams)*tangent;
}
float3 GetPositionVs(float2 uv,float EyeDepth){//不支持reversed-z
    float3 Vec;
    float tangent=tan(fov*3.1415926/360.0);
    Vec.xy=uv*2-1;
    Vec.xy*=float2(_ScreenParams.x/_ScreenParams.y,1);
    Vec.z=-1/tangent;
    return Vec*EyeDepth*tangent;
}
float3 GetPositionVs(float2 uv){
    // float4 WorldPos= mul(View2World_Matrix,float4(GetPositionVs(GetZBufferDepth(uv),uv),1));
    // return WorldPos.xyz/WorldPos.w;
    return GetPositionVs(GetZBufferDepth(uv),uv);
}
float3 GetNormal(float2 uv){
    float3 Norm=SampleSceneNormals(uv);
    Norm=mul((float3x3)World2View_Matrix,Norm);
    return normalize(Norm);
}
//左下角原点的屏幕uv
float2 GetScreenUv(float3 ViewPos){
    float2 Vec;
    float Aspect=_ScreenParams.x/_ScreenParams.y;
    float cot=1/tan(fov*3.1415926/360.0);
    Vec.x=ViewPos.x*cot/Aspect;
    Vec.y=ViewPos.y*cot;
    return (Vec.xy/ViewPos.z)*0.5+0.5;
}
float2 RotateDirection(float2 Vec,float x){
    return float2(Vec.x*cos(x)-Vec.y*sin(x),Vec.x*sin(x)+Vec.y*cos(x));
}
float FallOff(float Distance){
    return saturate(1-Distance*AoDistanceAttenuation*20.0);
}  
float2 FallOff(float2 Distance){
    return float2(FallOff(Distance.x),FallOff(Distance.y));
}        
float Noise2D(float2 value,float a ,float2 b)//1000,1000可以得到良好的噪声
{		
    #if defined USE_TEMPORALNOISE
    a*=1+_SinTime.y*0.1;
    #endif
    //avaoid artifacts
    float2 smallValue = sin(value);
    //get scalar value from 2d vector	
    float  random = dot(smallValue,b);
    random = frac(sin(random) * a);
    return random;
}
float GetUniformRadiusScale(float2 uv){
    return 1/length(GetPositionVs(uv));
}
//正确的世界坐标
// float3 BuildViewPos(float2 uv){
//     float3 Vec;
//     Vec.xy=uv*2-1;
//     Vec.xy*=float2(_ScreenParams.x/_ScreenParams.y,1)*tan(fov*3.1415926/360);
//     Vec.z=-1;
//     return Vec*LinearEyeDepth(GetZBufferDepth(uv),_ZBufferParams);
// }

struct VertexInput{
    float4 positionOS:POSITION;
    float2 uv:TEXCOORD0;
};

struct VertexOutput{
    float4 position:SV_POSITION;
    float2 uv:TEXCOORD0;
};

float ComputeHBAO(float3 P,float3 N,float3 S){
    float3 V=S-P;
    float VdotV=dot(V,V);
    float NdotV=dot(N,V)*rsqrt(VdotV);
    return saturate(NdotV-AngleBias)*FallOff(VdotV);//使用距离衰减
}
float ComputeGTAO(float h1,float h2,float n){
    return 0.25*(-cos(2*h2-n)+cos(n)+2*h2*sin(n))+0.25*(-cos(2*h1-n)+cos(n)+2*h1*sin(n));
}
void AccumulateHBAO(inout float Ao,
inout float RayPixels,
float StepSizePixels,
float2 Direction,
float2 FullResUv,
float3 PositionVs,
float3 NormalVs){
    float2 SnappedUv=round(RayPixels*Direction)*_CameraDepthTexture_TexelSize.xy+FullResUv;
    float3 S=GetPositionVs(SnappedUv);
    RayPixels+=StepSizePixels;
    Ao+=ComputeHBAO(PositionVs,NormalVs,S);
}
float GetHBAO(float2 FullResUv,float3 PositionVs,float3 NormalVs){
    float4 Rand=float4(1,0,1,1);
    Rand.xy=RotateDirection(Rand.xy,Noise2D(FullResUv));
    Rand.w=Noise2D(FullResUv);
    float StepSizePixels = max(1.0,lerp(0.8,1.2,Noise2D(FullResUv))*GetUniformRadiusScale(FullResUv)*RADIUSSCALE_HBAO*RADIUS / (STEPCOUNT + 1.0));
    float AngDelta=2.0*PI/DIRECTIONCOUNT;
    float Ao=0;
    UNITY_LOOP
    for(int i=0;i<DIRECTIONCOUNT;i++){
        float Angle=i*AngDelta;
        float2 Direction=RotateDirection(Rand.xy,Angle);
        float RayPixels=(Rand.z*StepSizePixels+1.0);//引入随机
        UNITY_LOOP
        for(int j=0;j<STEPCOUNT;j++){
            AccumulateHBAO(Ao,RayPixels,StepSizePixels,Direction,FullResUv,PositionVs,NormalVs);
        }
    }
    Ao/=STEPCOUNT*DIRECTIONCOUNT;
    return Ao;
}
float GetGTAO(float2 uv,float3 PositionVs,float3 NormalVs){
    float3 ViewDir=normalize(0-PositionVs);
    float AngleOffset=2*PI*Noise2D(uv);
    float AO,Angle,BentAngle,SliceLength,n,cos_n;
    float2 h,H,falloff,h1h2,h1h2Length,uvoffset;
    float3 SliceDir,h1,h2,PlaneNormal,PlaneTangent,SliceNormal,BentNormal;
    float4 uvSlice;
    BentNormal=0;
    AO=0;
    UNITY_LOOP
    for(int i=0;i<DIRECTIONCOUNT;i++){
        Angle=PI*i/DIRECTIONCOUNT+AngleOffset;
        SliceDir=float3(cos(Angle),sin(Angle),0);

        PlaneNormal=normalize(cross(SliceDir,ViewDir));
        PlaneTangent=cross(ViewDir,PlaneNormal);
        SliceNormal=NormalVs-PlaneNormal*dot(NormalVs,PlaneNormal);
        SliceLength=length(SliceNormal);

        cos_n=clamp(dot(normalize(SliceNormal),ViewDir),-1,1);
        n=-sign(dot(SliceNormal,PlaneTangent))*acos(cos_n);
        h=-1;

        float StepSize=max(1.0,lerp(0.9,1.1,Noise2D(uv))*GetUniformRadiusScale(uv)*RADIUSSCALE_GTAO*RADIUS / (STEPCOUNT + 1.0));
        UNITY_LOOP
        for(int j=0;j<STEPCOUNT;j++){
            uvoffset=SliceDir.xy*(1+j)*StepSize;
            uvoffset=round(uvoffset)*_CameraDepthTexture_TexelSize.xy;
            uvSlice=uv.xyxy+float4(uvoffset,-uvoffset);

            h1=GetPositionVs(uvSlice.xy)-PositionVs;
            h2=GetPositionVs(uvSlice.zw)-PositionVs;

            h1h2=float2(dot(h1,h1),dot(h2,h2));
            h1h2Length=rsqrt(h1h2);
            falloff=saturate(h1h2*(2/((Pow2(1.1-AoDistanceAttenuation)))));

            H=float2(dot(h1,ViewDir),dot(h2,ViewDir))*h1h2Length;
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
    //return float4(BentNormal,AO);
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

float4 Frag_HBAO(VertexOutput i):SV_Target{
    //正确的世界坐标return mul(View2World_Matrix,float4(BuildViewPos(i.uv),1));
    float3 PositionVs = GetPositionVs(i.uv);
    //return float4(GetScreenUv(PositionVS),0,1);
    if (-PositionVs.z > MAXDISTANCE)
    {
        return 1;
    }
    float3 Norm=GetNormal(i.uv);
    float Ao=GetHBAO(i.uv,PositionVs,Norm);
    Ao=saturate(1.0-2.0*Ao);
    Ao=pow(Ao,Intensity);
    return float4(Ao,Ao,Ao,1);
}

float4 Frag_GTAO(VertexOutput i):SV_Target{
    float3 PositionVs = GetPositionVs(i.uv);
    if (-PositionVs.z > MAXDISTANCE)
    {
        return 1;
    }
    float3 Norm=GetNormal(i.uv);
    float AO=GetGTAO(i.uv,PositionVs,Norm);
    AO=pow(AO,Intensity);
    return float4(AO,AO,AO,1);
}