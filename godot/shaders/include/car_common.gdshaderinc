// Shared helpers for the car material library (materials agent). Mobile-friendly: ALU only,
// no texture samples, no loops. Space conventions: "local" = car/model space in metres.
#ifndef CAR_COMMON_INC
#define CAR_COMMON_INC

vec3 car_hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float car_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float car_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth 2D value noise (cheap, 4 hashes).
float car_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = car_hash12(i);
	float b = car_hash12(i + vec2(1.0, 0.0));
	float c = car_hash12(i + vec2(0.0, 1.0));
	float d = car_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Pixel footprint (metres) of a local-space position.
float car_footprint(vec3 p) {
	return max(length(dFdx(p)), length(dFdy(p)));
}

// Specular anti-aliasing (Kaplanyan/Tokuyoshi, as in Filament): widen roughness where the
// normal changes quickly across a pixel so highlights never sparkle-alias.
float car_spec_aa(vec3 n, float rough) {
	vec3 dx = dFdx(n);
	vec3 dy = dFdy(n);
	float variance = 0.25 * (dot(dx, dx) + dot(dy, dy));
	float k = min(2.0 * variance, 0.18);
	return sqrt(clamp(rough * rough + k, 0.0, 1.0));
}

float car_schlick(float f0, float c) {
	float f = 1.0 - c;
	float f2 = f * f;
	return f0 + (1.0 - f0) * f2 * f2 * f;
}

vec3 car_schlick3(vec3 f0, float c) {
	float f = 1.0 - c;
	float f2 = f * f;
	return f0 + (1.0 - f0) * (f2 * f2 * f);
}

float car_d_ggx(float ndh, float a) {
	float a2 = a * a;
	float f = (ndh * a2 - ndh) * ndh + 1.0;
	return a2 / (PI * f * f + 1e-7);
}

float car_v_smith(float ndv, float ndl, float a) {
	float a2 = a * a;
	float gv = ndl * sqrt(ndv * ndv * (1.0 - a2) + a2);
	float gl = ndv * sqrt(ndl * ndl * (1.0 - a2) + a2);
	return 0.5 / (gv + gl + 1e-5);
}

// One stochastic metallic flake per cell of size `c` (local metres). Returns the tilted flake
// normal (local space, xyz) and its antialiased pixel coverage (w).
vec4 car_flake(vec3 p, vec3 n, float c, float fp, float tilt) {
	vec3 q = p / c;
	vec3 cell = floor(q);
	vec3 h = car_hash33(cell);
	vec3 ctr = cell + 0.2 + 0.6 * h;
	float r = 0.2 + 0.16 * fract(h.x * 7.13 + h.z * 3.1);
	float d = length(q - ctr);
	float aa = max(fp / c, 0.03);
	float cov = 1.0 - smoothstep(r - aa, r + aa, d);
	vec3 t = car_hash33(cell + 17.31) * 2.0 - 1.0;
	t -= n * dot(t, n);
	return vec4(normalize(n + t * tilt), cov);
}

// Water beads on a surface: returns local-space normal offset (xyz, tangent to n) and mask (w).
// `stretch` elongates drops along local -Y (runs on vertical panels).
vec4 car_beads(vec3 p, vec3 n, float c, float fp, float stretch, float density) {
	vec3 sc = vec3(1.0, 1.0 + stretch, 1.0);
	vec3 q = p / (c * sc);
	vec3 cell = floor(q);
	vec3 h = car_hash33(cell + 5.17);
	vec3 ctr = cell + 0.25 + 0.5 * h;
	float r = mix(0.12, 0.34, h.y) * step(1.0 - density, fract(h.z * 13.7 + h.x));
	vec3 o = q - ctr;
	o -= n * dot(o, n);
	float d = length(o);
	float aa = max(fp / c, 0.04);
	float m = 1.0 - smoothstep(r - aa, r + aa, d);
	vec3 dome = o / max(r, 1e-3);
	dome -= n * dot(dome, n);
	return vec4(dome * m, m);
}

#endif
