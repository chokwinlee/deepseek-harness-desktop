import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const cats = {
  '.d.ts/.d.mts/.d.cts': 0, '.ts sources': 0, '.map': 0, '.md': 0, '.json': 0,
  'js/cjs/mjs': 0, '.node': 0, '.wasm': 0, '.woff/.woff2': 0, '@types': 0, 'test/docs dirs': 0, 'other': 0,
};
const testDocs = /(^|\/)(test|tests|__tests__|doc|docs|example|examples|benchmark|benchmarks)(\/|$)/;

function dirSize(dir) {
  let t = 0;
  const walk = (d) => {
    let ents; try { ents = readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      const p = join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.isFile()) t += statSync(p).size;
    }
  };
  walk(dir);
  return t;
}

function walk(dir) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (testDocs.test(p + '/')) cats['test/docs dirs'] += dirSize(p);
      else walk(p);
    } else if (e.isFile()) {
      const s = statSync(p).size;
      const n = e.name;
      if (n.endsWith('.d.ts') || n.endsWith('.d.mts') || n.endsWith('.d.cts')) cats['.d.ts/.d.mts/.d.cts'] += s;
      else if (n.endsWith('.ts') || n.endsWith('.mts') || n.endsWith('.cts')) cats['.ts sources'] += s;
      else if (n.endsWith('.map')) cats['.map'] += s;
      else if (n.endsWith('.md')) cats['.md'] += s;
      else if (n.endsWith('.json')) cats['.json'] += s;
      else if (/\\.(js|cjs|mjs)$/.test(n)) cats['js/cjs/mjs'] += s;
      else if (n.endsWith('.node')) cats['.node'] += s;
      else if (n.endsWith('.wasm')) cats['.wasm'] += s;
      else if (n.endsWith('.woff') || n.endsWith('.woff2') || n.endsWith('.ttf')) cats['.woff/.woff2'] += s;
      else cats['other'] += s;
    }
  }
}

for (const d of readdirSync('.')) {
  if (d === '.bin') continue;
  if (d === '@types') { cats['@types'] += dirSize(d); continue; }
  walk(d);
}
const fmt = (n) => (n / 1048576).toFixed(1) + 'M';
let total = 0;
for (const [k, v] of Object.entries(cats)) {
  console.log(k.padEnd(18), fmt(v));
  total += v;
}
console.log('TOTAL'.padEnd(18), fmt(total));
