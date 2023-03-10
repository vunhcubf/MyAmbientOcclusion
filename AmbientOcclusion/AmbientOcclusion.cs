using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using ProfilingScope = UnityEngine.Rendering.ProfilingScope;
using System;

public class AmbientOcclusion : ScriptableRendererFeature
{
    [System.Serializable]
    public class Setting
    {
        public string RenderPassName = "GTAO";
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public int passEventOffset = 1;
        [InspectorToggleLeft] public bool Debug = false;
        public bool FullPrecision = false;

        [Space(10)]
        [Header("AO????")]
        public AO_Methods AOMethod = AO_Methods.GTAO;
        [InspectorToggleLeft] public bool TemporalJitter = true;
        [Range(0f, 5f)] public float Intensity = 1;
        [Range(0f, 1f)] public float Radius = 0.5f;
        [Range(1, 10)] public int Num_Direction = 4;
        [Range(3, 50)] public int Num_Step = 8;
        [Range(0f, 0.6f)] public float AngleBias = 0.1f;
        [Range(0f, 1f)] public float AoDistanceAttenuation = 0.1f;
        [Range(1, 2000)] public int MaxDistance = 1000;
        [InspectorToggleLeft] public bool MultiBounce = true;

        [Space(10)]
        [Header("????????")]
        [InspectorToggleLeft] public bool SpatialFilter = true;
        [InspectorToggleLeft] public bool TemporalFilter = true;
        [Range(0f, 40f)] public float BlurSharpness = 1;
        [Range(2, 10)] public int Kernel_Radius = 5;
        [Range(0f, 1f)] public float TemporalFilterIntensity = 0.2f;
    }
    public enum AO_Methods
    {
        GTAO,
        HBAO_Plus
    };
    public Setting Settings = new Setting();

    class RenderPass : ScriptableRenderPass
    {
        private static readonly int P_World2View_Matrix_ID = Shader.PropertyToID("World2View_Matrix");
        private static readonly int P_View2World_Matrix_ID = Shader.PropertyToID("View2World_Matrix");
        private static readonly int P_InvProjection_Matrix_ID = Shader.PropertyToID("InvProjection_Matrix");
        private static readonly int P_fov_ID = Shader.PropertyToID("fov");

        private static readonly int P_RADIUS_ID = Shader.PropertyToID("RADIUS");
        private static readonly int P_DIRECTIONCOUNT_ID = Shader.PropertyToID("DIRECTIONCOUNT");
        private static readonly int P_STEPCOUNT_ID = Shader.PropertyToID("STEPCOUNT");
        private static readonly int P_MAXDISTANCE_ID = Shader.PropertyToID("MAXDISTANCE");
        private static readonly int P_AngleBias_ID = Shader.PropertyToID("AngleBias");
        private static readonly int P_AoDistanceAttenuation_ID = Shader.PropertyToID("AoDistanceAttenuation");
        private static readonly int P_Intensity_ID = Shader.PropertyToID("Intensity");

        private static readonly int P_BlurSharpness_ID = Shader.PropertyToID("BlurSharpness");
        private static readonly int P_KernelRadius_ID = Shader.PropertyToID("Kernel_Radius");
        private static readonly int P_TemporalFilterIntensity_ID = Shader.PropertyToID("TemporalFilterIntensity");

        private static readonly int RT_AoBase_ID = Shader.PropertyToID("_RT_AoBase");

        private static readonly int RT_AoBlur_Spatial_X_ID = Shader.PropertyToID("_RT_AoBlur_Spatial_X");
        private static readonly int RT_AoBlur_Spatial_Y_ID = Shader.PropertyToID("_RT_AoBlur_Spatial_Y");
        private static readonly int AO_Current_RT_ID = Shader.PropertyToID("_AO_Current_RT");
        private static readonly int RT_Temporal_In_ID = Shader.PropertyToID("RT_Temporal_In");
        private static readonly int AO_Previous_RT_ID = Shader.PropertyToID("_AO_Previous_RT");
        private static readonly int RT_Spatial_In_X_ID = Shader.PropertyToID("RT_Spatial_In_X");
        private static readonly int RT_Spatial_In_Y_ID = Shader.PropertyToID("RT_Spatial_In_Y");
        private static readonly int RT_MultiBounce_Out_ID = Shader.PropertyToID("RT_MultiBounce_Out");
        private static readonly int RT_MultiBounce_In_ID = Shader.PropertyToID("RT_MultiBounce_In");
        private static readonly int GLOBAL_RT_AmbientOcclusion_ID = Shader.PropertyToID("AmbientOcclusion");

        private RenderTexture AO_Previous_RT;
        public Material BlurMaterial;

        private Setting Settings;
        public RenderPass(Setting Settings)
        {
            this.Settings = Settings;
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //????ʹ??Normal
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal | ScriptableRenderPassInput.Motion);
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var camera = renderingData.cameraData.camera;
            //??ʷ??Ϣ
            if (AO_Previous_RT is null || AO_Previous_RT.IsDestroyed())
            {
                AO_Previous_RT = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 0, GraphicsFormat.R16_UNorm);
                AO_Previous_RT.Create();
            }
            if (camera.pixelWidth != AO_Previous_RT.width || camera.pixelHeight != AO_Previous_RT.height)
            {
                AO_Previous_RT.DiscardContents();
                AO_Previous_RT.Release();
                DestroyImmediate(AO_Previous_RT);
                AO_Previous_RT = null;

                AO_Previous_RT =new RenderTexture(camera.pixelWidth, camera.pixelHeight, 0, GraphicsFormat.R16_UNorm);
                AO_Previous_RT.Create();
            }
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            Camera camera = renderingData.cameraData.camera;
            RenderTextureDescriptor AoTextureDesc = new RenderTextureDescriptor(camera.pixelWidth, camera.pixelHeight, GraphicsFormat.R16_UNorm, GraphicsFormat.None);
            RenderTextureDescriptor AoTextureDesc_Color = new RenderTextureDescriptor(camera.pixelWidth, camera.pixelHeight, GraphicsFormat.B10G11R11_UFloatPack32, GraphicsFormat.None);
            AoTextureDesc.depthBufferBits = 0;
            AoTextureDesc_Color.depthBufferBits = 0;

            var AoMaterial = new Material(Shader.Find("PostProcess/AmbientOcclusion"));
            var BlurMaterial = new Material(Shader.Find("PostProcess/AmbientOcclusion"));
            AoMaterial.SetMatrix(P_World2View_Matrix_ID, camera.worldToCameraMatrix);
            AoMaterial.SetMatrix(P_View2World_Matrix_ID, camera.cameraToWorldMatrix);
            AoMaterial.SetMatrix(P_InvProjection_Matrix_ID, camera.projectionMatrix.inverse);

            AoMaterial.SetFloat(P_fov_ID, camera.fieldOfView);

            AoMaterial.SetFloat(P_RADIUS_ID, Settings.Radius);
            AoMaterial.SetInt(P_DIRECTIONCOUNT_ID, Settings.Num_Direction);
            AoMaterial.SetInt(P_STEPCOUNT_ID, Settings.Num_Step);
            AoMaterial.SetInt(P_MAXDISTANCE_ID, Settings.MaxDistance);

            AoMaterial.SetFloat(P_AngleBias_ID, Settings.AngleBias);
            AoMaterial.SetFloat(P_AoDistanceAttenuation_ID, Settings.AoDistanceAttenuation);
            AoMaterial.SetFloat(P_Intensity_ID, Settings.Intensity);

            BlurMaterial.SetFloat(P_BlurSharpness_ID, Settings.BlurSharpness);
            BlurMaterial.SetInt(P_KernelRadius_ID, Settings.Kernel_Radius);

            if (Settings.TemporalJitter) { AoMaterial.EnableKeyword("USE_TEMPORALNOISE"); }
            if (Settings.FullPrecision) { AoMaterial.EnableKeyword("FULL_PRECISION_AO"); BlurMaterial.EnableKeyword("FULL_PRECISION_AO"); }
            if (Settings.MultiBounce) { BlurMaterial.EnableKeyword("MULTI_BOUNCE_AO"); }

            CommandBuffer cmd = CommandBufferPool.Get(Settings.RenderPassName);
            using (new ProfilingScope(cmd, profilingSampler))
            {
                cmd.GetTemporaryRT(RT_AoBase_ID, AoTextureDesc, FilterMode.Point);
                cmd.GetTemporaryRT(RT_AoBlur_Spatial_X_ID, AoTextureDesc, FilterMode.Point);
                cmd.GetTemporaryRT(RT_AoBlur_Spatial_Y_ID, AoTextureDesc, FilterMode.Point);
                cmd.GetTemporaryRT(AO_Current_RT_ID, AoTextureDesc, FilterMode.Point);
                if (Settings.MultiBounce)
                {
                    cmd.GetTemporaryRT(RT_MultiBounce_Out_ID, AoTextureDesc_Color, FilterMode.Point);
                }
                else
                {
                    cmd.GetTemporaryRT(RT_MultiBounce_Out_ID, AoTextureDesc, FilterMode.Point);
                }
                

                //??ʼ??????
                cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
                //????AO
                cmd.SetRenderTarget(RT_AoBase_ID);
                if (Settings.AOMethod is AO_Methods.GTAO) { cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, AoMaterial, 0, 1); }
                else if (Settings.AOMethod is AO_Methods.HBAO_Plus) { cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, AoMaterial, 0, 0); }

                //ʱ???˲?
                if (Settings.TemporalFilter)
                {
                    cmd.SetGlobalTexture(RT_Temporal_In_ID, RT_AoBase_ID);
                    BlurMaterial.SetFloat(P_TemporalFilterIntensity_ID, Settings.TemporalFilterIntensity);
                    cmd.SetRenderTarget(AO_Current_RT_ID);
                    BlurMaterial.SetTexture(AO_Previous_RT_ID, AO_Previous_RT);
                    cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, BlurMaterial, 0, 4);
                    cmd.Blit(AO_Current_RT_ID, AO_Previous_RT);
                }
                else { cmd.CopyTexture(RT_AoBase_ID, AO_Current_RT_ID); }

                //˫???˲?
                if (Settings.SpatialFilter)
                {
                    cmd.SetGlobalTexture(RT_Spatial_In_X_ID, AO_Current_RT_ID);
                    cmd.SetRenderTarget(RT_AoBlur_Spatial_X_ID);
                    cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, BlurMaterial, 0, 2);

                    cmd.SetGlobalTexture(RT_Spatial_In_Y_ID, RT_AoBlur_Spatial_X_ID);
                    cmd.SetRenderTarget(RT_AoBlur_Spatial_Y_ID);
                    cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, BlurMaterial, 0, 3);
                }
                else { cmd.CopyTexture(AO_Current_RT_ID, RT_AoBlur_Spatial_Y_ID); }
                //MultiBounce
                if (Settings.MultiBounce)
                {
                    cmd.SetGlobalTexture(RT_MultiBounce_In_ID, RT_AoBlur_Spatial_Y_ID);
                    cmd.SetRenderTarget(RT_MultiBounce_Out_ID);
                    cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, BlurMaterial, 0, 6);
                }
                else { cmd.CopyTexture(RT_AoBlur_Spatial_Y_ID, RT_MultiBounce_Out_ID); }

                //????????Ļ
                cmd.SetGlobalTexture(GLOBAL_RT_AmbientOcclusion_ID, RT_MultiBounce_Out_ID);
                if (Settings.Debug)
                {
                    cmd.SetRenderTarget(renderingData.cameraData.renderer.cameraColorTarget);
                    cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, BlurMaterial, 0, 5);
                }
                //??????????
                cmd.SetRenderTarget(renderingData.cameraData.renderer.cameraColorTarget);
                cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix, camera.projectionMatrix);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
        public override void FrameCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(RT_AoBlur_Spatial_Y_ID);
            cmd.ReleaseTemporaryRT(RT_AoBlur_Spatial_X_ID);
            cmd.ReleaseTemporaryRT(RT_AoBase_ID);
            cmd.ReleaseTemporaryRT(AO_Current_RT_ID);
            cmd.ReleaseTemporaryRT(RT_MultiBounce_Out_ID);
        }
    }
    private RenderPass RenderPass_Instance;
    public override void Create()
    {
        RenderPass_Instance = new RenderPass(Settings);
        RenderPass_Instance.renderPassEvent = Settings.passEvent + Settings.passEventOffset;
    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(RenderPass_Instance);
    }
}