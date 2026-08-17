import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import {
  readDesktopPreferences,
  smoothStreamEnabledFrom,
  writeSmoothStreamPreference,
} from '../src/desktop-preferences.js'

test('Desktop smooth streaming preference defaults on', async () => {
  assert.equal(smoothStreamEnabledFrom(undefined), true)
  assert.equal(smoothStreamEnabledFrom({}), true)
  assert.equal(smoothStreamEnabledFrom({ smoothStreamEnabled: false }), false)
})

test('Desktop preference write persists the toggle and preserves unrelated values', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'dsh-desktop-preferences-'))
  const path = join(directory, 'desktop-preferences.json')
  try {
    await writeSmoothStreamPreference(path, false)
    const first = await readDesktopPreferences(path)
    assert.equal(smoothStreamEnabledFrom(first), false)

    first.keepMe = 'value'
    await writeFile(path, `${JSON.stringify(first)}\n`, 'utf8')
    await writeSmoothStreamPreference(path, true)

    const persisted = JSON.parse(await readFile(path, 'utf8')) as Record<string, unknown>
    assert.equal(persisted.smoothStreamEnabled, true)
    assert.equal(persisted.keepMe, 'value')
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})
