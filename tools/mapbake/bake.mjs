// Riviera map bake: OpenStreetMap (ODbL, (c) OpenStreetMap contributors) + AWS Terrain Tiles
// -> godot/assets/map/riviera.bin (+ riviera.json for the UI, build/mapbake/preview.png to check).
//
// World frame: metres, +X east, +Z south, origin at config.CENTER. Everything the engine needs is
// precomputed here so World::build_from_bake() stays a fast loader:
//   heights (8 m grid, u16), land classes (u8), districts (u8), roads (graph edges split at
//   junctions, trimmed for junction polygons, height profiles with bridge/tunnel flags, grade
//   limits and layer clearance), junction polygons, building footprints (height, roof, style,
//   colour), trees, POIs and event routes (edge chains).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import * as CFG from './config.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const RAW = path.resolve(here, '../../build/mapbake');
const OUT_DIR = path.resolve(here, '../../godot/assets/map');
fs.mkdirSync(OUT_DIR, { recursive: true });
const t0 = Date.now();
const log = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);

// ---- Projection --------------------------------------------------------------------------------
const R = 6378137;
const coslat0 = Math.cos((CFG.CENTER.lat * Math.PI) / 180);
const toXZ = (lat, lon) => [((lon - CFG.CENTER.lon) * Math.PI) / 180 * R * coslat0, -((lat - CFG.CENTER.lat) * Math.PI) / 180 * R];
const toLL = (x, z) => [CFG.CENTER.lat - (z / R) * (180 / Math.PI), CFG.CENTER.lon + (x / (R * coslat0)) * (180 / Math.PI)];
const MIN_X = -CFG.SIZE_X / 2, MIN_Z = -CFG.SIZE_Z / 2, MAX_X = CFG.SIZE_X / 2, MAX_Z = CFG.SIZE_Z / 2;
const G = CFG.GRID;
const GW = Math.round(CFG.SIZE_X / G) + 1, GH = Math.round(CFG.SIZE_Z / G) + 1;
const inside = (x, z, m = 0) => x >= MIN_X + m && x <= MAX_X - m && z >= MIN_Z + m && z <= MAX_Z - m;

// ---- Small math helpers ----------------------------------------------------------------------
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => {
	const t = clamp((x - a) / (b - a), 0, 1);
	return t * t * (3 - 2 * t);
};
const dist2 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
function hash(n) {
	let x = Math.imul(n ^ 0x9e3779b9, 0x85ebca6b);
	x ^= x >>> 13;
	x = Math.imul(x, 0xc2b2ae35);
	x ^= x >>> 16;
	return (x >>> 0) / 4294967296;
}

// ---- DEM -----------------------------------------------------------------------------------------
const demRange = JSON.parse(fs.readFileSync(path.join(RAW, 'dem', 'range.json'), 'utf8'));
const TW = (demRange.x1 - demRange.x0 + 1) * 256, TH = (demRange.y1 - demRange.y0 + 1) * 256;
const mosaic = new Float32Array(TW * TH);
for (let tx = demRange.x0; tx <= demRange.x1; tx++)
	for (let ty = demRange.y0; ty <= demRange.y1; ty++) {
		const { data } = await sharp(path.join(RAW, 'dem', `${demRange.z}_${tx}_${ty}.png`)).removeAlpha().raw().toBuffer({ resolveWithObject: true });
		const ox = (tx - demRange.x0) * 256, oy = (ty - demRange.y0) * 256;
		for (let y = 0; y < 256; y++)
			for (let x = 0; x < 256; x++) {
				const o = (y * 256 + x) * 3;
				mosaic[(oy + y) * TW + ox + x] = data[o] * 256 + data[o + 1] + data[o + 2] / 256 - 32768;
			}
	}
const N2 = 2 ** demRange.z;
function demLL(lat, lon) {
	const px = (((lon + 180) / 360) * N2 - demRange.x0) * 256 - 0.5;
	const s = Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180));
	const py = (((1 - s / Math.PI) / 2) * N2 - demRange.y0) * 256 - 0.5;
	const x0 = clamp(Math.floor(px), 0, TW - 2), y0 = clamp(Math.floor(py), 0, TH - 2);
	const fx = clamp(px - x0, 0, 1), fy = clamp(py - y0, 0, 1);
	const a = mosaic[y0 * TW + x0], b = mosaic[y0 * TW + x0 + 1], c = mosaic[(y0 + 1) * TW + x0], d = mosaic[(y0 + 1) * TW + x0 + 1];
	return lerp(lerp(a, b, fx), lerp(c, d, fx), fy);
}
// Height grid (8 m) with a light blur to take the SRTM stair-stepping off.
let H = new Float32Array(GW * GH);
for (let j = 0; j < GH; j++)
	for (let i = 0; i < GW; i++) {
		const [lat, lon] = toLL(MIN_X + i * G, MIN_Z + j * G);
		H[j * GW + i] = demLL(lat, lon);
	}
function blur(src, passes) {
	let a = src;
	for (let p = 0; p < passes; p++) {
		const b = new Float32Array(a.length);
		for (let j = 0; j < GH; j++)
			for (let i = 0; i < GW; i++) {
				let s = 0, n = 0;
				for (let dj = -1; dj <= 1; dj++)
					for (let di = -1; di <= 1; di++) {
						const ii = clamp(i + di, 0, GW - 1), jj = clamp(j + dj, 0, GH - 1);
						s += a[jj * GW + ii];
						n++;
					}
				b[j * GW + i] = s / n;
			}
		a = b;
	}
	return a;
}
H = blur(H, 2);
function hAt(x, z) {
	const fx = clamp((x - MIN_X) / G, 0, GW - 1.001), fz = clamp((z - MIN_Z) / G, 0, GH - 1.001);
	const i = Math.floor(fx), j = Math.floor(fz), u = fx - i, v = fz - j;
	return lerp(lerp(H[j * GW + i], H[j * GW + i + 1], u), lerp(H[(j + 1) * GW + i], H[(j + 1) * GW + i + 1], u), v);
}
{
	let lo = Infinity, hi = -Infinity;
	for (const v of H) (lo = Math.min(lo, v)), (hi = Math.max(hi, v));
	log('dem', GW, 'x', GH, 'range', lo.toFixed(0), '..', hi.toFixed(0), 'm');
}

// ---- OSM ---------------------------------------------------------------------------------------
function loadOsm(file) {
	const j = JSON.parse(fs.readFileSync(path.join(RAW, file), 'utf8'));
	const nodes = new Map(), ways = [], rels = [];
	for (const e of j.elements) {
		if (e.type === 'node') nodes.set(e.id, e);
		else if (e.type === 'way') ways.push(e);
		else if (e.type === 'relation') rels.push(e);
	}
	return { nodes, ways, rels, wayById: new Map(ways.map((w) => [w.id, w])) };
}
const nodeXZ = (osm, id) => {
	const n = osm.nodes.get(id);
	return n ? toXZ(n.lat, n.lon) : null;
};

// Polygons from closed ways and multipolygon relations (outer rings joined end to end).
function polygons(osm, pred) {
	const out = [];
	for (const w of osm.ways) {
		if (!w.tags || !pred(w.tags) || w.nodes.length < 4 || w.nodes[0] !== w.nodes[w.nodes.length - 1]) continue;
		const ring = w.nodes.map((id) => nodeXZ(osm, id)).filter(Boolean);
		if (ring.length >= 4) out.push({ tags: w.tags, ring, id: w.id });
	}
	for (const r of osm.rels) {
		if (!r.tags || !pred(r.tags)) continue;
		const outers = r.members.filter((m) => m.type === 'way' && m.role !== 'inner').map((m) => osm.wayById.get(m.ref)).filter(Boolean);
		const segs = outers.map((w) => w.nodes.slice());
		while (segs.length) {
			let ring = segs.shift();
			let grew = true;
			while (grew && ring[0] !== ring[ring.length - 1]) {
				grew = false;
				for (let k = 0; k < segs.length; k++) {
					const s = segs[k];
					const end = ring[ring.length - 1];
					if (s[0] === end) ring = ring.concat(s.slice(1));
					else if (s[s.length - 1] === end) ring = ring.concat(s.slice(0, -1).reverse());
					else continue;
					segs.splice(k, 1);
					grew = true;
					break;
				}
			}
			const pts = ring.map((id) => nodeXZ(osm, id)).filter(Boolean);
			if (pts.length >= 4) out.push({ tags: r.tags, ring: pts, id: r.id });
		}
	}
	return out;
}

// Scanline fill of a polygon onto the 8 m grid.
function fillPoly(ring, cb) {
	let zmin = Infinity, zmax = -Infinity;
	for (const p of ring) (zmin = Math.min(zmin, p[1])), (zmax = Math.max(zmax, p[1]));
	const j0 = clamp(Math.ceil((zmin - MIN_Z) / G), 0, GH - 1), j1 = clamp(Math.floor((zmax - MIN_Z) / G), 0, GH - 1);
	for (let j = j0; j <= j1; j++) {
		const z = MIN_Z + j * G;
		const xs = [];
		for (let k = 0; k < ring.length - 1; k++) {
			const a = ring[k], b = ring[k + 1];
			if ((a[1] <= z && b[1] > z) || (b[1] <= z && a[1] > z)) xs.push(a[0] + ((z - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
		}
		xs.sort((p, q) => p - q);
		for (let k = 0; k + 1 < xs.length; k += 2) {
			const i0 = clamp(Math.ceil((xs[k] - MIN_X) / G), 0, GW - 1), i1 = clamp(Math.floor((xs[k + 1] - MIN_X) / G), 0, GW - 1);
			for (let i = i0; i <= i1; i++) cb(i, j);
		}
	}
}
function strokeLine(pts, halfw, cb) {
	for (let k = 0; k + 1 < pts.length; k++) {
		const a = pts[k], b = pts[k + 1];
		const len = dist2(a, b), steps = Math.max(1, Math.ceil(len / (G * 0.5)));
		for (let s = 0; s <= steps; s++) {
			const x = lerp(a[0], b[0], s / steps), z = lerp(a[1], b[1], s / steps);
			const r = Math.ceil(halfw / G);
			const ci = Math.round((x - MIN_X) / G), cj = Math.round((z - MIN_Z) / G);
			for (let dj = -r; dj <= r; dj++)
				for (let di = -r; di <= r; di++) {
					const i = ci + di, j = cj + dj;
					if (i < 0 || j < 0 || i >= GW || j >= GH) continue;
					if (Math.hypot(MIN_X + i * G - x, MIN_Z + j * G - z) <= halfw + G * 0.5) cb(i, j);
				}
		}
	}
}

// ---- Land classes -------------------------------------------------------------------------------
export const LAND = { SCRUB: 0, FOREST: 1, PARK: 2, FARM: 3, URBAN: 4, SAND: 5, ROCK: 6, SEA: 7, PORT: 8, WATER: 9 };
const land = new Uint8Array(GW * GH);
for (let k = 0; k < land.length; k++) land[k] = H[k] <= 0.4 ? LAND.SEA : LAND.SCRUB;
const landOsm = loadOsm('osm_land.json');
const LAND_RULES = [
	// order = paint order (later wins)
	[(t) => t.landuse === 'residential' || t.landuse === 'commercial' || t.landuse === 'retail' || t.landuse === 'construction', LAND.URBAN],
	[(t) => ['forest'].includes(t.landuse) || t.natural === 'wood', LAND.FOREST],
	[(t) => ['vineyard', 'orchard', 'farmland', 'meadow', 'allotments', 'greenhouse_horticulture', 'plant_nursery'].includes(t.landuse), LAND.FARM],
	[(t) => ['park', 'garden', 'golf_course', 'pitch', 'recreation_ground', 'playground'].includes(t.leisure) || ['grass', 'cemetery', 'village_green', 'recreation_ground'].includes(t.landuse), LAND.PARK],
	[(t) => ['scrub', 'heath', 'grassland'].includes(t.natural), LAND.SCRUB],
	[(t) => ['bare_rock', 'scree', 'cliff', 'rock', 'stone'].includes(t.natural), LAND.ROCK],
	[(t) => ['beach', 'sand'].includes(t.natural), LAND.SAND],
	[(t) => ['industrial', 'harbour', 'port', 'railway', 'depot'].includes(t.landuse) || t.amenity === 'parking' || t.leisure === 'marina', LAND.PORT],
	[(t) => t.natural === 'water' || t.water, LAND.WATER],
];
for (const [pred, cls] of LAND_RULES)
	for (const p of polygons(landOsm, pred))
		fillPoly(p.ring, (i, j) => {
			const k = j * GW + i;
			// Marinas / ports over the sea stay sea (the water inside the harbour).
			if (land[k] === LAND.SEA && cls !== LAND.WATER) return;
			land[k] = cls;
		});
// Piers and breakwaters: solid ground above the sea.
let piers = 0;
for (const w of landOsm.ways) {
	const t = w.tags || {};
	if (!['pier', 'breakwater', 'groyne'].includes(t.man_made)) continue;
	const pts = w.nodes.map((id) => nodeXZ(landOsm, id)).filter(Boolean);
	const closed = w.nodes[0] === w.nodes[w.nodes.length - 1];
	const cb = (i, j) => {
		const k = j * GW + i;
		land[k] = LAND.PORT;
		H[k] = Math.max(H[k], 2.2);
	};
	if (closed && t.area !== 'no') fillPoly(pts, cb);
	else strokeLine(pts, t.man_made === 'breakwater' ? 9 : 5, cb);
	piers++;
}
log('land classes painted, piers', piers);

// ---- Road graph ---------------------------------------------------------------------------------
const roadsOsm = loadOsm('osm_roads.json');
// Circuit de Monaco members (relation 148194) are always drivable; the pit lane is not.
const circuit = new Set();
{
	const c = JSON.parse(fs.readFileSync(path.join(RAW, 'osm_circuit.json'), 'utf8'));
	for (const e of c.elements)
		if (e.type === 'relation') for (const m of e.members) if (m.type === 'way' && m.role !== 'pit_lane') circuit.add(m.ref);
	for (const e of c.elements) if (e.type === 'way' && e.tags && /stands/i.test(e.tags.name || '')) circuit.delete(e.id);
}
const drivable = (t) => t && t.highway && (CFG.HIGHWAYS[t.highway] || (t.highway === 'service' && t.name && CFG.NAMED_SERVICE.test(t.name))) && t.area !== 'yes' && t.access !== 'private' && t.access !== 'no';
const ways = roadsOsm.ways.filter((w) => drivable(w.tags) || circuit.has(w.id));
const use = new Map();
for (const w of ways) w.nodes.forEach((id, k) => use.set(id, (use.get(id) || 0) + (k === 0 || k === w.nodes.length - 1 ? 2 : 1)));
// A graph vertex = shared node or way end. Edges run between consecutive vertices.
let edges = [];
for (const w of ways) {
	let cur = [w.nodes[0]];
	for (let k = 1; k < w.nodes.length; k++) {
		cur.push(w.nodes[k]);
		if (use.get(w.nodes[k]) >= 2 || k === w.nodes.length - 1) {
			edges.push({ way: w, nodes: cur });
			cur = [w.nodes[k]];
		}
	}
}
// Per-node flags: bridge/tunnel come from the way.
function edgeInfo(e) {
	const t = e.way.tags;
	const hw = t.highway === 'service' || t.highway === 'raceway' ? 'unclassified' : t.highway;
	let kind = CFG.HIGHWAYS[hw] || 'street';
	const oneway = t.oneway === 'yes' || t.oneway === '1' || t.junction === 'roundabout' || t.highway === 'motorway' ? 1 : t.oneway === '-1' ? -1 : 0;
	let lanes = parseInt(t.lanes || '0', 10);
	if (!lanes) lanes = kind === 'expressway' ? (oneway ? 2 : 4) : kind === 'ramp' ? 1 : kind === 'avenue' ? 2 : 2;
	if (oneway && lanes > 3) lanes = 3;
	const laneW = kind === 'expressway' ? 3.6 : kind === 'avenue' ? 3.3 : 3.0;
	let half = oneway ? (lanes * laneW) / 2 + 0.4 : (lanes * laneW) / 2;
	if (t.width) half = clamp(parseFloat(t.width) / 2, 2.2, 9);
	if (hw === 'living_street') half = Math.min(half, 2.6);
	const speed = parseInt(t.maxspeed || '0', 10) || { expressway: 110, ramp: 60, avenue: 50, street: 40 }[kind];
	return {
		kind, oneway, lanes: Math.max(1, lanes), half, speed,
		bridge: !!t.bridge && t.bridge !== 'no', tunnel: !!t.tunnel && t.tunnel !== 'no',
		layer: parseInt(t.layer || '0', 10) || 0, name: t.name || t.ref || '', ref: t.ref || '', roundabout: t.junction === 'roundabout', hw,
		gp: circuit.has(e.way.id), raceonly: t.highway === 'raceway',
	};
}
for (const e of edges) Object.assign(e, edgeInfo(e));
// Merge chains through degree-2 vertices when attributes match (OSM splits ways at every tag change).
function mergeChains() {
	const deg = new Map();
	for (const e of edges) for (const id of [e.nodes[0], e.nodes[e.nodes.length - 1]]) deg.set(id, (deg.get(id) || 0) + 1);
	const byEnd = new Map();
	edges.forEach((e, k) => {
		for (const id of [e.nodes[0], e.nodes[e.nodes.length - 1]]) {
			if (!byEnd.has(id)) byEnd.set(id, []);
			byEnd.get(id).push(k);
		}
	});
	const dead = new Set();
	const same = (a, b) => a.kind === b.kind && a.name === b.name && a.oneway === b.oneway && a.lanes === b.lanes && a.bridge === b.bridge && a.tunnel === b.tunnel && a.gp === b.gp && a.raceonly === b.raceonly;
	for (const [id, list] of byEnd) {
		if (deg.get(id) !== 2 || list.length !== 2) continue;
		const [ia, ib] = list;
		if (ia === ib || dead.has(ia) || dead.has(ib)) continue;
		const a = edges[ia], b = edges[ib];
		if (!same(a, b)) continue;
		// Orient a to end at id and b to start at id.
		let an = a.nodes, bn = b.nodes;
		if (an[an.length - 1] !== id) an = an.slice().reverse();
		if (bn[0] !== id) bn = bn.slice().reverse();
		if (an[an.length - 1] !== id || bn[0] !== id) continue;
		if (a.oneway && (an !== a.nodes) !== (bn !== b.nodes)) continue; // opposing one-way directions
		a.nodes = an.concat(bn.slice(1));
		dead.add(ib);
		// Re-point b's far end at a.
		const far = b.nodes[0] === id ? b.nodes[b.nodes.length - 1] : b.nodes[0];
		const l = byEnd.get(far);
		if (l) l[l.indexOf(ib)] = ia;
	}
	edges = edges.filter((_, k) => !dead.has(k));
}
mergeChains();
for (const e of edges) {
	e.pts = e.nodes.map((id) => nodeXZ(roadsOsm, id));
	e.len = 0;
	for (let k = 1; k < e.pts.length; k++) e.len += dist2(e.pts[k - 1], e.pts[k]);
}
// Drop edges fully outside the map and tiny dead-end stubs.
{
	const deg = new Map();
	for (const e of edges) for (const id of [e.nodes[0], e.nodes[e.nodes.length - 1]]) deg.set(id, (deg.get(id) || 0) + 1);
	edges = edges.filter((e) => {
		if (!e.pts.some((p) => inside(p[0], p[1], 20))) return false;
		const dead = deg.get(e.nodes[0]) === 1 || deg.get(e.nodes[e.nodes.length - 1]) === 1;
		return !(dead && e.len < 25 && e.kind === 'street');
	});
	// Clip to the map (keep a 20 m margin): cut at the first point outside.
	for (const e of edges) {
		let a = 0, b = e.pts.length - 1;
		while (a < b && !inside(e.pts[a][0], e.pts[a][1], 20)) a++;
		while (b > a && !inside(e.pts[b][0], e.pts[b][1], 20)) b--;
		if (a > 0 || b < e.pts.length - 1) {
			e.pts = e.pts.slice(a, b + 1);
			e.nodes = e.nodes.slice(a, b + 1);
		}
	}
	edges = edges.filter((e) => e.pts.length >= 2);
}
// Built-up area test for kind refinement.
const landAt = (x, z) => land[clamp(Math.round((z - MIN_Z) / G), 0, GH - 1) * GW + clamp(Math.round((x - MIN_X) / G), 0, GW - 1)];
function urbanShare(pts) {
	let u = 0;
	for (const p of pts) u += landAt(p[0], p[1]) === LAND.URBAN || landAt(p[0], p[1]) === LAND.PORT ? 1 : 0;
	return u / pts.length;
}
function nearSea(pts) {
	let n = 0;
	for (const p of pts)
		for (const [dx, dz] of [[120, 0], [-120, 0], [0, 120], [0, -120]]) if (landAt(p[0] + dx, p[1] + dz) === LAND.SEA) { n++; break; }
	return n / pts.length;
}
for (const e of edges) {
	const urb = urbanShare(e.pts);
	const alt = e.pts.reduce((a, p) => a + hAt(p[0], p[1]), 0) / e.pts.length;
	if (e.kind === 'street' && urb < 0.35) e.kind = alt > 180 && e.hw !== 'residential' ? 'touge' : nearSea(e.pts) > 0.4 ? 'coast' : 'rural';
	else if (e.kind === 'avenue' && urb < 0.3) e.kind = alt > 180 ? 'touge' : nearSea(e.pts) > 0.4 ? 'coast' : 'rural';
}
log('road edges', edges.length, 'km', (edges.reduce((a, e) => a + e.len, 0) / 1000).toFixed(1));

// ---- Junctions -------------------------------------------------------------------------------
const vert = new Map(); // node id -> {id, p, edges: [{e, atStart}]}
for (const e of edges)
	for (const [id, atStart] of [[e.nodes[0], true], [e.nodes[e.nodes.length - 1], false]]) {
		if (!vert.has(id)) vert.set(id, { id, p: nodeXZ(roadsOsm, id), inc: [] });
		vert.get(id).inc.push({ e, atStart });
	}
// Direction leaving the vertex along the edge (sampled ~8 m out).
function leave(e, atStart) {
	const pts = atStart ? e.pts : e.pts.slice().reverse();
	let acc = 0;
	for (let k = 1; k < pts.length; k++) {
		acc += dist2(pts[k - 1], pts[k]);
		if (acc >= 8 || k === pts.length - 1) {
			const d = [pts[k][0] - pts[0][0], pts[k][1] - pts[0][1]];
			const l = Math.hypot(d[0], d[1]) || 1;
			return [d[0] / l, d[1] / l];
		}
	}
	return [1, 0];
}
const junctions = [];
for (const v of vert.values()) {
	if (v.inc.length < 3) continue;
	const legs = v.inc.map((x) => ({ ...x, d: leave(x.e, x.atStart), w: x.e.half + 0.6 }));
	legs.sort((a, b) => Math.atan2(a.d[1], a.d[0]) - Math.atan2(b.d[1], b.d[0]));
	for (let k = 0; k < legs.length; k++) {
		const a = legs[k];
		let t = a.w + 0.5;
		for (const b of [legs[(k + 1) % legs.length], legs[(k + legs.length - 1) % legs.length]]) {
			const cos = clamp(a.d[0] * b.d[0] + a.d[1] * b.d[1], -1, 1);
			const th = Math.acos(cos);
			if (th > (170 * Math.PI) / 180 || th < 1e-3) continue;
			t = Math.max(t, b.w / Math.sin(th) + a.w / Math.tan(th));
		}
		a.trim = clamp(t, a.w, Math.min(28, a.e.len * 0.45));
	}
	const poly = [];
	for (const a of legs) {
		const n = [-a.d[1], a.d[0]];
		const c = [v.p[0] + a.d[0] * a.trim, v.p[1] + a.d[1] * a.trim];
		poly.push([c[0] - n[0] * a.w, c[1] - n[1] * a.w], [c[0] + n[0] * a.w, c[1] + n[1] * a.w]);
	}
	for (const a of legs) (a.atStart ? (a.e.trimStart = a.trim) : (a.e.trimEnd = a.trim));
	const big = legs.some((a) => a.e.kind === 'avenue' || a.e.kind === 'street');
	junctions.push({ v, poly, style: legs.some((a) => a.e.roundabout) ? 3 : big && legs.length >= 4 ? 1 : 0, legs });
}
log('junctions', junctions.length);

// ---- Road height profiles ------------------------------------------------------------------------
const STEP = 4;
const MAX_GRADE = { expressway: 0.06, ramp: 0.08, avenue: 0.12, street: 0.2, rural: 0.14, touge: 0.14, coast: 0.12 };
function resample(e) {
	const out = [];
	const fl = [];
	for (let k = 0; k + 1 < e.pts.length; k++) {
		const a = e.pts[k], b = e.pts[k + 1];
		const n = Math.max(1, Math.ceil(dist2(a, b) / STEP));
		for (let s = 0; s < n; s++) out.push([lerp(a[0], b[0], s / n), lerp(a[1], b[1], s / n)]);
	}
	out.push(e.pts[e.pts.length - 1]);
	return out;
}
// Vertex heights: terrain average in a small radius (so crossing streets agree).
for (const v of vert.values()) {
	let s = 0, n = 0;
	for (const [dx, dz] of [[0, 0], [6, 0], [-6, 0], [0, 6], [0, -6]]) (s += Math.max(hAt(v.p[0] + dx, v.p[1] + dz), 0.8)), n++;
	v.y = s / n + 0.25;
	const allTunnel = v.inc.every((x) => x.e.tunnel), allBridge = v.inc.every((x) => x.e.bridge);
	v.special = allTunnel || allBridge;
}
for (const e of edges) {
	const P = resample(e);
	const n = P.length;
	const ground = P.map((p) => Math.max(hAt(p[0], p[1]), 0.8) + 0.25);
	let y = ground.slice();
	const v0 = vert.get(e.nodes[0]), v1 = vert.get(e.nodes[e.nodes.length - 1]);
	if (e.tunnel || e.bridge) {
		// Structures span between their ends (the terrain under a bridge / over a tunnel is ignored).
		const ya = v0 ? v0.y : ground[0], yb = v1 ? v1.y : ground[n - 1];
		for (let k = 0; k < n; k++) y[k] = lerp(ya, yb, k / (n - 1));
		if (e.tunnel) for (let k = 0; k < n; k++) y[k] = Math.min(y[k], ground[k] - 1.0 + (Math.sin((Math.PI * k) / (n - 1)) > 0 ? 0 : 0));
	} else {
		// Smooth the terrain profile.
		const win = Math.max(1, Math.round((e.kind === 'expressway' ? 60 : e.kind === 'street' ? 16 : 32) / STEP));
		const sm = y.map((_, k) => {
			let s = 0, c = 0;
			for (let q = -win; q <= win; q++) {
				const kk = clamp(k + q, 0, n - 1);
				s += y[kk];
				c++;
			}
			return s / c;
		});
		y = sm;
	}
	// Pin the ends to the vertex heights and blend in over 24 m.
	const pin = (idx, target, dir) => {
		const span = Math.min(n - 1, Math.round(24 / STEP));
		const delta = target - y[idx];
		for (let q = 0; q <= span; q++) {
			const k = idx + dir * q;
			if (k < 0 || k >= n) break;
			y[k] += delta * (1 - smooth(0, span, q));
		}
	};
	if (v0) pin(0, v0.y, 1);
	if (v1) pin(n - 1, v1.y, -1);
	// Grade limit (both directions). The clamps can drag a pinned end off its vertex height, and
	// every road meeting at a vertex must arrive at the same height (else the junction patch
	// becomes a step), so blend any residual back in along the whole edge: ends stay exact, the
	// grade limit gives way only where the vertices themselves demand it.
	const g = (MAX_GRADE[e.kind] || 0.12) * STEP;
	for (let pass = 0; pass < 3; pass++) {
		for (let k = 1; k < n; k++) y[k] = clamp(y[k], y[k - 1] - g, y[k - 1] + g);
		for (let k = n - 2; k >= 0; k--) y[k] = clamp(y[k], y[k + 1] - g, y[k + 1] + g);
	}
	const r0 = v0 ? v0.y - y[0] : 0, r1 = v1 ? v1.y - y[n - 1] : 0;
	if (n > 1 && (Math.abs(r0) > 0.01 || Math.abs(r1) > 0.01))
		for (let k = 0; k < n; k++) {
			const t = k / (n - 1);
			y[k] += r0 * (1 - smooth(0, 1, t)) + r1 * smooth(0, 1, t);
		}
	e.P = P;
	e.Y = y;
	e.G = ground;
}
// Layer clearance: a bridge must pass >= 6.5 m over, a tunnel >= 7.5 m under, any road it crosses.
function segX(a, b, c, d) {
	const r = [b[0] - a[0], b[1] - a[1]], s = [d[0] - c[0], d[1] - c[1]];
	const den = r[0] * s[1] - r[1] * s[0];
	if (Math.abs(den) < 1e-9) return null;
	const t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den, u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den;
	return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? [t, u] : null;
}
const cell = new Map();
const ckey = (x, z) => `${Math.floor(x / 64)},${Math.floor(z / 64)}`;
edges.forEach((e, ei) => {
	for (let k = 0; k + 1 < e.P.length; k++) {
		const kk = ckey(e.P[k][0], e.P[k][1]);
		if (!cell.has(kk)) cell.set(kk, []);
		cell.get(kk).push([ei, k]);
	}
});
let lifts = 0;
for (let pass = 0; pass < 2; pass++)
	edges.forEach((e, ei) => {
		if (!e.bridge && !e.tunnel) return;
		for (let k = 0; k + 1 < e.P.length; k++) {
			const seen = cell.get(ckey(e.P[k][0], e.P[k][1])) || [];
			for (const [oi, ok] of seen) {
				if (oi === ei) continue;
				const o = edges[oi];
				if (o.nodes.includes(e.nodes[0]) || o.nodes.includes(e.nodes[e.nodes.length - 1])) continue;
				const hit = segX(e.P[k], e.P[k + 1], o.P[ok], o.P[ok + 1]);
				if (!hit) continue;
				const ye = lerp(e.Y[k], e.Y[k + 1], hit[0]), yo = lerp(o.Y[ok], o.Y[ok + 1], hit[1]);
				const need = e.bridge && e.layer >= o.layer ? yo + 6.5 - ye : e.tunnel ? ye - (yo - 7.5) : 0;
				if (need <= 0) continue;
				const sign = e.bridge && e.layer >= o.layer ? 1 : -1;
				const span = Math.round(70 / STEP);
				for (let q = -span; q <= span; q++) {
					const m = k + q;
					if (m < 0 || m >= e.P.length) continue;
					e.Y[m] += sign * need * (0.5 + 0.5 * Math.cos((Math.PI * q) / span));
				}
				lifts++;
			}
		}
	});
log('layer clearance fixes', lifts);

// Trim road ends for the junction polygons (the polygon covers the first `trim` metres).
function trimEdge(e) {
	const cum = [0];
	for (let k = 1; k < e.P.length; k++) cum.push(cum[k - 1] + dist2(e.P[k - 1], e.P[k]));
	const L = cum[cum.length - 1];
	// Short links between two junctions keep at least 1.5 m (never drop an edge: that would cut
	// the graph); shrink both trims proportionally instead.
	let ts = e.trimStart || 0, te = e.trimEnd || 0;
	if (ts + te > L - 1.5) {
		const k = Math.max(L - 1.5, 0) / Math.max(ts + te, 1e-6);
		ts *= k;
		te *= k;
	}
	const a = ts, b = L - te;
	if (b - a < 0.5) return false;
	const at = (s) => {
		let k = 1;
		while (k < cum.length - 1 && cum[k] < s) k++;
		const t = (s - cum[k - 1]) / Math.max(cum[k] - cum[k - 1], 1e-6);
		return [lerp(e.P[k - 1][0], e.P[k][0], t), lerp(e.P[k - 1][1], e.P[k][1], t), lerp(e.Y[k - 1], e.Y[k], t)];
	};
	const P = [at(a)];
	for (let k = 0; k < e.P.length; k++) if (cum[k] > a + 1 && cum[k] < b - 1) P.push([e.P[k][0], e.P[k][1], e.Y[k]]);
	P.push(at(b));
	e.out = P;
	e.outLen = b - a;
	return true;
}
edges = edges.filter(trimEdge);
edges.forEach((e, k) => (e.idx = k));
// Junction patches: each leg's mouth sits where that road now starts (its own grade over the trim
// length), the centre at the mean - a flat patch at the vertex height left steps at every mouth.
for (const j of junctions) {
	const mouth = j.legs.map((l) => (l.e.out ? (l.atStart ? l.e.out[0][2] : l.e.out[l.e.out.length - 1][2]) : j.v.y));
	j.y = mouth.reduce((a, b) => a + b, 0) / Math.max(mouth.length, 1);
	j.poly = j.poly.map((p, k) => [p[0], mouth[k >> 1] ?? j.y, p[1]]);
}
log('roads after trim', edges.length);

// ---- Buildings -------------------------------------------------------------------------------------
const bOsm = loadOsm('osm_buildings.json');
const COLOURS = { white: [236, 232, 222], cream: [240, 226, 196], beige: [222, 200, 165], yellow: [236, 205, 130], ochre: [214, 160, 90], orange: [222, 142, 88], pink: [226, 170, 160], red: [176, 70, 55], brown: [140, 100, 70], grey: [170, 170, 168], gray: [170, 170, 168] };
const RIVIERA = [[240, 226, 196], [236, 205, 150], [226, 178, 150], [232, 214, 180], [245, 238, 225], [214, 168, 120], [226, 196, 170], [205, 190, 160], [236, 222, 200], [196, 140, 110]];
function parseColour(s, seed) {
	if (s) {
		if (/^#[0-9a-f]{6}$/i.test(s)) return [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];
		const c = COLOURS[s.toLowerCase()];
		if (c) return c;
	}
	return RIVIERA[Math.floor(hash(seed) * RIVIERA.length)];
}
const buildings = [];
for (const b of polygons(bOsm, (t) => t.building && t.building !== 'no' && t.building !== 'roof')) {
	let ring = b.ring;
	if (ring[0][0] === ring[ring.length - 1][0] && ring[0][1] === ring[ring.length - 1][1]) ring = ring.slice(0, -1);
	let area = 0;
	for (let k = 0; k < ring.length; k++) {
		const a = ring[k], c = ring[(k + 1) % ring.length];
		area += a[0] * c[1] - c[0] * a[1];
	}
	area /= 2;
	if (Math.abs(area) < 14 || !ring.every((p) => inside(p[0], p[1], 2))) continue;
	if (area > 0) ring = ring.slice().reverse(); // store clockwise seen from above (+Z south => consistent winding)
	// Drop near-collinear points.
	const simp = [];
	for (let k = 0; k < ring.length; k++) {
		const a = ring[(k + ring.length - 1) % ring.length], p = ring[k], c = ring[(k + 1) % ring.length];
		const cr = (p[0] - a[0]) * (c[1] - p[1]) - (p[1] - a[1]) * (c[0] - p[0]);
		if (Math.abs(cr) > 0.05 || dist2(a, p) > 30) simp.push(p);
	}
	if (simp.length < 3 || simp.length > 250) continue;
	const t = b.tags;
	let h = parseFloat(t.height || t['building:height'] || '0');
	const lv = parseFloat(t['building:levels'] || '0');
	const kind = t.building;
	if (!h && lv) h = lv * 3.2 + (lv > 2 ? 1.5 : 1);
	const cx = simp.reduce((a, p) => a + p[0], 0) / simp.length, cz = simp.reduce((a, p) => a + p[1], 0) / simp.length;
	const monaco = dist2([cx, cz], toXZ(43.736, 7.422)) < 1400;
	if (!h) {
		const base = { house: 7.5, detached: 7.5, villa: 8.5, residential: monaco ? 16 : 10, apartments: monaco ? 22 : 14, hotel: 24, commercial: 14, office: 18, retail: 7, church: 15, cathedral: 22, chapel: 9, garage: 3.2, garages: 3.2, shed: 3, hut: 3, industrial: 9, warehouse: 9, public: 14, school: 12, civic: 14, parking: 12, service: 4, kiosk: 3.5, train_station: 10, transportation: 8 }[kind];
		h = (base || (monaco ? 15 : 9)) * (0.8 + 0.5 * hash(b.id));
	}
	h = clamp(h, 2.5, 220);
	let ymin = Infinity, ymax = -Infinity;
	for (const p of simp) {
		const g = hAt(p[0], p[1]);
		ymin = Math.min(ymin, g);
		ymax = Math.max(ymax, g);
	}
	ymin = Math.max(ymin, 0.5);
	const style = ['church', 'cathedral', 'chapel', 'mosque', 'synagogue'].includes(kind) || t.historic ? 5
		: ['industrial', 'warehouse', 'garage', 'garages', 'shed', 'service', 'parking'].includes(kind) ? 6
		: h > 45 ? 4
		: monaco && h > 14 ? 2
		: ['house', 'detached', 'villa', 'semidetached_house', 'terrace'].includes(kind) ? 3
		: h > 20 ? 1 : 0;
	const roof = t['roof:shape'] === 'flat' || h > 18 || style === 4 || style === 6 ? 0 : t['roof:shape'] === 'gabled' ? 2 : 1;
	buildings.push({ ring: simp, base: ymin - 0.3, top: ymax + h, style, roof, colour: parseColour(t['building:colour'], b.id), id: b.id });
	fillPoly(simp.concat([simp[0]]), (i, j) => {
		const k = j * GW + i;
		if (land[k] !== LAND.SEA) land[k] = LAND.URBAN;
	});
}
log('buildings', buildings.length);

// ---- Trees ---------------------------------------------------------------------------------------
const tOsm = loadOsm('osm_trees.json');
const TREE = { PINE: 0, CYPRESS: 1, PALM: 2, OLIVE: 3, PLANE: 4, BROADLEAF: 5 };
function treeKind(t, seed) {
	const g = `${t.genus || ''} ${t.species || ''} ${t['species:en'] || ''} ${t.taxon || ''}`.toLowerCase();
	if (/phoenix|washingtonia|palm|trachycarpus|chamaerops|syagrus/.test(g)) return TREE.PALM;
	if (/pinus|pine/.test(g)) return TREE.PINE;
	if (/cupressus|cypress/.test(g)) return TREE.CYPRESS;
	if (/olea|olive/.test(g)) return TREE.OLIVE;
	if (/platanus|plane/.test(g)) return TREE.PLANE;
	const r = hash(seed);
	return r < 0.3 ? TREE.PALM : r < 0.55 ? TREE.PLANE : r < 0.75 ? TREE.PINE : r < 0.88 ? TREE.CYPRESS : TREE.OLIVE;
}
const trees = [];
for (const n of tOsm.nodes.values()) {
	if (!n.tags || n.tags.natural !== 'tree') continue;
	const [x, z] = toXZ(n.lat, n.lon);
	if (inside(x, z, 2)) trees.push([x, z, treeKind(n.tags, n.id), clamp(Math.round(parseFloat(n.tags.height || '0') * 10), 0, 255)]);
}
for (const w of tOsm.ways) {
	if (!w.tags || w.tags.natural !== 'tree_row') continue;
	const pts = w.nodes.map((id) => nodeXZ(tOsm, id)).filter(Boolean);
	for (let k = 0; k + 1 < pts.length; k++) {
		const L = dist2(pts[k], pts[k + 1]);
		for (let s = 0; s < L; s += 9) {
			const x = lerp(pts[k][0], pts[k + 1][0], s / L), z = lerp(pts[k][1], pts[k + 1][1], s / L);
			if (inside(x, z, 2)) trees.push([x, z, treeKind(w.tags, w.id + k), 0]);
		}
	}
}
log('mapped trees', trees.length);

// ---- Districts -------------------------------------------------------------------------------------
const DG = 32;
const DW = Math.ceil(CFG.SIZE_X / DG), DH = Math.ceil(CFG.SIZE_Z / DG);
const seeds = CFG.DISTRICTS.map((d) => toXZ(d.lat, d.lon));
const districts = new Uint8Array(DW * DH);
for (let j = 0; j < DH; j++)
	for (let i = 0; i < DW; i++) {
		const x = MIN_X + (i + 0.5) * DG, z = MIN_Z + (j + 0.5) * DG;
		let best = 0, bd = Infinity;
		seeds.forEach((s, k) => {
			const d = dist2(s, [x, z]);
			if (d < bd) (bd = d), (best = k);
		});
		districts[j * DW + i] = best;
	}

// ---- Routes (event roads) -----------------------------------------------------------------------
// Graph over trimmed edges: vertices = OSM vertex ids; A* between the vertices nearest to waypoints.
const adj = new Map();
for (const e of edges)
	for (const [a, b, fwd] of [[e.nodes[0], e.nodes[e.nodes.length - 1], true], [e.nodes[e.nodes.length - 1], e.nodes[0], false]]) {
		if (!adj.has(a)) adj.set(a, []);
		adj.get(a).push({ to: b, e, fwd });
	}
function nearestVertex(x, z, pred = null) {
	let best = null, bd = Infinity;
	for (const v of vert.values()) {
		if (!adj.has(v.id)) continue;
		if (pred && !adj.get(v.id).some((s) => pred(s.e))) continue;
		const d = dist2(v.p, [x, z]);
		if (d < bd) (bd = d), (best = v);
	}
	return best;
}
// Cost of driving an edge for a route: preferred (named) roads are cheap, others expensive; one-way
// streets can't be driven backwards on public-road sprints.
let routeCost = (s) => s.e.outLen * (s.e.kind === 'street' ? 1.35 : 1.0);
function astar(a, b) {
	const open = new Map([[a.id, 0]]);
	const g = new Map([[a.id, 0]]);
	const came = new Map();
	const done = new Set();
	while (open.size) {
		let cur = null, cf = Infinity;
		for (const [id, f] of open) if (f < cf) (cf = f), (cur = id);
		open.delete(cur);
		if (cur === b.id) break;
		done.add(cur);
		for (const s of adj.get(cur) || []) {
			if (done.has(s.to)) continue;
			const w = routeCost(s);
			if (!isFinite(w)) continue;
			const ng = g.get(cur) + w;
			if (ng < (g.get(s.to) ?? Infinity)) {
				g.set(s.to, ng);
				came.set(s.to, { from: cur, s });
				open.set(s.to, ng + dist2(vert.get(s.to).p, b.p));
			}
		}
	}
	const path = [];
	let c = b.id;
	while (c !== a.id) {
		const st = came.get(c);
		if (!st) return null;
		path.unshift(st.s);
		c = st.from;
	}
	return path;
}
const routes = [];
const matches = (e, rx) => rx.test(`${e.name}|${e.ref}`);
if (process.env.MAPBAKE_DEBUG) {
	// Circuit subgraph connectivity report.
	const gpE = edges.filter((e) => e.gp);
	const comp = new Map();
	let nc = 0;
	for (const e of gpE)
		for (const id of [e.nodes[0], e.nodes[e.nodes.length - 1]]) {
			if (comp.has(id)) continue;
			const q = [id];
			comp.set(id, nc);
			while (q.length) {
				const c = q.pop();
				for (const s of adj.get(c) || []) if (s.e.gp && !comp.has(s.to)) (comp.set(s.to, nc), q.push(s.to));
			}
			nc++;
		}
	log('gp edges', gpE.length, 'components', nc, 'km', (gpE.reduce((a, e) => a + e.outLen, 0) / 1000).toFixed(2));
	for (const e of gpE) log('  gp', e.idx, e.name, e.hw, 'oneway', e.oneway, 'race', e.raceonly, 'comp', comp.get(e.nodes[0]), 'len', e.outLen.toFixed(0));
}
for (const r of CFG.ROUTES) {
	routeCost = (s) => {
		const wrongWay = s.e.oneway && (s.e.oneway === 1) !== s.fwd;
		// Closed circuit: its own streets, either direction (the waypoints set the race direction);
		// short non-member connectors (e.g. Rond-Point Sainte-Dévote) only when unavoidable.
		if (r.circuit) return s.e.outLen * (s.e.gp ? 1 : 8);
		if (!r.closed && wrongWay) return Infinity;
		return s.e.outLen * (r.prefer && matches(s.e, r.prefer) ? 0.25 : r.prefer ? 5.0 : 1.0);
	};
	let vs;
	// Waypoints: [lat, lon] or a street name (centroid of that street's circuit/preferred edges).
	const viaXZ = (v) => {
		if (Array.isArray(v)) return toXZ(v[0], v[1]);
		const own = edges.filter((e) => e.name === v && (!r.circuit || e.gp));
		let sx = 0, sz = 0, n = 0;
		for (const e of own) for (const p of e.out) (sx += p[0]), (sz += p[1]), n++;
		if (!n) throw new Error(`route ${r.id}: no street named ${v}`);
		return [sx / n, sz / n];
	};
	if (r.via) vs = r.via.map((v) => nearestVertex(...viaXZ(v), r.circuit ? (e) => e.gp : null));
	else {
		// Ends of the longest connected stretch of the preferred road.
		const own = edges.filter((e) => matches(e, r.prefer));
		const nb = new Map();
		// Directed: one-way carriageways (motorways) only link in their driving direction, so the two
		// ends always lie on the same carriageway.
		for (const e of own) {
			const a = e.nodes[0], b = e.nodes[e.nodes.length - 1];
			if (!nb.has(a)) nb.set(a, []);
			if (!nb.has(b)) nb.set(b, []);
			if (e.oneway !== -1) nb.get(a).push([b, e.outLen]);
			if (e.oneway !== 1) nb.get(b).push([a, e.outLen]);
		}
		const far = (start) => {
			const d = new Map([[start, 0]]);
			const q = [start];
			while (q.length) {
				const c = q.shift();
				for (const [n, l] of nb.get(c)) if (!d.has(n)) (d.set(n, d.get(c) + l), q.push(n));
			}
			let best = start;
			for (const [k, v] of d) if (v > d.get(best)) best = k;
			return [best, d];
		};
		// Longest directed run: from every source, the farthest reachable vertex.
		let bestPair = null, bestLen = -1;
		for (const s of nb.keys()) {
			const [b, db] = far(s);
			if (db.get(b) > bestLen) (bestLen = db.get(b)), (bestPair = [s, b]);
		}
		if (!bestPair) {
			log('route', r.id, 'no matching roads');
			continue;
		}
		let [a, b] = bestPair.map((id) => vert.get(id));
		// Two-way roads: climb uphill (hill climbs) or run west to east.
		const directed = own.some((e) => e.oneway);
		if (!directed && (a.y > b.y + 30 || (Math.abs(a.y - b.y) <= 30 && a.p[0] > b.p[0]))) [a, b] = [b, a];
		vs = [a, b];
	}
	let chain = [];
	let ok = true;
	if (r.circuit) {
		// Street chain: drive each named street end to end (entering at the end nearer the car),
		// A* only for the links between streets and back to the start.
		const baseCost = routeCost;
		let cur = vs[0];
		const start = vs[0];
		for (const street of r.via.slice(1)) {
			const own = edges.filter((e) => e.gp && e.name === street);
			const nb = new Map();
			for (const e of own)
				for (const [a, b] of [[e.nodes[0], e.nodes[e.nodes.length - 1]], [e.nodes[e.nodes.length - 1], e.nodes[0]]]) {
					if (!nb.has(a)) nb.set(a, []);
					nb.get(a).push([b, e.outLen]);
				}
			const far = (s0) => {
				const d = new Map([[s0, 0]]);
				const q = [s0];
				while (q.length) {
					const c = q.shift();
					for (const [n2, l] of nb.get(c)) if (!d.has(n2)) (d.set(n2, d.get(c) + l), q.push(n2));
				}
				let best = s0;
				for (const [k2, v2] of d) if (v2 > d.get(best)) best = k2;
				return best;
			};
			const e1 = far([...nb.keys()][0]), e2 = far(e1);
			let [entry, exit] = [vert.get(e1), vert.get(e2)];
			if (dist2(cur.p, exit.p) < dist2(cur.p, entry.p)) [entry, exit] = [exit, entry];
			routeCost = baseCost;
			const link = cur.id === entry.id ? [] : astar(cur, entry);
			routeCost = (s) => (s.e.gp && s.e.name === street ? s.e.outLen : Infinity);
			const body = astar(entry, exit);
			if (!link || !body) {
				ok = false;
				log('route', r.id, 'chain broke at', street);
				break;
			}
			chain = chain.concat(link, body);
			cur = exit;
		}
		routeCost = baseCost;
		const home = ok && cur.id !== start.id ? astar(cur, start) : [];
		if (!home) ok = false;
		else chain = chain.concat(home);
	} else {
		if (r.closed) vs.push(vs[0]);
		for (let k = 0; k + 1 < vs.length; k++) {
			if (vs[k].id === vs[k + 1].id) continue;
			const p = astar(vs[k], vs[k + 1]);
			if (!p) {
				ok = false;
				log('route', r.id, 'no path between waypoints', k, k + 1);
				break;
			}
			chain = chain.concat(p);
		}
	}
	if (!ok) continue;
	const len = chain.reduce((a, s) => a + s.e.outLen, 0);
	if (process.env.MAPBAKE_DEBUG) {
		const seq = [];
		for (const s of chain) if (!seq.length || seq[seq.length - 1][0] !== s.e.name) seq.push([s.e.name, s.e.outLen]);
		else seq[seq.length - 1][1] += s.e.outLen;
		log('  ', r.id, seq.map(([n, l]) => `${n || '?'}(${l.toFixed(0)})`).join(' > '));
	}
	routes.push({ id: r.id, name: r.name, closed: !!r.closed, roads: chain.map((s) => (s.fwd ? 1 : -1) * (s.e.idx + 1)), length: len });
	log('route', r.id, chain.length, 'roads', (len / 1000).toFixed(2), 'km');
}

// ---- POIs ----------------------------------------------------------------------------------------
const POI_TYPES = { festival: 0, garage: 1, event_start: 2, landmark: 9, fast_travel: 10, spawn: 12, barn: 8 };
const pois = CFG.POIS.map((p) => {
	const [x, z] = toXZ(p.lat, p.lon);
	return { type: POI_TYPES[p.type], id: p.id, x, y: hAt(x, z), z, yaw: 0, data: p.data || '' };
});

// ---- Write binary ------------------------------------------------------------------------------------
class W {
	constructor() {
		this.buf = Buffer.alloc(1 << 20);
		this.o = 0;
	}
	grow(n) {
		if (this.o + n <= this.buf.length) return;
		const nb = Buffer.alloc(Math.max(this.buf.length * 2, this.o + n));
		this.buf.copy(nb, 0, 0, this.o);
		this.buf = nb;
	}
	u8(v) { this.grow(1); this.buf.writeUInt8(v & 255, this.o); this.o += 1; }
	u16(v) { this.grow(2); this.buf.writeUInt16LE(v & 65535, this.o); this.o += 2; }
	i32(v) { this.grow(4); this.buf.writeInt32LE(v | 0, this.o); this.o += 4; }
	u32(v) { this.grow(4); this.buf.writeUInt32LE(v >>> 0, this.o); this.o += 4; }
	f32(v) { this.grow(4); this.buf.writeFloatLE(v, this.o); this.o += 4; }
	str(s) { const b = Buffer.from(s || '', 'utf8'); this.u16(b.length); this.grow(b.length); b.copy(this.buf, this.o); this.o += b.length; }
	bytes(b) { this.grow(b.byteLength); Buffer.from(b.buffer, b.byteOffset, b.byteLength).copy(this.buf, this.o); this.o += b.byteLength; }
	tag(t) { for (const c of t) this.u8(c.charCodeAt(0)); }
}
const KIND = { street: 0, avenue: 1, expressway: 2, ramp: 3, rural: 4, touge: 6, coast: 7 };
const w = new W();
w.tag('NTMB');
w.u32(1);
// Heights
w.tag('HGT ');
w.f32(MIN_X);
w.f32(MIN_Z);
w.f32(G);
w.u32(GW);
w.u32(GH);
const hq = new Uint16Array(GW * GH);
for (let k = 0; k < hq.length; k++) hq[k] = clamp(Math.round((H[k] + 100) / 0.05), 0, 65535);
w.bytes(hq);
w.tag('LAND');
w.bytes(land);
w.tag('DIST');
w.f32(DG);
w.u32(DW);
w.u32(DH);
w.u8(CFG.DISTRICTS.length);
for (const d of CFG.DISTRICTS) w.str(d.name);
w.bytes(districts);
w.tag('ROAD');
w.u32(edges.length);
for (const e of edges) {
	w.str(`r${e.idx}`);
	w.str(e.name);
	w.u8(KIND[e.kind] ?? 0);
	w.u8((e.oneway === 1 ? 1 : 0) | (e.oneway === -1 ? 2 : 0) | (e.bridge ? 4 : 0) | (e.tunnel ? 8 : 0) | (e.roundabout ? 16 : 0));
	w.u8(e.lanes);
	w.u8(clamp(e.speed, 0, 255));
	w.f32(e.half);
	const [cx, cz] = e.out[Math.floor(e.out.length / 2)];
	let best = 0, bd = Infinity;
	seeds.forEach((s, k) => {
		const d = dist2(s, [cx, cz]);
		if (d < bd) (bd = d), (best = k);
	});
	w.u8(best);
	w.i32(e.nodes[0] % 2147483647);
	w.i32(e.nodes[e.nodes.length - 1] % 2147483647);
	w.u32(e.out.length);
	for (const p of e.out) {
		w.f32(p[0]);
		w.f32(p[2]);
		w.f32(p[1]);
	}
}
w.tag('JUNC');
w.u32(junctions.length);
for (const j of junctions) {
	w.f32(j.v.p[0]);
	w.f32(j.y);
	w.f32(j.v.p[1]);
	w.u8(j.style);
	w.u8(j.poly.length);
	for (const p of j.poly) {
		w.f32(p[0]);
		w.f32(p[1]);
		w.f32(p[2]);
	}
	w.u8(j.legs.length);
	for (const l of j.legs) w.i32(l.e.idx ?? -1);
}
w.tag('BLDG');
w.u32(buildings.length);
for (const b of buildings) {
	w.f32(b.base);
	w.f32(b.top);
	w.u8(b.style);
	w.u8(b.roof);
	w.u8(b.colour[0]);
	w.u8(b.colour[1]);
	w.u8(b.colour[2]);
	w.u16(b.ring.length);
	for (const p of b.ring) {
		w.f32(p[0]);
		w.f32(p[1]);
	}
}
w.tag('TREE');
w.u32(trees.length);
for (const t of trees) {
	w.f32(t[0]);
	w.f32(t[1]);
	w.u8(t[2]);
	w.u8(t[3]);
}
w.tag('POIS');
w.u32(pois.length);
for (const p of pois) {
	w.u8(p.type);
	w.str(p.id);
	w.f32(p.x);
	w.f32(p.y);
	w.f32(p.z);
	w.f32(p.yaw);
	w.str(p.data);
}
w.tag('ROUT');
w.u32(routes.length);
for (const r of routes) {
	w.str(r.id);
	w.str(r.name);
	w.u8(r.closed ? 1 : 0);
	w.u32(r.roads.length);
	for (const v of r.roads) w.i32(v);
}
w.tag('END ');
fs.writeFileSync(path.join(OUT_DIR, 'riviera.bin'), w.buf.subarray(0, w.o));
fs.writeFileSync(
	path.join(OUT_DIR, 'riviera.json'),
	JSON.stringify({
		credit: 'Map data (c) OpenStreetMap contributors (ODbL). Elevation: AWS Terrain Tiles (SRTM, EU-DEM, NOAA).',
		center: CFG.CENTER, size: [CFG.SIZE_X, CFG.SIZE_Z],
		districts: CFG.DISTRICTS.map((d) => d.name),
		routes: routes.map((r) => ({ id: r.id, name: r.name, closed: r.closed, length_m: Math.round(r.length), roads: r.roads.map((v) => (v > 0 ? `r${v - 1}` : `~r${-v - 1}`)) })),
		counts: { roads: edges.length, junctions: junctions.length, buildings: buildings.length, trees: trees.length },
	}, null, 1),
);
log('wrote riviera.bin', (w.o / 1e6).toFixed(2), 'MB');

// ---- Preview (1 px = 4 m) ------------------------------------------------------------------------------
const PS = 4, PW = Math.round(CFG.SIZE_X / PS), PH = Math.round(CFG.SIZE_Z / PS);
const img = Buffer.alloc(PW * PH * 3);
const LAND_COL = [[150, 160, 110], [70, 105, 60], [110, 160, 90], [170, 170, 110], [205, 195, 180], [225, 210, 160], [150, 145, 135], [40, 90, 150], [175, 175, 180], [60, 110, 170]];
for (let y = 0; y < PH; y++)
	for (let x = 0; x < PW; x++) {
		const wx = MIN_X + x * PS, wz = MIN_Z + y * PS;
		const c = LAND_COL[landAt(wx, wz)];
		const h = hAt(wx, wz), hx = hAt(wx + 4, wz), hz = hAt(wx, wz + 4);
		const shade = clamp(0.8 + (h - hx) * 0.06 + (h - hz) * 0.04, 0.45, 1.25);
		const o = (y * PW + x) * 3;
		for (let k = 0; k < 3; k++) img[o + k] = clamp(c[k] * shade, 0, 255);
	}
const plot = (x, z, col, r = 0) => {
	const px = Math.round((x - MIN_X) / PS), py = Math.round((z - MIN_Z) / PS);
	for (let dy = -r; dy <= r; dy++)
		for (let dx = -r; dx <= r; dx++) {
			const X = px + dx, Y = py + dy;
			if (X < 0 || Y < 0 || X >= PW || Y >= PH) continue;
			const o = (Y * PW + X) * 3;
			img[o] = col[0];
			img[o + 1] = col[1];
			img[o + 2] = col[2];
		}
};
for (const b of buildings) for (const p of b.ring) plot(p[0], p[1], [120, 90, 80]);
const RC = { street: [255, 255, 255], avenue: [255, 230, 120], expressway: [230, 60, 120], ramp: [230, 110, 160], rural: [240, 240, 200], touge: [255, 150, 40], coast: [120, 230, 255] };
for (const e of edges) {
	const col = e.tunnel ? [60, 60, 60] : e.bridge ? [180, 80, 255] : RC[e.kind];
	for (let k = 0; k + 1 < e.out.length; k++) {
		const a = e.out[k], b = e.out[k + 1];
		const n = Math.ceil(dist2(a, b) / 2);
		for (let s = 0; s <= n; s++) plot(lerp(a[0], b[0], s / n), lerp(a[1], b[1], s / n), col, e.kind === 'expressway' || e.kind === 'avenue' ? 1 : 0);
	}
}
for (const j of junctions) for (const p of j.poly) plot(p[0], p[2], [255, 0, 0]);
const RTC = [[0, 255, 0], [255, 0, 255], [0, 255, 255], [255, 128, 0], [255, 255, 0], [128, 128, 255]];
routes.forEach((r, ri) => {
	for (const v of r.roads) {
		const e = edges[Math.abs(v) - 1];
		for (const p of e.out) plot(p[0], p[1], RTC[ri % RTC.length], 2);
	}
});
for (const p of pois) plot(p.x, p.z, [255, 0, 0], 4);
await sharp(img, { raw: { width: PW, height: PH, channels: 3 } }).png().toFile(path.join(RAW, 'preview.png'));
log('preview', PW, 'x', PH);
