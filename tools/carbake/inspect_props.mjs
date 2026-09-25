// Debug: lists the primitives/materials under nodes matching a regex in a raw prop source.
//   node inspect_props.mjs <uid> <regex>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const [uid, pick] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const d = await io.read(`../../build/carbake/raw_props/${uid}.glb`);
const rx = new RegExp(pick);
const walk = (x, dep) => {
	const m = x.getMesh();
	if (m)
		for (const p of m.listPrimitives()) {
			const mt = p.getMaterial();
			const t = mt?.getBaseColorTexture();
			const info = mt?.getBaseColorTextureInfo();
			console.log(' '.repeat(dep), x.getName(), p.getIndices()?.getCount() / 3, mt?.getName(), mt?.getAlphaMode(), mt?.getBaseColorFactor().map((v) => v.toFixed(2)).join(','),
				t?.getName(), t?.getMimeType(), t?.getSize(), 'texcoord', info?.getTexCoord(), 'ext', mt?.listExtensions().map((e) => e.extensionName).join('|'), 'attrs', p.listSemantics().join(','));
		}
	for (const c of x.listChildren()) walk(c, dep + 1);
};
for (const n of d.getRoot().listNodes()) if (rx.test(n.getName())) walk(n, 0);
