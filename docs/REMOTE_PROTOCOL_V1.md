# DSH Remote Protocol v1

This document is the platform-neutral contract shared by the native iOS and
Android DSH Remote clients. It does not add a relay or move Harness execution
off the user's computer.

## Compatibility identifier

- Contract name: `dsh-remote`
- Contract version: `1`
- Current Harness line: `@deepseek-ai/dsh@0.1.0-rc.8`
- Clients must ignore unknown JSON object fields.
- A missing optional capability must degrade to a readable, retryable state.
- A server response with a mismatched `rpcId` must be rejected.

`host.describe` remains the authoritative connection check. A successful HTTP
status from another route is not sufficient evidence that a host is Harness.

## Transport

Remote supports exactly two trust models:

1. A Desktop-issued private-LAN URL imported from its QR code. The URL may use
   private-address HTTP and must include the random bearer credential supplied
   by Desktop.
2. User-managed HTTPS, normally provided by Tailscale Serve. Credentials,
   Tailnet membership, and ACLs remain owned by the user.

HTTP RPC calls use `POST /api/<method>`. Live events use
`GET /api/events.mux` upgraded to WebSocket (`wss` for HTTPS, `ws` for the
authenticated private-LAN exception). When a bearer credential exists, both
transports send `Authorization: Bearer <credential>`.

Clients must reject manually entered cleartext URLs. The only cleartext HTTP
exception is a private LAN endpoint imported from a Desktop-generated pairing
QR code.

## RPC envelope

Request:

```json
{
  "type": "client-request",
  "rpcId": "client-generated-uuid",
  "method": "session.list",
  "payload": {}
}
```

Success response:

```json
{
  "rpcId": "client-generated-uuid",
  "result": {
    "ok": true,
    "value": {}
  }
}
```

Failure response:

```json
{
  "rpcId": "client-generated-uuid",
  "result": {
    "ok": false,
    "error": {
      "code": "stable-machine-code",
      "message": "Human-readable host message"
    }
  }
}
```

## Reviewed capability boundary

The LAN proxy exposes only these RPC routes:

- `host.describe`
- `workspace.list`
- `session.list`
- `session.create`
- `session.history`
- `session.attachment`
- `session.models`
- `session.selectModel`
- `session.prompt`
- `session.updateQueue`
- `session.cancel`
- `fileReferences/list`
- `sessionReferenceResolver/candidates`
- `subagent.list`
- `subagent.history`
- `subagent.prompt`
- `subagent.interrupt`
- `respond`

The only upgrade route is `events.mux`. Settings, credentials, arbitrary
directory operations, raw terminal access, plugin installation, and workspace
mutation remain outside the mobile boundary.

## Live events

Each WebSocket message contains an `rpcId` plus an object payload. Version 1
recognizes these payload `type` values:

- `session/event`
- `session/projection`
- `session/queue`
- `approval/requested`
- `approval/resolved`
- `question/requested`
- `question/resolved`

Unknown event types are ignored. The client combines live events with bounded
polling so reconnects and process suspension cannot permanently hide state.

## Client behavior

- Preserve project names, paths, prompts, and model output as user content.
- Localize product-owned labels and errors only.
- Keep access credentials, model calls, repositories, and execution on the
  user's computer.
- Never expose a generic cleartext network policy for the whole application.
- Bound image decoding and base64 expansion; the wire limit is 136 MiB.
- Persist saved computers locally and provide explicit removal of one or all
  computers.
- Provide an offline Demo client without network or model calls.
- Treat approvals and structured questions as unresolved until the host emits
  or returns an authoritative resolution.

## Cross-platform acceptance

Every native client must cover:

- connection parsing and endpoint policy;
- matching and mismatched RPC identifiers;
- API and HTTP failures;
- session, queue, approval, and question event parsing;
- WebSocket reconnect behavior;
- unknown fields and unknown event types;
- English and Simplified Chinese product copy;
- light, dark, large-text, and screen-reader semantics;
- fresh install, saved-computer, offline Demo, and destructive data-removal
  flows.
