import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import process from 'node:process'
import { timingSafeEqual } from 'node:crypto'

const READINESS_MARK = 'dsh lan remote:'
const ALLOWED_HTTP_PATHS = new Set([
  '/api/host.describe',
  '/api/session.list',
  '/api/session.history',
  '/api/session.prompt',
  '/api/session.cancel',
  '/api/respond',
])
const ALLOWED_UPGRADE_PATH = '/api/events.mux'
const MAX_BODY_BYTES = 2 * 1024 * 1024

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

function reject(socketOrResponse, status, message) {
  if ('writeHead' in socketOrResponse) {
    socketOrResponse.writeHead(status, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
    })
    socketOrResponse.end(message)
    return
  }
  socketOrResponse.end(
    `HTTP/1.1 ${status} ${message}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`,
  )
}

function proxyHeaders(request, target) {
  const headers = {
    accept: request.headers.accept || 'application/json',
    host: `${target.hostname}:${target.port}`,
  }
  if (request.headers['content-type']) headers['content-type'] = request.headers['content-type']
  if (request.headers['user-agent']) headers['user-agent'] = request.headers['user-agent']
  return headers
}

function collectBody(request) {
  return new Promise((resolve, rejectPromise) => {
    const chunks = []
    let size = 0
    request.on('data', chunk => {
      size += chunk.length
      if (size > MAX_BODY_BYTES) {
        rejectPromise(new Error('request body is too large'))
        request.destroy()
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => resolve(Buffer.concat(chunks)))
    request.on('error', rejectPromise)
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

const server = http.createServer(async (request, response) => {
  const path = new URL(request.url || '/', 'http://remote.invalid').pathname
  if (!authorized(request, token)) return reject(response, 401, 'Unauthorized')
  if (request.method !== 'POST' || !ALLOWED_HTTP_PATHS.has(path)) {
    return reject(response, 404, 'Not Found')
  }
  try {
    const body = await collectBody(request)
    const upstream = http.request({
      hostname: target.hostname,
      port: Number(target.port),
      method: 'POST',
      path,
      headers: { ...proxyHeaders(request, target), 'content-length': body.length },
    }, upstreamResponse => {
      const headers = { ...upstreamResponse.headers, 'cache-control': 'no-store' }
      delete headers['set-cookie']
      response.writeHead(upstreamResponse.statusCode || 502, headers)
      upstreamResponse.pipe(response)
    })
    upstream.on('error', () => reject(response, 502, 'Bad Gateway'))
    upstream.end(body)
  } catch {
    if (!response.headersSent) reject(response, 413, 'Payload Too Large')
  }
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
server.requestTimeout = 30_000
server.keepAliveTimeout = 5_000
server.maxRequestsPerSocket = 100
server.listen(port, advertisedAddress, () => {
  process.stdout.write(`${READINESS_MARK} http://${advertisedAddress}:${port}/\n`)
})

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)))
}
