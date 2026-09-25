// Prop bake: picks objects out of CC-BY / CC0 model packs (Sketchfab) and turns each into a
// game prop: transforms baked, scaled to its real height (or length), ground at y=0, centred on
// x/z, merged per material, simplified to a triangle budget, textures capped.
//   SKETCHFAB_TOKEN=... node props.mjs [key ...]
// Output godot/assets/props/<key>/<key>.gltf (+ .bin, images) and <key>.json (credit, size).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import draco3d from 'draco3dgltf';
import { MeshoptDecoder, MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'props.json'), 'utf8')).props;
const RAW = path.join(root, 'build/carbake/raw_props');
const OUT = path.join(root, 'godot/assets/props');
fs.mkdirSync(RAW, { recursive: true });

await MeshoptDecoder.ready;
await MeshoptSimplifier.ready;
MeshoptSimplifier.useExperimentalFeatures = true;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
	'draco3d.decoder': await draco3d.createDecoderModule(),
	'meshopt.decoder': MeshoptDecoder,
});

async function fetchModel(uid) {
	const glb = path.join(RAW, `${uid}.glb`);
	const meta = path.join(RAW, `${uid}.json`);
	if (fs.existsSync(glb)) return JSON.parse(fs.readFileSync(meta, 'utf8').replace(/^﻿/, ''));
	const m = await (await fetch(`https://api.sketchfab.com/v3/models/${uid}`)).json();
	const lic = m.license?.label || '';
	if (!/Attribution|CC0|Public Domain/i.test(lic) || /NonCommercial|NoDerivs/i.test(lic)) throw new Error(`licence ${lic}`);
	const token = process.env.SKETCHFAB_TOKEN;
	if (!token) throw new Error('SKETCHFAB_TOKEN not set');
	const d = await (await fetch(`https://api.sketchfab.com/v3/models/${uid}/download`, { headers: { Authorization: `Token ${token}` } })).json();
	fs.writeFileSync(glb, Buffer.from(await (await fetch(d.glb.url)).arrayBuffer()));
	const credit = { title: m.name, author: m.user?.displayName || m.user?.username, author_url: `https://sketchfab.com/${m.user?.username}`, license: lic, license_url: m.license?.url || '', source: m.viewerUrl };
	fs.writeFileSync(meta, JSON.stringify(credit, null, 1));
	return credit;
}

// Base colour texture, including legacy spec-gloss materials (diffuse texture in the extension).
const baseTex = (mat) => mat.getBaseColorTexture() || mat.getExtension('KHR_materials_pbrSpecularGlossiness')?.getDiffuseTexture() || null;

const mul = (M, x, y, z) => [M[0] * x + M[4] * y + M[8] * z + M[12], M[1] * x + M[5] * y + M[9] * z + M[13], M[2] * x + M[6] * y + M[10] * z + M[14]];

async function bakeProp(key, c) {
	const credit = await fetchModel(c.uid);
	const src = await io.read(path.join(RAW, `${c.uid}.glb`));
	const rx = new RegExp(c.pick);
	const picked = src.getRoot().listNodes().filter((n) => rx.test(n.getName()));
	if (!picked.length) throw new Error(`no node matches ${c.pick}`);
	// Gather primitives under the picked nodes with world transforms baked in.
	const parts = [];
	const tmp = [];
	const visit = (n) => {
		const mesh = n.getMesh();
		if (mesh) {
			const M = n.getWorldMatrix();
			const det = M[0] * (M[5] * M[10] - M[9] * M[6]) - M[4] * (M[1] * M[10] - M[9] * M[2]) + M[8] * (M[1] * M[6] - M[5] * M[2]);
			for (const p of mesh.listPrimitives()) {
				const pos = p.getAttribute('POSITION');
				if (!pos || p.getMode() !== 4) continue;
				const nv = pos.getCount();
				const P = new Float32Array(nv * 3), N = new Float32Array(nv * 3), UV = new Float32Array(nv * 2);
				const nrm = p.getAttribute('NORMAL'), uv = p.getAttribute('TEXCOORD_0');
				for (let v = 0; v < nv; v++) {
					pos.getElement(v, tmp);
					P.set(mul(M, tmp[0], tmp[1], tmp[2]), v * 3);
					if (nrm) {
						nrm.getElement(v, tmp);
						const q = mul([M[0], M[1], M[2], 0, M[4], M[5], M[6], 0, M[8], M[9], M[10], 0, 0, 0, 0, 1], tmp[0], tmp[1], tmp[2]);
						const l = Math.hypot(...q) || 1;
						N.set([q[0] / l, q[1] / l, q[2] / l], v * 3);
					} else N.set([0, 1, 0], v * 3);
					if (uv) {
						uv.getElement(v, tmp);
						UV.set([tmp[0], tmp[1]], v * 2);
					}
				}
				const ia = p.getIndices();
				const I = ia ? Uint32Array.from(ia.getArray()) : Uint32Array.from({ length: nv }, (_, k) => k);
				if (det < 0) for (let t = 0; t < I.length; t += 3) [I[t + 1], I[t + 2]] = [I[t + 2], I[t + 1]];
				parts.push({ P, N, UV, I, mat: p.getMaterial() });
			}
		}
		for (const ch of n.listChildren()) visit(ch);
	};
	for (const n of picked) visit(n);
	// Bounds, scale to the real size, ground at y = 0, centred on x/z.
	const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
	for (const p of parts)
		for (let v = 0; v < p.P.length; v += 3)
			for (let k = 0; k < 3; k++) (mn[k] = Math.min(mn[k], p.P[v + k])), (mx[k] = Math.max(mx[k], p.P[v + k]));
	const size = [mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]];
	let s;
	if (c.length) {
		// Boats: length along their longest horizontal axis; rotate so it runs along Z.
		s = c.length / Math.max(size[0], size[2]);
	} else s = c.height / size[1];
	const swap = c.length && size[0] > size[2];
	let cx = (mn[0] + mx[0]) / 2, cz = (mn[2] + mx[2]) / 2;
	// anchor "base": centre on the foot (vertices in the lowest 15%) - poles with arms.
	const band = (lo, hi) => {
		let sx = 0, sz = 0, n = 0;
		for (const p of parts)
			for (let v = 0; v < p.P.length; v += 3) {
				const t = (p.P[v + 1] - mn[1]) / size[1];
				if (t >= lo && t <= hi) (sx += p.P[v]), (sz += p.P[v + 2]), n++;
			}
		return n ? [sx / n, sz / n] : [cx, cz];
	};
	if (c.anchor === 'base') [cx, cz] = band(0, 0.15);
	// arm: rotate about Y so the top of the model (lamp head, sign face) points +Z.
	let yaw = 0;
	if (c.arm) {
		const [tx, tz] = band(0.8, 1);
		yaw = Math.atan2(tx - cx, tz - cz);
	}
	yaw += ((c.turn || 0) * Math.PI) / 180;
	const cy = Math.cos(yaw), sy = Math.sin(yaw);
	const y0 = c.waterline ? mn[1] + size[1] * c.waterline : mn[1];
	for (const p of parts)
		for (let v = 0; v < p.P.length; v += 3) {
			let x = (p.P[v] - cx) * s, y = (p.P[v + 1] - y0) * s, z = (p.P[v + 2] - cz) * s;
			let nx = p.N[v], nz = p.N[v + 2];
			if (swap) [x, z, nx, nz] = [z, -x, nz, -nx];
			if (yaw) [x, z, nx, nz] = [x * cy - z * sy, x * sy + z * cy, nx * cy - nz * sy, nx * sy + nz * cy];
			p.P[v] = x;
			p.P[v + 1] = y;
			p.P[v + 2] = z;
			p.N[v] = nx;
			p.N[v + 2] = nz;
		}
	// Merge by material and simplify to the budget.
	const byMat = new Map();
	for (const p of parts) {
		if (!byMat.has(p.mat)) byMat.set(p.mat, []);
		byMat.get(p.mat).push(p);
	}
	// Alpha-tested foliage (cards) is thinned card by card; opaque parts get the rest of the budget.
	const cardMats = new Set(), alphaMats = new Set();
	for (const mat of byMat.keys()) {
		if (!mat) continue;
		const t = baseTex(mat);
		const hasAlpha = t && t.getImage() ? (await sharp(t.getImage()).metadata()).hasAlpha : false;
		// cards:false = leaf clusters that simplify well (edge collapse keeps them fuller).
		if (c.cards !== false && (mat.getAlphaMode() !== 'OPAQUE' || hasAlpha)) cardMats.add(mat);
		else if (hasAlpha || mat.getAlphaMode() !== 'OPAQUE') alphaMats.add(mat);
	}
	let total = 0, cardTris = 0;
	for (const p of parts) {
		total += p.I.length / 3;
		if (cardMats.has(p.mat)) cardTris += p.I.length / 3;
	}
	const cardBudget = Math.min(cardTris, c.budget * 0.65);
	const cardKeep = cardTris ? Math.min(1, cardBudget / cardTris) : 1;
	const ratio = Math.min(1, (c.budget - cardBudget) / Math.max(1, total - cardTris));
	const doc = new Document();
	const buf = doc.createBuffer(`${key}.bin`);
	const mesh = doc.createMesh(key);
	const texMap = new Map();
	let outTris = 0;
	for (const [mat, list] of byMat) {
		// Weld identical vertices so the simplifier has shared edges to collapse.
		const P = [], N = [], UV = [], I = [];
		const weld = new Map();
		for (const p of list) {
			const rm = new Int32Array(p.P.length / 3).fill(-1);
			for (let v = 0; v < rm.length; v++) {
				const k = `${Math.round(p.P[v * 3] * 1e4)},${Math.round(p.P[v * 3 + 1] * 1e4)},${Math.round(p.P[v * 3 + 2] * 1e4)},${Math.round(p.UV[v * 2] * 1e4)},${Math.round(p.UV[v * 2 + 1] * 1e4)}`;
				if (!weld.has(k)) {
					weld.set(k, P.length / 3);
					P.push(p.P[v * 3], p.P[v * 3 + 1], p.P[v * 3 + 2]);
					N.push(p.N[v * 3], p.N[v * 3 + 1], p.N[v * 3 + 2]);
					UV.push(p.UV[v * 2], p.UV[v * 2 + 1]);
				}
				rm[v] = weld.get(k);
			}
			for (const i of p.I) I.push(rm[i]);
		}
		const Pf = Float32Array.from(P), Nf = Float32Array.from(N);
		let If = Uint32Array.from(I);
		const card = cardMats.has(mat);
		const r = card ? cardKeep : ratio;
		if (card && r < 0.98) {
			// Foliage cards: keep an even subset of whole cards and scale the survivors up about their
			// centre so the canopy keeps its coverage (edge collapse turns cards into shards).
			const par = Int32Array.from({ length: Pf.length / 3 }, (_, k) => k);
			const find = (a) => {
				while (par[a] !== a) a = par[a] = par[par[a]];
				return a;
			};
			for (let t = 0; t < If.length; t += 3) {
				const a = find(If[t]);
				par[find(If[t + 1])] = a;
				par[find(If[t + 2])] = a;
			}
			const islands = new Map();
			for (let t = 0; t < If.length; t += 3) {
				const k = find(If[t]);
				if (!islands.has(k)) islands.set(k, []);
				islands.get(k).push(t);
			}
			if (islands.size >= 12) {
				const keys = [...islands.keys()].sort((a, b) => ((a * 2654435761) >>> 0) - ((b * 2654435761) >>> 0));
				const keep = keys.slice(0, Math.max(1, Math.round(keys.length * r)));
				const grow = Math.min(1.45, 1 / Math.sqrt(keep.length / keys.length));
				const out = [];
				const moved = new Set();
				for (const k of keep) {
					const tris = islands.get(k);
					let mx2 = 0, my2 = 0, mz2 = 0, n = 0;
					for (const t of tris) for (let e = 0; e < 3; e++) (mx2 += Pf[If[t + e] * 3]), (my2 += Pf[If[t + e] * 3 + 1]), (mz2 += Pf[If[t + e] * 3 + 2]), n++;
					(mx2 /= n), (my2 /= n), (mz2 /= n);
					for (const t of tris)
						for (let e = 0; e < 3; e++) {
							const v = If[t + e];
							out.push(v);
							if (moved.has(v)) continue;
							moved.add(v);
							Pf[v * 3] = mx2 + (Pf[v * 3] - mx2) * grow;
							Pf[v * 3 + 1] = my2 + (Pf[v * 3 + 1] - my2) * grow;
							Pf[v * 3 + 2] = mz2 + (Pf[v * 3 + 2] - mz2) * grow;
						}
				}
				If = Uint32Array.from(out);
			}
		} else if (r < 0.98 && If.length > 150) {
			const target = Math.max(12, Math.floor((If.length / 3) * r) * 3);
			let err = 0.01;
			for (let a = 0; a < 5; a++, err *= 2) {
				const [si] = MeshoptSimplifier.simplifyWithAttributes(If, Pf, 3, Nf, 3, [0.3, 0.3, 0.3], null, target, err, a > 1 ? ['Prune'] : []);
				if (si.length >= 3) If = si;
				if (If.length <= target * 1.15) break;
			}
		}
		const nv = Pf.length / 3;
		const remap = new Int32Array(nv).fill(-1);
		let cnt = 0;
		for (const i of If) if (remap[i] < 0) remap[i] = cnt++;
		const pick = (src2, sz) => {
			const o = new Float32Array(cnt * sz);
			for (let v = 0; v < nv; v++) if (remap[v] >= 0) for (let k = 0; k < sz; k++) o[remap[v] * sz + k] = src2[v * sz + k];
			return o;
		};
		const Ic = cnt > 65535 ? new Uint32Array(If.length) : new Uint16Array(If.length);
		for (let k = 0; k < If.length; k++) Ic[k] = remap[If[k]];
		outTris += Ic.length / 3;
		// Material: copy factors + base colour / normal textures (resized).
		const m2 = doc.createMaterial(mat ? mat.getName() : 'mat');
		if (mat) {
			const sg = mat.getExtension('KHR_materials_pbrSpecularGlossiness');
			m2.setBaseColorFactor(sg ? sg.getDiffuseFactor() : mat.getBaseColorFactor());
			m2.setRoughnessFactor(sg ? 1 - sg.getGlossinessFactor() * 0.5 : mat.getRoughnessFactor()).setMetallicFactor(sg ? 0 : mat.getMetallicFactor());
			const cut = card || alphaMats.has(mat);
			m2.setAlphaMode(cut ? 'MASK' : mat.getAlphaMode()).setAlphaCutoff(cut ? 0.4 : mat.getAlphaCutoff()).setDoubleSided(cut || mat.getDoubleSided());
			for (const [getter, setter] of [['base', 'setBaseColorTexture'], ['getNormalTexture', 'setNormalTexture']]) {
				const t = getter === 'base' ? baseTex(mat) : mat[getter]();
				if (!t || !t.getImage()) continue;
				if (!texMap.has(t)) {
					const meta = await sharp(t.getImage()).metadata();
					const alpha = getter === 'base' && meta.hasAlpha;
					let sh = sharp(t.getImage()).resize({ width: c.texture_max, height: c.texture_max, fit: 'inside', withoutEnlargement: true });
					const img = alpha ? await sh.png().toBuffer() : await sh.jpeg({ quality: 88 }).toBuffer();
					const nt = doc.createTexture(`${key}_${texMap.size}`).setImage(img).setMimeType(alpha ? 'image/png' : 'image/jpeg').setURI(`${key}_${texMap.size}.${alpha ? 'png' : 'jpg'}`);
					texMap.set(t, nt);
					// Foliage textures with alpha: cut-out.
					if (alpha && m2.getAlphaMode() === 'OPAQUE') m2.setAlphaMode('MASK').setAlphaCutoff(0.4).setDoubleSided(true);
				}
				m2[setter](texMap.get(t));
			}
		}
		mesh.addPrimitive(
			doc.createPrimitive()
				.setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(pick(Pf, 3)).setBuffer(buf))
				.setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(pick(Nf, 3)).setBuffer(buf))
				.setAttribute('TEXCOORD_0', doc.createAccessor().setType('VEC2').setArray(pick(Float32Array.from(UV), 2)).setBuffer(buf))
				.setIndices(doc.createAccessor().setType('SCALAR').setArray(Ic).setBuffer(buf))
				.setMaterial(m2),
		);
	}
	doc.createScene('Scene').addChild(doc.createNode(key).setMesh(mesh));
	const outDir = path.join(OUT, key);
	fs.rmSync(outDir, { recursive: true, force: true });
	fs.mkdirSync(outDir, { recursive: true });
	await io.write(path.join(outDir, `${key}.gltf`), doc);
	const sz = size.map((v) => +(v * s).toFixed(2));
	fs.writeFileSync(path.join(outDir, `${key}.json`), JSON.stringify({ key, credit, size: swap ? [sz[2], sz[1], sz[0]] : sz, triangles: outTris }, null, 1));
	console.log(`${key}: ${total} -> ${outTris} tris, size ${sz.join(' x ')} m, ${byMat.size} materials`);
}

const only = process.argv.slice(2);
for (const [key, c] of Object.entries(cfg)) {
	if (only.length && !only.includes(key)) continue;
	try {
		await bakeProp(key, c);
	} catch (e) {
		console.log('FAILED', key, e.message);
	}
}
