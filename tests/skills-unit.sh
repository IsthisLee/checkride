#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 스킬 정의 검사. 모델을 부르지 않는다. 배포물이므로 회귀로 고정한다.
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE
G="$(cd "$(dirname "$0")/../plugin/skills" && pwd)"
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }

python3 - "$G" <<'PY'
import os, re, sys
root = sys.argv[1]
want = {"spec","init","tdd","ship","handoff","status","auto","config"}
found = {d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))}
assert found == want, f"스킬 목록 불일치: {sorted(found)}"
for name in sorted(want):
    p = os.path.join(root, name, "SKILL.md")
    assert os.path.isfile(p), f"{name}: SKILL.md 없음"
    t = open(p, encoding="utf-8").read()
    assert t.startswith("---\n"), f"{name}: frontmatter 시작 없음"
    fm, body = t.split("---\n", 2)[1], t.split("---\n", 2)[2]
    kv = dict(re.findall(r"^([a-z-]+):\s*(.+)$", fm, re.M))
    assert kv.get("name") == name, f"{name}: name={kv.get('name')} (폴더명과 달라 /이름이 어긋난다)"
    assert kv.get("disable-model-invocation") == "true", f"{name}: 사용자 전용이어야 한다"
    d = kv.get("description", "")
    assert 20 <= len(d) <= 200, f"{name}: description 길이 {len(d)}"
    assert "allowed-tools" in kv, f"{name}: allowed-tools 없음"
    assert len(body.strip()) >= 400, f"{name}: 본문이 너무 짧다({len(body.strip())}자)"
    assert body.lstrip().startswith("# "), f"{name}: 본문이 제목으로 시작하지 않는다"
PY
check 0 $? "스킬 여덟: 폴더명·name 일치, 사용자 전용, description, allowed-tools, 본문"

# 인자를 받는 스킬은 $ARGUMENTS를 실제로 쓴다
for n in spec tdd ship auto; do
  # shellcheck disable=SC2016  # $ARGUMENTS는 리터럴로 찾는다
  grep -q '\$ARGUMENTS' "$G/$n/SKILL.md" || { echo "❌ $n: \$ARGUMENTS 미사용"; fail=$((fail+1)); }
done
check 0 0 "인자를 받는 넷은 \$ARGUMENTS를 쓴다"

# 내장과 겹치는 것을 새로 만들지 않았는지 (전수 조사 결정)
for bad in "check:plan" "check:explore" "check:review" "check:verify" "check:commit"; do
  ls -d "$G/${bad#check:}" >/dev/null 2>&1 && { echo "❌ 내장과 겹치는 스킬 존재: $bad"; fail=$((fail+1)); }
done
check 0 0 "내장과 겹치는 스킬 없음(plan·explore·review·verify·commit)"

# 근거 인용이 있는지. 근거 없는 절차는 이 저장소가 막으려는 것이다.
for n in spec tdd ship auto; do
  grep -qE '"[A-Z][^"]{25,}"' "$G/$n/SKILL.md" || { echo "❌ $n: 원문 인용 없음"; fail=$((fail+1)); }
done
check 0 0 "핵심 넷은 공식·검증 문서를 원문으로 인용한다"

# 스킬은 설치본에 그대로 실려 모든 사용자가 받는다. 배포 대상을 한국어 사용자로 좁혔으므로
# 본문을 한국어로 쓴다. 사람이 읽는 것은 커맨드 목록의 description 이고, 본문은 모델이 읽는다.
# 둘 다 한국어여야 사용자가 /check: 를 칠 때 무엇을 고르는지 읽을 수 있다.
# 한국어로 써도 영어권 사용자가 부를 수는 있으므로 "내가 쓰는 언어로 답한다"는 남겨 둔다.
# 인용한 원문(영어)은 그대로 두고 번역을 붙인다. 그래서 영어가 섞이는 것은 정상이다.
python3 - "$G" <<'SKILLLANG'
import os, re, sys
root = sys.argv[1]
for name in sorted(os.listdir(root)):
    p = os.path.join(root, name, "SKILL.md")
    if not os.path.isfile(p):
        continue
    t = open(p, encoding="utf-8").read()
    fm, body = t.split("---\n", 2)[1], t.split("---\n", 2)[2]
    ko = re.findall(r"[가-힣]", body)
    assert len(ko) >= 200, f"{name}: 본문 한글 {len(ko)}자. 설치본 스킬은 한국어로 쓴다"
    # description 은 커맨드 목록에서 사람이 읽는 유일한 줄이라 여기가 한국어여야 한다.
    # 한 글자만 세면 영어 문장에 한국어 단어 하나를 끼운 것도 통과한다. 실측한 최솟값이
    # spec 의 25자이므로 15자로 잡는다(여유 10자). 비율은 쓰지 않는다. 고유명사와 인용이
    # 많은 description 은 비율이 29.8%까지 내려가 문턱을 안정적으로 잡을 수 없다.
    d = dict(re.findall(r"^([a-z-]+):\s*(.+)$", fm, re.M)).get("description", "")
    kod = re.findall(r"[가-힣]", d)
    assert len(kod) >= 15, f"{name}: description 한글 {len(kod)}자. 커맨드 목록에 뜨는 줄은 한국어로 쓴다"
    # 어미는 문장마다 갈린다("답한다"·"답하고"). 원문 검사가 어미를 뺀
    # "language I am writing to you in" 만 봤던 것과 같은 방식으로 불변 부분만 본다.
    assert re.search(r"내가 쓰는 언어로 답", body), \
        f"{name}: 내가 쓰는 언어로 답하라는 줄이 없다"
SKILLLANG
check 0 $? "스킬 여덟: 한국어로 쓰고 내가 쓰는 언어로 답하라고 지시한다"

echo; echo "실패 ${fail}건"; exit "$fail"
