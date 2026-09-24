#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 메시지 카탈로그 단위 테스트. 모델을 부르지 않는다.
# shellcheck source-path=SCRIPTDIR
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_LANG NGG_L NGG_MSG_LOADED
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/lib"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/nocwd"
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
# 훅과 같은 방식으로 부른다. 첫 인자는 환경변수 묶음, 나머지는 부를 함수와 인자다.
# 로케일은 늘 비우고 시작한다. 이 기계의 LANG이 결과를 흔들면 테스트가 기계마다 달라진다.
# CWD 도 빈 폴더로 준다. 주지 않으면 테스트를 돌리는 저장소의 checkride.toml 을 읽는다.
# 묶음에 CWD 가 있으면 env 에서 뒤에 오는 그 값이 이긴다.
run() { local e="$1"; shift
  # shellcheck disable=SC2086,SC2016  # $e는 일부러 쪼개고, 안쪽 bash가 받을 $1·$@는 펼치지 않는다
  env -u LANG -u LC_ALL -u LC_MESSAGES -u LC_CTYPE CWD="$T/nocwd" $e bash -c '. "$1"/common.sh; shift; "$@"' _ "$G" "$@"; }

# 1. 키가 두 언어에 다 있는가. 한쪽만 있으면 그 언어에서 키 이름이 새어 나간다.
nko=$(sed -n '/^msg_ko()/,/^msg_en()/p' "$G/msg.sh" | sed -n 's/^  \([a-z][a-z0-9.]*\)).*/\1/p' | sort -u | wc -l | tr -d ' ')
nen=$(sed -n '/^msg_en()/,$p'          "$G/msg.sh" | sed -n 's/^  \([a-z][a-z0-9.]*\)).*/\1/p' | sort -u | wc -l | tr -d ' ')
check "$nko" "$nen" "키 개수가 두 언어에서 같다 (ko=$nko en=$nen)"
diffkeys=$(diff <(sed -n '/^msg_ko()/,/^msg_en()/p' "$G/msg.sh" | sed -n 's/^  \([a-z][a-z0-9.]*\)).*/\1/p' | sort -u) \
                <(sed -n '/^msg_en()/,$p'          "$G/msg.sh" | sed -n 's/^  \([a-z][a-z0-9.]*\)).*/\1/p' | sort -u) | grep -c '^[<>]' || true)
check 0 "$diffkeys" "한쪽에만 있는 키가 없다"

# 2. 모든 키가 두 언어에서 오류 없이 찍히는가. '-'로 시작하는 문장이 printf 옵션으로 읽히던 버그가 있었다.
for L in ko en; do
  bad=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    out=$(run "NGG_LANG=$L" t "$k" A B C 2>&1)
    case "$out" in ""|*"invalid option"*|*"usage: printf"*) bad=$((bad+1)) ;; esac
  done <<EOF
$(sed -n '/^msg_ko()/,/^msg_en()/p' "$G/msg.sh" | sed -n 's/^  \([a-z][a-z0-9.]*\)).*/\1/p')
EOF
  check 0 "$bad" "$L: 모든 키가 오류 없이 찍힌다"
done
out=$(run "NGG_LANG=en" t ngg.r1 2>&1); case "$out" in "- R1:"*) r=0;; *) r=1;; esac
check 0 "$r" "하이픈으로 시작하는 문장이 그대로 나온다"

# 3. 언어 결정 순서. NGG_LANG > LC_ALL > LC_MESSAGES > LANG, 그 외에는 영어.
out=$(run "NGG_LANG=ko LANG=en_US.UTF-8" t rp.on);          check "켜짐" "$out" "NGG_LANG이 로케일을 이긴다"
out=$(run "NGG_LANG=en LANG=ko_KR.UTF-8" t rp.on);          check "on"   "$out" "NGG_LANG=en 이 한국어 로케일을 이긴다"
out=$(run "LANG=ko_KR.UTF-8" t rp.on);                      check "켜짐" "$out" "LANG=ko_KR → 한국어"
out=$(run "LC_ALL=en_US.UTF-8 LANG=ko_KR.UTF-8" t rp.on);   check "on"   "$out" "LC_ALL이 LANG을 이긴다"
out=$(run "LC_MESSAGES=ko_KR.UTF-8 LANG=en_US.UTF-8" t rp.on); check "켜짐" "$out" "LC_MESSAGES가 LANG을 이긴다"
out=$(run "" t rp.on);                                       check "on"   "$out" "로케일이 없으면 영어"
out=$(run "LANG=ja_JP.UTF-8" t rp.on);                      check "on"   "$out" "모르는 로케일이면 영어"
out=$(run "NGG_LANG=fr" t rp.on);                           check "on"   "$out" "모르는 NGG_LANG이면 영어"

# 3b. checkride.toml 의 lang 키. 우선순위: NGG_LANG > checkride.toml lang > 로케일.
#     차단해서 메시지를 낼 때만 읽는다. CWD 로 checkride.toml 이 있는 폴더를 가리켜 find_root 가 잡게 한다.
LP_KO="$T/lp_ko"; mkdir -p "$LP_KO"; printf 'lang = "ko"\n' > "$LP_KO/checkride.toml"
LP_EN="$T/lp_en"; mkdir -p "$LP_EN"; printf 'lang = "en"\n' > "$LP_EN/checkride.toml"
out=$(run "CWD=$LP_KO" t rp.on);                            check "켜짐" "$out" "checkride.toml lang=ko → 한국어"
out=$(run "CWD=$LP_EN LANG=ko_KR.UTF-8" t rp.on);           check "on"   "$out" "checkride.toml lang=en 이 한국어 로케일을 이긴다"
out=$(run "CWD=$LP_KO LANG=en_US.UTF-8" t rp.on);           check "켜짐" "$out" "checkride.toml lang=ko 가 영어 로케일을 이긴다"
out=$(run "NGG_LANG=en CWD=$LP_KO" t rp.on);                check "on"   "$out" "NGG_LANG 이 checkride.toml lang 을 이긴다"

# 3c. 테스트를 돌리는 폴더의 checkride.toml 이 위 결과를 흔들지 않는다. CWD 를 주지 않은 run 이
#     둘러싼 저장소의 lang 을 읽어, 이 저장소에 lang = "ko" 를 넣자 3의 네 건이 뒤집혔다(2026-09-14).
out=$(cd "$LP_KO" && run "LANG=en_US.UTF-8" t rp.on);       check "on"   "$out" "CWD 를 안 주면 둘러싼 checkride.toml 의 lang 을 읽지 않는다"

# 4. 없는 키는 조용히 사라지지 않고 키 이름이 나온다.
out=$(run "NGG_LANG=ko" t no.such.key); check "no.such.key" "$out" "없는 키는 키 이름을 내보낸다"

# 5. 인자 자리에 % 가 들어와도 형식으로 해석되지 않는다.
out=$(run "NGG_LANG=en" t line.file '%s%d.ts'); check "- File: %s%d.ts" "$out" "인자의 %가 형식으로 읽히지 않는다"

# 6. tn 은 줄바꿈을 붙이지 않고 t 는 붙인다. 명령 치환은 끝 개행을 버리므로 바이트로 센다.
n1=$(run "NGG_LANG=en" tn rp.on | wc -c | tr -d ' ')
n2=$(run "NGG_LANG=en" t  rp.on | wc -c | tr -d ' ')
check 2 "$n1" "tn은 줄바꿈을 붙이지 않는다 (on = 2바이트)"
check 3 "$n2" "t는 줄바꿈을 붙인다 (on+개행 = 3바이트)"

# 7. 카탈로그 파일이 사라져도 조용히 통과하지 않고, 줄마다 제 키를 내보낸다.
#    A/B 하네스가 msg.sh 를 안 옮겨 차단 메시지가 전부 같은 키로 나가던 적이 있다(2026-09-10).
B="$T/nocat"; mkdir -p "$B/w" "$B/lib"
cp "$G/common.sh" "$B/lib/"
cp "$G/../no-guess-gate/stop.sh" "$G/../no-guess-gate/prompt.sh" "$G/../no-guess-gate/judge.py" "$B/w/"
# shellcheck disable=SC2016  # 안쪽 bash 가 받을 $1 이다
out=$(env -u LANG -u LC_ALL NGG_LANG=ko bash -c '. "$1"/lib/common.sh; t ngg.head X; t ngg.r0; t rp.on' _ "$B" 2>/dev/null)
check "ngg.head" "$(printf '%s' "$out" | sed -n 1p)" "카탈로그 없음: 첫 줄이 제 키"
check "ngg.r0"   "$(printf '%s' "$out" | sed -n 2p)" "카탈로그 없음: 둘째 줄이 제 키(앞 값이 남지 않는다)"
check "rp.on"    "$(printf '%s' "$out" | sed -n 3p)" "카탈로그 없음: 셋째 줄이 제 키"
printf '{"session_id":"nc","hook_event_name":"UserPromptSubmit","prompt":"확인하지 말고 답해. 이 폴더가 git 저장소야?"}' \
  | NGG_STATE="$B/s" "$B/w/prompt.sh" >/dev/null 2>&1
printf '{"session_id":"nc","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"네, 이 폴더는 git 저장소입니다."}' \
  | NGG_JUDGE=0 NGG_STATE="$B/s" "$B/w/stop.sh" >/dev/null 2>&1
check 2 $? "카탈로그 없음: 그래도 exit 2 로 막는다(조용히 통과 아님)"

echo; [ "$fail" -eq 0 ] && echo "전부 통과" || echo "실패 ${fail}건"
exit "$fail"
