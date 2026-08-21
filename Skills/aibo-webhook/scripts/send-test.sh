#!/usr/bin/env bash
# POST a signed Aibo webhook, or GET-probe the public URL.
# Usage:
#   ./scripts/send-test.sh --url URL --secret SECRET
#   ./scripts/send-test.sh --url URL --secret SECRET --body ./payload.json
#   ./scripts/send-test.sh --probe --url URL
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  send-test.sh --url URL --secret SECRET [--body FILE]
  send-test.sh --probe --url URL

Env: AIBO_WEBHOOK_URL, AIBO_WEBHOOK_SECRET
EOF
}

url="${AIBO_WEBHOOK_URL:-}"
secret="${AIBO_WEBHOOK_SECRET:-}"
body_file=""
probe=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="${2:-}"; shift 2 ;;
    --secret) secret="${2:-}"; shift 2 ;;
    --body) body_file="${2:-}"; shift 2 ;;
    --probe) probe=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$url" ]]; then
  echo "missing --url (or AIBO_WEBHOOK_URL)" >&2
  exit 2
fi

if ! command -v curl >/dev/null; then
  echo "curl is required" >&2
  exit 1
fi

if [[ "$probe" -eq 1 ]]; then
  code=$(curl -sS -o /dev/null -w "%{http_code}" -X GET --max-time 15 "$url")
  echo "GET $url -> $code"
  if [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]; then
    if [[ "$code" == "405" ]]; then
      echo "OK: Aibo listener reached (405 on GET is expected)."
    else
      echo "Reached something (not 5xx). Settings Check treats this as up; 405 is the native listener."
    fi
    exit 0
  fi
  echo "FAIL: origin unreachable or 5xx (code: ${code:-empty})." >&2
  exit 1
fi

if [[ -z "$secret" ]]; then
  echo "missing --secret (or AIBO_WEBHOOK_SECRET)" >&2
  exit 2
fi

if ! command -v openssl >/dev/null; then
  echo "openssl is required to sign the body" >&2
  exit 1
fi

tmp=""
response_file=""
cleanup() {
  if [[ -n "$tmp" && -f "$tmp" ]]; then
    rm -f "$tmp"
  fi
  if [[ -n "$response_file" && -f "$response_file" ]]; then
    rm -f "$response_file"
  fi
}
trap cleanup EXIT

if [[ -n "$body_file" ]]; then
  if [[ ! -f "$body_file" ]]; then
    echo "body file not found: $body_file" >&2
    exit 2
  fi
  payload="$body_file"
else
  tmp=$(mktemp)
  payload="$tmp"
  printf '%s' '{"source":"Aibo Skill","status":"OK","summary":"smoke test from aibo-webhook"}' >"$payload"
fi

sig=$(openssl dgst -sha256 -hmac "$secret" -hex "$payload" | awk '{print $NF}')
if [[ -z "$sig" ]]; then
  echo "failed to compute HMAC" >&2
  exit 1
fi

if command -v uuidgen >/dev/null; then
  delivery_id=$(uuidgen)
else
  delivery_id="skill-$(date +%s)"
fi

response_file=$(mktemp)
code=$(curl -sS -o "$response_file" -w "%{http_code}" -X POST --max-time 15 \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: sha256=${sig}" \
  -H "X-Webhook-ID: ${delivery_id}" \
  --data-binary "@${payload}" \
  "$url")

echo "POST $url -> $code (X-Webhook-ID: $delivery_id)"
if [[ -s "$response_file" ]]; then
  echo "body: $(cat "$response_file")"
fi

if [[ "$code" == "200" ]]; then
  echo "OK: signed webhook accepted. Confirm the desktop bubble and Received Logs."
  exit 0
fi

echo "FAIL: expected 200" >&2
exit 1
