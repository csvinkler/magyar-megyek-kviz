Shader "Megyejaror/VoxelColor"
{
    Properties
    {
        _Color ("Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "Queue" = "Geometry" "RenderType" = "Opaque" }
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4 _Color;

            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct VertexOutput
            {
                float4 vertex : SV_POSITION;
                fixed3 lighting : TEXCOORD0;
            };

            VertexOutput vert(VertexInput input)
            {
                VertexOutput output;
                output.vertex = UnityObjectToClipPos(input.vertex);
                float3 normal = UnityObjectToWorldNormal(input.normal);
                float3 diffuse = _LightColor0.rgb
                    * saturate(dot(normal, normalize(_WorldSpaceLightPos0.xyz)));
                output.lighting = saturate(ShadeSH9(float4(normal, 1.0)) + diffuse);
                return output;
            }

            fixed4 frag(VertexOutput input) : SV_Target
            {
                return fixed4(_Color.rgb * input.lighting, _Color.a);
            }
            ENDCG
        }
    }
}
