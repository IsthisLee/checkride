#!/usr/bin/env bash
set -euo pipefail

die() { printf 'checkride share-hooks: %s\n' "$1" >&2; exit 1; }

plugin_root=$(cd "$(dirname "$0")" && pwd)
target=$(git rev-parse --show-toplevel 2>/dev/null) || die 'run this inside the target Git repository.'
dest="$target/.checkride"
marker="$dest/.managed-by-checkride"

[[ -d "$plugin_root/hooks" ]] || die "plugin hooks not found: $plugin_root/hooks"
# 공유 훅은 실행 상태를 이 헬퍼가 알려 주는 사용자별 경로에 쓴다. 없이 설치하면 모든 훅이 실행마다 실패한다.
[[ -f "$plugin_root/hooks/lib/state_path.py" ]] || die "state path helper not found: $plugin_root/hooks/lib/state_path.py"
if [[ -e "$dest/hooks" && ! -f "$marker" ]]; then
  die "$dest/hooks already exists and is not marked as Checkride-managed; move it before installing."
fi
if [[ -L "$dest/README.md" ]]; then
  die "$dest/README.md is a symlink; move it before installing."
fi
if [[ -e "$dest/README.md" && ! -f "$marker" ]]; then
  die "$dest/README.md already exists and is not marked as Checkride-managed; move it before installing."
fi

# 두 설정 파일을 모두 읽고 병합 결과를 만든 뒤에만 훅을 복사하고 파일을 쓴다. JSON 이 깨져 있으면 아무것도 바꾸지 않는다.
PYTHONUTF8=1 python3 - "$plugin_root" "$target" <<'PY'
import json
import pathlib
import re
import shutil
import sys

plugin, root = map(pathlib.Path, sys.argv[1:3])
bundle = root / ".checkride"
# 이 설치기가 넣은 핸들러. 옛 설치본의 `.checkride"/hooks/` 형식도 알아봐야 재설치 때 지운다.
MANAGED = re.compile(r'\.checkride"?/hooks/')
WS = " \t\r\n"


def fail(msg):
    raise SystemExit(f"checkride share-hooks: {msg}")


def managed(handler):
    return isinstance(handler, dict) and any(
        isinstance(v, str) and MANAGED.search(v) for v in handler.values())


def rebuild(manifest, pattern, build):
    """Rewrite every manifest handler through `build`; a command we do not recognise means the installer is stale."""
    hooks = json.loads((plugin / "hooks" / manifest).read_text(encoding="utf-8"))["hooks"]
    for groups in hooks.values():
        for group in groups:
            for i, handler in enumerate(group["hooks"]):
                m = re.fullmatch(pattern, handler.get("command", ""))
                if not m:
                    fail(f"unexpected command in {manifest}: {handler.get('command')!r}")
                group["hooks"][i] = {**handler, **build(m.group(1))}
    return hooks


def merge(hooks, additions):
    """Drop every managed handler, then append the new ones. Unrelated handlers keep their place."""
    emptied = set()
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            continue
        kept = []
        for group in groups:
            if isinstance(group, dict) and isinstance(group.get("hooks"), list):
                group["hooks"] = [h for h in group["hooks"] if not managed(h)]
                if not group["hooks"]:
                    continue
            kept.append(group)
        if groups and not kept:
            emptied.add(event)
        groups[:] = kept
    for event, groups in additions.items():
        existing = hooks.setdefault(event, [])
        if not isinstance(existing, list):
            raise ValueError(f"hooks.{event} must be an array")
        existing.extend(groups)
    for event in emptied:
        if not hooks[event]:
            del hooks[event]


def skip(text, i):
    while i < len(text) and text[i] in WS:
        i += 1
    return i


def members(text):
    """Top-level members as (key, key_start, value_start, value_end), plus the closing brace index."""
    dec = json.JSONDecoder()
    found = []
    i = skip(text, text.index("{") + 1)
    while text[i] != "}":
        key, j = dec.raw_decode(text, i)
        vs = skip(text, skip(text, j) + 1)
        _, ve = dec.raw_decode(text, vs)
        found.append((key, i, vs, ve))
        i = skip(text, ve)
        if text[i] == ",":
            i = skip(text, i + 1)
    return found, i


def indent_of(text, pos):
    """Leading whitespace of the line at `pos`, or None when something else precedes it on that line."""
    prefix = text[text.rfind("\n", 0, pos) + 1:pos]
    return None if prefix.strip() else prefix


def render(text, hooks):
    """Replace only the top-level "hooks" value so everything else in the file keeps its bytes."""
    if text is None:
        return json.dumps({"hooks": hooks}, ensure_ascii=False, indent=2) + "\n"

    def dump(indent):
        return json.dumps(hooks, ensure_ascii=False, indent=2).replace("\n", "\n" + indent)

    found, close = members(text)
    for key, ks, vs, ve in reversed(found):
        if key == "hooks":
            return text[:vs] + dump(indent_of(text, ks) or "") + text[ve:]
    if not found:
        return text[:close] + '\n  "hooks": ' + dump("  ") + "\n" + text[close:]
    indent = indent_of(text, found[-1][1])
    sep = " " if indent is None else "\n" + indent
    ve = found[-1][3]
    return text[:ve] + "," + sep + '"hooks": ' + dump(indent or "") + text[ve:]


def plan(rel, additions):
    path = root / rel
    try:
        text = path.read_bytes().decode("utf-8") if path.exists() else None
        config = {} if text is None else json.loads(text)
        if not isinstance(config, dict):
            raise ValueError("top level must be an object")
        hooks = config.get("hooks", {})
        if not isinstance(hooks, dict):
            raise ValueError("'hooks' must be an object")
        merge(hooks, additions)
        return path, text, render(text, hooks)
    except (OSError, ValueError) as exc:
        fail(f"cannot merge {rel}: {exc}")


# Claude Code 는 bash 로 돌린다. 상태 경로를 못 구하면 exit 1(차단하지 않는 오류)로 끝내 저장소 안에 상태를 쓰지 않는다.
claude = rebuild(
    "hooks.json",
    r'NGG_STATE="\$\{CLAUDE_PLUGIN_DATA\}" "\$\{CLAUDE_PLUGIN_ROOT\}"/hooks/(\S+)',
    lambda script: {"command": (
        'state="$(python3 "${CLAUDE_PROJECT_DIR}/.checkride/hooks/lib/state_path.py" "${CLAUDE_PROJECT_DIR}")" || exit 1; '
        f'NGG_STATE="$state" "${{CLAUDE_PROJECT_DIR}}/.checkride/hooks/{script}"')})
codex = rebuild(
    "hooks.codex.json",
    r'python3 "\$\{PLUGIN_ROOT\}/hooks/codex\.py" (\S+)',
    lambda sub: {
        "command": (
            'root="$(git rev-parse --show-toplevel)" && '
            'state="$(python3 "$root/.checkride/hooks/lib/state_path.py" "$root")" || exit 1; '
            f'PLUGIN_DATA="$state" python3 "$root/.checkride/hooks/codex.py" {sub}'),
        # PowerShell 은 네이티브 명령 출력의 끝 개행을 떼고 담는다. 헬퍼가 없거나 실패하면 변수가 비므로 그것도 막는다.
        # 마지막 exit 는 codex.py 의 종료 코드를 그대로 돌려준다. Windows PowerShell 5.1 은 없으면 0/1 로 뭉갠다.
        "commandWindows": (
            "$root = git rev-parse --show-toplevel; if ($LASTEXITCODE -or -not $root) { exit 1 }; "
            "$env:PLUGIN_DATA = py -3 (Join-Path $root '.checkride/hooks/lib/state_path.py') $root; "
            "if ($LASTEXITCODE -or -not $env:PLUGIN_DATA) { exit 1 }; "
            f"py -3 (Join-Path $root '.checkride/hooks/codex.py') {sub}; exit $LASTEXITCODE"),
    })
plans = [plan(".claude/settings.json", claude), plan(".codex/hooks.json", codex)]

if (bundle / "hooks").exists():
    shutil.rmtree(bundle / "hooks")
shutil.copytree(plugin / "hooks", bundle / "hooks",
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
for path, old, new in plans:
    if new != old:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(new.encode("utf-8"))
PY

touch "$marker" "$dest/.gitignore"
for line in '__pycache__/' '*.pyc'; do
  grep -Fxq "$line" "$dest/.gitignore" || printf '%s\n' "$line" >> "$dest/.gitignore"
done

cat > "$dest/README.md" <<'MD'
# Checkride 공유 훅

이 폴더는 Checkride 의 `setup-project-hooks.sh` 가 만든 공유 훅입니다. 팀원이 Checkride 플러그인을 따로 설치하지 않아도, Claude Code 와 Codex 가 이 저장소에 들어 있는 훅을 실행합니다.

## 소유

- `.checkride/hooks/` 와 이 `README.md` 는 설치 스크립트가 만듭니다. 다시 설치하면 통째로 덮어쓰므로 직접 고치지 않습니다.
- `.checkride/.managed-by-checkride` 는 이 폴더를 설치 스크립트가 관리한다는 표식입니다. 표식이 없는 `.checkride/hooks/` 는 설치 스크립트가 덮어쓰지 않습니다.
- `.claude/settings.json` 과 `.codex/hooks.json` 에서는 명령에 `.checkride/hooks/` 가 들어간 핸들러만 설치 스크립트가 관리합니다. 그 밖의 설정과 훅은 그대로 둡니다.
- 게이트 설정은 저장소 루트의 `checkride.toml` 에 둡니다. 설치 스크립트는 이 파일을 만들거나 고치지 않습니다.
- 훅의 실행 상태는 저장소가 아니라 사용자별 경로에 씁니다. 저장소 루트에서 `python3 .checkride/hooks/lib/state_path.py "$(pwd)"` 를 실행하면 그 경로가 나옵니다.

## 업데이트와 재설치

Checkride 플러그인을 업데이트한 뒤, 저장소 루트에서 설치 명령을 다시 실행합니다.

```bash
bash "$(find ~/.claude/plugins ~/.codex/plugins -path '*/setup-project-hooks.sh' -print -quit 2>/dev/null)"
```

설치 스크립트는 `.checkride/hooks/` 를 새 사본으로 바꾸고, 두 설정 파일의 관리 핸들러를 새 항목으로 교체합니다. 여러 번 실행해도 핸들러가 중복되지 않습니다. `git diff` 로 바뀐 내용을 검토한 뒤 커밋합니다.

## 끄기와 제거

- 규칙이나 항목 하나만 끄려면 `checkride.toml` 의 `disabled_rules` 에 이름을 적습니다.
- 공유 훅을 모두 제거하려면 `.claude/settings.json` 과 `.codex/hooks.json` 에서 명령에 `.checkride/hooks/` 가 들어간 핸들러를 지우고, `.checkride/` 폴더를 지운 뒤 커밋합니다.
- 사용자별 상태 폴더는 저장소에 들어 있지 않으므로 각자 지웁니다. 위의 `state_path.py` 명령으로 경로를 확인합니다.

## 신뢰

각 도구에서 이 저장소를 신뢰해야 저장소에 들어 있는 훅이 실행됩니다. 승인하기 전에 두 설정 파일의 훅 명령과 `.checkride/hooks/` 의 코드를 검토합니다. 훅이 바뀐 커밋을 받은 뒤에도 다시 검토합니다.

Codex CLI 0.156.1에서 새 저장소 훅은 프로젝트 `.codex/` 계층을 신뢰하지 않으면 `codex exec --dangerously-bypass-hook-trust`로도 실행되지 않았습니다. 이 플래그는 훅 정의 신뢰만 한 번 우회하고 프로젝트 신뢰를 대신하지 않습니다. 이 저장소에서는 `/hooks`에서 새 Checkride 훅을 검토하고 신뢰한 뒤 `codex exec`가 별도 우회 플래그 없이 프로젝트 훅을 실행했습니다. 자동화에서는 실행 전에 Codex 설정에 프로젝트 신뢰와 현재 훅 정의 신뢰가 저장되어 있어야 합니다. 비대화형 실행은 승인 화면을 띄우지 않습니다. [Codex 훅 문서](https://developers.openai.com/codex/hooks) (확인일: 2026-09-28).

Codex의 `Stop` 훅은 `stop_hook_active`가 참인 재진입에서도 두 게이트를 다시 실행합니다. 자동 continuation 프롬프트가 들어오면 원래 사용자 질문을 보존해 로컬 맥락 검사도 이어 갑니다. 최대 여덟 번 continuation을 요청하고, 여덟 번째 재진입 검사도 실패하거나 반복 상태를 저장·정리하지 못하면 `continue: false`와 `systemMessage`를 반환해 턴을 끝냅니다. 이 경고가 나오면 사용자가 답을 확인해야 합니다. Claude Code도 재진입 답변을 검사하며, 여덟 번 연속 턴을 이어 간 뒤에는 다음 차단을 덮어쓰고 턴을 끝냅니다.

## 보안 경고

이 훅과 `checkride.toml` 의 `test_command`·`fast_test_command` 는 에이전트의 샌드박스 밖에서, 저장소를 연 사용자의 권한으로 저장소 코드를 실행합니다. 이 저장소에 쓸 수 있는 사람은 `.checkride/hooks/` 나 `checkride.toml` 을 바꿔 팀원의 컴퓨터에서 임의의 코드를 실행할 수 있습니다. 이 파일들을 바꾸는 변경은 실행 코드로 보고 코드 리뷰에서 검토합니다.

## 설정·실행 코드 보호

훅 코드를 신뢰하기 전에 `.checkride/hooks/`, `.claude/settings.json`, `.codex/hooks.json`, `.codex/config.toml`, `checkride.toml` 과 그 검사 명령이 실행하는 스크립트를 검토합니다.

- Claude Code 에서는 프로젝트 `permissions.deny` 에 보호할 경로의 `Edit(...)`·`Write(...)` 규칙을 둘 수 있습니다. `Read` 차단은 읽기와 쓰기를 함께 막으므로 에이전트가 설정을 읽어야 하면 쓰지 않습니다. 도구 권한은 Bash 나 다른 자식 프로세스를 격리하지 않으므로 더 강한 경계에는 OS 샌드박스를 사용합니다.
- Codex 의 `sandbox_workspace_write.writable_roots` 는 쓰기 허용 경로를 추가하며 거부 목록이 아닙니다. 프로젝트 파일 쓰기 자체를 막아야 할 때 `read-only` 샌드박스를 사용하면 에이전트의 일반 수정도 제한됩니다.
- 보호 설정은 저장소 정책과 작업 흐름에 맞춰 팀이 정합니다. 훅 신뢰는 이 설정을 대신하지 않습니다.

공식 문서(2026-09-28 확인): [Claude Code 권한과 샌드박스](https://code.claude.com/docs/en/permissions), [Codex 설정과 샌드박스](https://developers.openai.com/codex/config-reference).
MD

printf '%s\n' \
  'Checkride hooks are now stored in this repository:' \
  '  .checkride/hooks/' \
  '  .checkride/README.md' \
  '  .claude/settings.json' \
  '  .codex/hooks.json' \
  'WARNING: Hooks and test_command/fast_test_command run repository code with your user permissions, outside the agent sandbox.' \
  'Review and commit these files. Collaborators must trust the hooks in each agent tool; see .checkride/README.md.'
