#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# setup.sh 와 plugin/setup-project-hooks.sh 단위 테스트. 모델을 부르지 않는다.
# core.hooksPath 는 값을 하나만 가진다. 덮어쓰면 앞의 것이 사라지고, 그 저장소가 쓰던
# 훅이 조용히 죽는다. husky·lefthook 을 쓰는 저장소에서 실제로 그렇게 됐다(V55).
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_PROFILE
export NGG_LANG=ko
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }

# 훅 폴더와 setup.sh 를 갖춘 새 git 저장소를 만든다.
mkrepo() {
  local d="$1" hooks="${2:-.githooks}"
  mkdir -p "$d"; git init -q "$d"
  git -C "$d" config user.name t; git -C "$d" config user.email t@example.invalid
  mkdir -p "$d/$hooks"; printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/$hooks/pre-commit"
  chmod +x "$d/$hooks/pre-commit"
  cp "$ROOT/setup.sh" "$d/setup.sh"; chmod +x "$d/setup.sh"
}

# 1. 기준선: 설정이 비어 있으면 건다
R1="$T/fresh"; mkrepo "$R1"
out=$(cd "$R1" && ./setup.sh 2>&1); check 0 $? "빈 설정 → exit 0"
check ".githooks" "$(git -C "$R1" config core.hooksPath)" "빈 설정 → hooksPath 를 건다"

# 2. 멱등: 같은 값이 이미 있으면 그대로 통과한다
out=$(cd "$R1" && ./setup.sh 2>&1); check 0 $? "같은 값 → exit 0 (멱등)"
check ".githooks" "$(git -C "$R1" config core.hooksPath)" "같은 값 → 그대로 둔다"

# 3. 남의 값이 있으면 덮지 않고 멈춘다. 이게 이 파일의 존재 이유다.
R2="$T/taken"; mkrepo "$R2"
git -C "$R2" config core.hooksPath .husky/_
out=$(cd "$R2" && ./setup.sh 2>&1); r=$?
check 1 "$r" "남의 hooksPath → exit 1 (조용히 덮지 않는다)"
check ".husky/_" "$(git -C "$R2" config core.hooksPath)" "남의 hooksPath → 값을 건드리지 않는다"
printf '%s' "$out" | grep -q '.husky/_'; check 0 $? "차단 메시지에 기존 값을 보인다"
printf '%s' "$out" | grep -q 'pre-commit'; check 0 $? "차단 메시지에 공존하는 법을 보인다"
printf '%s' "$out" | grep -q '\-\-force'; check 0 $? "차단 메시지에 덮어쓰는 법을 보인다"

# 4. --force 는 사람이 의도해서 줄 때만 덮는다
out=$(cd "$R2" && ./setup.sh --force 2>&1); check 0 $? "--force → exit 0"
check ".githooks" "$(git -C "$R2" config core.hooksPath)" "--force → 덮는다"

# 5. 훅 폴더가 없으면 멈춘다
R3="$T/nohooks"; mkdir -p "$R3"; git init -q "$R3"
cp "$ROOT/setup.sh" "$R3/setup.sh"; chmod +x "$R3/setup.sh"
out=$(cd "$R3" && ./setup.sh 2>&1); r=$?; check 1 "$r" "훅 폴더 없음 → exit 1"

# 6. git 저장소가 아니면 멈춘다
R4="$T/notgit"; mkdir -p "$R4"; cp "$ROOT/setup.sh" "$R4/setup.sh"; chmod +x "$R4/setup.sh"
out=$(cd "$R4" && ./setup.sh 2>&1); r=$?; check 1 "$r" "git 저장소 아님 → exit 1"

# 7. 모르는 인자는 조용히 무시하지 않는다
R5="$T/badarg"; mkrepo "$R5"
out=$(cd "$R5" && ./setup.sh --nope 2>&1); r=$?; check 1 "$r" "모르는 인자 → exit 1"

# ── plugin/setup-project-hooks.sh: 훅을 대상 저장소에 복사하고 두 도구의 훅 설정에 병합한다 ──
INST="$ROOT/plugin/setup-project-hooks.sh"
mkproj() { mkdir -p "$1"; git init -q "$1"; }
install_in() { (cd "$1" && bash "${2:-$INST}" 2>&1); }
py_run() { python3 - "$@"; }
# [ ... ] 뒤의 $?는 조건의 결과라 덮어쓰기 쉽다(SC2319). 파일 검사는 함수로 감싸 명령 결과로 만든다.
exists() { [ -e "$1" ]; }
isdir() { [ -d "$1" ]; }
# 설정 파일에서 공유 훅(.checkride/hooks/)을 가리키는 핸들러 수. 인자: 파일, 찾을 문자열(기본 .checkride/hooks/)
count_handlers() { py_run "$1" "${2:-.checkride/hooks/}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(sys.argv[2] in h.get("command", "")
          for gs in d.get("hooks", {}).values() for g in gs for h in g.get("hooks", [])))
PY
}
src_count() { py_run "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(len(g.get("hooks", [])) for gs in d["hooks"].values() for g in gs))
PY
}
CN=$(src_count "$ROOT/plugin/hooks/hooks.json"); XN=$(src_count "$ROOT/plugin/hooks/hooks.codex.json")

# 8. 빈 저장소에 설치한다. 실행 상태는 저장소 안(.checkride/data)에 두지 않는다
P1="$T/proj-fresh"; mkproj "$P1"
out=$(install_in "$P1"); check 0 $? "공유 훅 설치 → exit 0"
exists "$P1/.checkride/hooks/codex.py" && exists "$P1/.checkride/.managed-by-checkride"; check 0 $? "훅 사본과 관리 표식을 만든다"
exists "$P1/.checkride/data"; check 1 $? "저장소 안에 .checkride/data 를 만들지 않는다"
check "$CN" "$(count_handlers "$P1/.claude/settings.json")" "Claude 설정에 매니페스트의 핸들러를 모두 넣는다"
check "$XN" "$(count_handlers "$P1/.codex/hooks.json")" "Codex 설정에 매니페스트의 핸들러를 모두 넣는다"
check "$CN" "$(count_handlers "$P1/.claude/settings.json" state_path.py)" "Claude 핸들러가 사용자별 상태 경로 헬퍼를 쓴다"
check "$XN" "$(count_handlers "$P1/.codex/hooks.json" state_path.py)" "Codex 핸들러가 사용자별 상태 경로 헬퍼를 쓴다"
grep -q 'PLUGIN_ROOT\|PLUGIN_DATA}\|\.checkride/data' "$P1/.claude/settings.json" "$P1/.codex/hooks.json"
check 1 $? "변환 뒤 플러그인 변수와 .checkride/data 가 남지 않는다"
check "$XN" "$(py_run "$P1/.codex/hooks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(".checkride/hooks/codex.py" in h.get("commandWindows", "")
          for gs in d["hooks"].values() for g in gs for h in g["hooks"]))
PY
)" "Codex 핸들러마다 Windows 명령이 있다"

# 9. 다시 실행해도 두 설정 파일이 바이트 단위로 같다. 변환된 경로를 스스로 알아봐야 중복이 안 생긴다
cp "$P1/.claude/settings.json" "$T/c1"; cp "$P1/.codex/hooks.json" "$T/x1"
out=$(install_in "$P1"); check 0 $? "재실행 → exit 0"
cmp -s "$T/c1" "$P1/.claude/settings.json"; check 0 $? "재실행 → .claude/settings.json 이 그대로다"
cmp -s "$T/x1" "$P1/.codex/hooks.json"; check 0 $? "재실행 → .codex/hooks.json 이 그대로다"

# 10. 생성한 README 가 소유·재설치·제거·신뢰·보안 경고를 담는다
for h in '## 소유' '## 업데이트와 재설치' '## 끄기와 제거' '## 신뢰' '## 보안 경고' '## 설정·실행 코드 보호'; do
  grep -qx "$h" "$P1/.checkride/README.md"; check 0 $? "README 에 '$h' 절이 있다"
done
grep -q '샌드박스' "$P1/.checkride/README.md"; check 0 $? "README 가 샌드박스 밖에서 실행된다고 경고한다"
grep -q '첫 답을 차단한 뒤 다시 작성된 답은 검사하지 않습니다' "$P1/.checkride/README.md"; check 0 $? "README 가 Codex Stop 재진입 검사 경계를 알린다"
printf '%s' "$out" | grep -q 'outside the agent sandbox'; check 0 $? "설치 완료 메시지도 실행 권한과 샌드박스 경계를 경고한다"

# 11. 남의 설정과 인라인 배열은 글자 그대로 두고, 옛 Checkride 핸들러는 지운다
P2="$T/proj-existing"; mkproj "$P2"; mkdir -p "$P2/.claude" "$P2/.codex"
# shellcheck disable=SC2016  # JSON 리터럴이라 확장하지 않는다
printf '%s\n' '{' \
  '    "permissions": {"allow": ["Bash(ls)", "Read"], "deny": []},' \
  '    "hooks": {' \
  '        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mine"}]}],' \
  '        "Notification": [{"hooks": [{"type": "command", "command": "echo notify"}, {"type": "command", "command": "\"${CLAUDE_PROJECT_DIR}/.checkride\"/hooks/old.sh"}]}],' \
  '        "Stop": [{"hooks": [{"type": "command", "command": "NGG_STATE=\"${CLAUDE_PROJECT_DIR}/.checkride/data\" \"${CLAUDE_PROJECT_DIR}/.checkride\"/hooks/no-guess-gate/stop.sh"}]}]' \
  '    },' \
  '    "env": {"A": "1"}' \
  '}' > "$P2/.claude/settings.json"
# shellcheck disable=SC2016  # JSON 리터럴이라 확장하지 않는다
printf '%s\n' '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo codex-mine"},' \
  ' {"type": "command", "command": "PLUGIN_DATA=\"$(git rev-parse --show-toplevel)/.checkride/data\" python3 \"$(git rev-parse --show-toplevel)/.checkride/hooks/codex.py\" stop"}]}]},' \
  ' "other": [1, 2, 3]}' > "$P2/.codex/hooks.json"
out=$(install_in "$P2"); check 0 $? "기존 설정 위에 설치 → exit 0"
out=$(install_in "$P2"); check 0 $? "기존 설정 위에 재설치 → exit 0"
grep -qxF '    "permissions": {"allow": ["Bash(ls)", "Read"], "deny": []},' "$P2/.claude/settings.json"; check 0 $? "hooks 밖의 인라인 배열 줄을 그대로 둔다"
grep -qxF '    "env": {"A": "1"}' "$P2/.claude/settings.json"; check 0 $? "hooks 뒤의 줄도 그대로 둔다"
grep -qF ' "other": [1, 2, 3]}' "$P2/.codex/hooks.json"; check 0 $? "Codex 설정의 hooks 밖도 그대로 둔다"
check 1 "$(count_handlers "$P2/.claude/settings.json" 'echo mine')" "남의 Claude 핸들러는 한 번만 남는다"
check 1 "$(count_handlers "$P2/.claude/settings.json" 'echo notify')" "옛 핸들러와 같은 묶음의 남의 핸들러는 남는다"
check 1 "$(count_handlers "$P2/.codex/hooks.json" 'echo codex-mine')" "남의 Codex 핸들러는 한 번만 남는다"
check "$CN" "$(count_handlers "$P2/.claude/settings.json")" "Claude 관리 핸들러는 매니페스트 수만큼만 있다"
check "$XN" "$(count_handlers "$P2/.codex/hooks.json")" "Codex 관리 핸들러는 매니페스트 수만큼만 있다"
grep -q 'checkride\\"/hooks\|\.checkride/data' "$P2/.claude/settings.json" "$P2/.codex/hooks.json"
check 1 $? "옛 형식(.checkride\"/hooks, .checkride/data)의 핸들러를 지운다"

# 11-1. hooks 키가 없는 설정과 빈 객체에도 hooks 만 덧붙인다
P7="$T/proj-nohooks"; mkproj "$P7"; mkdir -p "$P7/.claude" "$P7/.codex"
printf '%s\n' '{' '  "permissions": {"allow": ["Read"]}' '}' > "$P7/.claude/settings.json"; printf '{}\n' > "$P7/.codex/hooks.json"
out=$(install_in "$P7"); check 0 $? "hooks 없는 설정 위에 설치 → exit 0"
grep -qxF '  "permissions": {"allow": ["Read"]},' "$P7/.claude/settings.json"; check 0 $? "hooks 없는 설정 → 기존 줄은 쉼표만 붙는다"
check "$CN" "$(count_handlers "$P7/.claude/settings.json")" "hooks 없는 설정 → 관리 핸들러를 넣는다"
check "$XN" "$(count_handlers "$P7/.codex/hooks.json")" "빈 객체 설정 → 관리 핸들러를 넣는다"

# 12. 복사본에서 __pycache__ 와 .pyc 를 뺀다. 가짜 플러그인 사본에 심어 확인한다
PL="$T/plugin-copy"; cp -R "$ROOT/plugin" "$PL"
mkdir -p "$PL/hooks/lib/__pycache__"; : > "$PL/hooks/lib/__pycache__/x.cpython-39.pyc"; : > "$PL/hooks/stray.pyc"
P3="$T/proj-pyc"; mkproj "$P3"
out=$(install_in "$P3" "$PL/setup-project-hooks.sh"); check 0 $? "__pycache__ 가 있는 플러그인에서 설치 → exit 0"
check 0 "$(find "$P3/.checkride/hooks" \( -name __pycache__ -o -name '*.pyc' \) | wc -l | tr -d ' ')" "__pycache__ 와 .pyc 를 복사하지 않는다"
grep -qxF '__pycache__/' "$P3/.checkride/.gitignore"; check 0 $? "실행 중 생기는 __pycache__ 를 Git 에서 뺀다"

# 13. 표식 없는 .checkride/hooks 는 덮지 않는다
P4="$T/proj-foreign"; mkproj "$P4"; mkdir -p "$P4/.checkride/hooks"; : > "$P4/.checkride/hooks/mine"
out=$(install_in "$P4"); check 1 $? "표식 없는 .checkride/hooks → exit 1"
exists "$P4/.checkride/hooks/mine"; check 0 $? "표식 없는 .checkride/hooks 를 건드리지 않는다"

# 기존 사용자 README 를 생성본으로 착각해 덮지 않는다.
P4R="$T/proj-readme"; mkproj "$P4R"; mkdir -p "$P4R/.checkride"
printf 'user-owned documentation\n' > "$P4R/.checkride/README.md"
out=$(install_in "$P4R"); check 1 $? "표식 없는 기존 .checkride/README.md → exit 1"
check 'user-owned documentation' "$(cat "$P4R/.checkride/README.md")" "기존 .checkride/README.md 내용을 보존한다"

# 14. 설정 JSON 이 깨져 있으면 아무것도 바꾸기 전에 멈춘다
P5="$T/proj-badjson"; mkproj "$P5"; mkdir -p "$P5/.claude"; printf '{"hooks": \n' > "$P5/.claude/settings.json"
out=$(install_in "$P5"); check 1 $? "깨진 settings.json → exit 1"
exists "$P5/.checkride/hooks"; check 1 $? "깨진 settings.json → 훅을 복사하지 않는다"

# 15. 상태 경로 헬퍼가 없는 플러그인에서는 설치하지 않는다. 설치하면 모든 훅이 실행마다 실패한다
rm -f "$PL/hooks/lib/state_path.py"; P6="$T/proj-nohelper"; mkproj "$P6"
out=$(install_in "$P6" "$PL/setup-project-hooks.sh"); check 1 $? "state_path.py 없음 → exit 1"

# 16. state_path.py: 저장소마다 다른, 저장소 밖의 사용자별 경로를 한 줄로 알려 주고 폴더를 만든다
SPY="$ROOT/plugin/hooks/lib/state_path.py"
sp_of() { HOME="$T/user-state" XDG_STATE_HOME="$T/user-state/.local/state" LOCALAPPDATA="$T/user-state/AppData" python3 "$SPY" "$@"; }
a=$(sp_of "$P1"); r=$?; check 0 "$r" "state_path.py → exit 0"
case "$a" in "$P1"*) r=1 ;; *) r=0 ;; esac; check 0 "$r" "state_path.py → 저장소 밖 경로"
isdir "$a"; check 0 $? "state_path.py → 폴더를 만든다"
check "$a" "$(sp_of "$P1/")" "state_path.py → 같은 저장소는 같은 경로"
case "$(sp_of "$P2")" in "$a") r=1 ;; *) r=0 ;; esac; check 0 "$r" "state_path.py → 다른 저장소는 다른 경로"
sp_of >/dev/null 2>&1; r=$?; check 1 "$r" "state_path.py 인자 없음 → exit 1"
bad_state="$P1/.checkride/runtime"
XDG_STATE_HOME="$bad_state" python3 "$SPY" "$P1" >/dev/null 2>&1; r=$?
check 1 "$r" "사용자 상태 경로가 저장소 안이면 state_path.py 가 거부한다"
exists "$bad_state/checkride"; check 1 $? "거부한 저장소 안 상태 경로를 만들지 않는다"

# 17. 설치한 Claude 훅이 저장소 사본으로 실제로 돌고, 상태를 저장소 밖 사용자별 경로에 쓴다
HOME_T="$T/home"; mkdir -p "$HOME_T"
before=$(find "$P1/.checkride" | sort)
cmd=$(py_run "$P1/.claude/settings.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])
PY
)
printf '{"session_id":"setup-e2e","prompt":"hi","hook_event_name":"UserPromptSubmit","cwd":"%s"}' "$P1" |
  (cd "$P1" && HOME="$HOME_T" XDG_STATE_HOME="$HOME_T/.local/state" LOCALAPPDATA="$HOME_T/AppData" CLAUDE_PROJECT_DIR="$P1" bash -c "$cmd" >/dev/null 2>&1)
check 0 $? "설치한 UserPromptSubmit 훅 → exit 0"
check "$before" "$(find "$P1/.checkride" | sort)" "훅 실행이 .checkride 안에 아무것도 쓰지 않는다"
sp=$(HOME="$HOME_T" XDG_STATE_HOME="$HOME_T/.local/state" LOCALAPPDATA="$HOME_T/AppData" python3 "$P1/.checkride/hooks/lib/state_path.py" "$P1")
isdir "$sp/state/setup-e2e"; check 0 $? "상태를 state_path.py 가 준 경로에 쓴다"

echo; echo "실패 ${fail}건"; exit "$fail"
