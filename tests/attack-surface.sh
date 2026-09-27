#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SECURITY.md 가 적어 둔 공격면이 코드와 맞는지 검사한다.
# 문서로 약속한 것을 검사로 바꾼다. 이 저장소가 Claude 에게 요구하는 것과 같은 기준이다.
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
G="$(cd "$(dirname "$0")/../plugin/hooks" && pwd)"
fail=0
ok()  { echo "✅ $1"; }
bad() { echo "❌ $1"; fail=$((fail+1)); }

# 런타임 훅만 본다. 테스트와 도구는 사용자 세션에서 돌지 않는다.
hooks_sh() {
  local f
  for f in "$G"/*/*.sh; do
    case "${f##*/}" in unit.sh|selftest.sh|ab.sh|fuzz.sh|attack-surface.sh|manifest.sh) continue;; esac
    printf '%s\n' "$f"
  done
}

# 1. "네트워크로 나가는 것은 판정기 하나뿐이다."
net=$(hooks_sh | xargs grep -nE '\b(curl|wget|nc|ncat|socat|ssh|scp|sftp|telnet)\b|https?://' 2>/dev/null | grep -v '^\s*#') || net=""
if [ -z "$net" ]; then ok "훅에 네트워크 명령이 없다"
else bad "훅에 네트워크 명령이 있다"; printf '%s\n' "$net" | sed 's/^/    /'; fi

# 2. 모델을 부르는 것은 judge.py 하나뿐이다.
cl=$(hooks_sh | xargs grep -ln '\bclaude\b' 2>/dev/null) || cl=""
if [ -z "$cl" ]; then ok "셸 훅이 모델을 부르지 않는다"
else bad "셸 훅이 모델을 부른다"; printf '%s\n' "$cl" | sed 's/^/    /'; fi
if grep -q 'claude' "$G/no-guess-gate/judge.py" && grep -q 'codex' "$G/no-guess-gate/judge.py"; then
  ok "Claude Code 와 Codex 판정기는 judge.py 하나에 모여 있다"
else bad "한쪽 모델 호출이 judge.py 에 없다"; fi

# 3. 판정기가 띄우는 세션은 사용자 설정을 읽지 않는다(주입 경로 차단).
for f in --no-session-persistence --disable-slash-commands; do
  if grep -q -- "$f" "$G/no-guess-gate/judge.py"; then ok "판정기가 $f 를 쓴다"; else bad "판정기에 $f 가 없다"; fi
done
if grep -q -- '--setting-sources' "$G/no-guess-gate/judge.py"; then ok "판정기가 --setting-sources 로 설정을 끊는다"; else bad "판정기가 설정을 끊지 않는다"; fi
if grep -q -- '--ignore-user-config' "$G/no-guess-gate/judge.py" &&
   grep -q -- '"--sandbox", "read-only"' "$G/no-guess-gate/judge.py" &&
   grep -q -- '"--disable", "hooks"' "$G/no-guess-gate/judge.py"; then
  ok "Codex 판정기는 사용자 설정·쓰기·훅을 끈다"
else bad "Codex 판정기 격리 옵션이 빠졌다"; fi
if grep -q 'stdin=subprocess.DEVNULL' "$G/no-guess-gate/judge.py" &&
   grep -q 'TemporaryDirectory' "$G/no-guess-gate/judge.py"; then
  ok "Codex 판정기는 stdin 을 닫고 임시 폴더에서 돈다"
else bad "Codex 판정기 stdin 또는 작업 폴더가 격리되지 않았다"; fi
if grep -q 'claude -p' "$G/no-guess-gate/judge.py" &&
   grep -q 'shutil.which("codex") or "codex"' "$G/no-guess-gate/judge.py" &&
   grep -q 'codex exec' "$(cd "$G/../.." && pwd)/SECURITY.md"; then
  ok "보안 문서가 Claude Code 와 Codex 판정기를 설명한다"
else bad "보안 문서에 Codex 판정 경로가 없다"; fi

# 4. 저장소 프로필은 비밀 파일의 '값'을 읽지 않는다. 이름만 본다.
if grep -nE '(cat|head|sed|awk|grep)[^|]*\.env' "$G/repo-profile/session.sh" >/dev/null 2>&1; then
  bad "프로필이 .env 값을 읽는다"; else ok "프로필이 .env 값을 읽지 않는다"; fi

# 5. 훅은 시스템 경로에 쓰지 않는다.
# ERE 에는 전방탐색이 없다. (?!...) 를 쓰면 grep 이 오류로 죽고 `|| true` 가 그것을 삼켜
# 이 검사가 늘 통과한다. 실제로 그렇게 짰다가 변별 시험에서 잡혔다. 경로를 그냥 나열한다.
w=$(hooks_sh | xargs grep -nE '^[^#]*>[[:space:]]*"?/(etc|usr|bin|sbin|Library|System|opt)/' 2>/dev/null) || w=""
if [ -z "$w" ]; then ok "시스템 경로에 쓰지 않는다"
else bad "시스템 경로에 쓴다"; printf '%s\n' "$w" | sed 's/^/    /'; fi

# 6. 훅 배선의 타임아웃이 전부 박혀 있다. 없으면 멈춘 훅이 세션을 붙잡는다.
n_cmd=$(grep -c '"type": *"command"' "$G/hooks.json")
n_to=$(grep -c '"timeout"' "$G/hooks.json")
if [ "$n_cmd" = "$n_to" ]; then ok "훅 $n_cmd 개 전부 타임아웃이 있다"; else bad "타임아웃 없는 훅이 있다(명령 $n_cmd · 타임아웃 $n_to)"; fi
codex_hooks=$(python3 - "$G/hooks.codex.json" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
handlers = [h for groups in hooks.values() for group in groups for h in group["hooks"]]
assert handlers and all(isinstance(h.get("timeout"), (int, float)) for h in handlers)
print(len(handlers))
PY
)
if [ -n "$codex_hooks" ]; then ok "Codex 훅 $codex_hooks 개 모두 타임아웃이 있다"
else bad "Codex 훅에 타임아웃 없는 핸들러가 있다"; fi

echo
if [ "$fail" -eq 0 ]; then echo "전부 통과"; else echo "실패 ${fail}건"; fi
exit "$fail"
