// Shared helpers for the texture-array environment shaders (Poly Haven CC0 sets packed by
// tools/carbake/envtex.mjs). Albedo arrays: RGB albedo, A height. Normal arrays: RG normal xy
// (OpenGL convention), B roughness, A ambient occlusion.

// Tangent-space normal xy (0..1) -> perturbation of world normal N with tangent T, bitangent B.
vec3 env_perturb(vec3 N, vec3 T, vec3 B, vec2 nxy, float strength) {
	vec2 d = (nxy * 2.0 - 1.0) * strength;
	return normalize(N + T * d.x + B * d.y);
}

// Height-weighted blend factor: higher texels of a layer win at transitions.
float env_hweight(float w, float h) {
	return w * pow(h + 0.15, 3.0);
}

// Cheap anti-tiling: the same layer sampled at a second rotated scale, mixed by a macro mask.
vec2 env_rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}
