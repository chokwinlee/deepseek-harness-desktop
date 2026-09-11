export interface LoopbackConnection {
  origin: string
  cookie: string
}
export function connectLoopback(raw: string): Promise<LoopbackConnection>
export function callRemote<T = unknown>(connection: LoopbackConnection, method: string, args: unknown): Promise<T>
