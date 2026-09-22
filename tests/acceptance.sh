#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 새 사용자 관점의 인수 테스트. 빈 프로젝트를 만들어 플러그인을 걸고 게이트와 스킬을 실제로 돌린다.
# 모델을 부르고 몇 분 걸린다. 단위 테스트가 덮지 못하는 것, 곧 "설치한 사람이 겪는 것"을 본다.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/plugin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/newproj"; mkdir -p "$P/src" "$P/test"
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }

# 사용자의 진짜 프로젝트에 가까운 것을 만든다
cat > "$P/package.json" <<'J'
{ "name": "newproj", "version": "1.0.0", "scripts": { "test": "node --test test/" } }
J
cat > "$P/src/add.js" <<'J'
module.exports = (a, b) => a + b;
J
cat > "$P/test/add.test.js" <<'J'
const test = require('node:test');
const assert = require('node:assert');
const add = require('../src/add.js');
test('adds', () => { assert.strictEqual(add(1, 2), 3); });
J
( cd "$P" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )

run() { # $1 이름  $2 도구  $3 프롬프트  → 결과를 $T/out 에
  ( cd "$P" && CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 NGG_LANG=ko NGG_HEADLESS=1 \
      claude -p "$3" --plugin-dir "$PLUGIN" --allowedTools "$2" \
      --model haiku --max-turns 20 --setting-sources "" --output-format json 2>/dev/null ) \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(str(d.get("result") or ""))' > "$T/out.$1" 2>/dev/null
}

echo "── 게이트: 설정 없는 새 프로젝트에서 ──"
run g1 'Read,Glob,Grep' "명령을 실행하지 말고 답해. 이 프로젝트에 src/missing.js 가 있어?"
grep -qiE '없|not|no such|찾을 수 없|확인' "$T/out.g1"; check 0 $? "근거 게이트: 도구 없이 단정하지 않는다"

echo "── 스킬 ──"
# 빈 프로젝트에는 답할 사람도, 인수인계할 것도 없다. 인터뷰하는 스킬(setup-checks·spec)은 묻고
# 멈추는 것이, handoff 는 "이어받을 것이 없다"고 밝히는 것이 맞는 동작이다. 그래서 "파일을 썼나" 가
# 아니라 "설계대로 행동했나" 를 본다. 없는 것을 지어내지 않는 것이 이 플러그인이 강제하려는 바다.

run setup-checks 'Read,Glob,Grep,Bash,Write,Edit' "/check:setup-checks"
grep -qE 'npm test|test_command|검사 명령' "$T/out.setup-checks"; check 0 $? "setup-checks: 검사 명령을 찾아 보고한다"
grep -qE '\?|물|선택|결정|제안' "$T/out.setup-checks"; check 0 $? "setup-checks: 쓰기 전에 사용자에게 묻는다(설계대로)"

run status 'Read,Glob,Grep,Bash' "/check:status"
grep -qE '게이트|gate' "$T/out.status"; check 0 $? "status: 게이트 상태를 보고한다"

run spec 'AskUserQuestion,Read,Glob,Grep,Write' "/check:spec 곱셈 함수를 더한다"
if [ -f "$P/SPEC.md" ]; then check 0 0 "spec: SPEC.md 를 쓰거나 인터뷰한다"
else grep -qE '\?|물|질문|확인' "$T/out.spec"; check 0 $? "spec: SPEC.md 를 쓰거나 인터뷰한다"; fi

run handoff 'Read,Glob,Grep,Bash,Write' "/check:handoff"
if [ -f "$P/HANDOFF.md" ]; then check 0 0 "handoff: HANDOFF.md 를 쓰거나 이어받을 것이 없다고 밝힌다"
else grep -qE '진행.*없|인수인계.*없|작업이 없|nothing to hand|no work' "$T/out.handoff"
     check 0 $? "handoff: HANDOFF.md 를 쓰거나 이어받을 것이 없다고 밝힌다"; fi
echo "── 일부러 돌리지 않은 것 ──"
echo "   finish: 커밋·푸시·PR 을 만든다. 인수 테스트가 남의 저장소에 쓰면 안 된다."
echo "   full-cycle: 위 스킬들을 순서대로 부르는 오케스트레이터라 개별 검증으로 충분하다."

echo
[ "$fail" -eq 0 ] && echo "전부 통과" || echo "실패 ${fail}건"
exit "$fail"
