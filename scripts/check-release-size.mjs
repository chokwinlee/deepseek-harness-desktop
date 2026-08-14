import { appendFile, readdir, stat } from 'node:fs/promises'
import { extname, join, resolve } from 'node:path'

const SIZE_BUDGETS = {
  mac: {
    '.dmg': 160_000_000,
    '.zip': 175_000_000,
  },
  win: {
    '.exe': 140_000_000,
    '.zip': 185_000_000,
  },
}

function option(name) {
  const index = process.argv.indexOf(name)
  return index === -1 ? undefined : process.argv[index + 1]
}

function megabytes(bytes) {
  return `${(bytes / 1_000_000).toFixed(1)} MB`
}

const platform = option('--platform')
if (platform === undefined || !(platform in SIZE_BUDGETS)) {
  throw new Error('Use --platform mac or --platform win.')
}

const releaseDirectory = resolve(option('--directory') ?? 'release')
const budgets = SIZE_BUDGETS[platform]
const entries = await readdir(releaseDirectory, { withFileTypes: true })
const artifacts = []

for (const entry of entries) {
  if (!entry.isFile()) continue
  const extension = extname(entry.name)
  const budget = budgets[extension]
  if (budget === undefined || !entry.name.includes(`-${platform}-`)) continue
  const { size } = await stat(join(releaseDirectory, entry.name))
  artifacts.push({ name: entry.name, size, budget })
}

const missingExtensions = Object.keys(budgets).filter(
  extension => !artifacts.some(artifact => extname(artifact.name) === extension),
)
if (missingExtensions.length > 0) {
  throw new Error(`Missing ${platform} release artifacts: ${missingExtensions.join(', ')}`)
}

artifacts.sort((left, right) => left.name.localeCompare(right.name))
const rows = artifacts.map(artifact => ({
  ...artifact,
  status: artifact.size <= artifact.budget ? 'PASS' : 'FAIL',
}))

console.log(`Release size report (${platform})`)
for (const row of rows) {
  console.log(`${row.status} ${row.name}: ${megabytes(row.size)} / ${megabytes(row.budget)}`)
}

if (process.env.GITHUB_STEP_SUMMARY !== undefined) {
  const summary = [
    `### Release size report (${platform})`,
    '',
    '| Artifact | Size | Budget | Status |',
    '| --- | ---: | ---: | :---: |',
    ...rows.map(row => `| \`${row.name}\` | ${megabytes(row.size)} | ${megabytes(row.budget)} | ${row.status} |`),
    '',
  ].join('\n')
  await appendFile(process.env.GITHUB_STEP_SUMMARY, summary)
}

const oversized = rows.filter(row => row.status === 'FAIL')
if (oversized.length > 0) {
  throw new Error(`Release size budget exceeded by: ${oversized.map(row => row.name).join(', ')}`)
}
