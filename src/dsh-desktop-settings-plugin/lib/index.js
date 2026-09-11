import { installRemoteV1 } from './remote-v1.js'
export const inject = ['connection', 'typertGateway', 'sessions', 'webServer']
/** Desktop settings and the compatibility boundary for existing native Remotes. */
export function apply(ctx) { installRemoteV1(ctx) }
