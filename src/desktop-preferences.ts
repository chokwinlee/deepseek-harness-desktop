import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

export interface DesktopPreferences {
  smoothStreamEnabled?: boolean
  [key: string]: unknown
}

/** Default-on preference reader that rejects malformed values without disabling the feature. */
export function smoothStreamEnabledFrom(value: unknown): boolean {
  if (typeof value !== 'object' || value === null) return true
  const enabled = (value as DesktopPreferences).smoothStreamEnabled
  return typeof enabled === 'boolean' ? enabled : true
}

export async function readDesktopPreferences(path: string): Promise<DesktopPreferences> {
  try {
    const parsed = JSON.parse(await readFile(path, 'utf8')) as unknown
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as DesktopPreferences
      : {}
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT' || error instanceof SyntaxError) return {}
    throw error
  }
}

/** Preserve unrelated Desktop preferences and replace the file atomically. */
export async function writeSmoothStreamPreference(path: string, enabled: boolean): Promise<void> {
  const preferences = await readDesktopPreferences(path)
  preferences.smoothStreamEnabled = enabled
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.desktop-next-${String(process.pid)}`
  await writeFile(temporary, `${JSON.stringify(preferences, null, 2)}\n`, 'utf8')
  try {
    await rename(temporary, path)
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code
    if (process.platform !== 'win32' || (code !== 'EEXIST' && code !== 'EPERM')) throw error
    await rm(path, { force: true })
    await rename(temporary, path)
  }
}
