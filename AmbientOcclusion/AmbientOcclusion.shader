Shader "PostProcess/AmbientOcclusion"
{
    SubShader
    {
        Pass
        {
        Name "HBAO"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBase.hlsl"
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_HBAO
            #pragma shader_feature FULL_PRECISION_AO
            #pragma shader_feature USE_TEMPORALNOISE
            #pragma shader_feature _GBUFFER_NORMALS_OCT
            ENDHLSL
        }
        Pass
        {
        Name "GTAO"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBase.hlsl"
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_GTAO
            #pragma shader_feature FULL_PRECISION_AO
            #pragma shader_feature USE_TEMPORALNOISE
            #pragma shader_feature _GBUFFER_NORMALS_OCT
            ENDHLSL
        }
        Pass
        {
        Name "BilateralFilter_X"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBlur.hlsl"
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_Bilateral_X
            #pragma shader_feature FULL_PRECISION_AO
            ENDHLSL
        }
        Pass
        {
        Name "BilateralFilter_Y"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBlur.hlsl"
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_Bilateral_Y
            #pragma shader_feature FULL_PRECISION_AO
            ENDHLSL
        }
        Pass
        {
        Name "TemporalFilter"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBlur.hlsl"
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_TemporalFilter
            #pragma shader_feature FULL_PRECISION_AO
            ENDHLSL
        }
        Pass
        {
        Name "BlendtoScreen"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBlur.hlsl"
            #pragma shader_feature DEBUG_AO_ONLY
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_BlendToScreen
            #pragma shader_feature FULL_PRECISION_AO
            ENDHLSL
        }
        Pass
        {
        Name "CopyDepth"
        ZWrite Off
        ZTest Always
        CUll off
        Tags{"LightMode"="PostProcess"}
            HLSLPROGRAM
            #include "AoBlur.hlsl"
            #pragma shader_feature DEBUG_AO_ONLY
            #pragma vertex Vert_PostProcessDefault
            #pragma fragment Frag_CopyDepth
            #pragma shader_feature FULL_PRECISION_AO
            ENDHLSL
        }
    }
}