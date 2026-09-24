// Car bake: raw Sketchfab/glTF car -> game-ready GLB + metadata.
//   node bake.mjs [key ...]        (keys from cars.json "cars" and "traffic"; none = all)
// Input  build/carbake/raw/<key>.glb (+ <key>.json licence record from fetch.mjs)
// Output godot/assets/cars/<key>/<key>.glb + <key>.json
//
// Steps: bake node transforms -> drop junk (config regex, ground planes) -> length along Z, Y up ->
// scale to the real length -> nose to -Z (lamp positions) -> split every primitive into connected
// islands -> find the four wheels from the tyre islands -> every island fully inside a wheel
// cylinder joins that wheel (callipers stay non-spinning) -> wheels re-centred on their hubs ->
// ground at y=0, origin mid-wheelbase -> materials tagged "<class>:<name>" (paint, glass, light_*,
// tyre, rim, caliper, disc, chrome, interior, other) -> merged per material -> simplified to the
// triangle budget (interior decimated harder) -> textures resized, WebP -> PNG.
// Output nodes: Body, Wheel_FL/FR/RL/RR (hub pivots) with children Spin (tyre/rim/disc) and
// Caliper. Car faces -Z, +X is its right side (the game's convention).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO, Primitive } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, textureCompress } from '@gltf-transform/functions';
import draco3d from 'draco3dgltf';
import { MeshoptDecoder, MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const cfgAll = JSON.parse(fs.readFileSync(path.join(here, 'cars.json'), 'utf8'));
const RAW = path.join(root, 'build/carbake/raw');
const OUT = path.join(root, 'godot/assets/cars');

await MeshoptDecoder.ready;
await MeshoptSimplifier.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
	'draco3d.decoder': await draco3d.createDecoderModule(),
	'meshopt.decoder': MeshoptDecoder,
});

// ---- Material classes ---------------------------------------------------------------------------
const DEFAULT_RX = {
	reverse: /reverse|retro/i,
	signal: /signal|indicator|blinker|turn_?l|orange|amber|clignot|frecce/i,
	tail: /tail|rear.?light|rear_?lamp|brake.?light|breake?_?light|posterior|stop.?l|red.?light|redlight|lightred|glassred|red_lights|feu.?ar|lucipost/i,
	head: /head.?light|headlamp|hd_?light|front.?light|anterior|fari|phare|low.?beam|high.?beam|hl_front|projector|drl|running.?light|run_lights|lens/i,
	glass: /glass|window|windscreen|windshield|vetro|verre|vitre|win_glass|\bglas\b/i,
	tyre: /tire|tyre|rubber|pneu|gomma|rezina|michelin|reifen/i,
	caliper: /caliper|calliper|pinza|brembo/i,
	disc: /disc|disk|rotor/i,
	rim: /\brim|rims|_rim|wheel|cerch|jante|alloy|felge/i,
	paint: /paint|carros|livrea|body_?colou?r|bodypaint|car_?paint|main_color|\|primary|coloured/i,
	interior: /interior|\|int_|_int\b|\bint\b|seat|leather|dash|cockpit|carpet|belt|steer|pedal|gauge|display|monitor|upholster|alcantara|tappet|skin_spugna|volante/i,
	chrome: /chrome|chrom/i,
	light: /light|lamp|lucci|luci/i,
};
const CLASS_ORDER = ['paint', 'reverse', 'signal', 'tail', 'head', 'glass', 'tyre', 'caliper', 'disc', 'rim', 'interior', 'chrome', 'light'];

function classify(name, cfg) {
	for (const cls of CLASS_ORDER) {
		const key = cls === 'light' ? null : cls;
		if (key && cfg[key] && new RegExp(cfg[key], 'i').test(name)) return map(cls);
	}
	for (const cls of CLASS_ORDER) {
		if (cls === 'paint') continue; // paint only by config or by the fallback below
		if (DEFAULT_RX[cls].test(name)) {
			// "glass" on a lamp is a lamp lens
			if (cls === 'glass' && DEFAULT_RX.light.test(name)) return 'light_head';
			return map(cls);
		}
	}
	// A configured paint regex is authoritative (names like "..._PAINT_2" are often not the body).
	if (!cfg.paint && DEFAULT_RX.paint.test(name)) return 'paint';
	return 'other';
	function map(c) {
		return { reverse: 'light_reverse', signal: 'light_signal', tail: 'light_tail', head: 'light_head', light: 'light_misc' }[c] || c;
	}
}

// ---- Geometry helpers ---------------------------------------------------------------------------
function xform(M, x, y, z) {
	return [M[0] * x + M[4] * y + M[8] * z + M[12], M[1] * x + M[5] * y + M[9] * z + M[13], M[2] * x + M[6] * y + M[10] * z + M[14]];
}
function normalMatrix(M) {
	const a = M[0], b = M[4], c = M[8], d = M[1], e = M[5], f = M[9], g = M[2], h = M[6], i = M[10];
	const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
	const det = a * A + b * B + c * C;
	const inv = [A, -(b * i - c * h), b * f - c * e, B, a * i - c * g, -(a * f - c * d), C, -(a * h - b * g), a * e - b * d].map((v) => v / det);
	// inverse (row-major 3x3) transposed -> returns row-major normal matrix
	return { n: [inv[0], inv[3], inv[6], inv[1], inv[4], inv[7], inv[2], inv[5], inv[8]], det };
}

function extractParts(doc) {
	const parts = [];
	const scene = doc.getRoot().getDefaultScene() || doc.getRoot().listScenes()[0];
	const tmp = [];
	scene.traverse((node) => {
		const mesh = node.getMesh();
		if (!mesh) return;
		const M = node.getWorldMatrix();
		const { n: NM, det } = normalMatrix(M);
		for (const prim of mesh.listPrimitives()) {
			if (prim.getMode() !== Primitive.Mode.TRIANGLES) continue;
			const pos = prim.getAttribute('POSITION');
			if (!pos) continue;
			const nv = pos.getCount();
			const P = new Float32Array(nv * 3);
			for (let v = 0; v < nv; v++) {
				pos.getElement(v, tmp);
				const p = xform(M, tmp[0], tmp[1], tmp[2]);
				P.set(p, v * 3);
			}
			let N = null;
			const nrm = prim.getAttribute('NORMAL');
			if (nrm) {
				N = new Float32Array(nv * 3);
				for (let v = 0; v < nv; v++) {
					nrm.getElement(v, tmp);
					let x = NM[0] * tmp[0] + NM[1] * tmp[1] + NM[2] * tmp[2];
					let y = NM[3] * tmp[0] + NM[4] * tmp[1] + NM[5] * tmp[2];
					let z = NM[6] * tmp[0] + NM[7] * tmp[1] + NM[8] * tmp[2];
					const l = Math.hypot(x, y, z) || 1;
					N[v * 3] = x / l;
					N[v * 3 + 1] = y / l;
					N[v * 3 + 2] = z / l;
				}
			}
			const readAttr = (name, size) => {
				const a = prim.getAttribute(name);
				if (!a) return null;
				const s = a.getElementSize();
				const out = new Float32Array(nv * size);
				for (let v = 0; v < nv; v++) {
					a.getElement(v, tmp);
					for (let k = 0; k < size; k++) out[v * size + k] = k < s ? tmp[k] : 1;
				}
				return out;
			};
			const idxAcc = prim.getIndices();
			let idx = idxAcc ? Uint32Array.from(idxAcc.getArray()) : Uint32Array.from({ length: nv }, (_, k) => k);
			if (det < 0)
				for (let t = 0; t < idx.length; t += 3) {
					const s = idx[t + 1];
					idx[t + 1] = idx[t + 2];
					idx[t + 2] = s;
				}
			const mat = prim.getMaterial();
			parts.push({
				node: node.getName() || mesh.getName() || '',
				mat,
				matName: mat ? mat.getName() || '' : '',
				P, N,
				UV0: readAttr('TEXCOORD_0', 2),
				UV1: readAttr('TEXCOORD_1', 2),
				C: readAttr('COLOR_0', 4),
				idx,
			});
		}
	});
	return parts;
}

function bboxOf(P, idxList) {
	const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
	const visit = (v) => {
		for (let k = 0; k < 3; k++) {
			const x = P[v * 3 + k];
			if (x < mn[k]) mn[k] = x;
			if (x > mx[k]) mx[k] = x;
		}
	};
	if (idxList) for (const v of idxList) visit(v);
	else for (let v = 0; v < P.length / 3; v++) visit(v);
	return { mn, mx };
}
function unionBox(boxes) {
	const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
	for (const b of boxes) for (let k = 0; k < 3; k++) {
		mn[k] = Math.min(mn[k], b.mn[k]);
		mx[k] = Math.max(mx[k], b.mx[k]);
	}
	return { mn, mx };
}
const size = (b) => [b.mx[0] - b.mn[0], b.mx[1] - b.mn[1], b.mx[2] - b.mn[2]];
const center = (b) => [(b.mx[0] + b.mn[0]) / 2, (b.mx[1] + b.mn[1]) / 2, (b.mx[2] + b.mn[2]) / 2];

function applyToParts(parts, fnP, fnN) {
	for (const p of parts) {
		for (let v = 0; v < p.P.length; v += 3) {
			const r = fnP(p.P[v], p.P[v + 1], p.P[v + 2]);
			p.P[v] = r[0];
			p.P[v + 1] = r[1];
			p.P[v + 2] = r[2];
			if (p.N && fnN) {
				const q = fnN(p.N[v], p.N[v + 1], p.N[v + 2]);
				p.N[v] = q[0];
				p.N[v + 1] = q[1];
				p.N[v + 2] = q[2];
			}
		}
	}
}

// Connected components of one part's triangles -> [{tris: Uint32Array (triangle ids), verts: Set, box}]
function islands(part) {
	const nv = part.P.length / 3;
	const parent = new Int32Array(nv);
	for (let i = 0; i < nv; i++) parent[i] = i;
	const find = (x) => {
		while (parent[x] !== x) {
			parent[x] = parent[parent[x]];
			x = parent[x];
		}
		return x;
	};
	// Join vertices that share a position too (UV seams split vertices; the island is one piece).
	const byPos = new Map();
	for (let v = 0; v < nv; v++) {
		const k = `${Math.round(part.P[v * 3] * 1e5)},${Math.round(part.P[v * 3 + 1] * 1e5)},${Math.round(part.P[v * 3 + 2] * 1e5)}`;
		const o = byPos.get(k);
		if (o === undefined) byPos.set(k, v);
		else parent[find(v)] = find(o);
	}
	const idx = part.idx;
	for (let t = 0; t < idx.length; t += 3) {
		const a = find(idx[t]), b = find(idx[t + 1]), c = find(idx[t + 2]);
		parent[b] = a;
		parent[find(c)] = find(a);
	}
	const groups = new Map();
	for (let t = 0; t < idx.length / 3; t++) {
		const r = find(idx[t * 3]);
		let g = groups.get(r);
		if (!g) groups.set(r, (g = []));
		g.push(t);
	}
	const out = [];
	for (const tris of groups.values()) {
		const verts = new Set();
		for (const t of tris) {
			verts.add(idx[t * 3]);
			verts.add(idx[t * 3 + 1]);
			verts.add(idx[t * 3 + 2]);
		}
		out.push({ tris, verts, box: bboxOf(part.P, verts) });
	}
	return out;
}

function triArea(P, a, b, c) {
	const ux = P[b * 3] - P[a * 3], uy = P[b * 3 + 1] - P[a * 3 + 1], uz = P[b * 3 + 2] - P[a * 3 + 2];
	const vx = P[c * 3] - P[a * 3], vy = P[c * 3 + 1] - P[a * 3 + 1], vz = P[c * 3 + 2] - P[a * 3 + 2];
	return 0.5 * Math.hypot(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx);
}

// ---- Main ---------------------------------------------------------------------------------------
async function bake(key, cfg, isTraffic) {
	const src = path.join(RAW, `${key}.glb`);
	if (!fs.existsSync(src)) {
		console.log('MISSING', key);
		return;
	}
	const creditPath = path.join(RAW, `${key}.json`);
	const credit = fs.existsSync(creditPath) ? JSON.parse(fs.readFileSync(creditPath, 'utf8').replace(/^﻿/, '')) : {};
	const doc = await io.read(src);
	// Pose fixes before baking (e.g. close a door modelled open): node_rot = {name: [x,y,z,w]}.
	for (const [name, q] of Object.entries(cfg.node_rot || {})) {
		const n = doc.getRoot().listNodes().find((x) => x.getName() === name);
		if (n) n.setRotation(q);
		else console.log('   node_rot: no node', name);
	}
	let parts = extractParts(doc).filter((p) => p.idx.length >= 3);
	const log = [];

	// Junk: config regex, invisible materials.
	const drop = cfg.drop ? new RegExp(cfg.drop, 'i') : null;
	parts = parts.filter((p) => {
		const nm = `${p.node}|${p.matName}`;
		if (drop && drop.test(nm)) return false;
		if (p.mat && p.mat.getAlpha() === 0 && p.mat.getAlphaMode() !== 'OPAQUE') return false;
		return true;
	});
	// Ground planes / backdrops: flat parts covering most of the scene footprint.
	for (let pass = 0; pass < 2; pass++) {
		const boxes = parts.map((p) => bboxOf(p.P));
		const U = size(unionBox(boxes));
		parts = parts.filter((p, i) => {
			const s = size(boxes[i]);
			const flat = s[1] < 0.03 * Math.max(s[0], s[2]);
			if (flat && s[0] > 0.7 * U[0] && s[2] > 0.7 * U[2] && parts.length > 3) {
				log.push(`dropped plane ${p.node}|${p.matName}`);
				return false;
			}
			return true;
		});
	}

	// Axes: Y up (if Y is the longest axis the file is Z-up), length along Z.
	let U = size(unionBox(parts.map((p) => bboxOf(p.P))));
	if (U[1] > U[0] && U[1] > U[2]) {
		applyToParts(parts, (x, y, z) => [x, z, -y], (x, y, z) => [x, z, -y]);
		log.push('Z-up source rotated');
		U = size(unionBox(parts.map((p) => bboxOf(p.P))));
	}
	if (U[0] > U[2]) {
		applyToParts(parts, (x, y, z) => [z, y, -x], (x, y, z) => [z, y, -x]);
		U = size(unionBox(parts.map((p) => bboxOf(p.P))));
	}
	const s = cfg.length / U[2];
	applyToParts(parts, (x, y, z) => [x * s, y * s, z * s], null);

	// Classes.
	for (const p of parts) p.cls = classify(`${p.node}|${p.matName}`, cfg);
	// Paint fallback: biggest-area "other" material that isn't near-black.
	if (!parts.some((p) => p.cls === 'paint')) {
		const area = new Map();
		for (const p of parts) {
			if (p.cls !== 'other' || !p.mat) continue;
			const c = p.mat.getBaseColorFactor();
			if (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] < 0.02 && !p.mat.getBaseColorTexture()) continue;
			let a = 0;
			for (let t = 0; t < p.idx.length; t += 3) a += triArea(p.P, p.idx[t], p.idx[t + 1], p.idx[t + 2]);
			area.set(p.mat, (area.get(p.mat) || 0) + a);
		}
		let best = null, ba = 0;
		for (const [m, a] of area) if (a > ba) (best = m), (ba = a);
		if (best) {
			for (const p of parts) if (p.mat === best) p.cls = 'paint';
			log.push(`paint fallback -> ${best.getName()}`);
		}
	}

	// Nose to -Z: head lamps ahead of tail lamps.
	const centroidZ = (clsList) => {
		let sum = 0, n = 0;
		for (const p of parts) if (clsList.includes(p.cls)) for (let v = 2; v < p.P.length; v += 3) (sum += p.P[v]), n++;
		return n ? sum / n : null;
	};
	const boxAll = unionBox(parts.map((p) => bboxOf(p.P)));
	const cz0 = center(boxAll)[2];
	let flip = false;
	if (cfg.flip !== undefined) flip = cfg.flip;
	else {
		const hz = centroidZ(['light_head']), tz = centroidZ(['light_tail']);
		if (hz !== null && tz !== null) flip = hz > tz;
		else if (tz !== null) flip = tz < cz0;
		else if (hz !== null) flip = hz > cz0;
		else log.push('WARNING: no lamps found to orient the nose; assuming -Z');
	}
	if (flip) applyToParts(parts, (x, y, z) => [-x, y, -z], (x, y, z) => [-x, y, -z]);

	// Islands.
	const isl = [];
	for (const p of parts) for (const i of islands(p)) isl.push({ part: p, ...i });
	const B = unionBox(isl.map((i) => i.box));
	const BC = center(B), BS = size(B);

	// Wheels from tyre islands (fallback: rim islands; then round islands touching the ground).
	const quad = (c) => (c[0] < BC[0] ? 0 : 1) + (c[2] < BC[2] ? 0 : 2); // 0 FL,1 FR,2 RL,3 RR
	// A road wheel is round (side view), touches the ground and sits outboard. Spare wheels on
	// tailgates, steering wheels and window seals fail one of those.
	const roundGround = (i) => {
		const sz = size(i.box);
		const ratio = sz[1] / Math.max(sz[2], 1e-6);
		// x-extent up to 0.9 d: front wheels are often modelled steered (un-steered below).
		return sz[1] > 0.12 * BS[1] && ratio > 0.8 && ratio < 1.25 && sz[0] < 0.9 * sz[1] &&
			i.box.mn[1] < B.mn[1] + 0.06 * BS[1] && Math.abs(center(i.box)[0] - BC[0]) > 0.2 * BS[0];
	};
	const pick = (pred) => {
		const q = [[], [], [], []];
		for (const i of isl) if (pred(i)) q[quad(center(i.box))].push(i);
		return q;
	};
	if (process.env.CARBAKE_DEBUG) {
		console.log('  scene box', B.mn.map((v) => v.toFixed(3)).join(','), '..', B.mx.map((v) => v.toFixed(3)).join(','));
		for (const i of isl)
			if (i.part.cls === 'tyre' || i.part.cls === 'rim')
				console.log('  ', i.part.cls, i.part.matName, 'size', size(i.box).map((v) => v.toFixed(3)).join(','), 'min', i.box.mn.map((v) => v.toFixed(3)).join(','), 'round+ground', roundGround(i));
	}
	let q = pick((i) => i.part.cls === 'tyre' && roundGround(i));
	if (q.some((l) => l.length === 0)) q = pick((i) => (i.part.cls === 'tyre' || i.part.cls === 'rim') && roundGround(i));
	if (q.some((l) => l.length === 0)) {
		q = pick(roundGround);
		log.push('wheels from round ground-touching islands');
	}
	let wheels = null;
	if (q.every((l) => l.length > 0)) {
		wheels = q.map((list) => {
			// Tallest candidate is the tyre; candidates whose centre lies inside it join (tread/sidewall pieces).
			list.sort((a, b) => size(b.box)[1] - size(a.box)[1]);
			const main = list[0];
			const inside = (i) => {
				const c = center(i.box);
				return c[1] > main.box.mn[1] && c[1] < main.box.mx[1] && c[2] > main.box.mn[2] && c[2] < main.box.mx[2] && Math.abs(c[0] - center(main.box)[0]) < 0.25;
			};
			const box = unionBox(list.filter(inside).map((i) => i.box));
			const c = center(box), sz = size(box);
			return { c, r: Math.max(sz[1], sz[2]) / 2, w: sz[0], box };
		});
		// Sanity: roughly symmetric radii.
		const rs = wheels.map((w) => w.r);
		if (Math.max(...rs) > 1.6 * Math.min(...rs)) {
			log.push(`WARNING: odd wheel radii ${rs.map((r) => r.toFixed(2))}`);
		}
	} else log.push('WARNING: wheels not found (procedural wheels will be used)');

	// Assign islands to wheels.
	if (wheels) {
		for (const i of isl) {
			if (['paint', 'glass', 'interior'].includes(i.part.cls)) continue;
			const c = center(i.box), sz = size(i.box);
			for (let k = 0; k < 4; k++) {
				const w = wheels[k];
				const m = 0.05 * w.r;
				const outward = w.c[0] > BC[0] ? 1 : -1;
				const xin = outward > 0 ? i.box.mn[0] >= w.box.mn[0] - 0.14 : i.box.mx[0] <= w.box.mx[0] + 0.14;
				const xout = outward > 0 ? i.box.mx[0] <= w.box.mx[0] + 0.04 : i.box.mn[0] >= w.box.mn[0] - 0.04;
				const inY = Math.abs(c[1] - w.c[1]) + sz[1] / 2 <= w.r + m;
				const inZ = Math.abs(c[2] - w.c[2]) + sz[2] / 2 <= w.r + m;
				if (xin && xout && inY && inZ) {
					i.wheel = k;
					i.caliper = i.part.cls === 'caliper';
					break;
				}
			}
		}
		// Un-steer: the tyre's axle is its direction of least spread seen from above (PCA on x/z).
		for (let k = 0; k < 4; k++) {
			const w = wheels[k];
			const tyres = isl.filter((i) => i.wheel === k && size(i.box)[1] > 0.8 * 2 * w.r);
			let n = 0, mx = 0, mz = 0;
			for (const i of tyres) for (const v of i.verts) (mx += i.part.P[v * 3]), (mz += i.part.P[v * 3 + 2]), n++;
			if (n < 16) continue;
			mx /= n;
			mz /= n;
			let sxx = 0, sxz = 0, szz = 0;
			for (const i of tyres)
				for (const v of i.verts) {
					const x = i.part.P[v * 3] - mx, z = i.part.P[v * 3 + 2] - mz;
					sxx += x * x;
					sxz += x * z;
					szz += z * z;
				}
			let theta = 0.5 * Math.atan2(2 * sxz, sxx - szz) + Math.PI / 2; // axle = normal to the rolling plane
			while (theta > Math.PI / 2) theta -= Math.PI;
			while (theta <= -Math.PI / 2) theta += Math.PI;
			if (Math.abs(theta) < (1.5 * Math.PI) / 180) continue;
			const cs = Math.cos(theta), sn = Math.sin(theta);
			const rot = (arr, v, ox, oz) => {
				const x = arr[v * 3] - ox, z = arr[v * 3 + 2] - oz;
				arr[v * 3] = ox + x * cs + z * sn;
				arr[v * 3 + 2] = oz - x * sn + z * cs;
			};
			const mine = isl.filter((i) => i.wheel === k);
			for (const i of mine)
				for (const v of i.verts) {
					rot(i.part.P, v, w.c[0], w.c[2]);
					if (i.part.N) rot(i.part.N, v, 0, 0);
				}
			for (const i of mine) i.box = bboxOf(i.part.P, i.verts);
			const box = unionBox(mine.filter((i) => size(i.box)[1] > 0.8 * 2 * w.r).map((i) => i.box));
			w.box = box;
			w.c = center(box);
			w.w = size(box)[0];
			log.push(`un-steered ${['FL', 'FR', 'RL', 'RR'][k]} by ${((theta * 180) / Math.PI).toFixed(1)} deg`);
			w.steered = true;
		}
		// Only front wheels steer: a steered rear pair means the nose is really at +Z. With no lamp
		// evidence (or config) to the contrary, turn the car round.
		const rearSteered = wheels[2].steered && wheels[3].steered && !wheels[0].steered && !wheels[1].steered;
		const lampsKnown = parts.some((p) => p.cls === 'light_head' || p.cls === 'light_tail');
		if (rearSteered && cfg.flip === undefined && !lampsKnown) {
			const turn = (x, y, z) => [-x + 2 * BC[0], y, -z + 2 * BC[2]];
			applyToParts(parts, turn, (x, y, z) => [-x, y, -z]);
			for (const i of isl) i.box = bboxOf(i.part.P, i.verts);
			for (const w of wheels) {
				w.c = turn(...w.c);
				w.box = { mn: [2 * BC[0] - w.box.mx[0], w.box.mn[1], 2 * BC[2] - w.box.mx[2]], mx: [2 * BC[0] - w.box.mn[0], w.box.mx[1], 2 * BC[2] - w.box.mn[2]] };
			}
			// Wheel slots follow the new corners.
			const reorder = [3, 2, 1, 0];
			const nw = reorder.map((k) => wheels[k]);
			for (const i of isl) if (i.wheel !== undefined) i.wheel = reorder.indexOf(i.wheel);
			wheels.splice(0, 4, ...nw);
			flip = !flip;
			log.push('steered pair was at the back: turned the car round');
		}
	}

	// Frame: ground at y=0 (tyre bottoms), x centred on the track, origin mid-wheelbase.
	let dx = -BC[0], dy = -B.mn[1], dz = -BC[2];
	if (wheels) {
		dx = -wheels.reduce((a, w) => a + w.c[0], 0) / 4;
		dy = -wheels.reduce((a, w) => a + (w.c[1] - w.r), 0) / 4;
		dz = -(wheels[0].c[2] + wheels[1].c[2] + wheels[2].c[2] + wheels[3].c[2]) / 4;
	}
	applyToParts(parts, (x, y, z) => [x + dx, y + dy, z + dz], null);
	if (wheels)
		for (const w of wheels) {
			w.c = [w.c[0] + dx, w.c[1] + dy, w.c[2] + dz];
			w.box = { mn: [w.box.mn[0] + dx, w.box.mn[1] + dy, w.box.mn[2] + dz], mx: [w.box.mx[0] + dx, w.box.mx[1] + dy, w.box.mx[2] + dz] };
		}

	// Group islands -> output buckets: key = group|material|class.
	const buckets = new Map();
	for (const i of isl) {
		const grp = i.wheel === undefined ? 'Body' : `${['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'][i.wheel]}/${i.caliper ? 'Caliper' : 'Spin'}`;
		const bk = `${grp}\u0000${i.part.cls}\u0000${i.part.matName}`;
		let b = buckets.get(bk);
		if (!b) buckets.set(bk, (b = { grp, cls: i.part.cls, mat: i.part.mat, items: [] }));
		b.items.push(i);
	}

	// Triangle budget: interior decimated at 40% of the exterior ratio.
	const budget = cfg.budget || cfgAll.defaults.budget;
	let tInt = 0, tExt = 0;
	for (const i of isl) (i.part.cls === 'interior' ? (tInt += i.tris.length) : (tExt += i.tris.length));
	const ratio = Math.min(1, budget / (tExt + 0.4 * tInt));

	// Build output document in place: new meshes on the same materials, old scene dropped.
	const r0 = doc.getRoot();
	const scene = r0.getDefaultScene() || r0.listScenes()[0];
	for (const n of scene.listChildren()) scene.removeChild(n);
	for (const sc of r0.listScenes()) if (sc !== scene) sc.dispose();
	for (const sk of r0.listSkins()) sk.dispose();
	for (const an of r0.listAnimations()) an.dispose();
	const buf = r0.listBuffers()[0] || doc.createBuffer();
	const nodes = {};
	const getNode = (grp) => {
		if (nodes[grp]) return nodes[grp];
		const [a, b] = grp.split('/');
		let n;
		if (!b) {
			n = doc.createNode(a);
			scene.addChild(n);
		} else {
			const parent = getNode(a);
			n = doc.createNode(`${a}_${b}`);
			parent.addChild(n);
		}
		if (!b && a.startsWith('Wheel_')) {
			const w = wheels[['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'].indexOf(a)];
			n.setTranslation(w.c);
		}
		n.setMesh(doc.createMesh(n.getName()));
		return (nodes[grp] = n);
	};
	const matClone = new Map();
	let triOut = 0;
	for (const b of buckets.values()) {
		// Merge islands into one vertex/index set.
		const vmap = new Map();
		const order = [];
		const idx = [];
		for (const i of b.items) {
			const pi = i.part.idx;
			for (const t of i.tris)
				for (let k = 0; k < 3; k++) {
					const vv = pi[t * 3 + k];
					// Weld on equal attributes: triangle-soup sources otherwise can't be simplified.
					const pp = i.part;
					const q5 = (x) => Math.round(x * 1e5), q3 = (x) => Math.round(x * 1e3);
					let kk = `${q5(pp.P[vv * 3])},${q5(pp.P[vv * 3 + 1])},${q5(pp.P[vv * 3 + 2])}`;
					if (pp.N) kk += `|${q3(pp.N[vv * 3])},${q3(pp.N[vv * 3 + 1])},${q3(pp.N[vv * 3 + 2])}`;
					if (pp.UV0) kk += `|${q5(pp.UV0[vv * 2])},${q5(pp.UV0[vv * 2 + 1])}`;
					if (pp.C) kk += `|${q3(pp.C[vv * 4])},${q3(pp.C[vv * 4 + 1])},${q3(pp.C[vv * 4 + 2])}`;
					if (!pp.N) kk = `${partId(pp)}:${vv}`;
					let o = vmap.get(kk);
					if (o === undefined) {
						o = order.length;
						vmap.set(kk, o);
						order.push([i.part, vv]);
					}
					idx.push(o);
				}
		}
		const nv = order.length;
		const P = new Float32Array(nv * 3), N = new Float32Array(nv * 3);
		const hasUV0 = order.every(([p]) => p.UV0), hasUV1 = order.every(([p]) => p.UV1), hasC = order.every(([p]) => p.C);
		const UV0 = hasUV0 ? new Float32Array(nv * 2) : null, UV1 = hasUV1 ? new Float32Array(nv * 2) : null, C = hasC ? new Float32Array(nv * 4) : null;
		const [grpA, grpB] = b.grp.split('/');
		const hub = grpB ? wheels[['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'].indexOf(grpA)].c : [0, 0, 0];
		order.forEach(([p, v], o) => {
			P[o * 3] = p.P[v * 3] - hub[0];
			P[o * 3 + 1] = p.P[v * 3 + 1] - hub[1];
			P[o * 3 + 2] = p.P[v * 3 + 2] - hub[2];
			if (p.N) N.set(p.N.subarray(v * 3, v * 3 + 3), o * 3);
			if (UV0) UV0.set(p.UV0.subarray(v * 2, v * 2 + 2), o * 2);
			if (UV1) UV1.set(p.UV1.subarray(v * 2, v * 2 + 2), o * 2);
			if (C) C.set(p.C.subarray(v * 4, v * 4 + 4), o * 4);
		});
		let I = Uint32Array.from(idx);
		// Missing normals -> area-weighted smooth normals.
		if (order.some(([p]) => !p.N)) computeNormals(P, I, N);
		// Simplify.
		const r = b.cls === 'interior' ? ratio * 0.4 : ratio;
		if (r < 0.98 && I.length > 300) {
			const target = Math.max(36, Math.floor((I.length / 3) * r) * 3);
			// Start with a tight error bound and relax it until the budget is met (max 8x).
			let err = b.cls === 'interior' ? 0.03 : 0.006;
			for (let attempt = 0; attempt < 4; attempt++, err *= 2) {
				const [si] = MeshoptSimplifier.simplify(I, P, 3, target, err, []);
				if (si.length >= 3) I = si;
				if (I.length <= target * 1.1) break;
			}
		}
		// Compact.
		const remap = new Int32Array(nv).fill(-1);
		let cnt = 0;
		for (const v of I) if (remap[v] < 0) remap[v] = cnt++;
		const pick = (src, sz) => {
			if (!src) return null;
			const out = new Float32Array(cnt * sz);
			for (let v = 0; v < nv; v++) if (remap[v] >= 0) out.set(src.subarray(v * sz, v * sz + sz), remap[v] * sz);
			return out;
		};
		const Pc = pick(P, 3), Nc = pick(N, 3), U0 = pick(UV0, 2), U1 = pick(UV1, 2), Cc = pick(C, 4);
		const Ic = cnt > 65535 ? new Uint32Array(I.length) : new Uint16Array(I.length);
		for (let k = 0; k < I.length; k++) Ic[k] = remap[I[k]];
		triOut += Ic.length / 3;

		// Material tagged with its class (cloned when one source material serves two classes).
		let mat = b.mat;
		if (mat) {
			const tag = `${b.cls}:${mat.getName() || 'mat'}`;
			const ck = `${mat.getName()}\u0000${b.cls}`;
			if (!matClone.has(ck)) {
				const already = [...matClone.values()].includes(mat);
				const m = already ? mat.clone() : mat;
				m.setName(tag);
				matClone.set(ck, m);
			}
			mat = matClone.get(ck);
		} else {
			mat = doc.createMaterial(`${b.cls}:none`);
			matClone.set(Math.random(), mat);
		}
		const prim = doc.createPrimitive()
			.setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(Pc).setBuffer(buf))
			.setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(Nc).setBuffer(buf))
			.setIndices(doc.createAccessor().setType('SCALAR').setArray(Ic).setBuffer(buf))
			.setMaterial(mat);
		if (U0) prim.setAttribute('TEXCOORD_0', doc.createAccessor().setType('VEC2').setArray(U0).setBuffer(buf));
		if (U1) prim.setAttribute('TEXCOORD_1', doc.createAccessor().setType('VEC2').setArray(U1).setBuffer(buf));
		if (Cc) prim.setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(Cc).setBuffer(buf));
		getNode(b.grp).getMesh().addPrimitive(prim);
	}

	// Drop everything the old scene referenced, strip decoder-only extensions.
	for (const e of r0.listExtensionsUsed())
		if (['KHR_draco_mesh_compression', 'EXT_meshopt_compression', 'KHR_mesh_quantization'].includes(e.extensionName)) e.dispose();
	await doc.transform(prune(), dedup());
	// Textures: fit inside texture_max, WebP -> PNG (JPEG stays JPEG). Godot VRAM-compresses on import.
	// Resolution by what the texture is on: the body and wheels are seen close up, the cabin
	// through tinted glass. Keeps each car's GPU texture memory to a few MB on the device.
	const texMaxAll = cfg.texture_max || cfgAll.defaults.texture_max;
	const CLASS_TEX = { paint: 1024, rim: 1024, tyre: 512, caliper: 256, disc: 256, glass: 256, interior: 256, chrome: 512, other: 512 };
	const texLimit = new Map();
	for (const m of r0.listMaterials()) {
		const cls = (m.getName() || '').split(':')[0];
		const lim = Math.min(texMaxAll, cls.startsWith('light') ? 512 : CLASS_TEX[cls] || 512);
		for (const t of [m.getBaseColorTexture(), m.getNormalTexture(), m.getMetallicRoughnessTexture(), m.getOcclusionTexture(), m.getEmissiveTexture()])
			if (t) texLimit.set(t, Math.max(texLimit.get(t) || 0, lim));
	}
	for (const t of r0.listTextures()) {
		const img = t.getImage();
		if (!img) continue;
		const texMax = texLimit.get(t) || 512;
		const meta = await sharp(img).metadata();
		const big = Math.max(meta.width || 0, meta.height || 0) > texMax;
		const webp = t.getMimeType() === 'image/webp';
		// Opaque PNG/WebP -> JPEG: Godot re-encodes to ASTC/ETC2 anyway, lossless sources only bloat the repo.
		const opaque = t.getMimeType() !== 'image/jpeg' ? (await sharp(img).stats()).isOpaque : true;
		const toJpeg = t.getMimeType() !== 'image/jpeg' && opaque;
		if (!big && !webp && !toJpeg) continue;
		const fit = { width: texMax, height: texMax, fit: 'inside', withoutEnlargement: true };
		const jpeg = t.getMimeType() === 'image/jpeg' || toJpeg;
		const encode = (sh) => (jpeg ? sh.jpeg({ quality: 90 }) : sh.png()).toBuffer();
		let out = null;
		try {
			out = await encode(sharp(img).resize(fit));
		} catch {
			// Some 16-bit / odd-interpretation sources trip libvips' colourspace step: go via raw 8-bit.
			try {
				const { data, info } = await sharp(img).toColourspace('srgb').raw({ depth: 'uchar' }).toBuffer({ resolveWithObject: true });
				out = await encode(sharp(data, { raw: { width: info.width, height: info.height, channels: info.channels } }).resize(fit));
			} catch (e) {
				log.push(`texture kept as-is (${e.message})`);
			}
		}
		if (!out) continue;
		t.setImage(out);
		t.setMimeType(jpeg ? 'image/jpeg' : 'image/png');
		if (t.getURI()) t.setURI(t.getURI().replace(/\.(webp|png|jpe?g)$/i, jpeg ? '.jpg' : '.png'));
	}
	for (const e of r0.listExtensionsUsed()) if (e.extensionName === 'EXT_texture_webp') e.dispose();

	// Lamp and exhaust anchors (car space) for the game (headlight beams, showroom, exhaust FX).
	const anchors = (pred) => {
		const pts = [];
		for (const i of isl) {
			if (i.wheel !== undefined || !pred(i)) continue;
			const c = center(i.box);
			pts.push([c[0] + dx, c[1] + dy, c[2] + dz]);
		}
		const side = (sgn) => {
			const l = pts.filter((p) => Math.sign(p[0]) === sgn);
			if (!l.length) return null;
			return l.reduce((a, p) => [a[0] + p[0] / l.length, a[1] + p[1] / l.length, a[2] + p[2] / l.length], [0, 0, 0]).map((v) => +v.toFixed(3));
		};
		return [side(-1), side(1)].filter(Boolean);
	};
	// .gltf + .bin + one image file per texture: Godot imports the images as textures directly (no
	// extracted duplicates of GLB-embedded images). The folder is rebuilt from scratch every bake.
	const outDir = path.join(OUT, key);
	fs.rmSync(outDir, { recursive: true, force: true });
	fs.mkdirSync(outDir, { recursive: true });
	r0.listTextures().forEach((t, n) => t.setURI(`${key}_${n}.${t.getMimeType() === 'image/jpeg' ? 'jpg' : 'png'}`));
	for (const b of r0.listBuffers()) b.setURI(`${key}.bin`);
	await io.write(path.join(outDir, `${key}.gltf`), doc);
	const fin = unionBox(parts.map((p) => bboxOf(p.P)));
	const wl = wheels ? wheels.map((w) => ({ pos: w.c.map((v) => +v.toFixed(4)), radius: +w.r.toFixed(4), width: +w.w.toFixed(4) })) : null;
	const meta = {
		key,
		traffic: isTraffic,
		credit,
		length: +size(fin)[2].toFixed(3),
		width: +size(fin)[0].toFixed(3),
		height: +size(fin)[1].toFixed(3),
		bounds: { min: fin.mn.map((v) => +v.toFixed(3)), max: fin.mx.map((v) => +v.toFixed(3)) },
		wheels: wl,
		wheelbase: wheels ? +(((wheels[2].c[2] + wheels[3].c[2]) - (wheels[0].c[2] + wheels[1].c[2])) / 2).toFixed(4) : null,
		track_front: wheels ? +Math.abs(wheels[1].c[0] - wheels[0].c[0]).toFixed(4) : null,
		track_rear: wheels ? +Math.abs(wheels[3].c[0] - wheels[2].c[0]).toFixed(4) : null,
		headlights: anchors((i) => i.part.cls === 'light_head'),
		taillights: anchors((i) => i.part.cls === 'light_tail'),
		exhausts: anchors((i) => /exhaust|pipe|scarico|muffler|auspuff/i.test(`${i.part.node}|${i.part.matName}`) && center(i.box)[2] > 0),
		classes: [...new Set([...matClone.values()].map((m) => m.getName()))].sort(),
		triangles: Math.round(triOut),
		source_triangles: Math.round((tInt + tExt)),
	};
	fs.writeFileSync(path.join(outDir, `${key}.json`), JSON.stringify(meta, null, 1));
	const wbErr = cfg.wheelbase && meta.wheelbase ? ((meta.wheelbase - cfg.wheelbase) / cfg.wheelbase * 100).toFixed(1) : '?';
	console.log(`${key}: ${meta.source_triangles} -> ${meta.triangles} tris, L${meta.length} W${meta.width} H${meta.height}, wb ${meta.wheelbase} (${wbErr}% vs real), r ${wl ? wl.map((w) => w.radius.toFixed(2)).join('/') : '-'}, flip=${flip}`);
	for (const l of log) console.log('   ', l);
	const cls = {};
	for (const m of meta.classes) {
		const c = m.split(':')[0];
		cls[c] = (cls[c] || 0) + 1;
	}
	console.log('    classes', JSON.stringify(cls));
}

const partIds = new WeakMap();
let nextPart = 0;
function partId(p) {
	if (!partIds.has(p)) partIds.set(p, nextPart++);
	return partIds.get(p);
}

function computeNormals(P, I, N) {
	N.fill(0);
	for (let t = 0; t < I.length; t += 3) {
		const a = I[t], b = I[t + 1], c = I[t + 2];
		const ux = P[b * 3] - P[a * 3], uy = P[b * 3 + 1] - P[a * 3 + 1], uz = P[b * 3 + 2] - P[a * 3 + 2];
		const vx = P[c * 3] - P[a * 3], vy = P[c * 3 + 1] - P[a * 3 + 1], vz = P[c * 3 + 2] - P[a * 3 + 2];
		const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
		for (const v of [a, b, c]) {
			N[v * 3] += nx;
			N[v * 3 + 1] += ny;
			N[v * 3 + 2] += nz;
		}
	}
	for (let v = 0; v < N.length; v += 3) {
		const l = Math.hypot(N[v], N[v + 1], N[v + 2]) || 1;
		N[v] /= l;
		N[v + 1] /= l;
		N[v + 2] /= l;
	}
}

const only = process.argv.slice(2);
for (const [group, isTraffic] of [['cars', false], ['traffic', true]])
	for (const [key, c] of Object.entries(cfgAll[group] || {})) {
		if (only.length && !only.includes(key)) continue;
		try {
			await bake(key, c, isTraffic);
		} catch (e) {
			console.log('FAILED', key, e.stack);
		}
	}
