---
name: aibo-webhook
description: >-
  Guides wiring a product's notifications into Aibo desktop bubbles via Aibo's
  signed HTTP webhook. Covers listener setup, choosing public ingress (managed
  tunnel, mesh VPN funnel, or the user's own reverse proxy — never prescribe a
  vendor), sender integration (direct, payload adapter, or an ingest hop the
  user already runs — never invent a relay), signed smoke tests, and acceptance.
  Use when the user mentions Aibo webhook, Setup Guide, sending CI/deploy/product
  events to Aibo, HMAC X-Webhook-Signature, or exposing Aibo's local listener.
---

# Aibo Webhook

Get events from **the user's product** onto the Aibo on **this Mac**.

Protocol details: [references/protocol.md](references/protocol.md).
Smoke test: execute [scripts/send-test.sh](scripts/send-test.sh) (do not rewrite the signer).

## Role

You **advise**. The user **chooses** how the Mac is reached from the internet (or their LAN). Do not install a tunnel/VPN/proxy, rewrite DNS, or pick a vendor because it is convenient. Do not stand up a Worker, queue consumer, or ingest relay because a sender got a bot challenge — only reuse a hop they already operate and name.

Never write the Shared Secret into git, README, CI logs, screenshots, or committed env files. Ask the user to paste it, or read it from a local untracked file they name.

Aibo is the receiver. This skill does not run inside Aibo; it tells the **sending** project (and the person at the Mac) how to reach it.

## Workflow

Copy and keep this checklist updated as you go:

```
Aibo webhook
- [ ] 1. Intake (Aibo running; values from Settings; what to send)
- [ ] 2. Listener on (Status Running; Local URL + Secret known)
- [ ] 3. Ingress chosen by the user; Tunnel URL saved; Connectivity OK
- [ ] 4. Sender speaks Aibo's contract (direct, adapter, or existing ingest hop)
- [ ] 5. Signed POST smoke test → bubble + Received Logs
- [ ] 6. Acceptance
```

### 1. Intake

Confirm, don't assume:

1. Aibo is installed and running on the Mac that should show bubbles.
2. Ask the user to open **Aibo → Settings → Webhook** and read back (or paste):
   - Listener toggle and **Status** (want Running)
   - **Port** / **Local URL** (default `http://127.0.0.1:8787/webhook`)
   - **Secret**
   - **Tunnel URL** if already filled
3. What should appear on the desktop (product name, which events, rough wording for `status` / `summary`).
4. How they want this Mac reachable. If they already have a tunnel, mesh VPN, or a reverse proxy, **use that**. If they don't know, go to step 3 and stop after suggestions.
5. Whether they already run a forwarder for **signed Aibo JSON** (an ingest URL they can name). If yes, CI that cannot hit Tunnel URL can POST there. If no, do not create one.

If Aibo is not running or the listener is off, finish that before writing sender code.

### 2. Listener (Aibo side)

Aibo binds **loopback only**. Nothing on the LAN or WAN can hit the port unless a process **on this Mac** forwards to `127.0.0.1:<port>/webhook`.

Settings:

- Toggle listen **on**
- **Status** = Running
- Copy **Secret** (regenerating invalidates every sender at once — confirm first)
- **Tunnel URL** = the public (or VPN) URL that reaches this Mac's `/webhook` (include the path). Connectivity Check and senders that can hit it POST here. A CI job blocked by an edge challenge may POST to a **pre-existing** ingest hop instead — that hop still targets this URL.

Local URL is not the URL you give GitHub / CI / a SaaS. Give them Tunnel URL, or an ingest URL they already run.

### 3. Public ingress — suggest, then wait

Aibo does not include a tunnel. Something in front must terminate the public (or VPN) URL and forward to Local URL **on this Mac**, preserving path `/webhook` (or rewriting **to** `/webhook`).

If the user has not chosen, present these **categories** with 1–2 examples each, tradeoffs in one line, then **stop**:

| Category | Examples (not a ranking) | Fits when |
| --- | --- | --- |
| Managed HTTPS tunnel | Cloudflare Tunnel, ngrok, similar | They want a public hostname quickly; accept a helper process on the Mac |
| Mesh VPN expose | Tailscale Funnel/Serve, similar | They already live on that network |
| Own reverse proxy | Caddy/nginx/Traefik on a VPS, or a small relay they already run | They want their own domain and ops; the VPS still needs a path **to this Mac** (VPN, reverse SSH, tunnel). Opening Aibo's port on the internet does not work — Aibo will not bind it. |

Ask: what they already run, whether senders need a stable public HTTPS URL, whether an edge WAF/bot challenge might block server User-Agents (GitHub Actions against a Cloudflare Tunnel hostname is a known case).

If they need CI to POST and they pick a managed tunnel that challenges bots: ask whether they **already** have a forwarder for signed Aibo JSON. Yes → use it in step 4. No → do not create one; they can skip the challenge if they control the WAF, pick another ingress category, or later name a hop they already run.

After they pick, help configure **that** option only. Paste the resulting URL into **Tunnel URL**. In Settings, click **Check**. Treat Connectivity **OK** as the ingress health signal (Aibo probes with GET; the listener itself answers **405** to GET, which counts as reachable).

Do not treat a helper daemon being “running” as proof the edge can reach this Mac.

### 4. Sender

Three topologies. Pick from what already exists; do not invent a hop:

- **Direct** — the source can POST arbitrary JSON and custom headers. Point it at Tunnel URL. Sign with Aibo's Secret. This is the common case for homegrown backends and any “generic webhook” field. GitHub Actions can sign too — that does **not** mean it can reach Tunnel URL (see ingest hop).
- **Adapter** — the source has a **fixed body or its own signature** (native GitHub/Ghost/etc. webhooks). A tiny relay verifies the vendor, maps fields to Aibo JSON, HMAC-signs with Aibo's Secret, and POSTs to Tunnel URL. The SaaS webhook URL is the **adapter**, not Aibo. Settings **Tunnel URL** is still the URL that reaches Aibo. Use an adapter only for payload shape, never as a workaround for a bot challenge.
- **Existing ingest hop** — the source already speaks Aibo JSON + HMAC, but cannot POST to Tunnel URL. Typical: GitHub Actions / other CI User-Agents hitting a managed HTTPS tunnel that runs bot challenge (Cloudflare Tunnel custom hostnames often return **403** HTML “Just a moment…” — not a signing bug). If the user **already** runs a forwarder that accepts that signed body and POSTs it to Tunnel URL, point the sender at **that** URL (they name it). Settings **Tunnel URL** stays the URL that reaches Aibo.

**If they do not already have an ingest hop, stop.** Do not create a Worker, queue consumer, reverse-proxy app, or “tiny relay” in the sending repo so CI can get past a challenge. Offer: skip/disable the challenge on that hostname if they control the WAF (many free plans cannot); pick a different ingress category that does not challenge server User-Agents; or they already operate a forwarder and will paste its URL. Wait.

Required request (see [references/protocol.md](references/protocol.md)):

- `POST` to Tunnel URL, or to a pre-existing ingest URL that forwards there (path that becomes `/webhook` on Aibo)
- Body: UTF-8 JSON. Prefer `source`, `status`, `summary` (status → capsule, summary → text beside it, ≤280 chars)
- `X-Webhook-Signature: sha256=<hex>` — HMAC-SHA256 of the **raw body bytes** with the Secret
- `X-Webhook-ID` — unique per delivery; reuse on retry (dedup window is recent IDs)

Sign the bytes you send. Re-serializing JSON after signing fails verification.

Do not send `X-Aibo-Test` for real or acceptance deliveries (that header is Aibo's own probe; it skips Received Logs).

Never commit the Secret. Prefer a secret store / CI secret / local env.

### 5. Smoke test

From a machine that can reach Tunnel URL (often this Mac):

```bash
# Reachability (expect 405 from Aibo; other 2xx–4xx may be a proxy in front)
curl -sS -o /dev/null -w "%{http_code}\n" -X GET "$AIBO_WEBHOOK_URL"

# Signed POST — 200 and a desktop bubble
./scripts/send-test.sh --url "$AIBO_WEBHOOK_URL" --secret "$AIBO_WEBHOOK_SECRET"
```

Ask the user to look at the desktop bubble (`source` + `status` + `summary`) and **Settings → Webhook → Received Logs**.

Always smoke-test Tunnel URL from this Mac first. If CI will use a pre-existing ingest URL, run the signed POST against that URL too — do not create a hop to make the test pass.

Then one negative check: same command with a wrong secret must be **401** and no new bubble.

### 6. Acceptance

All of these:

- [ ] Listener Status Running
- [ ] Tunnel URL set (includes `/webhook` unless a rewrite is documented)
- [ ] Settings **Check** → Connectivity OK
- [ ] Signed POST → HTTP 200
- [ ] Bubble shows the intended source / status / summary
- [ ] Same `X-Webhook-ID` again → 200 and **no** second bubble
- [ ] Bad signature → 401
- [ ] Real sender path (CI job, app code, adapter, or existing ingest hop) uses env/secrets, not a hardcoded Secret
- [ ] User confirmed they are happy with the ingress they chose
- [ ] No new relay/Worker/adapter was added solely to dodge a bot challenge

Stop. Do not add extra products, dashboards, a second tunnel, or an ingest relay “just in case”.

## Troubleshooting (short)

| Symptom | Likely cause |
| --- | --- |
| GET/POST hang or 5xx | Ingress cannot reach this Mac; Aibo quit; listener off; wrong port |
| 404 | Path is not `/webhook` when it hits Aibo |
| 405 on POST | Method stripped/rewritten; POST did not arrive as POST |
| 401 | Wrong Secret; signed a different byte string than the body; `sha256=` prefix missing |
| 200, no bubble | Duplicate `X-Webhook-ID` / identical unsigned body (fallback id); dismiss mode; Aibo hidden |
| 200, no Received Logs | `X-Aibo-Test` was set; or looking at the wrong Mac |
| 403 / HTML “Just a moment…” from CI (e.g. GitHub Actions → Cloudflare Tunnel) | Edge bot/WAF, not a bad signature and not a missing adapter. If the user already has a forwarder for signed Aibo JSON, POST there. If not: skip the challenge on that hostname, pick a different ingress, or wait — do not create an adapter or relay |
| Native GitHub/Ghost/etc. payload looks wrong | Need an adapter for **payload shape**; do not point vendor-native webhooks at Aibo and hope |

Settings **Check** failing while `curl` to localhost works means the **ingress** is the problem, not the signer.
