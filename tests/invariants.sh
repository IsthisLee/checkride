#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 저장소가 스스로 지켜야 하는 불변식. 매니페스트·CHANGELOG·문서의 숫자, 그리고 셸 인용.
# 전부 조용히 어긋나는 것들이라 사람이 눈으로 볼 수 없다.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "✅ $1"; }
bad() { echo "❌ $1"; fail=$((fail+1)); }
j() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));
import functools
v=d
for k in sys.argv[2].split('.'):
    v = v[int(k)] if k.isdigit() else v.get(k)
    if v is None: break
print('' if v is None else v)" "$1" "$2" 2>/dev/null; }

M="$R/.claude-plugin/marketplace.json"; P="$R/plugin/.claude-plugin/plugin.json"
for f in "$M" "$P"; do
  if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$f"; then ok "$(basename "$f"): 올바른 JSON"; else bad "$(basename "$f"): JSON 파싱 실패"; fi
done

pv=$(j "$P" version); mv=$(j "$M" plugins.0.version)
if [ -n "$pv" ] && [ "$pv" = "$mv" ]; then ok "버전이 두 매니페스트에서 같다($pv)"; else bad "버전이 다르다(plugin=$pv marketplace=$mv)"; fi

pn=$(j "$P" name); mn=$(j "$M" plugins.0.name)
if [ -n "$pn" ] && [ "$pn" = "$mn" ]; then ok "플러그인 이름이 같다($pn)"; else bad "플러그인 이름이 다르다(plugin=$pn marketplace=$mn)"; fi

if grep -q "^## \[$pv\]" "$R/CHANGELOG.md"; then ok "CHANGELOG 에 [$pv] 항목이 있다"; else bad "CHANGELOG 에 [$pv] 항목이 없다"; fi

# shellcheck disable=SC2016  # $schema 는 JSON 의 키 이름이다. 셸이 펼치면 안 된다
if [ -n "$(j "$M" '$schema')" ]; then ok "marketplace 에 \$schema 가 있다"; else bad "marketplace 에 \$schema 가 없다"; fi
if [ -n "$(j "$M" plugins.0.tags)" ]; then ok "marketplace 에 tags 가 있다(Claude Code 안의 검색 필드)"; else bad "marketplace 에 tags 가 없다"; fi

src=$(j "$M" plugins.0.source)
if [ -d "$R/$src" ]; then ok "source 경로가 실재한다($src)"; else bad "source 경로가 없다($src)"; fi
if [ -f "$R/plugin/.claude-plugin/plugin.json" ]; then ok "strict=true 가 요구하는 plugin.json 이 있다"; else bad "plugin.json 이 없다"; fi

# 중괄호 없는 변수 뒤에 한글이 바로 붙으면 bash 가 그것까지 변수 이름으로 읽는다.
# set -u 아래서는 unbound variable 로 그 자리에서 죽는다. 실패 분기에 있으면 통과할 때는
# 안 보이다가 정작 실패를 알려야 할 때 죽는다. 이 저장소에서 세 번 났다.
bad_expand=$(python3 "$R/tests/lint-expand.py" "$R")
if [ -z "$bad_expand" ]; then ok "변수 뒤에 한글이 바로 붙은 곳이 없다"
else bad "변수 확장이 한글을 먹는 곳이 있다. \${var} 로 감싸라"; printf '%s\n' "$bad_expand" | sed 's/^/    /'; fi

# 훅을 임시 폴더로 복사해 돌리는 하네스는 lib/ 를 통째로 옮겨야 한다. msg.sh 를 빠뜨리면
# 게이트는 여전히 막지만 메시지가 키 이름으로 나가 측정값이 통째로 달라진다. 실제로 그렇게 잘못 쟀다.
missing=""
for h in "$R"/tests/*/unit.sh "$R"/tests/no-guess-gate/selftest.sh "$R"/tests/no-guess-gate/ab.sh; do
  [ -f "$h" ] || continue
  # lib/unit.sh 는 일부러 common.sh 만 옮긴다. 카탈로그가 없을 때를 시험하는 곳이다.
  case "$h" in */lib/unit.sh) continue;; esac
  grep -E '^[^#]*\bcp\b.*common\.sh' "$h" >/dev/null || continue
  grep -E '^[^#]*\bcp\b.*msg\.sh' "$h" >/dev/null || missing="$missing ${h#"$R"/}"
done
if [ -z "$missing" ]; then ok "훅을 복사하는 하네스가 전부 msg.sh 도 옮긴다"
else bad "msg.sh 를 빠뜨린 하네스가 있다:$missing"; fi

# Windows 는 " < > : | ? * 가 든 파일명을 체크아웃하지 못한다. 그런 파일이 커밋되면
# CI 가 체크아웃 단계에서 죽고 원인이 안 보인다. 실제로 그렇게 한 번 깨졌다.
badname=$(git -C "$R" ls-files | tr -d '"' | grep -nE '[<>:|?*\\]' || true)
badq=$(git -C "$R" ls-files | grep -c '"' || true)
if [ -z "$badname" ] && [ "$badq" = 0 ]; then ok "Windows 가 못 만드는 파일명이 없다"
else bad "Windows 에서 체크아웃 못 하는 파일명이 있다"; printf '%s\n' "$badname" | sed 's/^/    /'; fi

# 문서가 "실리는 것은 N개" 라고 적는다. 사용자가 설치 전에 확인하라고 안내한 숫자라 틀리면 안 된다.
# 실리는 것은 "커밋된 것" 이다. find 로 세면 py_compile 이 만든 __pycache__ 까지 잡혀
# CI 에서 하나 더 나온다. 실제로 그렇게 세 OS 가 깨졌다. git 이 아는 것만 센다.
n_pl=$(git -C "$R" ls-files plugin | wc -l | tr -d ' ')
[ "$n_pl" = 0 ] && n_pl=$(find "$R/plugin" -type f -not -path '*/__pycache__/*' | wc -l | tr -d ' ')
if grep -q "${n_pl}개 파일" "$R/SECURITY.md"; then ok "plugin/ 파일 수가 문서와 같다(${n_pl}개)"
else bad "plugin/ 파일 수가 문서와 다르다(실제 ${n_pl}개)"; fi

# 문서가 적어 둔 개수가 실제와 같은지. 숫자는 조용히 낡는다.
n_sk=$(find "$R/plugin/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$n_sk" = 8 ]; then ok "커맨드가 여덟이다"; else bad "커맨드가 여덟이 아니다(${n_sk}개). 문서를 고쳐라"; fi
# 훅 모듈은 커밋된 .sh 를 가진 디렉터리다. 디렉터리를 그냥 세면 py_compile 이 만든
# __pycache__ 까지 잡힌다. 파일 수 검사와 같은 이유로 git 이 아는 것만 본다.
n_gate=$(git -C "$R" ls-files "plugin/hooks/*/*.sh" | sed 's|.*/hooks/||; s|/.*||' | grep -v '^lib$' | sort -u | wc -l | tr -d ' ')
if [ "$n_gate" = 5 ]; then ok "훅 모듈이 다섯이다(게이트 넷 + 프로필)"; else bad "훅 모듈이 다섯이 아니다(${n_gate}개)"; fi
n_in=$(python3 "$R/tests/fuzz-inputs.py" | wc -l | tr -d ' ')
n_hook=$(grep -oE '[a-z-]+/[a-z]+\.sh' "$R/tests/fuzz.sh" | sort -u | wc -l | tr -d ' ')
want=$(( (n_in + 1) * n_hook ))
if grep -q "${want}회" "$R/docs/gates.md"; then ok "퍼징 횟수가 문서와 같다(${want}회)"; else bad "퍼징 횟수가 문서와 다르다(실제 ${want}회)"; fi


# 훅이 부르는 메시지 키와 카탈로그가 맞는지. 어긋나면 조용히 망가진다.
# 키가 없으면 모델이 문장 대신 ngg.r0 같은 키 이름을 받는다. 막히기는 하는데
# 무엇을 하라는지 몰라 행동이 달라진다. 이 저장소에서 실제로 났던 사고다.
# 반대로 아무도 안 부르는 키는 두 언어를 손보는 비용만 남긴다.
# common.sh 도 메시지를 내보내므로 제외 대상은 카탈로그 자신뿐이다.
if python3 - "$R" <<'MSGCOVER'
import os, re, sys
root = sys.argv[1]
cat_path = os.path.join(root, "plugin/hooks/lib/msg.sh")
cat = open(cat_path, encoding="utf-8").read()
defined = set(re.findall(r'^  ([a-z][a-z0-9.]*)\)', cat, re.M))
used = set()
for d, _, fs in os.walk(os.path.join(root, "plugin/hooks")):
    for f in fs:
        p = os.path.join(d, f)
        if not f.endswith(".sh") or os.path.abspath(p) == os.path.abspath(cat_path):
            continue
        t = open(p, encoding="utf-8").read()
        used |= set(re.findall(r'(?:^|[^A-Za-z_])tn? +([a-z][a-z0-9]*\.[a-z0-9.]*)', t, re.M))
missing = sorted(used - defined)
dead = sorted(defined - used)
assert not missing, f"카탈로그에 없는 키를 부른다: {missing}"
assert not dead, f"아무도 부르지 않는 키가 있다: {dead}"
MSGCOVER
then ok "메시지 키: 훅이 부르는 것과 카탈로그가 정확히 같다($(grep -cE '^  [a-z][a-z0-9.]*\)' "$R/plugin/hooks/lib/msg.sh") 줄, 두 언어)"
else bad "메시지 키가 어긋난다"; fi

# setup.sh 는 CONTRIBUTING 의 설치 절차가 부르는 파일이다. 없거나 실행 비트가 없으면
# 클론한 사람이 첫 줄에서 멈춘다.
if [ -x "$R/setup.sh" ]; then ok "setup.sh 가 있고 실행 비트가 있다"
else bad "setup.sh 가 없거나 실행 비트가 없다"; fi
for c in "$R/CONTRIBUTING.md" "$R/CONTRIBUTING.en.md"; do
  n=${c##*/}
  if grep -q './setup.sh' "$c"; then ok "${n} 가 setup.sh 를 안내한다"
  else bad "${n} 가 setup.sh 를 안내하지 않는다"; fi
done

# 이름을 바꾼 뒤 옛 이름이 남으면 설치 명령과 커맨드가 갈린다. VERIFICATION 은 과거 기록이라 뺀다.
# CHANGELOG 와 VERIFICATION 은 이력이라 옛 이름을 그대로 둔다(CHANGELOG.md:81 이 그렇게 정한다).
# 이 스크립트 자신은 검색 패턴 문자열 안에 옛 이름을 그대로 담고 있어 자기 자신과 항상 걸린다. 빼지 않으면
# old 가 0 이 될 수 없다.
# decisions.md 182행도 이력이다. 2026-09-22 에 개발 기계에서 실측한 상태 폴더 목록을 그대로 적은
# 문장이라 `check-did-you-check` 를 남긴다. 고치면 실측 기록이 아니게 된다.
old=$(grep -rln "did-you-check\|/check:" \
        --exclude-dir=.git --exclude-dir=.private --exclude-dir=.superpowers \
        --exclude=VERIFICATION.md --exclude=CHANGELOG.md --exclude=invariants.sh --exclude=decisions.md \
        "$R" 2>/dev/null | wc -l | tr -d ' ')
if [ "$old" = 0 ]; then ok "옛 이름이 남아 있지 않다"; else bad "옛 이름이 ${old}개 파일에 남았다"; fi

echo
if [ "$fail" -eq 0 ]; then echo "전부 통과"; else echo "실패 ${fail}건"; fi
exit "$fail"
