import { readdirSync, statSync, unlinkSync, rmdirSync } from 'node:fs';
import { join } from 'node:path';

const DRY = process.env.DRY_RUN === '1';
const root = process.argv[2] ?? '.';

function option(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const platform = option('--platform');
const arch = option('--arch');

const DEL_EXT = new Set(['.map', '.d.ts', '.d.mts', '.d.cts', '.ts', '.mts', '.cts', '.tgz']);
const DEL_DIR = new Set(['test', 'tests', '__tests__', '__mocks__', 'example', 'examples', 'demo', 'demos', 'benchmark', 'benchmarks', 'coverage', '.github', '.circleci']);
const DEL_FILE = (n) =>
  /^(CHANGELOG|changelog|HISTORY|history|AUTHORS|CONTRIBUTING|CONTRIBUTORS|SECURITY|CODE_OF_CONDUCT|SUPPORT|UPGRADING|MAINTAINERS|PULL_REQUEST_TEMPLATE|ISSUE_TEMPLATE)/.test(n) ||
  /^(package-lock|npm-shrinkwrap|yarn.lock|pnpm-lock.yaml|tsconfig|jsconfig)/.test(n) ||
  /^\.(npmignore|gitignore|gitattributes|editorconfig|eslintrc|eslintignore|prettierrc|prettierignore|babelrc|browserslistrc|yarnrc|npmrc|nvmrc|node-version|travis.yml|appveyor.yml|DS_Store|eslintcache|nycrc|istanbul)/.test(n) ||
  n === '.gitignore' || n === '.npmignore' || n === '.eslintrc' || n === '.prettierrc';

let removed = 0;
let bytes = 0;

function shouldDeleteFile(name) {
  const lower = name.toLowerCase();
  if (name === 'README.md' || name === 'readme.md') return false;
  if (/^LICENSE/.test(name) || /^COPYING/.test(name)) return false;
  if (DEL_EXT.has(name.slice(name.lastIndexOf('.')))) return true;
  if (name.endsWith('.md')) return true;
  if (DEL_FILE(name)) return true;
  if (name.endsWith('.map')) return true;
  return false;
}

function walk(dir) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    if (e.name === '.bin' || e.name === '@types') {
      if (e.name === '@types' && e.isDirectory()) {
        const sz = dirSize(join(dir, e.name));
        if (DRY) { console.log('  [dir]', join(dir, e.name), fmt(sz)); bytes += sz; removed++; }
        else { rmrf(join(dir, e.name)); }
      }
      continue;
    }
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (DEL_DIR.has(e.name)) {
        const sz = dirSize(p);
        if (DRY) { console.log('  [dir]', p, fmt(sz)); bytes += sz; removed++; }
        else rmrf(p);
        continue;
      }
      walk(p);
    } else if (e.isFile()) {
      if (shouldDeleteFile(e.name)) {
        const sz = statSync(p).size;
        if (DRY) { console.log('  [file]', p, fmt(sz)); bytes += sz; removed++; }
        else {
          bytes += sz; removed++;
          try { unlinkSync(p); } catch {}
        }
      }
    }
  }
}

function dirSize(dir) {
  let t = 0;
  const w = (d) => {
    let ents; try { ents = readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      const p = join(d, e.name);
      if (e.isDirectory()) w(p);
      else if (e.isFile()) t += statSync(p).size;
    }
  };
  w(dir);
  return t;
}

function rmrf(dir) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    const p = join(dir, e.name);
    if (e.isDirectory()) rmrf(p);
    else try { unlinkSync(p); } catch {}
  }
  try { rmdirSync(dir); } catch {}
}

function removeDirectory(dir) {
  const size = dirSize(dir);
  if (size === 0) return;
  bytes += size;
  removed++;
  if (DRY) console.log('  [dir]', dir, fmt(size));
  else rmrf(dir);
}

function prunePlatformPayloads() {
  if (platform !== 'darwin' || !['arm64', 'x64'].includes(arch)) return;

  const nodePty = join(root, 'node-pty');
  for (const name of ['win32-arm64', 'win32-x64', arch === 'arm64' ? 'darwin-x64' : 'darwin-arm64']) {
    removeDirectory(join(nodePty, 'prebuilds', name));
  }
  removeDirectory(join(nodePty, 'third_party', 'conpty'));

  const sharpRoot = join(root, '@img');
  const nativeSharp = join(sharpRoot, `sharp-darwin-${arch}`);
  const nativeLibvips = join(sharpRoot, `sharp-libvips-darwin-${arch}`);
  if (dirSize(nativeSharp) > 0 && dirSize(nativeLibvips) > 0) {
    removeDirectory(join(sharpRoot, 'sharp-wasm32'));
  }
}

// remove empty dirs bottom-up
function pruneEmptyDirs(dir) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    if (e.isDirectory() && e.name !== '.bin') {
      const p = join(dir, e.name);
      pruneEmptyDirs(p);
    }
  }
  if (!DRY) {
    try {
      if (readdirSync(dir).length === 0) { rmdirSync(dir); }
    } catch {}
  }
}

const fmt = (n) => (n / 1048576).toFixed(1) + 'M';

for (const d of readdirSync(root)) {
  if (d.startsWith('.')) continue;
  if (d === '@types') {
    const sz = dirSize(join(root, d));
    if (DRY) { console.log('  [dir]', join(root, d), fmt(sz)); bytes += sz; removed++; }
    else { bytes += sz; removed++; rmrf(join(root, d)); }
    continue;
  }
  walk(join(root, d));
}
prunePlatformPayloads();
pruneEmptyDirs(root);
console.log((DRY ? '[dry-run] ' : '[applied] ') + 'removed ' + removed + ' items, ' + fmt(bytes) + ' of file bytes');
