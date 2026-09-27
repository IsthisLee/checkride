#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Adapt Codex hook events to the existing checkride shell gates."""
import json
import hashlib
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / "hooks"
STOP_RETRY_LIMIT = 8


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(2)


mode = sys.argv[1] if len(sys.argv) > 1 else ""
if os.environ.get("NGG_INNER"):
    if mode in ("stop", "subagent-stop"):
        print('{"continue":true}')
    raise SystemExit(0)

try:
    EVENT = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError) as exc:
    fail(f"Checkride Codex hook received invalid JSON: {exc}")
if not isinstance(EVENT, dict):
    fail("Checkride Codex hook expected a JSON object.")


def project_root():
    repo = Path(os.path.abspath(EVENT.get("cwd") or os.getcwd()))
    try:
        root = subprocess.run(["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True, encoding="utf-8", timeout=5)
        if root.returncode == 0 and root.stdout.strip():
            repo = Path(os.path.abspath(root.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        return repo
    return repo


REPO = project_root()
def state_path():
    configured = (os.environ.get("NGG_STATE") or os.environ.get("PLUGIN_DATA")
                  or os.environ.get("CLAUDE_PLUGIN_DATA"))
    if configured:
        return configured
    repo = REPO
    helper = HOOKS / "lib" / "state_path.py"
    try:
        result = subprocess.run([sys.executable, str(helper), str(repo)], check=True,
                                capture_output=True, text=True, encoding="utf-8", timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        fail(f"Checkride could not find an external state directory: {exc}")
    value = result.stdout.strip()
    state = Path(value).resolve() if value else repo
    if not value or state == repo or repo in state.parents:
        fail("Checkride state directory must be outside the repository.")
    return value


def duplicate_plugin_hook():
    marker = REPO / ".checkride" / ".managed-by-checkride"
    return marker.is_file() and ROOT.resolve() != (REPO / ".checkride").resolve()


if duplicate_plugin_hook():
    if mode in ("stop", "subagent-stop"):
        print('{"continue":true}')
    raise SystemExit(0)

STATE = state_path()
os.environ["NGG_STATE"] = STATE


def run(script, event, judge_provider=False, capture_start_error=False):
    env = dict(os.environ)
    env["CLAUDE_PROJECT_DIR"] = str(REPO)
    if judge_provider:
        env["NGG_JUDGE_PROVIDER"] = "codex"
    try:
        return subprocess.run(
            ["bash", str(HOOKS / script)], input=json.dumps(event), text=True,
            capture_output=True, cwd=event.get("cwd") or None, env=env,
        )
    except (OSError, subprocess.SubprocessError, TypeError, ValueError) as exc:
        message = f"Checkride could not start hook {script}: {exc}"
        if capture_start_error:
            return subprocess.CompletedProcess(["bash", str(HOOKS / script)], 2, "", message)
        fail(message)


def stop_retry_file(event, hook_mode):
    turn_id = event.get("turn_id")
    if not turn_id:
        prompt = Path(STATE) / "state" / str(event.get("session_id") or "") / "prompt"
        try:
            turn_id = prompt.read_text(encoding="utf-8")
        except OSError:
            turn_id = ""
    identity = json.dumps([hook_mode, event.get("session_id"), turn_id, event.get("agent_id")],
                          ensure_ascii=False, separators=(",", ":"))
    key = hashlib.sha256(identity.encode("utf-8")).hexdigest()
    return Path(STATE) / "stop-retries" / f"{key}.count"


def end_stop(reason):
    message = " ".join(reason.split())[:1000] or "Checkride could not verify this turn."
    print(json.dumps({"continue": False, "stopReason": message,
                      "systemMessage": message}, ensure_ascii=False))
    raise SystemExit(0)


def clear_retry_file(path):
    try:
        path.unlink(missing_ok=True)
        return True
    except OSError:
        return False


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


TEST_PATH = re.compile(r"(^|/)([^/]+\.(test|spec)\.[^/]+|__tests__|tests?|test_[^/]+\.py|[^/]+_test\.(go|py|rb|ex)|spec)(/|$)")
FILE_ACTIONS = {"write", "edit", "patch", "create", "delete", "remove", "append", "replace", "update", "save", "move", "rename", "upload", "put"}
PATH_KEYS = {"file_path", "path", "filename", "filepath"}
CONTENT_KEYS = {"content", "new_content", "old_content", "text", "patch", "old_string", "new_string"}


def file_fields(value, names):
    found = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in names and isinstance(child, str) and child:
                found.append(child)
            elif isinstance(child, (dict, list)):
                found.extend(file_fields(child, names))
    elif isinstance(value, list):
        for child in value:
            found.extend(file_fields(child, names))
    return found


def write_action(tool, tool_input):
    details = tool_input if isinstance(tool_input, dict) else {}
    tokens = [part for part in re.split(r"[^a-z0-9]+", tool.lower()) if part]
    action = next((part for part in tokens if part in FILE_ACTIONS), "")
    explicit = next((details[key].lower() for key in ("operation", "action", "op", "mode")
                     if isinstance(details.get(key), str)), "")
    if explicit in FILE_ACTIONS:
        action = explicit
    paths = file_fields(details, PATH_KEYS)
    has_content = bool(file_fields(details, CONTENT_KEYS))
    file_tool = any(part in tokens for part in ("file", "filesystem", "document"))
    if action and file_tool:
        return action, paths
    if explicit in FILE_ACTIONS:
        return explicit, paths
    if paths and has_content:
        return action or "write", paths
    return "", paths


def patch_events(event):
    tool_input = event.get("tool_input")
    patch = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(patch, str) or not patch.strip():
        fail("Checkride cannot inspect apply_patch: tool_input.command is missing.")
    if not patch.startswith("*** Begin Patch") or not patch.rstrip().endswith("*** End Patch"):
        fail("Checkride cannot inspect apply_patch: patch format is not recognized.")
    if re.search(r"^\*\*\* Move to:", patch, re.I | re.M):
        fail("Checkride cannot inspect apply_patch move targets; split the move into supported edits.")
    try:
        changes = list(edits(patch))
    except (ValueError, IndexError) as exc:
        fail(f"Checkride cannot inspect apply_patch: {exc}")
    if not changes:
        fail("Checkride cannot inspect apply_patch: no changed paths were found.")
    return changes


def check_edit(path, old, new):
    absolute = os.path.abspath(os.path.join(EVENT.get("cwd") or os.getcwd(), path))
    return synthetic(absolute, old, new)


def git_root(event):
    cwd = str(Path(event.get("cwd") or os.getcwd()).resolve())
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True, encoding="utf-8")
    return Path(result.stdout.strip()).resolve() if result.returncode == 0 else None


def git_snapshot(event):
    root = git_root(event)
    if root is None:
        return None
    paths = set()
    for args in (["diff", "--name-only", "--no-renames", "-z", "HEAD"],
                 ["ls-files", "--others", "--exclude-standard", "-z"]):
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
        if result.returncode != 0:
            return None
        paths.update(p.decode("utf-8", "surrogateescape") for p in result.stdout.split(b"\0") if p)
    snapshot = {}
    for rel in paths:
        path = root / rel
        try:
            snapshot[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
        except FileNotFoundError:
            snapshot[rel] = None
        except OSError:
            snapshot[rel] = "unreadable"
    return root, snapshot


def snapshot_file(event):
    key = str(EVENT.get("tool_use_id") or EVENT.get("turn_id") or EVENT.get("session_id") or "")
    name = hashlib.sha256(key.encode("utf-8")).hexdigest()
    return Path(STATE) / "state" / (EVENT.get("session_id") or "") / "pending" / f"{name}.json"


def save_snapshot(event):
    current = git_snapshot(event)
    if current is None:
        return
    root, before = current
    path = snapshot_file(event)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"root": str(root), "before": before}), encoding="utf-8")


def record_bash_changes(event):
    path = snapshot_file(event)
    try:
        before = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        before = None
    try:
        path.unlink()
    except OSError:
        pass
    current = git_snapshot(event)
    if before is None or current is None:
        root = git_root(event) or Path(event.get("cwd") or os.getcwd()).resolve()
        record_changed([str(root / "__checkride_unknown_change__.sh")])
        return
    root, after = current
    old = before["before"] if before.get("root") == str(root) else {}
    changed = [str(root / rel) for rel in old.keys() | after.keys() if old.get(rel) != after.get(rel)]
    record_changed(changed)


def record_changed(paths):
    changed = Path(STATE) / "state" / (EVENT.get("session_id") or "") / "changed"
    changed.parent.mkdir(parents=True, exist_ok=True)
    with changed.open("a", encoding="utf-8") as stream:
        for path in paths:
            stream.write(str(Path(path).resolve()) + "\n")


def first_field(value, names):
    if not isinstance(value, dict):
        return ""
    for name in names:
        item = value.get(name)
        if isinstance(item, str):
            return item
    return ""


def pre_other(event):
    tool = str(event.get("tool_name") or "")
    if tool in ("Bash", "apply_patch"):
        return
    block(run("no-guess-gate/pre.sh", event))
    details = event.get("tool_input")
    action, paths = write_action(tool, details)
    if not action:
        return
    if not paths:
        fail(f"Checkride cannot inspect the file path for writing tool {tool}; blocked.")
    old_text = first_field(details, ("old_string", "old_content"))
    new_text = first_field(details, ("new_string", "new_content", "content", "text"))
    for rel in dict.fromkeys(paths):
        absolute = os.path.abspath(os.path.join(event.get("cwd") or os.getcwd(), rel))
        if action in ("delete", "remove"):
            if TEST_PATH.search(rel):
                deletion = dict(event)
                deletion["tool_name"] = "Bash"
                deletion["tool_input"] = {"command": "rm -- " + shlex.quote(rel)}
                block(run("test-integrity/pre.sh", deletion))
            continue
        if action == "append":
            try:
                old_text = Path(absolute).read_text(encoding="utf-8")
            except OSError:
                old_text = ""
            new_text = old_text + new_text
        elif not old_text:
            try:
                old_text = Path(absolute).read_text(encoding="utf-8")
            except OSError:
                old_text = ""
        if not new_text:
            fail(f"Checkride cannot inspect the content for writing tool {tool}; blocked.")
        adapted = synthetic(absolute, old_text, new_text)
        block(run("test-integrity/pre.sh", adapted))
        block(run("project-guard/pre.sh", adapted))


def block(result):
    if result.returncode:
        sys.stderr.write(result.stderr or f"Checkride hook failed with exit {result.returncode}.\n")
        raise SystemExit(2)


if mode == "prompt":
    retry_file = stop_retry_file(EVENT, "stop")
    try:
        stop_continuation = int(retry_file.read_text(encoding="ascii")) > 0
    except (OSError, ValueError):
        stop_continuation = False
    if not stop_continuation:
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
    save_snapshot(EVENT)
elif mode == "pre-other":
    pre_other(EVENT)
elif mode == "pre-patch":
    block(run("no-guess-gate/pre.sh", EVENT))
    for rel, old, new, kind in patch_events(EVENT):
        path = os.path.abspath(os.path.join(EVENT.get("cwd") or os.getcwd(), rel))
        if kind == "delete" and TEST_PATH.search(rel):
            deletion = dict(EVENT)
            deletion["tool_name"] = "Bash"
            deletion["tool_input"] = {"command": "rm -- " + shlex.quote(rel)}
            block(run("test-integrity/pre.sh", deletion))
            continue
        if kind == "add" or TEST_PATH.search(rel):
            block(run("test-integrity/pre.sh", synthetic(path, old, new)))
        block(run("project-guard/pre.sh", synthetic(path, old, new)))
elif mode == "post-bash":
    # Codex's Bash tool_response contains output, not process metadata. The
    # transcript is explicitly not a stable hook interface, so record unknown.
    root = Path(STATE) / "state" / EVENT.get("session_id", "")
    if EVENT.get("agent_id"):
        root /= "agent-" + EVENT["agent_id"]
    root.mkdir(parents=True, exist_ok=True)
    with (root / "bashseq").open("a") as stream:
        stream.write("?")
    record_bash_changes(EVENT)
elif mode == "post-patch":
    try:
        paths = [str((Path(EVENT.get("cwd") or ".") / rel).resolve())
                 for rel, _old, _new, _kind in patch_events(EVENT)]
    except SystemExit:
        root = git_root(EVENT) or Path(EVENT.get("cwd") or os.getcwd()).resolve()
        record_changed([str(root / "__checkride_unknown_change__.sh")])
        raise
    record_changed(paths)
elif mode == "post-other":
    action, paths = write_action(str(EVENT.get("tool_name") or ""), EVENT.get("tool_input"))
    if action:
        if not paths:
            root = git_root(EVENT) or Path(EVENT.get("cwd") or os.getcwd()).resolve()
            record_changed([str(root / "__checkride_unknown_change__.sh")])
        else:
            record_changed([str((Path(EVENT.get("cwd") or os.getcwd()) / p).resolve()) for p in paths])
elif mode in ("stop", "subagent-stop"):
    scripts = ["no-guess-gate/stop.sh"]
    if mode == "stop":
        scripts.append("done-gate/stop.sh")
    retry_file = stop_retry_file(EVENT, mode)
    active = EVENT.get("stop_hook_active") is True
    try:
        retries = int(retry_file.read_text(encoding="ascii")) if active else 0
    except (OSError, ValueError):
        retries = 0
    for script in scripts:
        result = run(script, EVENT, judge_provider=True, capture_start_error=True)
        if result.returncode:
            if active and retries >= STOP_RETRY_LIMIT:
                reason = result.stderr or "Checkride could not verify this turn."
                if not clear_retry_file(retry_file):
                    reason += " Retry state could not be cleared; the turn ended for manual review."
                end_stop(reason)
            retries += 1
            try:
                retry_file.parent.mkdir(parents=True, exist_ok=True)
                retry_file.write_text(str(retries), encoding="ascii")
            except OSError:
                end_stop((result.stderr or "Checkride could not verify this turn.") +
                         " Retry state could not be saved, so the turn ended for manual review.")
            block(result)
    if not clear_retry_file(retry_file):
        end_stop("The gates passed, but Checkride could not clear the retry state. "
                 "The turn ended for manual review.")
    print('{"continue":true}')
else:
    fail(f"unknown Codex hook mode: {mode}")
