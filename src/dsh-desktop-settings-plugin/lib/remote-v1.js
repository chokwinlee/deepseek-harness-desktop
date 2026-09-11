import { randomUUID } from 'node:crypto'
import { WebSocketServer } from 'ws'
import { HARNESS_VERSION } from './upgrade.js'

const methods = new Set(['host.describe', 'workspace.list', 'session.list', 'session.create', 'session.history', 'session.attachment', 'session.models', 'session.selectModel', 'session.prompt', 'session.updateQueue', 'session.cancel', 'subagent.list', 'subagent.history', 'subagent.prompt', 'subagent.interrupt'])
const failure = error => ({ ok: false, error: { code: error.code || 'desktop/remote-failed', message: error.message || String(error), details: {} } })

/** Bridge the upstream gap between draining an inbox item and journaling its user message. */
export function promptReceipts(limit = 2048) {
  const pending = new Map()
  const accepted = new Map()
  return (sessionId, requestId, admit) => {
    const key = JSON.stringify([sessionId, requestId])
    if (accepted.has(key)) return Promise.resolve(accepted.get(key))
    if (pending.has(key)) return pending.get(key)
    const receipt = Promise.resolve().then(admit).then(value => {
      accepted.set(key, value)
      if (accepted.size > limit) accepted.delete(accepted.keys().next().value)
      return value
    }).finally(() => pending.delete(key))
    pending.set(key, receipt)
    return receipt
  }
}

/** Read exactly one stream baseline and release all observation listeners. */
export async function firstFrame(gateway, namespace, method, args, signal) {
  const abort = new AbortController()
  const combined = signal ? AbortSignal.any([signal, abort.signal]) : abort.signal
  const stream = await gateway.stream({ namespace, method, args, signal: combined })
  const iterator = stream[Symbol.asyncIterator]()
  try {
    const next = await iterator.next()
    if (next.done) throw new Error(`Missing ${namespace}/${method} baseline`)
    return next.value
  } finally { abort.abort(); await iterator.return?.() }
}

export async function invokeLegacy(ctx, endpoint, payload, signal) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Invalid Remote payload')
  const gateway = ctx.typertGateway
  const invoke = (namespace, method, args) => gateway.invoke({ namespace, method, args, signal })
  switch (endpoint) {
    case 'host.describe': return { version: HARNESS_VERSION, attachedSessions: ctx.sessions.list().length }
    case 'workspace.list': return (await firstFrame(gateway, 'workspace', 'follow', {}, signal)).value
    case 'session.list': return invoke('session', 'list', { _request: payload })
    case 'session.history':
    case 'subagent.history': {
      const address = endpoint === 'session.history' ? { kind: 'session', sessionId: payload.sessionId } : { kind: 'subagent', parentSessionId: payload.parentSessionId, childSessionId: payload.childSessionId, mode: payload.mode }
      const snapshot = await firstFrame(gateway, 'session', 'follow', { request: { address, ...(payload.maxMessages === undefined ? {} : { maxMessages: payload.maxMessages }) } }, signal)
      return { events: snapshot.records, hasMore: snapshot.hasMore, projections: snapshot.projections }
    }
    case 'session.models': {
      const catalog = await invoke('session', 'modelCatalog', {})
      const snapshot = await firstFrame(gateway, 'session', 'follow', { request: { address: { kind: 'session', sessionId: payload.sessionId }, maxMessages: 1 } }, signal)
      const current = snapshot.projections.values.modelSelection?.next ?? catalog.default
      return { current, routable: catalog.routableProviders.includes(current.provider), groups: catalog.groups, failures: catalog.failures }
    }
    case 'subagent.list': return invoke('subagents', 'list', { parentSessionId: payload.parentSessionId })
    case 'subagent.prompt': return invoke('subagents', 'prompt', { request: payload })
    case 'subagent.interrupt': return invoke('subagents', 'interruptByParent', { childSessionId: payload.childSessionId, parentSessionId: payload.parentSessionId, mode: payload.mode })
    case 'session.prompt': return invoke('session', 'prompt', { request: { ...payload, requestId: payload.requestId ?? randomUUID() } })
    default: {
      if (!methods.has(endpoint)) throw new Error('Unsupported Remote method')
      return invoke('session', endpoint.slice('session.'.length), { request: payload })
    }
  }
}

/** Keep the installed native Remote v1 clients on the reviewed API surface. */
export function installRemoteV1(ctx) {
  const admitPrompt = promptReceipts()
  for (const endpoint of methods) ctx.effect(() => ctx.connection.fetch.register({
    path: `/api/${endpoint}`, methods: ['POST'], requestBody: 'buffered',
    fetch: async request => {
      let envelope
      try {
        envelope = await request.json()
        if (envelope.type !== 'client-request' || envelope.method !== endpoint || typeof envelope.rpcId !== 'string' || !envelope.rpcId) return Response.json({ error: 'Invalid RPC envelope' }, { status: 400 })
        const payload = endpoint === 'session.prompt' ? { ...envelope.payload, requestId: envelope.rpcId } : envelope.payload
        const invoke = () => invokeLegacy(ctx, endpoint, payload, request.signal)
        const value = endpoint === 'session.prompt'
          ? await admitPrompt(payload.sessionId, envelope.rpcId, invoke)
          : await invoke()
        return Response.json({ type: 'server-response', rpcId: envelope.rpcId, result: { ok: true, value } })
      } catch (error) { return Response.json({ type: 'server-response', rpcId: envelope?.rpcId, result: failure(error) }) }
    },
  }), `desktop Remote v1 ${endpoint}`)

  const pending = new Map()
  const sockets = new Set()
  const server = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 })
  const send = (socket, payload, rpcId = randomUUID()) => {
    if (socket.readyState === 1 && socket.bufferedAmount < 4 * 1024 * 1024) socket.send(JSON.stringify({ rpcId, payload }))
    else if (socket.readyState === 1) socket.close(1013, 'Slow Remote client; reconnect')
  }
  const broadcast = payload => { for (const socket of sockets) send(socket, payload) }
  ctx.on('session/event', (session, event) => broadcast({ type: 'session/event', sessionId: session.id, event }))
  // Reuse the upstream stream owners so queue/projection lifetimes track the socket.
  async function controls(socket, signal) {
    const stream = await ctx.typertGateway.stream({ namespace: 'session', method: 'control', args: {}, signal })
    const emitQueue = (sessionId, items) => send(socket, { type: 'session/queue', sessionId, items: items.map(item => ({ ...item, content: item.message.content })) })
    for await (const frame of stream) {
      if (frame.type === 'baseline') {
        for (const [id, items] of Object.entries(frame.value.queues)) emitQueue(id, items)
        for (const [id, value] of Object.entries(frame.value.projections)) send(socket, { type: 'session/projection', sessionId: id, projections: value })
      } else if (frame.type === 'queue') emitQueue(frame.sessionId, frame.items)
      else if (frame.type === 'projection') send(socket, { type: 'session/projection', sessionId: frame.sessionId, key: frame.key, value: frame.value, seq: frame.seq })
    }
  }
  const handler = ctx.connection.createSharedFetchHandler('/api')
  async function result(clientId, eventId, outcome) {
    const response = await handler.fetch(new Request('http://dsh.internal/api/$events/result', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method: '$events/result', payload: { args: { clientId, eventId, outcome } } }),
    }))
    const body = await response.json()
    if (!body.result?.ok) throw new Error(body.result?.error?.message || 'Remote decision was rejected')
  }
  async function events(socket, signal) {
    let clientId
    const stream = await ctx.typertGateway.wireStream.open('$events', { args: {} }, signal)
    for await (const frame of stream) {
      if (frame.type === 'ready') clientId = frame.clientId
      else if (frame.type === 'waterfall') {
        const kind = frame.event === 'approval/request' ? 'approval' : frame.event === 'user-questions/request' ? 'question' : undefined
        if (!kind) { await result(clientId, frame.eventId, { kind: 'next' }); continue }
        pending.set(frame.eventId, { clientId, kind, agentId: frame.agentId, socket })
        send(socket, { ...frame.request, type: `${kind}/requested`, sessionId: frame.agentId, ...(kind === 'approval' ? { approvalId: frame.eventId } : {}) }, frame.eventId)
      } else if (frame.type === 'cancel') {
        const entry = pending.get(frame.eventId)
        pending.delete(frame.eventId)
        if (entry) send(socket, { type: `${entry.kind}/resolved`, sessionId: entry.agentId, approvalId: frame.eventId, questionRpcId: frame.eventId }, frame.eventId)
      }
    }
  }
  ctx.effect(() => ctx.connection.fetch.register({
    path: '/api/respond', methods: ['POST'], requestBody: 'buffered',
    fetch: async request => {
      try {
        const envelope = await request.json()
        const entry = pending.get(envelope.rpcId)
        if (envelope.type !== 'client-response' || !entry) throw new Error('Decision is no longer pending')
        const value = envelope.result?.value
        let outcome
        if (envelope.result?.ok === false && entry.kind === 'question') outcome = { kind: 'rejected', error: { name: 'Error', code: 'cancelled', message: 'User cancelled the question' } }
        else {
          if (value?.sessionId !== entry.agentId) throw new Error('Decision session mismatch')
          if (entry.kind === 'approval') {
            if (value.approvalId !== envelope.rpcId || !['allowed-once', 'rejected'].includes(value.outcome)) throw new Error('Invalid approval decision')
            outcome = { kind: 'result', value: value.outcome }
          } else {
            if (!Array.isArray(value.answer?.answers)) throw new Error('Invalid question answer')
            outcome = { kind: 'result', value: value.answer }
          }
        }
        await result(entry.clientId, envelope.rpcId, outcome)
        pending.delete(envelope.rpcId)
        send(entry.socket, { type: `${entry.kind}/resolved`, sessionId: entry.agentId, approvalId: envelope.rpcId, questionRpcId: envelope.rpcId }, envelope.rpcId)
        return Response.json({ accepted: true })
      } catch (error) { return Response.json({ accepted: false, reason: error.message }) }
    },
  }), 'desktop Remote v1 decisions')
  ctx.effect(() => ctx.webServer.registerUpgrade({ path: '/api/events.mux', handler: (request, socket, head) => {
    const rejection = ctx.connection.requestRejection(request)
    if (rejection) { socket.end(`HTTP/1.1 ${rejection} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`); return }
    server.handleUpgrade(request, socket, head, websocket => {
      const abort = new AbortController()
      sockets.add(websocket)
      websocket.on('error', () => abort.abort())
      websocket.on('close', () => { abort.abort(); sockets.delete(websocket); for (const [id, entry] of pending) if (entry.socket === websocket) pending.delete(id) })
      void Promise.all([controls(websocket, abort.signal), events(websocket, abort.signal)]).catch(() => websocket.close(1011, 'Remote stream closed'))
    })
  } }), 'desktop Remote v1 live events')
  ctx.effect(() => () => { for (const socket of sockets) socket.terminate(); server.close() }, 'desktop Remote v1 sockets')
}
