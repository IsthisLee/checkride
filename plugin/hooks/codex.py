#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Adapt Codex hook events to the existing checkride shell gates."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / "hooks"
EVENT = json.load(sys.stdin)
STATE = os.environ.get("PLUGIN_DATA") or os.environ.get("CLAUDE_PLUGIN_DATA") or str(ROOT)
os.environ["NGG_STATE"] = STATE


def run(script, event):
    return subprocess.run(
        ["bash", str(HOOKS / script)], input=json.dumps(event), text=True,
        capture_output=True, cwd=event.get("cwd") or None, env=os.environ,
    )


def synthetic(path, old, new):
    d = dict(EVENT)
    d["tool_name"] = "Edit"
    d["hook_event_name"] = "PreToolUse"
    d["tool_input"] = {"file_path": path, "old_string": old, "new_string": new}
    return d


def edits(patch):
    """Yield changed hunks from Codex apply_patch input."""
    path = None
    kind = None
    old, new = [], []
    in_hunk = False
    for line in patch.splitlines():
        if line.startswith("*** Update File: "):
            if path and (old or new):
                yield path, "\n".join(old), "\n".join(new), kind
            path = line.removeprefix("*** Update File: ").strip()
            kind = "update"
            old, new, in_hunk = [], [], False
        elif line.startswith("*** Add File: ") or line.startswith("*** Delete File: "):
            if path and (old or new):
                yield path, "\n".join(old), "\n".join(new), kind
            path = line.split(": ", 1)[1].strip()
            kind = "delete" if line.startswith("*** Delete File: ") else "add"
            if kind == "delete":
                yield path, "", "", kind
                path = None
            old, new, in_hunk = [], [], False
        elif line.startswith("@@"):
            if in_hunk and (old or new):
                yield path, "\n".join(old), "\n".join(new), kind
            old, new, in_hunk = [], [], True
        elif kind == "add" and line.startswith("+"):
            new.append(line[1:])
        elif in_hunk and line.startswith("+"):
            new.append(line[1:])
        elif in_hunk and line.startswith("-"):
            old.append(line[1:])
        elif in_hunk and line.startswith(" "):
            old.append(line[1:])
            new.append(line[1:])
    if path and (old or new):
        yield path, "\n".join(old), "\n".join(new), kind


def block(result):
    if result.returncode == 2:
        sys.stderr.write(result.stderr)
        raise SystemExit(2)


mode = sys.argv[1]
if mode == "prompt":
    block(run("no-guess-gate/prompt.sh", EVENT))
elif mode == "session":
    result = run("repo-profile/session.sh", EVENT)
    if result.stdout.strip():
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "SessionStart", "additionalContext": result.stdout.strip()
        }}))
elif mode == "pre-bash":
    for script in ("no-guess-gate/pre.sh", "test-integrity/pre.sh", "done-gate/pre.sh"):
        block(run(script, EVENT))
elif mode == "pre-patch":
    block(run("no-guess-gate/pre.sh", EVENT))
    patch = (EVENT.get("tool_input") or {}).get("command", "")
    for rel, old, new, kind in edits(patch):
        path = str((Path(EVENT.get("cwd") or ".") / rel).resolve())
        if kind == "delete" and re.search(r"(^|/)(\.test\.|\.spec\.|__tests__/|tests?/|test_[^/]+\.py$|_test\.(go|py|rb|ex)$|spec/)", rel):
            deletion = dict(EVENT)
            deletion["tool_name"] = "Bash"
            deletion["tool_input"] = {"command": "rm -- " + json.dumps(rel)}
            block(run("test-integrity/pre.sh", deletion))
        if kind == "add":
            continue
        if re.search(r"(^|/)(\.test\.|\.spec\.|__tests__/|tests?/|test_[^/]+\.py$|_test\.(go|py|rb|ex)$|spec/)", rel):
            block(run("test-integrity/pre.sh", synthetic(path, old, new)))
        block(run("project-guard/pre.sh", synthetic(path, old, new)))
elif mode == "post-bash":
    response = EVENT.get("tool_response")
    status = None
    def find_status(value):
        if isinstance(value, dict):
            for key in ("exit_code", "exitCode", "returncode", "return_code"):
                if isinstance(value.get(key), int):
                    return value[key]
            for child in value.values():
                found = find_status(child)
                if found is not None:
                    return found
        elif isinstance(value, list):
            for child in value:
                found = find_status(child)
                if found is not None:
                    return found
        elif isinstance(value, str):
            match = re.search(r"(?:exit(?:ed)?(?: with)? code|exit_code)[:= ]+(\d+)", value, re.I)
            if match:
                return int(match.group(1))
        return None
    status = find_status(response)
    if status is None:
        # Codex does not expose a dedicated PostToolUseFailure event. Mark an unknown
        # result neutrally so it cannot leave a stale failure as the last Bash result.
        root = Path(STATE) / "state" / EVENT.get("session_id", "")
        if EVENT.get("agent_id"):
            root /= "agent-" + EVENT["agent_id"]
        root.mkdir(parents=True, exist_ok=True)
        with (root / "bashseq").open("a") as stream:
            stream.write("?")
    else:
        adapted = dict(EVENT)
        adapted["hook_event_name"] = "PostToolUse" if status == 0 else "PostToolUseFailure"
        block(run("no-guess-gate/bashres.sh", adapted))
elif mode == "post-patch":
    patch = (EVENT.get("tool_input") or {}).get("command", "")
    session = EVENT.get("session_id", "")
    changed = Path(STATE) / "state" / session / "changed"
    changed.parent.mkdir(parents=True, exist_ok=True)
    for rel, _old, _new, _kind in edits(patch):
        path = (Path(EVENT.get("cwd") or ".") / rel).resolve()
        with changed.open("a") as stream:
            stream.write(str(path) + "\n")
elif mode in ("stop", "subagent-stop"):
    scripts = ["no-guess-gate/stop.sh"]
    if mode == "stop":
        scripts.append("done-gate/stop.sh")
    for script in scripts:
        block(run(script, EVENT))
else:
    raise SystemExit("unknown Codex hook mode")
