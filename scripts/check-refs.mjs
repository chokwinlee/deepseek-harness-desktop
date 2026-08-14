import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const targets = process.argv.slice(2);
const refs = {};
for (const t of targets) refs[t] = [];

function mentions(src, t) {
  const pats = [
    `from '${t}'`, `from "${t}"`, `require('${t}')`, `require("${t}")`,
    `import('${t}')`, `import("${t}")`, `import '${t}'`, `import "${t}"`,
  ];
  return pats.some((p) => src.includes(p));
}

function walk(dir) {
  let ents; try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    if (e.name === '.bin' || e.name === '@types') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(js|cjs|mjs)$/.test(e.name)) {
      let src; try { src = readFileSync(p, 'utf8'); } catch { continue; }
      for (const t of targets) if (mentions(src, t)) refs[t].push(p);
    }
  }
}

for (const d of readdirSync('.')) {
  if (d.startsWith('.')) continue;
  walk(d);
}
for (const t of targets) {
  const files = refs[t].filter((f) => !f.startsWith('./' + t));
  console.log(t.padEnd(22), String(files.length).padStart(3), 'references');
  for (const f of files.slice(0, 5)) console.log('    ', f);
}
