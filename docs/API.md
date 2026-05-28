# Chat HTTP API

The `Windows11Zombie-Chat` service exposes a small JSON HTTP API on
`127.0.0.1:7878` (configurable via `ZOMBIE_CHAT_PORT`). The server
refuses to bind to any non-loopback address.

## Authentication

There is no authentication on the loopback endpoint by default. The
trust assumption is that any user able to connect to `127.0.0.1` on
this host is already an Administrator of it.

An optional shared-secret token can be enabled by setting
`ZOMBIE_CHAT_TOKEN` in `secrets\env` and restarting the service.
When set, requests must carry `Authorization: ****** or
the server returns `401 Unauthorized`.

## CSRF and origin

The server rejects requests whose `Host:` header is not
`127.0.0.1`, `localhost`, or `[::1]`. POST requests additionally
require a same-origin `Origin:`/`Referer:` header. Both behaviours
default to enabled and can be loosened only with
`ZOMBIE_ALLOW_REMOTE=1`, which also relaxes the bind check.

## Endpoints

### `GET /` — chat UI

Returns the single-page HTML interface. Cached `Content-Type:
text/html; charset=utf-8`.

### `GET /api/health`

```json
{
  "ok": true,
  "facts": {
    "hostname": "WIN11-BOX",
    "os": "Windows 11 Pro",
    "uptime_s": 123456
  }
}
```

### `GET /api/conversations`

```json
{ "conversations": [ { "id": 1, "created_at": 0.0, "title": "..." } ] }
```

### `GET /api/conversation/{id}`

```json
{
  "messages": [
    { "id": 1, "role": "user|assistant|system", "content": "...", "meta": {} }
  ],
  "events": [
    { "id": 1, "kind": "tool_call|tool_observation|pending_tool_call", "payload": {} }
  ]
}
```

### `GET /api/audit`

Returns the 50 most recent audit entries, parsed.

```json
{ "entries": [ { "id": "...", "ts_utc": "...", "type": "tool_call", "..." } ] }
```

### `GET /api/tools`

Returns the closed tool registry.

```json
{
  "tools": [
    { "name": "fs.read", "classification": "read_only", "description": "..." }
  ]
}
```

### `POST /api/message`

Send a new user message. Creates a conversation when
`conversation_id` is null.

```json
{
  "conversation_id": 1,
  "prompt": "what services are running?"
}
```

Response — accepted, agent processing begins:

```json
{
  "conversation_id": 1,
  "message_id": 42,
  "pending": [ { "tool_call_id": "...", "tool": "svc.status", "classification": "read_only" } ]
}
```

### `POST /api/approve`

Approve or deny a pending tool call.

```json
{
  "tool_call_id": "abc123",
  "decision": "approve",
  "phrase": "yes, I understand this is destructive"
}
```

`decision` is `approve` or `deny`. `phrase` is required when the
classification is `destructive`. Returns the queued tool call's
outcome.

## Request and response limits

| Limit | Value | Rationale |
| --- | --- | --- |
| Max request body | 1 MiB | Bounds memory; an operator prompt is far smaller. |
| Max audit entries in `GET /api/audit` | 50 | Bounded for UI rendering; full log lives in `logs\audit.log`. |
| Max tool calls per turn | per `policy.yaml` `agent.max_tool_calls_per_turn` | Defense against runaway loops. |
| Max elevated tool calls per turn | per `policy.yaml` `agent.max_elevated_calls_per_turn` | Defense against approval-fatigue exploits. |

## Errors

All errors return a JSON body of the form `{ "error": "..." }` with
a 4xx status. The chat UI displays the message verbatim, so error
strings should be operator-readable.

## Stability

These endpoints follow [Semantic Versioning](https://semver.org/).
Breaking changes bump the major version. Additive changes (new
fields, new endpoints) can land in a minor release. The legacy
`proposal_id` field on `/api/approve` was removed; only
`tool_call_id` is accepted.
