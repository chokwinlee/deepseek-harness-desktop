import { spawn, type ChildProcessByStdio } from 'node:child_process'
import type { Readable } from 'node:stream'

const READY_LINE = /^dsh web:\s+(http:\/\/127\.0\.0\.1:(\d+))(?:\s|$)/
const STARTUP_TAIL_LINES = 40
const READINESS_GRACE_MS = 300
const STOP_GRACE_MS = 5_000
const FORCE_STOP_GRACE_MS = 2_000

/** Origin of a line emitted by the managed Harness process. */
export type HarnessLogSource = 'stdout' | 'stderr'

/** Process inputs and lifecycle tunables for one Harness server. */
export interface HarnessSupervisorOptions {
  executable: string
  script: string
  cwd: string
  env: NodeJS.ProcessEnv
  startupTimeoutMs?: number
  readinessGraceMs?: number
  onLog?: (source: HarnessLogSource, line: string) => void
}

/** Parse the official CLI readiness line and reject non-loopback or invalid ports. */
export function parseHarnessUrl(line: string): string | undefined {
  const match = READY_LINE.exec(line)
  if (match === null) return undefined
  const port = Number(match[2])
  if (!Number.isInteger(port) || port < 1 || port > 65_535) return undefined
  return match[1]
}

function redactSecrets(line: string): string {
  return line
    .replace(/(bearer\s+)[a-z0-9._~-]+/gi, '$1[redacted]')
    .replace(/((?:api[_-]?key|token|password)\s*[:=]\s*)\S+/gi, '$1[redacted]')
}

/** Split arbitrary process chunks into complete lines while retaining one tail. */
class LineReader {
  private pending = ''

  constructor(private readonly accept: (line: string) => void) {}

  push(chunk: Buffer | string): void {
    this.pending += chunk.toString()
    const lines = this.pending.split(/\r?\n/)
    this.pending = lines.pop() ?? ''
    for (const line of lines) this.accept(line)
  }

  flush(): void {
    if (this.pending.length > 0) this.accept(this.pending)
    this.pending = ''
  }
}

/** Owns one `dsh web` child from readiness through complete process exit. */
export class HarnessSupervisor {
  private child: ChildProcessByStdio<null, Readable, Readable> | undefined
  private readonly tail: string[] = []

  constructor(private readonly options: HarnessSupervisorOptions) {}

  /** Start the loopback server and resolve only after the CLI readiness line. */
  async start(): Promise<string> {
    if (this.child !== undefined) throw new Error('DeepSeek Harness is already running')

    const child = spawn(
      this.options.executable,
      ['--expose-internals', this.options.script, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'],
      {
        cwd: this.options.cwd,
        env: this.options.env,
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      },
    )
    this.child = child
    child.once('exit', () => {
      if (this.child === child) this.child = undefined
    })

    return await new Promise<string>((resolve, reject) => {
      let settled = false
      let readinessTimer: NodeJS.Timeout | undefined
      const startupTimeoutMs = this.options.startupTimeoutMs ?? 90_000
      const timer = setTimeout(() => {
        fail(new Error(`DeepSeek Harness did not become ready within ${String(startupTimeoutMs)} ms${this.tailText()}`))
      }, startupTimeoutMs)

      const finish = (url: string): void => {
        if (settled) return
        settled = true
        cleanup()
        resolve(url)
      }
      const fail = (error: Error): void => {
        if (settled) return
        settled = true
        cleanup()
        reject(error)
      }
      const handleLine = (source: HarnessLogSource, rawLine: string): void => {
        const line = redactSecrets(rawLine)
        this.record(source, line)
        const url = source === 'stdout' ? parseHarnessUrl(line) : undefined
        if (url !== undefined && readinessTimer === undefined) {
          readinessTimer = setTimeout(() => {
            finish(url)
          }, this.options.readinessGraceMs ?? READINESS_GRACE_MS)
        }
      }
      const stdout = new LineReader(line => { handleLine('stdout', line) })
      const stderr = new LineReader(line => { handleLine('stderr', line) })
      const handleExit = (code: number | null, signal: NodeJS.Signals | null): void => {
        stdout.flush()
        stderr.flush()
        fail(new Error(`DeepSeek Harness exited before it was ready (code ${String(code)}, signal ${String(signal)})${this.tailText()}`))
      }
      const handleError = (error: Error): void => {
        fail(new Error(`Unable to start DeepSeek Harness: ${error.message}${this.tailText()}`))
      }
      const cleanup = (): void => {
        clearTimeout(timer)
        if (readinessTimer !== undefined) clearTimeout(readinessTimer)
        child.off('error', handleError)
        child.off('exit', handleExit)
      }

      child.stdout.on('data', chunk => { stdout.push(chunk as Buffer) })
      child.stderr.on('data', chunk => { stderr.push(chunk as Buffer) })
      child.once('error', handleError)
      child.once('exit', handleExit)
    })
  }

  /** Request graceful shutdown, then force termination, and wait for exit. */
  async stop(): Promise<void> {
    const child = this.child
    if (child === undefined || child.exitCode !== null || child.signalCode !== null) return

    const exited = new Promise<void>((resolve) => {
      child.once('exit', () => { resolve() })
    })
    child.kill('SIGTERM')
    if (await this.waitFor(exited, STOP_GRACE_MS)) return

    child.kill('SIGKILL')
    await this.waitFor(exited, FORCE_STOP_GRACE_MS)
  }

  private record(source: HarnessLogSource, line: string): void {
    if (line.length === 0) return
    this.options.onLog?.(source, line)
    this.tail.push(`${source}: ${line}`)
    if (this.tail.length > STARTUP_TAIL_LINES) this.tail.shift()
  }

  private tailText(): string {
    return this.tail.length === 0 ? '' : `\n\nRecent output:\n${this.tail.join('\n')}`
  }

  private async waitFor(promise: Promise<void>, timeoutMs: number): Promise<boolean> {
    let timeout: NodeJS.Timeout | undefined
    const expired = new Promise<false>((resolve) => {
      timeout = setTimeout(() => { resolve(false) }, timeoutMs)
    })
    const result = await Promise.race([promise.then(() => true), expired])
    if (timeout !== undefined) clearTimeout(timeout)
    return result
  }
}
