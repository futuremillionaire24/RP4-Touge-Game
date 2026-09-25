// Photographic sky: two day-cycle keyframes (Poly Haven CC0 HDRIs baked by tools/carbake/
// skybake.mjs to upper-hemisphere panoramas) blended by time of day, each rotated so its sun
// glow sits at the game sun's azimuth. Weather skies (partly cloudy / overcast) contribute only
// their cloud detail, normalised by their own low frequencies and re-lit by the day-cycle
// colours, so sunset clouds glow orange. The sun (or moon) disc is drawn at the real light.
shader_type sky;

uniform sampler2D sky_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_b : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_p : source_color, filter_linear_mipmap, repeat_enable; // partly cloudy
uniform sampler2D sky_o : source_color, filter_linear_mipmap, repeat_enable; // overcast
uniform float blend = 0.0;
uniform vec4 rot = vec4(0.0); // u offsets: a, b, partly, overcast
uniform vec2 energy = vec2(1.0);
uniform vec2 weather = vec2(0.0); // partly cloudy amount, overcast amount
uniform float flash = 0.0;

vec3 pano(sampler2D t, vec3 d, float r, float lod) {
	float az = atan(d.x, -d.z); // 0 = north (-Z), +90 deg = east (+X)
	float u = fract(az / TAU + 0.5 + r);
	float el = asin(clamp(d.y, 0.0, 1.0));
	return textureLod(t, vec2(u, 1.0 - el / (PI * 0.5)), lod).rgb;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void sky() {
	vec3 d = EYEDIR;
	// Explicit LOD: the azimuth wrap would otherwise spike the mip level along a seam; the
	// radiance cubemap is tiny, so it reads blurred levels.
	float lod = AT_CUBEMAP_PASS ? 3.0 : 0.0;
	vec3 dd = normalize(vec3(d.x, max(d.y, 0.002), d.z)); // below the horizon: horizon row
	vec3 day = mix(pano(sky_a, dd, rot.x, lod) * energy.x, pano(sky_b, dd, rot.y, lod) * energy.y, blend);
	vec3 day_lf = mix(pano(sky_a, dd, rot.x, 7.0) * energy.x, pano(sky_b, dd, rot.y, 7.0) * energy.y, blend);
	if (weather.x > 0.001) {
		vec3 p = pano(sky_p, dd, rot.z, lod);
		vec3 p_lf = pano(sky_p, dd, rot.z, 7.0);
		// Clouds brighter than their surroundings stay bright, re-tinted by the day palette.
		vec3 detail = p / max(p_lf, vec3(0.03));
		day = mix(day, day_lf * mix(detail, vec3(luma(detail)), 0.6), weather.x);
	}
	if (weather.y > 0.001) {
		vec3 o = pano(sky_o, dd, rot.w, lod);
		float o_lf = luma(pano(sky_o, dd, rot.w, 7.0));
		vec3 tint = day_lf / max(luma(day_lf), 1e-4);
		vec3 grey = vec3(luma(o) / max(o_lf, 0.03)) * luma(day_lf) * 0.8 * mix(vec3(1.0), tint, 0.25);
		day = mix(day, grey, weather.y);
	}
	vec3 col = day;
	// Sun / moon: HDR disc + tight aureole + broad glow (blooms through the glow pass).
	if (LIGHT0_ENABLED) {
		float cs = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(cos(radians(0.62)), cos(radians(0.5)), cs);
		float glow = pow(max(cs, 0.0), 1400.0) * 2.5 + pow(max(cs, 0.0), 90.0) * 0.18;
		float vis = (1.0 - weather.y * 0.97) * smoothstep(-0.02, 0.01, d.y);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * 30.0 + glow) * vis;
	}
	// Below the horizon (only seen over the sea's edge / in reflections): darker haze.
	col = mix(col, day * 0.6, smoothstep(0.0, -0.3, d.y));
	col += vec3(0.8, 0.85, 1.0) * flash * 2.0;
	COLOR = col;
}
