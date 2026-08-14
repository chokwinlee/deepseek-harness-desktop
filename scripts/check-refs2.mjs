import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const targets = process.argv.slice(2);
const refs = {};
for (const t of targets) refs[t] = [];

function mentions(src, t) {
  let i = src.indexOf(t);
  while (i >= 0) {
    const j = i - 1;
    if (j >= 0 && (src[j] === "'" || src[j] === '"')) {
      const before = src.slice(Math.max(0, i - 20), j);
      if (before.includes('import') || before.includes('require') || before.includes('from')) {
        return true;
      }
    }
    i = src.indexOf(t, i + 1);
  }
  return false;
}

function walk(dir) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    if (e.name === '.bin' || e.name === '@types') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.js') || e.name.endsWith('.cjs') || e.name.endsWith('.mjs')) {
      let src;
      try { src = readFileSync(p, 'utf8'); } catch { continue; }
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
  console.log(t.padEnd(24), String(files.length).padStart(3), 'references');
  for (const f of files.slice(0, 6)) console.log('    ', f);
}
