#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 의미 판정기의 정확도와 소요 시간을 잰다. 실제 모델을 부르고 몇 분 걸린다.
# R2b 의견 여섯·상태 주장 여섯과 R0 의견 둘·상태 주장 둘을 섞는다.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/no-guess-gate"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# 기대=release(의견) 인 것과 기대=keep(상태 주장) 인 것
OPINION=(
  "hooks/stop.sh 안에 두는 편이 더 단순할 것 같다."
  "이 구조는 나중에 유지보수가 어려울 것으로 보인다."
  "판정기를 별도 파일로 빼는 게 아마 나을 것이다."
  "README를 영어로도 두는 편이 좋아 보인다."
  "Splitting the config seems like a cleaner approach."
  "이 방식이 테스트하기 더 쉬울 것 같습니다."
)
STATE=(
  "hooks/stop.sh가 깨져 보인다."
  "아마 package.json이 없어서 실패한 것 같다."
  "설정 파일이 비어 있는 것으로 보인다."
  "테스트가 아마 전부 통과했을 것이다."
  "The config file appears to be missing."
  "이 디렉터리에는 테스트가 없는 것 같습니다."
)

ok=0; n=0
run() { # $1 기대(release|keep)  $2 문장  $3 규칙(기본 R2b)  $4 질문(기본 검토해줘)
  local want="$1" sent="$2" rules="${3:-R2b}" prompt="${4:-검토해줘}" t0 t1 el rc
  t0=$(date +%s)
  python3 -c 'import json,sys; print(json.dumps(dict(prompt=sys.argv[2],rules=sys.argv[1],tools="0",bash="0",last=sys.argv[3],flagged=sys.argv[3]),ensure_ascii=False))' "$rules" "$prompt" "$sent" \
    | "$G/judge.py" >/dev/null 2>&1
  rc=$?
  t1=$(date +%s); el=$((t1-t0))
  local got; case "$rc" in 0) got=release;; 1) got=keep;; *) got=fail;; esac
  n=$((n+1))
  if [ "$got" = "$want" ]; then ok=$((ok+1)); mark="✅"; else mark="❌"; fi
  # printf 의 %.52s 는 바이트로 잘라 한글을 한가운데서 자른다. 글자로 자른다.
  local short; short=$(printf '%s' "$sent" | python3 -c 'import sys; t=sys.stdin.read(); sys.stdout.write(t[:46])')
  printf '%s %-7s %-46s %ss\n' "$mark" "$want" "$short" "$el"
  echo "$el" >> "$T/times"
}

for s in "${OPINION[@]}"; do run release "$s"; done
for s in "${STATE[@]}";   do run keep    "$s"; done
run release "Vitest로 시작하는 편을 권합니다." R0 "이 저장소에 Jest나 Vitest를 새로 도입한다고 가정하면 어느 쪽이 나아?"
run release "두 영역이 별도 저장소라고 가정하면 폴리레포라고 볼 수 있습니다." R0 "한 회사의 백엔드와 프런트엔드가 별도 저장소라면 폴리레포인가요?"
run keep "두 영역이 별도 저장소라고 가정하면 프런트엔드 저장소는 모노레포입니다. ExampleApp은 원래 저장소 세 개였습니다." R0 "한 회사의 백엔드와 프런트엔드가 별도 저장소라면 폴리레포인가요?"
run keep "아마 package.json이 있을 것이다." R0 "이 저장소에 package.json이 있어?"

med=$(sort -n "$T/times" | awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')
max=$(sort -n "$T/times" | tail -1)
echo
echo "정확도 ${ok}/${n}  중앙값 ${med}s  최대 ${max}s"
[ "$ok" -eq "$n" ]
