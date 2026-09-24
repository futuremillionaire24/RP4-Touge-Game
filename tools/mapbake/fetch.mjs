// Downloads the raw map data into build/mapbake/ (cached; delete a file to refetch):
//   osm_roads.json, osm_buildings.json, osm_land.json, osm_trees.json  (Overpass API, ODbL)
//   dem/<z>_<x>_<y>.png  (AWS Terrain Tiles, Terrarium encoding)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CENTER, SIZE_X, SIZE_Z, DEM_ZOOM } from './config.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(here, '../../build/mapbake');
fs.mkdirSync(path.join(OUT, 'dem'), { recursive: true });

const R = 6378137;
const dLat = (SIZE_Z / 2 / R) * (180 / Math.PI);
const dLon = (SIZE_X / 2 / (R * Math.cos((CENTER.lat * Math.PI) / 180))) * (180 / Math.PI);
const S = CENTER.lat - dLat - 0.002, N = CENTER.lat + dLat + 0.002, W = CENTER.lon - dLon - 0.002, E = CENTER.lon + dLon + 0.002;
const bbox = `${S.toFixed(5)},${W.toFixed(5)},${N.toFixed(5)},${E.toFixed(5)}`;
console.log('bbox', bbox);

const UA = { 'User-Agent': 'EuroGTFestival-mapbake/1.0 (private game prototype)' };
const ENDPOINTS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];

async function overpass(file, body) {
	const f = path.join(OUT, file);
	if (fs.existsSync(f)) return console.log('cached', file);
	const q = `[out:json][timeout:180];(${body});out body;>;out skel qt;`;
	for (const ep of ENDPOINTS) {
		for (let attempt = 0; attempt < 3; attempt++) {
			try {
				const r = await fetch(ep, { method: 'POST', headers: { ...UA, 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'data=' + encodeURIComponent(q) });
				if (!r.ok) throw new Error('HTTP ' + r.status);
				const txt = await r.text();
				JSON.parse(txt);
				fs.writeFileSync(f, txt);
				return console.log('ok', file, (txt.length / 1e6).toFixed(1) + 'MB');
			} catch (e) {
				console.log('retry', file, ep, e.message);
				await new Promise((res) => setTimeout(res, 5000 * (attempt + 1)));
			}
		}
	}
	throw new Error('overpass failed: ' + file);
}

await overpass('osm_roads.json', `way["highway"](${bbox});`);
await overpass('osm_buildings.json', `way["building"](${bbox});relation["building"](${bbox});way["building:part"](${bbox});`);
await overpass(
	'osm_land.json',
	`way["landuse"](${bbox});relation["landuse"](${bbox});way["natural"](${bbox});relation["natural"](${bbox});` +
		`way["leisure"](${bbox});relation["leisure"](${bbox});way["man_made"~"pier|breakwater|groyne"](${bbox});way["amenity"="parking"](${bbox});`,
);
await overpass('osm_trees.json', `node["natural"="tree"](${bbox});way["natural"="tree_row"](${bbox});`);
// Circuit de Monaco (relation 148194): member ways (some are raceway/service-only segments).
await overpass('osm_circuit.json', `relation(148194);way(r);`);
await overpass('osm_pois.json', `node["tourism"](${bbox});node["historic"](${bbox});node["amenity"~"fuel|cafe|restaurant"](${bbox});`);

// DEM tiles.
const tx = (lon) => ((lon + 180) / 360) * 2 ** DEM_ZOOM;
const ty = (lat) => ((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** DEM_ZOOM;
const x0 = Math.floor(tx(W)), x1 = Math.floor(tx(E)), y0 = Math.floor(ty(N)), y1 = Math.floor(ty(S));
let n = 0;
for (let x = x0; x <= x1; x++)
	for (let y = y0; y <= y1; y++) {
		const f = path.join(OUT, 'dem', `${DEM_ZOOM}_${x}_${y}.png`);
		if (fs.existsSync(f)) continue;
		const r = await fetch(`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${DEM_ZOOM}/${x}/${y}.png`, { headers: UA });
		if (!r.ok) throw new Error(`dem ${x},${y} HTTP ${r.status}`);
		fs.writeFileSync(f, Buffer.from(await r.arrayBuffer()));
		n++;
	}
console.log(`dem tiles x ${x0}-${x1} y ${y0}-${y1}, downloaded ${n}`);
fs.writeFileSync(path.join(OUT, 'dem', 'range.json'), JSON.stringify({ z: DEM_ZOOM, x0, x1, y0, y1 }));
