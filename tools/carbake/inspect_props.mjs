// Debug: lists the primitives/materials under nodes matching a regex in a raw source GLB.
//   node inspect_props.mjs <file under build/carbake/raw_props or raw, without .glb> <node regex> [material regex]
import fs from 'node:fs';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import draco3d from 'draco3dgltf';
import { MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';

const [name, pick, matPick] = process.argv.slice(2);
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
	'draco3d.decoder': await draco3d.createDecoderModule(),
	'meshopt.decoder': MeshoptDecoder,
});
const file = [`../../build/carbake/raw_props/${name}.glb`, `../../build/carbake/raw/${name}.glb`].find((f) => fs.existsSync(f));
const d = await io.read(file);
const rx = new RegExp(pick);
const mrx = matPick ? new RegExp(matPick) : null;
const seen = new Set();
const walk = async (x, dep) => {
	const m = x.getMesh();
	if (m)
		for (const p of m.listPrimitives()) {
			const mt = p.getMaterial();
			if (mrx && !mrx.test(mt?.getName() || '')) continue;
			const t = mt?.getBaseColorTexture();
			let alpha = '';
			if (t && !seen.has(t)) {
				seen.add(t);
				const meta = await sharp(t.getImage()).metadata();
				const st = await sharp(t.getImage()).stats();
				alpha = `hasAlpha ${meta.hasAlpha} opaque ${st.isOpaque} ${meta.width}x${meta.height}`;
			}
			console.log(' '.repeat(dep), x.getName(), p.getIndices()?.getCount() / 3, mt?.getName(), mt?.getAlphaMode(), mt?.getAlphaCutoff(), mt?.getBaseColorFactor().map((v) => v.toFixed(2)).join(','),
				t?.getMimeType(), alpha, 'ext', mt?.listExtensions().map((e) => e.extensionName).join('|'));
		}
	for (const c of x.listChildren()) await walk(c, dep + 1);
};
for (const n of d.getRoot().listNodes()) if (rx.test(n.getName())) await walk(n, 0);
