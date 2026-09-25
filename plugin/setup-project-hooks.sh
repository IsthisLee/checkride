#!/usr/bin/env bash
set -euo pipefail

die() { printf 'checkride share-hooks: %s\n' "$1" >&2; exit 1; }

plugin_root=$(cd "$(dirname "$0")" && pwd)
target=$(git rev-parse --show-toplevel 2>/dev/null) || die 'run this inside the target Git repository.'
dest="$target/.checkride"
marker="$dest/.managed-by-checkride"

[[ -d "$plugin_root/hooks" ]] || die "plugin hooks not found: $plugin_root/hooks"
if [[ -e "$dest/hooks" && ! -f "$marker" ]]; then
  die "$dest/hooks already exists and is not marked as Checkride-managed; move it before installing."
fi
mkdir -p "$dest"
if [[ -f "$marker" ]]; then rm -rf "$dest/hooks"; fi
cp -R "$plugin_root/hooks" "$dest/hooks"
touch "$marker"
mkdir -p "$dest/data"
touch "$dest/.gitignore"
grep -Fxq '/data/' "$dest/.gitignore" || printf '/data/\n' >> "$dest/.gitignore"

python3 - "$target" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
bundle = root / ".checkride"


def transform(value, replacements):
    if isinstance(value, dict):
        return {k: transform(v, replacements) for k, v in value.items()}
    if isinstance(value, list):
        return [transform(v, replacements) for v in value]
    if isinstance(value, str):
        for old, new in replacements:
            value = value.replace(old, new)
        return value
    return value


def merge_hooks(path, additions, checkride_marker):
    if path.exists():
        try:
            config = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"cannot merge {path.relative_to(root)}: {exc}")
    else:
        config = {}
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise SystemExit(f"cannot merge {path.relative_to(root)}: 'hooks' must be an object")
    for event, groups in additions.get("hooks", {}).items():
        existing = hooks.setdefault(event, [])
        if not isinstance(existing, list):
            raise SystemExit(f"cannot merge {path.relative_to(root)}: hooks.{event} must be an array")
        kept = []
        for group in existing:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                kept.append(group)
                continue
            group["hooks"] = [
                handler for handler in group["hooks"]
                if checkride_marker not in json.dumps(handler, ensure_ascii=False)
            ]
            if group["hooks"]:
                kept.append(group)
        existing[:] = kept
        existing.extend(groups)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")


claude_source = json.loads((bundle / "hooks/hooks.json").read_text())
claude_hooks = transform(claude_source, [
    ("${CLAUDE_PLUGIN_DATA}", "${CLAUDE_PROJECT_DIR}/.checkride/data"),
    ("${CLAUDE_PLUGIN_ROOT}", "${CLAUDE_PROJECT_DIR}/.checkride"),
])
merge_hooks(root / ".claude/settings.json", claude_hooks, ".checkride/hooks/")

codex_source = json.loads((bundle / "hooks/hooks.codex.json").read_text())
codex_hooks = transform(codex_source, [
    ('python3 "${PLUGIN_ROOT}/hooks/codex.py"',
     'PLUGIN_DATA="$(git rev-parse --show-toplevel)/.checkride/data" python3 "$(git rev-parse --show-toplevel)/.checkride/hooks/codex.py"'),
])
for groups in codex_hooks["hooks"].values():
    for group in groups:
        for handler in group.get("hooks", []):
            command = handler.get("command", "")
            if ".checkride/hooks/codex.py" in command:
                args = command.rsplit(" ", 1)[1]
                handler["commandWindows"] = (
                    "$root = git rev-parse --show-toplevel; "
                    "$env:PLUGIN_DATA = Join-Path $root '.checkride/data'; "
                    f"py -3 (Join-Path $root '.checkride/hooks/codex.py') {args}"
                )
merge_hooks(root / ".codex/hooks.json", codex_hooks, ".checkride/hooks/codex.py")
PY

printf '%s\n' \
  'Checkride hooks are now stored in this repository:' \
  '  .checkride/hooks/' \
  '  .claude/settings.json' \
  '  .codex/hooks.json' \
  'Review and commit these files. Collaborators must trust the hooks in each agent tool.'
