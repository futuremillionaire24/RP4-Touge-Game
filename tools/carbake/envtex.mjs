// Environment texture arrays from Poly Haven (CC0): downloads 1k/2k maps per layer and packs
// them into two stacked images per set (see envtex.json):
//   <set>_albedo.webp  RGB albedo, A height (displacement, normalised per layer)
//   <set>_normal.webp  RG normal xy (OpenGL), B roughness, A ambient occlusion
// plus a .import file so Godot imports each as a Texture2DArray, and env_textures.json with the
// real tile size (m) and author of every layer.
//   node envtex.mjs [set ...]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'envtex.json'), 'utf8')).sets;
const CACHE = path.join(root, 'build/envtex');
const OUT = path.join(root, 'godot/assets/env');
fs.mkdirSync(CACHE, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });
const UA = { 'User-Agent': 'RP4-EuroGT-envbake/1.0' };

async function getJson(url) {
	const r = await fetch(url, { headers: UA });
	if (!r.ok) throw new Error(`${r.status} ${url}`);
	return r.json();
}

async function download(url, file) {
	if (fs.existsSync(file)) return file;
	const r = await fetch(url, { headers: UA });
	if (!r.ok) throw new Error(`${r.status} ${url}`);
	fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
	return file;
}

// One map at the best resolution >= size (falls back to what exists).
async function map(files, id, key, size) {
	const m = files[key];
	if (!m) return null;
	const res = ['1k', '2k', '4k'].find((r) => m[r] && parseInt(r) * 1024 >= size) || Object.keys(m)[0];
	const fmt = m[res].jpg ? 'jpg' : 'png';
	const file = path.join(CACHE, `${id}_${key}_${res}.${fmt}`);
	return download(m[res][fmt].url, file);
}

async function raw(file, size, channels) {
	return sharp(file).resize(size, size, { fit: 'fill' }).removeAlpha().toColourspace(channels === 1 ? 'b-w' : 'srgb').raw().toBuffer();
}

const manifest = fs.existsSync(path.join(OUT, 'env_textures.json')) ? JSON.parse(fs.readFileSync(path.join(OUT, 'env_textures.json'), 'utf8')) : {};
const only = process.argv.slice(2);
for (const [set, def] of Object.entries(cfg)) {
	if (only.length && !only.includes(set)) continue;
	const S = def.size;
	const n = def.layers.length;
	const alb = Buffer.alloc(S * S * n * 4);
	const nrm = Buffer.alloc(S * S * n * 4);
	const layers = [];
	for (let l = 0; l < n; l++) {
		const id = def.layers[l];
		const info = await getJson(`https://api.polyhaven.com/info/${id}`);
		const files = await getJson(`https://api.polyhaven.com/files/${id}`);
		const diff = await raw(await map(files, id, 'Diffuse', S), S, 3);
		const nor = await raw(await map(files, id, 'nor_gl', S), S, 3);
		const rgh = files.Rough ? await raw(await map(files, id, 'Rough', S), S, 1) : null;
		const ao = files.AO ? await raw(await map(files, id, 'AO', S), S, 1) : null;
		const disp = files.Displacement ? await raw(await map(files, id, 'Displacement', S), S, 1) : null;
		// Normalise height to the full 0..255 range so height blending is comparable across layers.
		let lo = 255, hi = 0;
		if (disp) for (const v of disp) (lo = Math.min(lo, v)), (hi = Math.max(hi, v));
		const o = S * S * 4 * l;
		for (let p = 0; p < S * S; p++) {
			alb[o + p * 4] = diff[p * 3];
			alb[o + p * 4 + 1] = diff[p * 3 + 1];
			alb[o + p * 4 + 2] = diff[p * 3 + 2];
			alb[o + p * 4 + 3] = disp ? Math.round(((disp[p] - lo) / Math.max(1, hi - lo)) * 255) : 128;
			nrm[o + p * 4] = nor[p * 3];
			nrm[o + p * 4 + 1] = nor[p * 3 + 1];
			nrm[o + p * 4 + 2] = rgh ? rgh[p] : 200;
			nrm[o + p * 4 + 3] = ao ? ao[p] : 255;
		}
		const dims = info.dimensions || [2000, 2000];
		layers.push({ id, name: info.name, tile_m: +(dims[0] / 1000).toFixed(3), authors: Object.keys(info.authors || {}), license: 'CC0', source: `https://polyhaven.com/a/${id}` });
		console.log(`${set}[${l}] ${id} tile ${(dims[0] / 1000).toFixed(2)} m`);
	}
	for (const [suffix, buf] of [['albedo', alb], ['normal', nrm]]) {
		const file = path.join(OUT, `${set}_${suffix}.webp`);
		// High-quality lossy: the importer re-compresses to VRAM formats (ETC2/ASTC/BPTC) anyway.
		await sharp(buf, { raw: { width: S, height: S * n, channels: 4 } }).webp({ quality: suffix === 'normal' ? 95 : 92, alphaQuality: 100, smartSubsample: true }).toFile(file);
		fs.writeFileSync(
			file + '.import',
			[
				'[remap]',
				'',
				'importer="2d_array_texture"',
				'type="CompressedTexture2DArray"',
				'',
				'[params]',
				'',
				'compress/mode=2',
				'compress/high_quality=false',
				'compress/lossy_quality=0.7',
				'compress/hdr_compression=1',
				'compress/channel_pack=0',
				'mipmaps/generate=true',
				'mipmaps/limit=-1',
				'slices/horizontal=1',
				`slices/vertical=${n}`,
				'',
			].join('\n'),
		);
		console.log(`  -> ${path.relative(root, file)} (${(fs.statSync(file).size / 1e6).toFixed(1)} MB)`);
	}
	manifest[set] = { size: S, layers };
}
fs.writeFileSync(path.join(OUT, 'env_textures.json'), JSON.stringify(manifest, null, 1));
