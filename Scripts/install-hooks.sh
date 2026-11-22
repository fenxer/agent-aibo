#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${AIBO_APP:-$ROOT/.derivedData/Build/Products/Debug/aibo.app}"
HOOK="$APP/Contents/Helpers/aibo-hook"
CURSOR_HOOKS_JSON="${HOME}/.cursor/hooks.json"
CODEX_HOOKS_JSON="${HOME}/.codex/hooks.json"

if [[ ! -x "$HOOK" ]]; then
  echo "error: aibo-hook not found at $HOOK" >&2
  echo "Build the app first (./Scripts/run.sh or xcodebuild), or set AIBO_APP." >&2
  exit 1
fi

export AIBO_HOOK_COMMAND="$HOOK"
export AIBO_CURSOR_HOOKS_JSON="$CURSOR_HOOKS_JSON"
export AIBO_CODEX_HOOKS_JSON="$CODEX_HOOKS_JSON"

python3 <<'PY'
import json
import os
import tempfile
from pathlib import Path

command = os.environ["AIBO_HOOK_COMMAND"]
marker = "aibo-hook"

cursor_events = [
    "sessionStart",
    "sessionEnd",
    "beforeSubmitPrompt",
    "preToolUse",
    "postToolUse",
    "postToolUseFailure",
    "beforeShellExecution",
    "afterAgentResponse",
    "subagentStart",
    "subagentStop",
    "stop",
]

codex_events = [
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "PermissionRequest",
    "SubagentStart",
    "SubagentStop",
    "Stop",
]


def load_object(path: Path) -> dict:
    if path.exists():
        raw = path.read_text(encoding="utf-8").strip()
        if raw:
            data = json.loads(raw)
            if not isinstance(data, dict):
                raise SystemExit(f"error: {path} is not a JSON object; refusing to overwrite")
            return data
    return {}


def write_atomic(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(data, indent=2, sort_keys=True) + "\n")
        tmp.replace(path)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise


def install_cursor(path: Path) -> None:
    data = load_object(path)
    hooks = data.get("hooks")
    if hooks is None:
        hooks = {}
    elif not isinstance(hooks, dict):
        raise SystemExit(f"error: {path} has invalid hooks value; refusing to overwrite")

    def is_aibo(entry):
        return isinstance(entry, dict) and marker in str(entry.get("command", ""))

    for event in cursor_events:
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
    write_atomic(path, data)
    print(f"Installed Cursor hooks → {path}")


def install_codex(path: Path) -> None:
    data = load_object(path)
    hooks = data.get("hooks")
    if hooks is None:
        hooks = {}
    elif not isinstance(hooks, dict):
        raise SystemExit(f"error: {path} has invalid hooks value; refusing to overwrite")

    def strip_aibo_from_group(group):
        if not isinstance(group, dict):
            return group
        nested = group.get("hooks")
        if not isinstance(nested, list):
            return group
        kept = [
            entry for entry in nested
            if not (isinstance(entry, dict) and marker in str(entry.get("command", "")))
        ]
        if not kept:
            return None
        if len(kept) == len(nested):
            return group
        updated = dict(group)
        updated["hooks"] = kept
        return updated

    for event in codex_events:
        groups = hooks.get(event, [])
        if groups is None:
            groups = []
        if not isinstance(groups, list):
            raise SystemExit(f"error: hooks.{event} is not an array; refusing to overwrite")
        cleaned = []
        for g in groups:
            kept_group = strip_aibo_from_group(g)
            if kept_group is not None:
                cleaned.append(kept_group)
        cleaned.append({"hooks": [{"type": "command", "command": command}]})
        hooks[event] = cleaned

    data["hooks"] = hooks
    write_atomic(path, data)
    print(f"Installed Codex hooks → {path}")


install_cursor(Path(os.environ["AIBO_CURSOR_HOOKS_JSON"]))
install_codex(Path(os.environ["AIBO_CODEX_HOOKS_JSON"]))
print(f"command: {command}")
PY
