#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${AIBO_APP:-$ROOT/.derivedData/Build/Products/Debug/aibo.app}"
HOOK="$APP/Contents/Helpers/aibo-hook"
HOOKS_JSON="${HOME}/.cursor/hooks.json"

if [[ ! -x "$HOOK" ]]; then
  echo "error: aibo-hook not found at $HOOK" >&2
  echo "Build the app first (./Scripts/run.sh or xcodebuild), or set AIBO_APP." >&2
  exit 1
fi

export AIBO_HOOK_COMMAND="$HOOK"
export AIBO_HOOKS_JSON="$HOOKS_JSON"

python3 <<'PY'
import json
import os
from pathlib import Path

command = os.environ["AIBO_HOOK_COMMAND"]
path = Path(os.environ["AIBO_HOOKS_JSON"])
marker = "aibo-hook"
events = [
    "sessionStart",
    "sessionEnd",
    "beforeSubmitPrompt",
    "preToolUse",
    "postToolUse",
    "postToolUseFailure",
    "beforeShellExecution",
    "afterAgentResponse",
    "stop",
]

def is_aibo(entry):
    return isinstance(entry, dict) and marker in str(entry.get("command", ""))

if path.exists():
    raw = path.read_text(encoding="utf-8").strip()
    if raw:
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise SystemExit(f"error: {path} is not a JSON object; refusing to overwrite")
    else:
        data = {}
else:
    data = {}

hooks = data.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    raise SystemExit(f"error: {path} has invalid hooks value; refusing to overwrite")

for event in events:
    entries = hooks.get(event, [])
    if entries is None:
        entries = []
    if not isinstance(entries, list):
        raise SystemExit(f"error: hooks.{event} is not an array; refusing to overwrite")
    entries = [e for e in entries if not is_aibo(e)]
    entries.append({"type": "command", "command": command})
    hooks[event] = entries

data["hooks"] = hooks
data.setdefault("version", 1)

path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
tmp.replace(path)
print(f"Installed Cursor hooks → {path}")
print(f"command: {command}")
PY
