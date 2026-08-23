import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import process from 'node:process'
import { timingSafeEqual } from 'node:crypto'
import { realpathSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const READINESS_MARK = 'dsh lan remote:'
const ALLOWED_HTTP_PATHS = new Set([
  '/api/host.describe',
  '/api/workspace.list',
  '/api/session.list',
  '/api/session.create',
  '/api/session.history',
  '/api/session.attachment',
  '/api/session.models',
  '/api/session.selectModel',
  '/api/session.prompt',
  '/api/session.updateQueue',
  '/api/session.cancel',
  '/api/fileReferences/list',
  '/api/sessionReferenceResolver/candidates',
  '/api/subagent.list',
  '/api/subagent.history',
  '/api/subagent.prompt',
  '/api/subagent.interrupt',
  '/api/respond',
])
const ALLOWED_UPGRADE_PATH = '/api/events.mux'
export const MAX_BODY_BYTES = 136 * 1024 * 1024

export function inspectDeclaredBodyLength(value, maxBytes = MAX_BODY_BYTES) {
  if (value === undefined) return { status: 'ok', bytes: undefined }
  if (Array.isArray(value) || typeof value !== 'string') return { status: 'invalid' }
  const normalized = value.trim()
  if (!/^\d+$/.test(normalized)) return { status: 'invalid' }
  const bytes = Number(normalized)
  if (!Number.isSafeInteger(bytes) || bytes > maxBytes) return { status: 'too-large' }
  return { status: 'ok', bytes }
}

export function streamedBodyExceedsLimit(bytes, maxBytes = MAX_BODY_BYTES) {
  return bytes > maxBytes
}

class BodyTooLargeError extends Error {
  constructor() {
    super('request body is too large')
    this.code = 'BODY_TOO_LARGE'
  }
}

class ClientAbortedError extends Error {
  constructor() {
    super('client aborted the request body')
    this.code = 'CLIENT_ABORTED'
  }
}

function option(name) {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : undefined
}

function fail(message) {
  process.stderr.write(`[dsh-lan-remote] ${message}\n`)
  process.exit(1)
}

function privateIPv4(address) {
  const octets = address.split('.').map(Number)
  return octets.length === 4
    && octets.every(value => Number.isInteger(value) && value >= 0 && value <= 255)
    && (octets[0] === 10
      || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31)
      || (octets[0] === 192 && octets[1] === 168))
}

function preferredAddress() {
  const explicit = process.env.DSH_LAN_REMOTE_HOST?.trim()
  if (explicit && privateIPv4(explicit)) return explicit
  const candidates = []
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (entry.family === 'IPv4' && !entry.internal && privateIPv4(entry.address)) {
        candidates.push(entry.address)
      }
    }
  }
  candidates.sort((left, right) => {
    const leftPreferred = left.startsWith('192.168.') ? 0 : 1
    const rightPreferred = right.startsWith('192.168.') ? 0 : 1
    return leftPreferred - rightPreferred || left.localeCompare(right)
  })
  return candidates[0]
}

function authorized(request, token) {
  const value = request.headers.authorization
  if (typeof value !== 'string' || !value.startsWith('Bearer ')) return false
  const received = Buffer.from(value.slice(7), 'utf8')
  const expected = Buffer.from(token, 'utf8')
  return received.length === expected.length && timingSafeEqual(received, expected)
}

function reject(socketOrResponse, status, message, close = false) {
  if ('writeHead' in socketOrResponse) {
    if (socketOrResponse.headersSent || socketOrResponse.destroyed) return
    const headers = {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
    }
    if (close) headers.Connection = 'close'
    socketOrResponse.writeHead(status, headers)
    socketOrResponse.end(message)
    return
  }
  socketOrResponse.end(
    `HTTP/1.1 ${status} ${message}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`,
  )
}

export function proxyHeaders(request, target, declaredBytes) {
  const headers = {
    accept: request.headers.accept || 'application/json',
    host: `${target.hostname}:${target.port}`,
  }
  if (request.headers['content-type']) headers['content-type'] = request.headers['content-type']
  if (request.headers['user-agent']) headers['user-agent'] = request.headers['user-agent']
  if (declaredBytes !== undefined) headers['content-length'] = String(declaredBytes)
  return headers
}

export function forwardRequestBody(request, upstream, maxBytes = MAX_BODY_BYTES) {
  return new Promise((resolve, rejectPromise) => {
    let size = 0
    let settled = false

    const cleanup = () => {
      request.off('data', onData)
      request.off('end', onEnd)
      request.off('aborted', onAborted)
      request.off('close', onRequestClose)
      request.off('error', onRequestError)
      upstream.off('drain', onDrain)
      upstream.off('error', onUpstreamError)
    }
    const fail = error => {
      if (settled) return
      settled = true
      cleanup()
      request.resume()
      rejectPromise(error)
    }
    const onDrain = () => {
      if (!settled) request.resume()
    }
    const onData = chunk => {
      request.pause()
      size += chunk.length
      if (streamedBodyExceedsLimit(size, maxBytes)) {
        fail(new BodyTooLargeError())
        return
      }
      try {
        if (upstream.write(chunk)) request.resume()
        else upstream.once('drain', onDrain)
      } catch (error) {
        fail(error)
      }
    }
    const onEnd = () => {
      if (settled) return
      settled = true
      cleanup()
      try {
        upstream.end()
        resolve(size)
      } catch (error) {
        rejectPromise(error)
      }
    }
    const onAborted = () => fail(new ClientAbortedError())
    const onRequestClose = () => {
      if (!request.complete) fail(new ClientAbortedError())
    }
    const onRequestError = error => fail(error)
    const onUpstreamError = error => fail(error)

    request.on('data', onData)
    request.on('end', onEnd)
    request.on('aborted', onAborted)
    request.on('close', onRequestClose)
    request.on('error', onRequestError)
    upstream.on('error', onUpstreamError)
    request.resume()
  })
}

function upgradeRequest(request, target) {
  const headers = [
    `GET ${ALLOWED_UPGRADE_PATH} HTTP/1.1`,
    `Host: ${target.hostname}:${target.port}`,
    'Connection: Upgrade',
    'Upgrade: websocket',
  ]
  for (const name of ['sec-websocket-key', 'sec-websocket-version', 'sec-websocket-protocol']) {
    const value = request.headers[name]
    if (typeof value === 'string' && value.length <= 512) headers.push(`${name}: ${value}`)
  }
  return `${headers.join('\r\n')}\r\n\r\n`
}

function inspectHttpRequest(request, response, token) {
  const path = new URL(request.url || '/', 'http://remote.invalid').pathname
  if (!authorized(request, token)) {
    reject(response, 401, 'Unauthorized', true)
    request.resume()
    return undefined
  }
  if (request.method !== 'POST' || !ALLOWED_HTTP_PATHS.has(path)) {
    reject(response, 404, 'Not Found', true)
    request.resume()
    return undefined
  }
  const declared = inspectDeclaredBodyLength(request.headers['content-length'])
  if (declared.status === 'invalid') {
    reject(response, 400, 'Bad Request', true)
    request.resume()
    return undefined
  }
  if (declared.status === 'too-large') {
    reject(response, 413, 'Payload Too Large', true)
    request.resume()
    return undefined
  }
  return { path, declaredBytes: declared.bytes }
}

async function proxyHttpRequest(request, response, target, token, sendContinue = false) {
  const inspected = inspectHttpRequest(request, response, token)
  if (!inspected) return
  if (sendContinue) response.writeContinue()

  let upstreamResponse
  let upstreamResponseError
  let proxyingUpstreamResponse = false
  let settleUpstream
  const upstreamOutcome = new Promise(resolve => {
    settleUpstream = resolve
  })
  let upstream
  try {
    upstream = http.request({
      hostname: target.hostname,
      port: Number(target.port),
      method: 'POST',
      path: inspected.path,
      headers: proxyHeaders(request, target, inspected.declaredBytes),
    }, value => {
      upstreamResponse = value
      const failUpstreamResponse = error => {
        if (upstreamResponseError) return
        upstreamResponseError = error
        if (!proxyingUpstreamResponse) return
        if (!response.headersSent) reject(response, 502, 'Bad Gateway', true)
        else response.destroy(error)
      }
      value.once('aborted', () => failUpstreamResponse(new Error('upstream response aborted')))
      value.once('error', failUpstreamResponse)
      settleUpstream({ response: value })
    })
    upstream.once('error', error => settleUpstream({ error }))
  } catch (error) {
    reject(response, 502, 'Bad Gateway', true)
    request.resume()
    return
  }

  const stopUpstreamWhenClientLeaves = () => {
    if (!response.writableEnded) {
      upstream.destroy()
      upstreamResponse?.destroy()
    }
  }
  response.once('close', stopUpstreamWhenClientLeaves)

  try {
    await forwardRequestBody(request, upstream)
    const outcome = await upstreamOutcome
    if (outcome.error) throw outcome.error
    if (upstreamResponseError) throw upstreamResponseError
    if (response.destroyed) {
      outcome.response.destroy()
      return
    }

    const headers = { ...outcome.response.headers, 'cache-control': 'no-store' }
    delete headers['set-cookie']
    proxyingUpstreamResponse = true
    response.writeHead(outcome.response.statusCode || 502, headers)
    outcome.response.pipe(response)
  } catch (error) {
    upstream.destroy(error instanceof Error ? error : undefined)
    upstreamResponse?.destroy()
    if (error?.code === 'CLIENT_ABORTED' || request.aborted || response.destroyed) return
    if (error?.code === 'BODY_TOO_LARGE') {
      reject(response, 413, 'Payload Too Large', true)
      return
    }
    reject(response, 502, 'Bad Gateway', true)
  }
}

export function createLanRemoteServer(target, token) {
  const server = http.createServer()
  server.on('request', (request, response) => {
    void proxyHttpRequest(request, response, target, token)
  })
  server.on('checkContinue', (request, response) => {
    void proxyHttpRequest(request, response, target, token, true)
  })

  server.on('upgrade', (request, socket, head) => {
    const path = new URL(request.url || '/', 'http://remote.invalid').pathname
    if (!authorized(request, token)) return reject(socket, 401, 'Unauthorized')
    if (path !== ALLOWED_UPGRADE_PATH) return reject(socket, 404, 'Not Found')
    const upstream = net.connect(Number(target.port), target.hostname, () => {
      upstream.write(upgradeRequest(request, target))
      if (head.length) upstream.write(head)
      socket.pipe(upstream).pipe(socket)
    })
    upstream.on('error', () => socket.destroy())
    socket.on('error', () => upstream.destroy())
  })

  server.on('clientError', (_error, socket) => reject(socket, 400, 'Bad Request'))
  server.headersTimeout = 10_000
  server.requestTimeout = 300_000
  server.keepAliveTimeout = 5_000
  server.maxRequestsPerSocket = 100
  return server
}

function launchedDirectly() {
  if (!process.argv[1]) return false
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))
  } catch {
    return false
  }
}

function main() {
  const targetValue = option('--target')
  const token = option('--token')
  const port = Number(option('--port'))
  if (!targetValue || !token || !Number.isInteger(port) || port < 1 || port > 65535) {
    fail('usage: --target http://127.0.0.1:<port> --token <secret> --port <port>')
  }
  if (!/^[a-f0-9]{64}$/.test(token)) fail('token must be 64 lowercase hexadecimal characters')

  const target = new URL(targetValue)
  if (target.protocol !== 'http:' || target.hostname !== '127.0.0.1' || !target.port) {
    fail('target must be an explicit loopback HTTP endpoint')
  }
  const advertisedAddress = preferredAddress()
  if (!advertisedAddress) fail('no private IPv4 address is available')

  const server = createLanRemoteServer(target, token)
  server.listen(port, advertisedAddress, () => {
    process.stdout.write(`${READINESS_MARK} http://${advertisedAddress}:${port}/\n`)
  })

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => server.close(() => process.exit(0)))
  }
}

if (launchedDirectly()) main()
