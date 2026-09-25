// Sky keyframes from Poly Haven HDRIs (CC0, "qwantani" pure-sky day cycle + weather skies).
// Each 4k HDR is decoded, its sun (or brightest region) located, exposed to LDR with a recorded
// exposure (so night stays darker than noon in game), and the upper hemisphere written as
// godot/assets/env/sky/<id>.jpg (4096x1024: row 0 = zenith, last row = horizon).
// godot/assets/env/sky/sky.json lists {id, hour, sun_u, sun_el, energy, horizon colour}.
//   node skybake.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const CACHE = path.join(root, 'build/envtex');
const OUT = path.join(root, 'godot/assets/env/sky');
fs.mkdirSync(CACHE, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });
const UA = { 'User-Agent': 'RP4-EuroGT-envbake/1.0' };

// Day cycle (hour = game time the keyframe is shown at) + weather skies (hour -1).
// sun_el: fixed elevation (deg) where the sun is below the horizon (glow detection would lie);
// energy: sky brightness in game (Poly Haven exposures are per-image, not comparable).
// The visible sun is painted out (paint_sun) - the game draws its own disc at the real light.
const SKIES = [
	{ id: 'qwantani_dawn_puresky', hour: 5.4, sun_el: -4, energy: 0.25 },
	{ id: 'qwantani_sunrise_puresky', hour: 6.2, energy: 0.6, paint_sun: true },
	{ id: 'qwantani_morning_puresky', hour: 7.6, energy: 0.9, paint_sun: true },
	{ id: 'qwantani_mid_morning_puresky', hour: 9.6, energy: 0.95, paint_sun: true },
	{ id: 'qwantani_noon_puresky', hour: 12.5, energy: 1.0, paint_sun: true },
	{ id: 'qwantani_afternoon_puresky', hour: 15.2, energy: 1.0, paint_sun: true },
	{ id: 'qwantani_late_afternoon_puresky', hour: 16.8, energy: 0.95, paint_sun: true },
	{ id: 'qwantani_sunset_puresky', hour: 17.9, energy: 0.75, paint_sun: true },
	{ id: 'qwantani_dusk_1_puresky', hour: 18.5, sun_el: -2.5, energy: 0.38 },
	{ id: 'qwantani_dusk_2_puresky', hour: 19.1, sun_el: -6, energy: 0.16 },
	{ id: 'qwantani_night_puresky', hour: 21.5, sun_el: -35, energy: 0.018 },
	{ id: 'kloofendal_overcast_puresky', hour: -1, weather: 'overcast', energy: 0.62 },
	{ id: 'kloofendal_48d_partly_cloudy_puresky', hour: -1, weather: 'cloudy', energy: 0.95, paint_sun: true },
];

// Removes the sun and its lens-flare rays (angular radius r, deg): fills the disc with the mean
// of the surrounding ring, then feathers a heavily blurred copy over r..r+5 deg so no seam or
// ray remnants survive.
function paintSun(rgb, W, HH, su, sv, r) {
	const dir = (u, v) => {
		const az = (u - 0.5) * 2 * Math.PI, el = (1 - v) * Math.PI / 2;
		return [Math.cos(el) * Math.sin(az), Math.sin(el), -Math.cos(el) * Math.cos(az)];
	};
	const s = dir(su, sv);
	const ang = (x, y) => {
		const d = dir((x + 0.5) / W, (y + 0.5) / HH);
		return (Math.acos(Math.min(1, d[0] * s[0] + d[1] * s[1] + d[2] * s[2])) * 180) / Math.PI;
	};
	const hx = Math.ceil(((r + 6) / 360) * W / Math.max(0.2, Math.cos(((1 - sv) * Math.PI) / 2))), hy = Math.ceil(((r + 6) / 90) * HH);
	const cx = Math.round(su * W), cy = Math.round(sv * HH);
	const X0 = cx - hx, Y0 = Math.max(0, cy - hy), WW = 2 * hx + 1, WH = Math.min(HH, cy + hy + 1) - Y0;
	const idx = (x, y) => ((y * W + (((x % W) + W) % W)) * 3);
	const A = new Float32Array(WW * WH);
	const ring = [0, 0, 0];
	let rn = 0;
	for (let y = 0; y < WH; y++)
		for (let x = 0; x < WW; x++) {
			const a = ang(X0 + x, Y0 + y);
			A[y * WW + x] = a;
			if (a >= r && a < r + 1) { const o = idx(X0 + x, Y0 + y); ring[0] += rgb[o]; ring[1] += rgb[o + 1]; ring[2] += rgb[o + 2]; rn++; }
		}
	for (let c = 0; c < 3; c++) ring[c] /= Math.max(1, rn);
	for (let y = 0; y < WH; y++)
		for (let x = 0; x < WW; x++) if (A[y * WW + x] < r) { const o = idx(X0 + x, Y0 + y); rgb[o] = ring[0]; rgb[o + 1] = ring[1]; rgb[o + 2] = ring[2]; }
	// Blurred copy of the window: 3 separable box passes.
	let B = new Float32Array(WW * WH * 3);
	for (let y = 0; y < WH; y++) for (let x = 0; x < WW; x++) { const o = idx(X0 + x, Y0 + y); B.set([rgb[o], rgb[o + 1], rgb[o + 2]], (y * WW + x) * 3); }
	const R = 22;
	for (let pass = 0; pass < 3; pass++)
		for (const horiz of [true, false]) {
			const N = new Float32Array(B.length);
			for (let y = 0; y < WH; y++)
				for (let x = 0; x < WW; x++) {
					const acc = [0, 0, 0];
					let n = 0;
					for (let k = -R; k <= R; k++) {
						const xx = horiz ? x + k : x, yy = horiz ? y : y + k;
						if (xx < 0 || yy < 0 || xx >= WW || yy >= WH) continue;
						const o = (yy * WW + xx) * 3;
						acc[0] += B[o]; acc[1] += B[o + 1]; acc[2] += B[o + 2]; n++;
					}
					N.set([acc[0] / n, acc[1] / n, acc[2] / n], (y * WW + x) * 3);
				}
			B = N;
		}
	for (let y = 0; y < WH; y++)
		for (let x = 0; x < WW; x++) {
			const a = A[y * WW + x];
			const t = a < r ? 1 : a > r + 5 ? 0 : 1 - (a - r) / 5;
			if (t <= 0) continue;
			const w = t * t * (3 - 2 * t);
			const o = idx(X0 + x, Y0 + y);
			for (let c = 0; c < 3; c++) rgb[o + c] = rgb[o + c] * (1 - w) + B[(y * WW + x) * 3 + c] * w;
		}
}

// Radiance RGBE (.hdr) decoder: new-style RLE scanlines. Returns Float32 RGB.
function decodeHdr(buf) {
	let p = 0;
	const line = () => {
		let s = '';
		while (buf[p] !== 0x0a) s += String.fromCharCode(buf[p++]);
		p++;
		return s;
	};
	while (line() !== '');
	const m = /-Y (\d+) \+X (\d+)/.exec(line());
	const H = +m[1], W = +m[2];
	const out = new Float32Array(W * H * 3);
	const scan = new Uint8Array(W * 4);
	for (let y = 0; y < H; y++) {
		if (buf[p] === 2 && buf[p + 1] === 2 && ((buf[p + 2] << 8) | buf[p + 3]) === W) {
			p += 4;
			for (let c = 0; c < 4; c++) {
				let x = 0;
				while (x < W) {
					let n = buf[p++];
					if (n > 128) {
						n -= 128;
						const v = buf[p++];
						for (let k = 0; k < n; k++) scan[(x++) * 4 + c] = v;
					} else for (let k = 0; k < n; k++) scan[(x++) * 4 + c] = buf[p++];
				}
			}
		} else {
			for (let x = 0; x < W; x++) for (let c = 0; c < 4; c++) scan[x * 4 + c] = buf[p++];
		}
		for (let x = 0; x < W; x++) {
			const e = scan[x * 4 + 3];
			const f = e ? Math.pow(2, e - 136) : 0;
			const o = (y * W + x) * 3;
			out[o] = scan[x * 4] * f;
			out[o + 1] = scan[x * 4 + 1] * f;
			out[o + 2] = scan[x * 4 + 2] * f;
		}
	}
	return { W, H, rgb: out };
}

async function fetchHdr(id) {
	const file = path.join(CACHE, `${id}_4k.hdr`);
	if (!fs.existsSync(file)) {
		const f = await (await fetch(`https://api.polyhaven.com/files/${id}`, { headers: UA })).json();
		const r = await fetch(f.hdri['4k'].hdr.url, { headers: UA });
		fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
	}
	return fs.readFileSync(file);
}

const lum = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
const soft = (x) => (x < 0.8 ? x : 0.8 + 0.2 * (1 - Math.exp(-(x - 0.8) / 0.2)));
const srgb = (x) => (x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055);

const meta = [];
for (const s of SKIES) {
	const info = await (await fetch(`https://api.polyhaven.com/info/${s.id}`, { headers: UA })).json();
	const { W, H, rgb } = decodeHdr(await fetchHdr(s.id));
	const HH = H / 2; // upper hemisphere
	// Sun: brightest texel of a 4x-downsampled luminance map (robust to single hot pixels).
	let best = -1, bu = 0.5, bv = 0.5;
	const L = [];
	for (let y = 0; y < HH; y += 4)
		for (let x = 0; x < W; x += 4) {
			let l = 0;
			for (let dy = 0; dy < 4; dy++) for (let dx = 0; dx < 4; dx++) { const o = ((y + dy) * W + x + dx) * 3; l += lum(rgb[o], rgb[o + 1], rgb[o + 2]); }
			L.push(l / 16);
			if (l > best) (best = l), (bu = (x + 2) / W), (bv = (y + 2) / HH);
		}
	if (s.paint_sun) paintSun(rgb, W, HH, bu, bv, 7.5);
	L.sort((a, b) => a - b);
	const l95 = L[Math.floor(L.length * 0.95)];
	const scale = 0.8 / Math.max(l95, 1e-6);
	// Horizon colour (average of the lowest 3% of rows) for fog / ambient tint.
	const hc = [0, 0, 0];
	let hn = 0;
	for (let y = Math.floor(HH * 0.97); y < HH; y++)
		for (let x = 0; x < W; x += 8) { const o = (y * W + x) * 3; hc[0] += rgb[o]; hc[1] += rgb[o + 1]; hc[2] += rgb[o + 2]; hn++; }
	const px = Buffer.alloc(W * HH * 3);
	for (let i = 0; i < W * HH; i++)
		for (let c = 0; c < 3; c++) px[i * 3 + c] = Math.round(srgb(Math.min(1, soft(rgb[i * 3 + c] * scale))) * 255);
	const jpg = path.join(OUT, `${s.id}.jpg`);
	await sharp(px, { raw: { width: W, height: HH, channels: 3 } }).jpeg({ quality: 88, chromaSubsampling: '4:4:4' }).toFile(jpg);
	fs.writeFileSync(jpg + '.import', '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nprocess/fix_alpha_border=false\ndetect_3d/compress_to=0\n');
	const e = {
		id: s.id,
		hour: s.hour,
		weather: s.weather || '',
		sun_u: +bu.toFixed(4),
		sun_el: s.sun_el ?? +((1 - bv) * 90).toFixed(2),
		energy: s.energy,
		horizon: hc.map((v) => +Math.min(1, (v / hn) * scale).toFixed(4)),
		authors: Object.keys(info.authors || {}),
		license: 'CC0',
		source: `https://polyhaven.com/a/${s.id}`,
	};
	meta.push(e);
	console.log(`${s.id}: sun u ${e.sun_u} el ${e.sun_el} deg`);
}
fs.writeFileSync(path.join(OUT, 'sky.json'), JSON.stringify({ skies: meta }, null, 1));
