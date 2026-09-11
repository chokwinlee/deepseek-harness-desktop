import { randomUUID } from 'node:crypto'
/** Exchange the private launch token for a cookie; never forward it to another host. */
export async function connectLoopback(raw) {
  const url = new URL(raw)
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port) throw new Error('Expected an explicit loopback Harness URL')
  const response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(10_000) })
  if (response.status !== 303 && response.status !== 200) throw new Error(`Harness login failed (${response.status})`)
  const cookie = response.headers.getSetCookie().map(value => value.split(';', 1)[0]).join('; ')
  if (!cookie) throw new Error('Harness did not issue a browser session cookie')
  return { origin: url.origin, cookie }
}
export async function callRemote(connection, method, args) {
  const rpcId = randomUUID()
  const response = await fetch(new URL(`/api/${method}`, connection.origin), {
    method: 'POST', headers: { 'content-type': 'application/json', cookie: connection.cookie },
    body: JSON.stringify({ type: 'client-request', rpcId, method, payload: { args } }),
    signal: AbortSignal.timeout(10_000),
  })
  if (!response.ok) throw new Error(`Harness ${method} failed (${response.status})`)
  const envelope = await response.json()
  if (envelope.rpcId !== rpcId) throw new Error('Harness RPC correlation mismatch')
  if (!envelope.result?.ok) throw new Error(envelope.result?.error?.message || 'Harness RPC failed')
  return envelope.result.value
}
