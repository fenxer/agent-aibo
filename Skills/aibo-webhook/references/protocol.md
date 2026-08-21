# Aibo webhook protocol

Aibo's listener is a small loopback HTTP/1.1 server. It is not a generic webhook SaaS.

## Listener

| | |
| --- | --- |
| Bind | `127.0.0.1` only (loopback interface) |
| Default port | `8787` (user-changeable in Settings) |
| Path | exactly `/webhook` (query string ignored) |
| Local URL | `http://127.0.0.1:<port>/webhook` |

The process that exposes a public or VPN URL must run **on the same Mac** (or have a path to that loopback). Publishing the port on another host does nothing: Aibo will not accept non-loopback connections.

## Request

`POST /webhook`

| Header | Required | Notes |
| --- | --- | --- |
| `Content-Type` | no | Use `application/json` |
| `X-Webhook-Signature` | **yes** | `sha256=` + lowercase hex HMAC-SHA256 of **raw body** with the Shared Secret |
| `X-Webhook-ID` | recommended | Opaque delivery id. Repeats of a recent id return 200 and do not create another bubble. If omitted, Aibo uses `body:` + first 32 hex chars of SHA-256(body) |
| `X-Aibo-Test` | no | Aibo's own Settings probe. Any non-empty value skips Received Logs. **Do not** send this from real senders or acceptance tests |

HMAC is over the exact bytes on the wire. Pretty-print, key reordering, or UTF-8 vs Latin-1 mismatches all 401.

### Body

JSON object preferred. Display cap is 280 characters (truncated with `…`).

| Field | Role |
| --- | --- |
| `source` | Header label on the bubble. Fallbacks: `sender`, `from`, then `event` |
| `status` | Capsule text |
| `summary` | Line beside the capsule. Fallbacks: `message`, `text` |

Example:

```json
{
  "source": "Deploy",
  "status": "OK",
  "summary": "main shipped to production"
}
```

Empty or non-JSON bodies still need a valid signature; the bubble text then falls back to a generic line.

Do not send Cursor Cloud Agent webhooks here. That is a different product. Prefer an explicit `source` rather than relying on `event` heuristics.

## Response

Plain text reason phrase. No JSON error body.

| Code | Meaning |
| --- | --- |
| 200 | Accepted, **or** duplicate id (no new bubble) |
| 401 | Missing/invalid signature, or empty Secret |
| 404 | Path ≠ `/webhook` |
| 405 | Method ≠ `POST` (GET is what Settings **Check** uses; reachable origin often returns 405) |
| 400 | Unreadable HTTP request |

## Settings fields

| UI | Meaning |
| --- | --- |
| Local URL | Loopback listener. Do not give this to SaaS. |
| Secret | HMAC key (Keychain). Regenerating breaks every sender. |
| Tunnel URL | URL **senders** (or the adapter) POST to. Must reach this Mac's `/webhook`. `http` or `https`. |
| Connectivity / Check | Event-driven GET to Tunnel URL. 5xx / network error = down. Other HTTP codes (including 405) = OK. |

## Topologies

```
Direct:   Source --(Aibo JSON + HMAC)--> Tunnel URL --> 127.0.0.1:port/webhook
Adapter:  Source --(vendor payload)--> adapter --(Aibo JSON + HMAC)--> Tunnel URL --> listener
```

Tunnel URL in Aibo is always the URL that hits Aibo, never the vendor-facing adapter URL.

## Signing snippets

OpenSSL (same as `scripts/send-test.sh`):

```bash
SIG=$(openssl dgst -sha256 -hmac "$SECRET" -hex "$BODY_FILE" | awk '{print $NF}')
# header: X-Webhook-Signature: sha256=$SIG
```

Python:

```python
import hmac, hashlib
sig = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
header = f"sha256={sig}"
```

Node:

```js
import { createHmac } from "node:crypto";
const header = "sha256=" + createHmac("sha256", secret).update(body).digest("hex");
```
