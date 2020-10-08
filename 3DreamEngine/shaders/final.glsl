extern Image canvas_depth;

extern Image canvas_bloom;
extern Image canvas_ao;
extern Image canvas_SSR;

extern Image canvas_exposure;

extern vec3 viewPos;

extern float gamma;
extern float exposure;

#ifdef FOG_ENABLED
varying vec3 viewVec;
extern mat4 transformInverse;
extern float fog_density;
extern float fog_scatter;
extern vec3 fog_color;
extern vec3 fog_sun;
extern vec3 fog_sunColor;
extern float fog_max;
extern float fog_min;
#endif

#ifdef AUTOEXPOSURE_ENABLED
varying float eyeAdaption;
#endif

#ifdef FXAA_ENABLED
#define FXAA_REDUCE_MIN (1.0 / 128.0)
#define FXAA_REDUCE_MUL (1.0 / 8.0)
#define FXAA_SPAN_MAX (8.0)

//combined and modified code from https://github.com/mattdesl/glsl-fxaa
vec4 fxaa(Image tex, vec2 tc) {
	vec2 inverseVP = 1.0 / love_ScreenSize.xy;
	vec2 v_rgbNW = (tc + vec2(-1.0, -1.0) * inverseVP);
	vec2 v_rgbNE = (tc + vec2(1.0, -1.0) * inverseVP);
	vec2 v_rgbSW = (tc + vec2(-1.0, 1.0) * inverseVP);
	vec2 v_rgbSE = (tc + vec2(1.0, 1.0) * inverseVP);
	
	vec4 texColor = Texel(tex, tc);
	
	vec3 rgbNW = Texel(tex, v_rgbNW).xyz;
	vec3 rgbNE = Texel(tex, v_rgbNE).xyz;
	vec3 rgbSW = Texel(tex, v_rgbSW).xyz;
	vec3 rgbSE = Texel(tex, v_rgbSE).xyz;
	vec3 rgbM = texColor.xyz;
	
	vec3 luma = vec3(0.299, 0.587, 0.114);
	float lumaNW = dot(rgbNW, luma);
	float lumaNE = dot(rgbNE, luma);
	float lumaSW = dot(rgbSW, luma);
	float lumaSE = dot(rgbSE, luma);
	float lumaM  = dot(rgbM,  luma);
	
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
	
	mediump vec2 dir;
	dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
	dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
	
	float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
	
	float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = min(vec2(FXAA_SPAN_MAX, FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * inverseVP;
	
	vec3 rgbA = 0.5 * (
		Texel(tex, tc + dir * (1.0 / 3.0 - 0.5)).xyz +
		Texel(tex, tc + dir * (2.0 / 3.0 - 0.5)).xyz);
	
	vec3 rgbB = rgbA * 0.5 + 0.25 * (
		Texel(tex, tc + dir * -0.5).xyz +
		Texel(tex, tc + dir * 0.5).xyz);
	
	float lumaB = dot(rgbB, luma);
	if ((lumaB < lumaMin) || (lumaB > lumaMax)) {
		return vec4(rgbA, texColor.a);
	} else {
		return vec4(rgbB, texColor.a);
	}
}
#endif



#ifdef PIXEL
vec4 effect(vec4 color, Image canvas_color, vec2 tc, vec2 sc) {
	vec2 tc_final = tc;
	
	//color
#ifdef FXAA_ENABLED
	vec4 c = fxaa(canvas_color, tc_final);
#else
	vec4 c = Texel(canvas_color, tc_final);
#endif
	
	//ao
#ifdef AO_ENABLED
	float ao = Texel(canvas_ao, tc_final).r;
	c.rgb *= ao;
#endif
	
	//bloom
#ifdef BLOOM_ENABLED
	vec3 bloom = Texel(canvas_bloom, tc_final).rgb;
	c.rgb += bloom;
#endif
	
	//screen space reflections merge
#ifdef SSR_ENABLED
	vec3 ref = Texel(canvas_SSR, tc_final).rgb;
	c.rgb += ref;
#endif

	//fog
#ifdef FOG_ENABLED
	float depth = Texel(canvas_depth, tc_final).r;
	
	if (fog_max > fog_min) {
		vec3 vec = viewVec * depth;
		vec3 stepVec = vec / vec.y;
		
		//ray
		vec3 pos_near = viewPos;
		vec3 pos_far = viewPos + vec;
		
		//find entry/exit heights
		float height_near = clamp(pos_near.y, fog_min, fog_max);
		float height_far = clamp(pos_far.y, fog_min, fog_max);
		
		//find points
		pos_near += stepVec * (height_near - pos_near.y);
		pos_far += stepVec * (height_far - pos_far.y);
		
		//get average density
		float heightDiff = fog_max - fog_min;
		float nearDensity = 1.0 - (height_near - fog_min) / heightDiff;
		float farDensity = 1.0 - (height_far - fog_min) / heightDiff;
		depth = distance(pos_far, pos_near) * (farDensity + nearDensity) * 0.5;
	}
	
	//finish fog
	float fog = 1.0 - exp(-depth * fog_density);
	if (fog_scatter > 0.0) {
		float fog_sunStrength = max(dot(fog_sun, normalize(viewVec)), 0.0);
		vec3 fogColor = fog_color + fog_sunColor * pow(fog_sunStrength, 8.0) * fog_scatter;
		c.rgb = mix(c.rgb, fogColor, fog);
	} else {
		c.rgb = mix(c.rgb, fog_color, fog);
	}
#endif
	
	//additional post effects
#ifdef POSTEFFECTS_ENABLED
	
	//eye adaption
#ifdef AUTOEXPOSURE_ENABLED
	c.rgb *= eyeAdaption;
#endif
	
	//exposure
#ifdef EXPOSURE_ENABLED
	c.rgb = vec3(1.0) - exp(-c.rgb * exposure);
#endif
	
	//gamma correction
	c.rgb = pow(c.rgb, vec3(1.0 / gamma));
#endif
	
	return vec4(c.rgb, c.a);
}
#endif

#ifdef VERTEX
	vec4 position(mat4 transform_projection, vec4 vertex_position) {
#ifdef AUTOEXPOSURE_ENABLED
		eyeAdaption = Texel(canvas_exposure, vec2(0.5, 0.5)).r;
#endif
		vec4 pos = transform_projection * vertex_position;
#ifdef FOG_ENABLED
		viewVec = (transformInverse * vec4(pos.x, - pos.y, 1.0, 1.0)).xyz;
#endif
		return pos;
	}
#endif