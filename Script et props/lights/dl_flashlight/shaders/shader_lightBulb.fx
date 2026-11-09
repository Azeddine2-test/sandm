//------------------------------------------------------------------------------------------
// Settings
//------------------------------------------------------------------------------------------
texture colorRT < string renderTarget = "yes"; >;
texture normalRT < string renderTarget = "yes"; >;

bool isFLon = true;
float4 gLightColor = float4(1,1,0.8,0.8);

texture gTexture0 < string textureState="0,Texture"; >;
sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

//------------------------------------------------------------------------------------------
// Structure of color data sent to the renderer ( from the pixel shader  )
//------------------------------------------------------------------------------------------
struct Pixel
{
    float4 World : COLOR0;      // Render target #0
    float4 Color : COLOR1;      // Render target #1
    float4 Normal : COLOR2;      // Render target #2
};

Pixel PixelShaderPS(float4 TexCoord : TEXCOORD0, float4 Position : POSITION, float4 Diffuse:COLOR0) : COLOR0
{
    Pixel output;
	
	float4 Tex = tex2D(Sampler0, TexCoord);
	if (isFLon==true) 	{ output.World = float4(Tex.rgb,1)*float4(gLightColor.rgb,1); }
						else
						{ output.World = float4(Tex.rgb,1)*Diffuse;}

    output.Color = float4(Tex.rgb,1)*Diffuse;
    output.Normal = float4(0,0,0,1);
    return output;
}

technique shader_lightBulb
{
    pass P0
    {
		PixelShader = compile ps_2_0 PixelShaderPS();
    }
}

technique fallback
{
    pass P0
    {
    }
}

