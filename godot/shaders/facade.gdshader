// European / Riviera building facades on flat wall quads. UV = metres along the perimeter / up
// from the base, UV2.x = style + seed * 0.98, UV2.y = ground-floor line above the base (m),
// COLOR.rgb wall colour (OSM building:colour or a Riviera pastel), COLOR.a wall height / 250 m.
// Styles (tools/mapbake): 0 low town house, 1 mid-rise, 2 Monaco apartments, 3 villa/house,
// 4 tower, 5 church/historic, 6 industrial/garage.
// Real surfaces from the "facade" texture array (Poly Haven CC0: stucco, plaster, sandstone,
// concrete, slatted shutters). Depth is faked: recessed windows parallax against the view,
// balconies and cornices cast baked shadow bands. Windows light up at night.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/env_layers.gdshaderinc"

global uniform float nt_night;
global uniform float nt_wetness;
global uniform float nt_snow;

uniform sampler2DArray facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_normal : filter_linear_mipmap_anisotropic, repeat_enable;

const float F_STUCCO = 0.0;
const float F_PLASTER = 1.0;
const float F_GREY = 2.0;
const float F_STONE = 3.0;
const float F_CONCRETE = 4.0;
const float F_SLATS = 5.0;
const float FTILE[6] = float[](2.0, 2.0, 1.0, 2.0, 2.71, 2.0);

// Provencal shutter paints: sage, grey-blue, dove grey, walnut, lavender blue, cream.
const vec3 SHUTTER[6] = vec3[](vec3(0.33, 0.43, 0.33), vec3(0.3, 0.42, 0.5), vec3(0.55, 0.57, 0.55), vec3(0.36, 0.24, 0.16), vec3(0.3, 0.36, 0.55), vec3(0.82, 0.8, 0.72));
// Awning canvas colours for shop fronts.
const vec3 AWNING[5] = vec3[](vec3(0.55, 0.08, 0.08), vec3(0.1, 0.25, 0.18), vec3(0.08, 0.14, 0.35), vec3(0.7, 0.55, 0.2), vec3(0.2, 0.2, 0.22));

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Anti-aliased rectangle mask (metres); aa = pixel footprint.
float rect(vec2 p, vec2 mn, vec2 mx, float aa) {
	vec2 a = smoothstep(mn - aa, mn + aa, p) * (1.0 - smoothstep(mx - aa, mx + aa, p));
	return a.x * a.y;
}

// Wall material sample: texture detail normalised by the layer's average colour, so the OSM /
// palette colour sets the hue and the texture only adds real surface grain.
vec4 wall_tex(float layer, vec2 m, vec3 tint, out vec4 nrm) {
	vec3 uv = vec3(m / FTILE[int(layer)], layer);
	vec4 a = texture(facade_albedo, uv);
	nrm = texture(facade_normal, uv);
	vec3 avg = textureLod(facade_albedo, vec3(0.5, 0.5, layer), 12.0).rgb;
	vec3 detail = a.rgb / max(avg, vec3(0.05));
	return vec4(tint * mix(vec3(1.0), detail, 0.85), a.a);
}

// Geometric trim (chunk_builder: projecting cornices, balcony slabs and fronts). kind 1 stone
// moulding, 2 rendered parapet with a painted steel handrail, 3 glass balustrade.
// UV = metres (along, up from the piece's base).
void trim_fragment(vec2 uv, float kind, float seed, vec3 wall_col, vec3 N, inout vec3 albedo, inout float rough, inout float metal, inout float spec, inout vec2 nxy) {
	vec4 tn;
	vec3 stone = mix(wall_col, vec3(0.9, 0.88, 0.82), 0.65);
	if (kind < 1.5) {
		vec4 t = wall_tex(F_STONE, uv * vec2(1.0, 2.0), stone, tn);
		albedo = t.rgb;
		rough = 0.85;
		nxy = tn.rg;
	} else if (kind < 2.5) {
		vec4 t = wall_tex(seed < 0.5 ? F_STUCCO : F_PLASTER, uv, mix(wall_col, vec3(0.93, 0.92, 0.88), 0.45), tn);
		albedo = t.rgb;
		nxy = tn.rg;
		rough = 0.9;
		// Painted steel handrail capping the parapet (dark bronze or white).
		float aa = fwidth(uv.y) + 0.002;
		float rail = smoothstep(0.985 - aa, 0.985 + aa, uv.y);
		albedo = mix(albedo, seed > 0.7 ? vec3(0.85, 0.85, 0.83) : vec3(0.08, 0.07, 0.06), rail);
		metal = rail * 0.5;
		rough = mix(rough, 0.4, rail);
		// Drip streaks below the slab edge.
		albedo *= 0.9 + 0.1 * nt_value_noise(vec2(uv.x * 3.0, uv.y * 0.3));
	} else {
		// Tinted glass panels in slim aluminium frames every ~1.2 m.
		float aa = fwidth(uv.x) + 0.002;
		float to_joint = 0.6 - abs(fract(uv.x / 1.2) - 0.5) * 1.2; // metres to the nearest panel joint
		float post = 1.0 - smoothstep(0.03, 0.03 + aa, to_joint);
		float frame = max(post, smoothstep(0.95, 0.97, uv.y));
		albedo = mix(vec3(0.16, 0.2, 0.22), vec3(0.7, 0.71, 0.72), frame);
		spec = mix(0.75, 0.5, frame);
		rough = mix(0.08, 0.4, frame);
		metal = frame * 0.7;
		nxy = vec2(0.5);
	}
	albedo *= mix(1.0, 0.78, clamp(nt_wetness, 0.0, 1.0));
}

void fragment() {
	float trim = floor((UV2.x + 0.001) / 10.0);
	float code = UV2.x - trim * 10.0;
	int style = int(floor(code + 0.001));
	float seed = clamp(fract(code + 0.001) / 0.98, 0.0, 1.0);
	float anchor = UV2.y; // ground-floor line above the wall base (m)
	vec2 m = UV;
	float wall_h = max(COLOR.a * 250.0, 3.0);
	// Real stucco sits around 0.5-0.7 albedo; OSM/palette colours are sRGB swatches.
	vec3 wall_col = min(COLOR.rgb, vec3(0.92)) * 0.78;
	vec3 N = normalize(world_nrm);
	vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
	// Tangent frame from screen derivatives (walls carry no tangents): T along +u, B up.
	vec3 dp1 = dFdx(world_pos);
	vec3 dp2 = dFdy(world_pos);
	vec3 T = cross(dp2, N) * dFdx(m.x) + cross(N, dp1) * dFdy(m.x);
	T = normalize(T - N * dot(T, N) + vec3(1e-6));
	vec3 B = vec3(0.0, 1.0, 0.0);
	float aa = max(fwidth(m.x), fwidth(m.y)) * 0.75 + 0.002;
	float far = smoothstep(0.03, 0.12, aa); // fine details fade once they alias
	if (trim > 0.5) {
		vec3 t_alb;
		float t_rough = 0.85, t_metal = 0.0, t_spec = 0.5;
		vec2 t_nxy = vec2(0.5);
		trim_fragment(UV, trim, seed, wall_col, N, t_alb, t_rough, t_metal, t_spec, t_nxy);
		// The wall frame (B = up) degenerates on the horizontal soffits and caps: keep them flat.
		vec3 Nt = env_perturb(N, T, B, t_nxy, abs(N.y) > 0.5 ? 0.0 : 0.6 * (1.0 - far));
		NORMAL = normalize((VIEW_MATRIX * vec4(Nt, 0.0)).xyz);
		ALBEDO = t_alb;
		ROUGHNESS = mix(t_rough, t_rough * 0.55, clamp(nt_wetness, 0.0, 1.0));
		METALLIC = t_metal;
		SPECULAR = t_spec;
	} else {

		// ---- Layout per style (metres) ----
		float fh = 3.1;          // floor height
		float gf = 4.2;          // ground floor height
		float bw = 2.7 + seed * 0.7; // bay width
		vec2 win = vec2(1.15, 2.05); // window size
		float sill = 0.35;       // window bottom above the floor
		float shutters = 1.0;    // chance of shutters
		float balcony = 0.0;     // 0 none, 1 per window, 2 continuous
		float cornice = 1.0;
		float wall_layer = seed < 0.5 ? F_STUCCO : (seed < 0.8 ? F_PLASTER : F_GREY);
		float base_layer = F_STONE;
		bool shops = true;
		if (style == 1) { fh = 3.2; shutters = 0.5; balcony = 1.0; }
		else if (style == 2) { fh = 3.05; balcony = seed < 0.55 ? 1.0 : 2.0; shutters = 0.6; }
		else if (style == 3) { fh = 3.0; gf = 3.0; win = vec2(1.0, 1.45); sill = 0.9; balcony = seed > 0.7 ? 1.0 : 0.0; base_layer = wall_layer; shops = false; cornice = 0.5; }
		else if (style == 4) { fh = 3.3; gf = 5.0; bw = 3.0; win = vec2(2.7, 2.5); sill = 0.25; shutters = 0.0; balcony = 2.0; wall_layer = seed < 0.5 ? F_STUCCO : F_CONCRETE; cornice = 0.0; }
		else if (style == 5) { fh = 5.5; gf = 5.5; bw = 4.2; win = vec2(1.3, 3.0); sill = 1.4; shutters = 0.0; wall_layer = F_STONE; shops = false; }
		else if (style == 6) { fh = 5.0; gf = 5.0; bw = 6.0; win = vec2(3.4, 1.1); sill = 3.4; shutters = 0.0; wall_layer = F_CONCRETE; base_layer = F_CONCRETE; shops = false; cornice = 0.0; }
		vec3 shutter_col = SHUTTER[int(fract(seed * 7.31) * 5.99)];
		float top = wall_h - (cornice > 0.0 ? 0.9 : 0.4);

		// ---- Cells ----
		// Floors are level, counted from the anchor; below it (downhill walls) are lower storeys.
		float ya = m.y - anchor;
		bool ground = ya >= 0.0 && ya < gf;
		float y = ya >= 0.0 ? ya - gf : ya;
		float fi = floor(y / fh);
		float fy = y - fi * fh;
		float bi = floor(m.x / bw);
		float fx = m.x - (bi + 0.5) * bw;
		float cell_h = nt_hash(vec2(bi, fi) + seed * 91.0);
		// Fewer windows on narrow return walls: skip some bays on low houses.
		bool has_win = !ground && m.y + (fh - fy) < top + 0.2 && !(style == 3 && cell_h < 0.25) && m.y > 0.8;
		if (ground) { fy = ya; }

		// ---- Wall ----
		vec4 wn;
		vec4 wall = wall_tex(wall_layer, m, wall_col, wn);
		vec3 albedo = wall.rgb;
		float rough = mix(0.82, 0.95, wn.b);
		vec2 nxy = wn.rg;
		float height = wall.a;

		// Rusticated stone base / plinth on the ground floor.
		float plinth = ground ? 1.0 : 0.0;
		if (ground && style != 3) {
			vec4 bn;
			vec3 stone_tint = mix(wall_col, vec3(0.86, 0.82, 0.74), base_layer == F_STONE ? 0.6 : 0.0);
			vec4 base_c = wall_tex(base_layer, m * vec2(1.0, 1.0), stone_tint, bn);
			albedo = base_c.rgb;
			nxy = bn.rg;
			rough = mix(0.8, 0.95, bn.b);
		}

		// Cornices: string course at each floor line, heavy cornice at the roof line.
		float band = 0.0;
		float shadow = 1.0;
		if (cornice > 0.0 && style != 4) {
			float course = rect(vec2(0.0, fy), vec2(-1.0, 0.0), vec2(1.0, 0.16 * cornice), aa) * (ground ? 0.0 : 1.0);
			float gf_line = rect(vec2(0.0, ya), vec2(-1.0, gf - 0.25), vec2(1.0, gf + 0.05), aa);
			float roof_c = rect(vec2(0.0, m.y), vec2(-1.0, top), vec2(1.0, top + 0.55), aa);
			band = max(max(course, gf_line), roof_c);
			// Soft shadow under the projecting roof cornice and ground-floor course.
			shadow *= 1.0 - 0.35 * smoothstep(top - 0.6, top, m.y) * step(m.y, top);
			shadow *= 1.0 - 0.3 * smoothstep(gf - 0.7, gf - 0.25, ya) * step(ya, gf - 0.25) * step(0.0, ya);
			albedo = mix(albedo, mix(wall_col, vec3(0.9, 0.88, 0.82), 0.65) * (0.9 + 0.2 * height), band);
		}
		// Parapet above the roof cornice.
		if (m.y > top + 0.55) {
			albedo = wall.rgb * 0.95;
		}

		// ---- Windows (recessed, parallax) ----
		vec3 emit = vec3(0.0);
		float glass = 0.0;
		float metal = 0.0;
		float spec = 0.5;
		if (has_win) {
			vec2 c = vec2(fx, fy - sill - win.y * 0.5); // window-centred coordinates
			vec2 hw = win * 0.5;
			float opening = rect(c, -hw, hw, aa);
			// Arched heads on churches.
			if (style == 5) {
				float arc = length(vec2(c.x, max(c.y - (hw.y - hw.x), 0.0))) - hw.x;
				opening = smoothstep(aa, -aa, arc) * rect(c, -hw, vec2(hw.x, hw.y + hw.x), aa);
			}
			// Parallax: the glass sits `depth` behind the wall plane.
			vec3 vt = vec3(dot(V, T), dot(V, B), dot(V, N));
			float depth = style == 4 ? 0.12 : 0.24;
			vec2 off = -vt.xy / max(vt.z, 0.25) * depth;
			vec2 cg = c + off;
			float inner = rect(cg, -hw, hw, aa) * opening;
			float reveal = opening - inner;
			// Frame: pale painted timber / aluminium ring around the glass.
			float frame = inner * (1.0 - rect(cg, -hw + 0.07, hw - 0.07, aa));
			float mullion = inner * rect(cg, vec2(-0.03, -hw.y), vec2(0.03, hw.y), aa) * (style == 4 ? 0.0 : 1.0);
			float transom = inner * rect(cg, vec2(-hw.x, hw.y - 0.55), vec2(hw.x, hw.y - 0.5), aa) * (style == 4 ? 0.0 : 1.0);
			float glass_m = clamp(inner - frame - mullion - transom, 0.0, 1.0);
			// Glass: dark, reflective, with sheer curtains / blinds in some windows.
			float lit_h = nt_hash(vec2(bi * 1.7, fi * 3.1) + seed * 13.0);
			vec3 interior = mix(vec3(0.02, 0.025, 0.03), vec3(0.08, 0.075, 0.07), lit_h);
			float curtain = step(0.55, lit_h) * smoothstep(-0.2, 0.6, cg.y / hw.y);
			interior = mix(interior, vec3(0.42, 0.4, 0.36), curtain * 0.6);
			vec3 frame_col = style == 4 ? vec3(0.55, 0.56, 0.58) : vec3(0.86, 0.85, 0.8);
			vec3 reveal_col = wall.rgb * mix(0.45, 0.8, smoothstep(hw.y, hw.y - 0.3, c.y)); // lintel shadow on top
			albedo = mix(albedo, reveal_col, reveal);
			albedo = mix(albedo, frame_col, clamp(frame + mullion + transom, 0.0, 1.0));
			albedo = mix(albedo, interior, glass_m);
			rough = mix(rough, 0.06, glass_m);
			rough = mix(rough, 0.5, clamp(frame + mullion + transom, 0.0, 1.0));
			spec = mix(spec, 0.75, glass_m);
			glass = glass_m;
			nxy = mix(nxy, vec2(0.5), opening);
			// Stone sill and lintel on classic facades.
			if (style != 4 && style != 6) {
				float sillm = rect(c, vec2(-hw.x - 0.12, -hw.y - 0.1), vec2(hw.x + 0.12, -hw.y), aa);
				float lint = rect(c, vec2(-hw.x - 0.08, hw.y), vec2(hw.x + 0.08, hw.y + 0.14), aa) * (style == 5 ? 0.0 : 1.0);
				albedo = mix(albedo, vec3(0.85, 0.83, 0.77) * (0.9 + 0.2 * height), max(sillm, lint));
				shadow *= 1.0 - 0.3 * rect(c, vec2(-hw.x - 0.1, -hw.y - 0.35), vec2(hw.x + 0.1, -hw.y - 0.1), aa); // drip shadow
			}
			// Shutters: open panels either side (or closed over the window).
			if (shutters > 0.0 && fract(seed * 13.7) < shutters) {
				float closed = step(nt_hash(vec2(bi, fi) + seed * 3.0), 0.22);
				vec2 sp = vec2(abs(c.x) - hw.x - hw.x * 0.5 - 0.03, c.y);
				float open_panel = rect(sp, vec2(-hw.x * 0.5, -hw.y), vec2(hw.x * 0.5, hw.y), aa) * (1.0 - closed);
				float shut = max(open_panel, opening * closed);
				vec4 sn;
				vec3 slat_uv_tint = shutter_col;
				vec4 sl = wall_tex(F_SLATS, vec2(c.x, c.y) * vec2(1.0, 1.6), slat_uv_tint, sn);
				// Panel border.
				float edge = 1.0 - rect(closed > 0.5 ? c : sp, closed > 0.5 ? -hw + 0.05 : vec2(-hw.x * 0.5 + 0.05, -hw.y + 0.05), closed > 0.5 ? hw - 0.05 : vec2(hw.x * 0.5 - 0.05, hw.y - 0.05), aa);
				vec3 sc = mix(sl.rgb, shutter_col * 0.85, edge);
				albedo = mix(albedo, sc, shut);
				rough = mix(rough, 0.6, shut);
				nxy = mix(nxy, sn.rg, shut * (1.0 - far));
				glass *= 1.0 - shut;
				spec = mix(spec, 0.45, shut);
				// Open shutters stand off the wall: thin shadow line on their inner edge.
				shadow *= 1.0 - 0.35 * open_panel * (1.0 - smoothstep(0.0, 0.08, abs(abs(c.x) - hw.x - 0.03)));
			}
			// Balcony: slab + wrought-iron railing in front of the lower window.
			if (balcony > 0.0) {
				float span = balcony > 1.5 ? 1.0 : rect(vec2(fx, 0.0), vec2(-hw.x - 0.45, -1.0), vec2(hw.x + 0.45, 1.0), aa);
				float slab = span * rect(vec2(0.0, fy), vec2(-1.0, 0.0), vec2(1.0, 0.18), aa);
				float rail_zone = span * rect(vec2(0.0, fy), vec2(-1.0, 0.18), vec2(1.0, 1.08), aa);
				float top_rail = span * rect(vec2(0.0, fy), vec2(-1.0, 1.02), vec2(1.0, 1.1), aa);
				float bar_d = abs(fract(m.x / 0.13) - 0.5) * 0.13; // metres from the nearest bar
				float bars = 1.0 - smoothstep(0.012, 0.012 + aa, bar_d);
				bars = mix(bars, 0.3, far) * rail_zone; // average density once the bars alias
				vec3 slab_col = mix(wall_col, vec3(0.92, 0.9, 0.86), 0.6);
				if (style == 4 || style == 2 && seed > 0.8) {
					// Modern: glass balustrade with a white slab edge.
					albedo = mix(albedo, mix(albedo, vec3(0.45, 0.55, 0.6), 0.35), rail_zone);
					spec = mix(spec, 0.7, rail_zone);
					rough = mix(rough, 0.1, rail_zone);
				} else {
					albedo = mix(albedo, vec3(0.05, 0.05, 0.05), max(bars, top_rail));
					metal = max(metal, 0.4 * max(bars, top_rail));
					rough = mix(rough, 0.55, max(bars, top_rail));
				}
				albedo = mix(albedo, slab_col, slab);
				// The slab above shades the top of this floor.
				shadow *= 1.0 - 0.4 * span * smoothstep(fh - 0.5, fh, fy);
			}
			// Night: lit rooms, whole floors on offices, warm or cool.
			if (nt_night > 0.0) {
				float floor_lit = nt_hash(vec2(fi, seed * 51.0));
				float lit = step(0.6 - 0.1 * seed, lit_h * 0.6 + floor_lit * 0.4);
				vec3 tint = mix(vec3(1.0, 0.78, 0.5), vec3(0.75, 0.86, 1.0), step(0.7, nt_hash(vec2(bi, fi) + 3.3)));
				emit += tint * glass * lit * (0.5 + 0.8 * curtain) * (0.4 + 0.4 * lit_h) * nt_night;
			}
		}

		// ---- Ground floor: shop fronts with awnings, or doors ----
		if (ground && shops) {
			float sb = floor(m.x / (bw * 2.0));
			float sx = m.x - (sb + 0.5) * bw * 2.0;
			float sh = nt_hash(vec2(sb, 7.0) + seed * 17.0);
			vec2 c = vec2(sx, ya);
			float shop = rect(c, vec2(-bw + 0.35, 0.25), vec2(bw - 0.35, gf - 1.05), aa);
			vec3 vt = vec3(dot(V, T), dot(V, B), dot(V, N));
			vec2 off = -vt.xy / max(vt.z, 0.25) * 0.3;
			float inner = rect(c + off, vec2(-bw + 0.35, 0.25), vec2(bw - 0.35, gf - 1.05), aa) * shop;
			float frame = inner * (1.0 - rect(c + off, vec2(-bw + 0.45, 0.35), vec2(bw - 0.45, gf - 1.15), aa));
			float gl = clamp(inner - frame, 0.0, 1.0);
			bool shuttered = sh < 0.18; // closed roller shutter
			// Lit shop interior seen through the glass: shelves of goods on a back wall ~2.5 m deep.
			vec2 cb = c + (-vt.xy / max(vt.z, 0.25)) * 2.5;
			vec2 shelf = vec2(floor(cb.x / 0.18), floor(cb.y / 0.38));
			float goods = step(0.25, fract(cb.y / 0.38)) * step(0.15, fract(cb.x / 0.18)) * step(0.45, nt_hash(shelf + sb));
			vec3 item = mix(vec3(0.5, 0.46, 0.4), vec3(nt_hash(shelf + 1.3), nt_hash(shelf + 5.1), nt_hash(shelf + 9.7)), 0.3);
			vec3 wall_in = mix(vec3(0.3, 0.27, 0.23), vec3(0.16, 0.17, 0.19), step(0.5, nt_hash(vec2(sb, 3.0))));
			// Ceiling lights make the top of the room brighter; the floor falls into shadow.
			float light_in = mix(0.35, 1.0, smoothstep(0.2, gf - 1.2, cb.y));
			vec3 interior = mix(wall_in, item, goods * step(0.5, cb.y) * step(cb.y, gf - 1.5)) * light_in * 0.45;
			albedo = mix(albedo, wall.rgb * 0.35, shop - inner);
			albedo = mix(albedo, vec3(0.12, 0.12, 0.13), frame);
			if (shuttered) {
				vec4 sn;
				vec4 sl = wall_tex(F_SLATS, c * vec2(1.0, 2.0), vec3(0.62, 0.63, 0.64), sn);
				albedo = mix(albedo, sl.rgb, shop);
				nxy = mix(nxy, sn.rg, shop);
				rough = mix(rough, 0.5, shop);
			} else {
				albedo = mix(albedo, interior, gl);
				rough = mix(rough, 0.1, gl);
				spec = mix(spec, 0.45, gl);
				// Above the window: striped canvas awning, or a painted fascia board with lettering.
				float band_m = rect(c, vec2(-bw + 0.25, gf - 1.0), vec2(bw - 0.25, gf - 0.45), aa);
				vec3 ac = AWNING[int(sh * 4.99)];
				if (sh > 0.55) {
					float stripe = step(0.5, fract(sx / 0.35));
					ac = mix(ac, vec3(0.92, 0.9, 0.85), stripe * step(0.75, sh));
					albedo = mix(albedo, ac * (0.8 + 0.2 * smoothstep(gf - 1.0, gf - 0.45, ya)), band_m);
					rough = mix(rough, 0.85, band_m);
				} else {
					vec2 lt = vec2(sx / 0.22, (ya - (gf - 0.9)) / 0.36);
					float letters = step(abs(sx), bw * 0.55) * step(0.15, lt.y) * step(lt.y, 0.85) * step(0.45, nt_hash(vec2(floor(lt.x), sb)));
					albedo = mix(albedo, mix(ac * 0.8, vec3(0.9, 0.85, 0.7), letters), band_m);
					metal = max(metal, 0.5 * band_m * letters);
					rough = mix(rough, 0.45, band_m);
				}
				// Shops are lit inside by day; brighter at night.
				float on = mix(0.35, 1.0, nt_night);
				emit += mix(vec3(1.0, 0.86, 0.62), vec3(0.88, 0.93, 1.0), step(0.6, sh)) * interior * gl * on * 1.6;
			}
			nxy = mix(nxy, vec2(0.5), shop * (shuttered ? 0.0 : 1.0));
		} else if (ground) {
			// Entrance door on houses / churches.
			float db = floor(m.x / 9.0);
			float dx = m.x - (db + 0.5) * 9.0;
			float door = rect(vec2(dx, ya), vec2(-0.55, 0.0), vec2(0.55, style == 5 ? 3.6 : 2.3), aa);
			albedo = mix(albedo, vec3(0.28, 0.18, 0.1), door);
			rough = mix(rough, 0.6, door);
		}

		// ---- Weathering ----
		float streak = nt_value_noise(vec2(m.x * 2.3, m.y * 0.07) + seed * 10.0);
		albedo *= mix(1.0, 0.82 + 0.18 * streak, 0.7 * (1.0 - glass));
		albedo *= mix(0.72, 1.0, smoothstep(0.0, 1.2, m.y)); // splash / grime at the foot
		albedo *= 0.92 + 0.16 * nt_fbm(m * 0.05 + seed * 3.0, 2);
		albedo *= shadow;

		float wet = clamp(nt_wetness, 0.0, 1.0);
		albedo *= mix(1.0, 0.78, wet * (1.0 - glass));
		rough = mix(rough, rough * 0.55, wet);

		vec3 Nw = env_perturb(N, T, B, nxy, 0.9 * (1.0 - far * 0.6));
		NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);
		ALBEDO = albedo;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
	}
}
