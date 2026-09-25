// Debug: where each material of a baked car sits (mean / min / max z, nose at -Z) - for checking
// lamp classes.   node lamp_where.mjs <car key> [material regex]
import { NodeIO } from '@gltf-transform/core';

const [key, pick] = process.argv.slice(2);
const rx = pick ? new RegExp(pick) : /^light_/;
const doc = await new NodeIO().read(`../../godot/assets/cars/${key}/${key}.gltf`);
const acc = new Map();
for (const mesh of doc.getRoot().listMeshes())
	for (const p of mesh.listPrimitives()) {
		const name = p.getMaterial()?.getName() || '';
		if (!rx.test(name)) continue;
		const pos = p.getAttribute('POSITION');
		const a = acc.get(name) || { n: 0, z: 0, zmin: Infinity, zmax: -Infinity, tris: 0 };
		const v = [];
		for (let i = 0; i < pos.getCount(); i++) {
			pos.getElement(i, v);
			a.n++;
			a.z += v[2];
			a.zmin = Math.min(a.zmin, v[2]);
			a.zmax = Math.max(a.zmax, v[2]);
		}
		a.tris += (p.getIndices()?.getCount() || 0) / 3;
		acc.set(name, a);
	}
for (const [name, a] of acc) console.log(`${name.padEnd(36)} z mean ${(a.z / a.n).toFixed(2)}  [${a.zmin.toFixed(2)}, ${a.zmax.toFixed(2)}]  tris ${a.tris}`);
