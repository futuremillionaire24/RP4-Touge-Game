// Downloads every model listed in cars.json into build/carbake/raw/<key>.glb (+ <key>.json licence
// record). Sketchfab models need a personal API token in SKETCHFAB_TOKEN (never committed);
// "url" sources are fetched directly. The licence is re-checked through the public API and anything
// that isn't CC-BY / CC0 (or is NonCommercial / NoDerivatives) is refused.
//   node fetch.mjs [key ...]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'cars.json'), 'utf8'));
const out = path.resolve(here, '../../build/carbake/raw');
fs.mkdirSync(out, { recursive: true });
const token = process.env.SKETCHFAB_TOKEN || '';
const only = process.argv.slice(2);

for (const [key, c] of Object.entries({ ...cfg.cars, ...cfg.traffic })) {
	if (only.length && !only.includes(key)) continue;
	const glb = path.join(out, `${key}.glb`);
	if (fs.existsSync(glb)) continue;
	if (c.url) {
		const buf = Buffer.from(await (await fetch(c.url)).arrayBuffer());
		fs.writeFileSync(glb, buf);
		fs.writeFileSync(path.join(out, `${key}.json`), JSON.stringify(c.credit, null, 1));
		console.log('ok', key, 'url');
		continue;
	}
	const meta = await (await fetch(`https://api.sketchfab.com/v3/models/${c.uid}`)).json();
	const lic = meta.license?.label || '';
	if (!/Attribution|CC0|Public Domain/i.test(lic) || /NonCommercial|NoDerivs/i.test(lic)) {
		console.log('REFUSED licence', key, lic);
		continue;
	}
	if (!token) {
		console.log('need SKETCHFAB_TOKEN for', key);
		continue;
	}
	const r = await fetch(`https://api.sketchfab.com/v3/models/${c.uid}/download`, { headers: { Authorization: `Token ${token}` } });
	if (!r.ok) {
		console.log('download api', r.status, key);
		continue;
	}
	const d = await r.json();
	fs.writeFileSync(glb, Buffer.from(await (await fetch(d.glb.url)).arrayBuffer()));
	const credit = {
		title: meta.name,
		author: meta.user?.displayName || meta.user?.username,
		author_url: meta.user?.profileUrl || `https://sketchfab.com/${meta.user?.username}`,
		license: lic,
		license_url: meta.license?.url || '',
		source: meta.viewerUrl,
	};
	fs.writeFileSync(path.join(out, `${key}.json`), JSON.stringify(credit, null, 1));
	console.log('ok', key, lic, '|', meta.name, '|', credit.author);
}
