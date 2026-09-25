// Prints the README's markdown tables from the game data: the roster (godot/scripts/data/cars.gd:
// CARS + STOCK_PI) and the CC-BY credits the asset tools write next to every baked model.
//   node tools/readme_tables.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = fs.readFileSync(path.join(root, 'godot/scripts/data/cars.gd'), 'utf8');
const credit = (p) => {
	try {
		return JSON.parse(fs.readFileSync(path.join(root, p), 'utf8').replace(/^﻿/, '')).credit || {};
	} catch {
		return {};
	}
};
// FH4 PI bands (CarData.pi_class): D <= 500, C <= 600, B <= 700, A <= 800, S1 <= 900, S2 <= 998, X.
const cls = (pi) => (pi <= 500 ? 'D' : pi <= 600 ? 'C' : pi <= 700 ? 'B' : pi <= 800 ? 'A' : pi <= 900 ? 'S1' : pi <= 998 ? 'S2' : 'X');
const piBlock = /const STOCK_PI := \{([\s\S]*?)\n\}/.exec(src)[1];
const pis = Object.fromEntries([...piBlock.matchAll(/"(\w+)":\s*(\d+)/g)].map((m) => [m[1], +m[2]]));
const cars = [...src.matchAll(/^\t"(\w+)": \{\n\t\t"name": "([^"]+)", "maker": "([^"]+)", "country": "(\w+)", "year": (\d+), "price": ([\d_]+), "unlock": "(\w+)"/gm)].map((m) => ({
	key: m[1], name: m[2], maker: m[3], country: m[4], year: +m[5], price: +m[6].replace(/_/g, ''), unlock: m[7],
}));
const UNLOCK = { starter: 'Starter choice', shop: 'Autoshow', barn: 'Barn find', championship: 'Festival Grand Prix prize' };
const money = (n) => 'CR ' + n.toLocaleString('en-US');
const link = (c) => (c.source ? `[${c.title}](${c.source}) by ${c.author}` : '—');

const out = [];
out.push('| Class | PI | Car | Year | How to get it | 3D model (CC-BY 4.0) |');
out.push('| :---: | :---: | :--- | :---: | :--- | :--- |');
for (const c of cars.sort((a, b) => (pis[a.key] || 0) - (pis[b.key] || 0))) {
	const pi = pis[c.key] || 0;
	const how = c.unlock === 'shop' || c.unlock === 'starter' ? `${UNLOCK[c.unlock]} · ${money(c.price)}` : UNLOCK[c.unlock] || c.unlock;
	out.push(`| ${cls(pi)} | ${pi} | **${c.name}** | ${c.year} | ${how} | ${link(credit(`godot/assets/cars/${c.key}/${c.key}.json`))} |`);
}
out.push('');
out.push('| Traffic | 3D model (CC-BY 4.0) |');
out.push('| :--- | :--- |');
for (const k of ['vw_polo', 'skoda_superb', 'volvo_v60', 'vw_t6', 'mb_sprinter', 'town_bus']) out.push(`| ${k} | ${link(credit(`godot/assets/cars/${k}/${k}.json`))} |`);
out.push('');
out.push('| World prop | 3D model |');
out.push('| :--- | :--- |');
for (const k of fs.readdirSync(path.join(root, 'godot/assets/props')).sort().filter((k) => !k.endsWith('_far'))) {
	const c = credit(`godot/assets/props/${k}/${k}.json`);
	out.push(`| ${k.replace(/_/g, ' ')} | ${link(c)}${c.license && !/Attribution/.test(c.license) ? ` (${c.license})` : ''} |`);
}
console.log(out.join('\n'));
