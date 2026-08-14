import { readFile } from 'node:fs/promises'

const packageManifest = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'))
const tauriConfig = JSON.parse(await readFile(new URL('../src-tauri/tauri.conf.json', import.meta.url), 'utf8'))
const cargoManifest = await readFile(new URL('../src-tauri/Cargo.toml', import.meta.url), 'utf8')
const packageStart = cargoManifest.indexOf('[package]')
const nextSection = cargoManifest.indexOf('\n[', packageStart + '[package]'.length)
const cargoPackage = packageStart === -1
  ? ''
  : cargoManifest.slice(packageStart, nextSection === -1 ? undefined : nextSection)
const cargoVersion = /^version\s*=\s*"([^"]+)"\s*$/m.exec(cargoPackage)?.[1]

const versions = {
  package: packageManifest.version,
  tauri: tauriConfig.version,
  cargo: cargoVersion,
}
const unique = new Set(Object.values(versions))
if (unique.size !== 1 || unique.has(undefined)) {
  throw new Error(`Version mismatch: ${JSON.stringify(versions)}`)
}

const version = packageManifest.version
const expectedTag = process.argv[2]
if (expectedTag !== undefined && expectedTag !== `v${version}`) {
  throw new Error(`Release tag ${expectedTag} does not match v${version}`)
}
console.log(`Version sync passed: ${version}`)
