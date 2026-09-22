#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# AGENTS.md 가 적어 둔 각 검사의 건수가 실제와 같은지 본다.
#
# 왜 따로 두나: 이 검사는 단위 테스트를 **실제로 돌려** 건수를 센다. tests/invariants.sh 안에
# 넣으면 전체 검사가 invariants 를 부르고 invariants 가 다시 전체를 부르는 재귀가 된다.
# 정적으로 `check` 호출 수를 세는 방법도 안 된다. 루프와 함수 안에서 불려 실제 건수와 어긋난다
# (2026-09-22 실측: no-guess-gate 는 호출 7곳에 실제 170건).
#
# 그래서 전체 검사 명령의 **맨 끝에** 한 번만 둔다. 앞에서 이미 돈 테스트를 다시 돌리는 비용은
# 감수한다. 문서의 숫자가 조용히 낡는 것을 막는 값이 그보다 크다.
# 2026-09-22 에 invariants.sh 에 검사를 하나 더하고 AGENTS.md 를 안 고쳐 449 가 448 인 채로
# 남을 뻔했다. 숫자를 지키는 검사가 정작 자기 숫자는 세지 않았다.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# 모델을 부르는 tests/acceptance.sh 와 회귀·A/B·판정기 정확도는 세지 않는다. 건수가 고정돼 있지 않다.
# **이 파일 자신도 목록에 넣지 않는다.** 아래 루프가 각 파일을 실제로 실행하므로, 자신을 넣으면
# 자기가 자기를 부르는 무한 재귀가 된다. 그래서 합계에는 이 검사의 1건을 상수로 더한다.
TESTS="lib/unit.sh no-guess-gate/unit.sh done-gate/unit.sh test-integrity/unit.sh
       project-guard/unit.sh repo-profile/unit.sh setup/unit.sh
       skills-unit.sh attack-surface.sh invariants.sh"

sum=0
for t in $TESTS; do
  real=$(bash "$R/tests/$t" 2>/dev/null | grep -cE '^(✅|❌)')
  sum=$((sum + real))
  # AGENTS.md 가 그 파일을 적은 줄에서 첫 번째 "N건" 을 꺼낸다.
  doc=$(grep -F "tests/$t" "$R/AGENTS.md" | head -1 | grep -oE '[0-9]+건' | head -1 | tr -d '건')
  if [ -z "$doc" ]; then
    echo "❌ AGENTS.md 에 tests/$t 의 건수가 없다"; fail=$((fail+1))
  elif [ "$doc" != "$real" ]; then
    echo "❌ tests/$t: 문서 ${doc}건, 실제 ${real}건"; fail=$((fail+1))
  fi
done

# 이 검사 자신의 1건. 위 루프가 세지 못하므로(재귀) 여기서 더한다.
sum=$((sum + 1))

doc_sum=$(grep -oE '합계 [0-9]+건' "$R/AGENTS.md" | head -1 | grep -oE '[0-9]+')
if [ -z "$doc_sum" ]; then
  echo "❌ AGENTS.md 에 합계가 없다"; fail=$((fail+1))
elif [ "$doc_sum" != "$sum" ]; then
  echo "❌ 합계: 문서 ${doc_sum}건, 실제 ${sum}건"; fail=$((fail+1))
fi

if [ "$fail" = 0 ]; then echo "✅ AGENTS.md 의 검사 건수가 실제와 같다(합계 ${sum}건)"; fi
echo; if [ "$fail" -eq 0 ]; then echo "전부 통과"; else echo "실패 ${fail}건"; fi
exit "$fail"
