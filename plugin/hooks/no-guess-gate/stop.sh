#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# Stop / SubagentStop: 근거 없는 결론 게이트 v4. 위반 시 exit 2로 턴 종료 차단.
[ -n "${NGG_INNER:-}" ] && { cat >/dev/null; exit 0; }  # 판정기가 띄운 중첩 세션에서는 돌지 않는다
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"; read_in; s=$(state_dir "$d")
# shellcheck disable=SC2153  # LAST/PROMPT 등은 _common.sh의 read_in이 eval로 정의한다
last="$LAST"; prompt=$(cat "$s/prompt" 2>/dev/null); f="$s/tools"
ntools=$({ wc -l < "$f"; } 2>/dev/null | tr -d ' '); ntools=${ntools:-0}
nbash=$(grep -c '^Bash$' "$f" 2>/dev/null); nbash=${nbash:-0}
nask=$(grep -c '^AskUserQuestion$' "$f" 2>/dev/null); nask=${nask:-0}
off=""; offbad=""
log() { local lf; lf="$(state_root "$d")/state/events.log"
  echo "$HOOK_EVENT_NAME${AGENT_ID:+/agent} active=$STOP_HOOK_ACTIVE tools=$ntools bash=$nbash ctx=$1${judge_log:+ $judge_log}${off:+ off=[$off]}${offbad:+ off?=[$offbad]} viol=[$2] last=$(printf '%s' "$last" | head -c 80 | LC_ALL=C tr '\n' ' ')" >> "$lf"
  if [ "$(wc -l < "$lf" 2>/dev/null || echo 0)" -gt 2200 ]; then tail -n 2000 "$lf" > "$lf.tmp" 2>/dev/null && mv "$lf.tmp" "$lf"; fi; }
if [ "$nask" -gt 0 ]; then log - "(exempt:ask-tool)"; touch "$s/turn_closed"; exit 0; fi
ASKRE='(\?[[:space:]]*$|which (one|takes priority|do you)|should I|do you want|would you like|please (confirm|clarify|tell me)|어느 쪽|어떻게 할까|할까요\?|원하시|확인해 주|알려 주|선택해 주)'
if printf '%s' "$last" | grep -qiE "$ASKRE"; then log - "(exempt:question)"; touch "$s/turn_closed"; exit 0; fi

FILE='[A-Za-z0-9_.-]+\.(json|js|jsx|ts|tsx|md|sh|yml|yaml|env|lock|sql|css|scss|py|go|rs)'
LOCALQ="(this (directory|folder|file|repo|repository|project|codebase|code|config|setting)|the (code|codebase|repo|repository|project|config|current directory)|current directory|in here|이 (디렉터리|폴더|파일|저장소|프로젝트|코드|설정)|여기|현재 (디렉터리|폴더)|코드베이스|저장소|$FILE)"
PATHRE="((^|[^A-Za-z0-9])/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+|$FILE)"
# 답이 "여기 있는 파일" 의 상태를 말해도 코드베이스 맥락이다. 명사 없이 쓰인 "Here is …" 는 잡지 않는다(V49 tp-defer).
HERELOCAL='(\b(files?|scripts?|tests?|folders?|directories|modules?|configs?)\b[^.]{0,20}\bhere\b|(여기|이 디렉터리|이 폴더|이 저장소)(에 있는| 있는|에|의|안의|안에 있는) ?[^.]{0,20}(파일|스크립트|테스트|폴더|디렉터리))'
ctx=0; printf '%s' "$prompt" | grep -qiE "$LOCALQ" && ctx=1; printf '%s' "$last" | grep -qE "$PATHRE" && ctx=1
printf '%s' "$last" | grep -qiE "$HERELOCAL" && ctx=1
# 정규식의 대괄호 안에는 멀티바이트 문자를 넣지 않는다. LC_ALL=C 같은 로케일에서 grep·sed 가
# 바이트로 매칭해 한국어 글자를 한가운데서 자르고, 그러면 R1 이 조용히 안 걸린다. 교체(|)로 쓴다.
R1PHRASE="(there('s| is| are) (no|a|an)|(does|doesn't|do not|don't) (contain|exist|have)|존재하지 않|파일이 없|파일이 있|디렉터리에 (없|있))"
R1STATE='(없다([[:space:],.)]|$)|없습니다|없음([[:space:],.)]|$)|없어(요)?([[:space:],.)]|$)|있다([[:space:],.)]|$)|있습니다|있음([[:space:],.)]|$)|존재(한다|합니다|하지 않는다|하지 않습니다)([[:space:],.)]|$)|비어 ?있|is missing|not found|no such|does not exist|doesn'"'"'t exist|exists([[:space:],.)]|$)|is empty)'
r1_hit() { printf '%s' "$last" | grep -qiE "$R1PHRASE" && return 0; printf '%s\n' "$last" | sed -E 's/(\.|!|\?|。)([[:space:]]|$)/\1\n/g' | grep -E "$PATHRE" | grep -v '수 있' | grep -qiE "$R1STATE"; }
R2a='(should (verify|check|confirm)|need(s)? to (verify|check|confirm)|would need to (check|verify|run|look)|without checking|to be sure|확인 필요|실측 필요|검증 필요|확인해야|검증해야|확인이 필요|확인하지 않았|검증하지 않았|미확인)'
# 불가 면제. 실측이 불가능한 이유를 밝힌 답. "안 했다"(NEG)와 다르다. R0·R2a·R2b에서 벗어나고 단정(R1)과 검증 주장(R3)에는 적용하지 않는다.
CANNOT='(확인할 수 없|검증할 수 없|실행할 수 없|접근할 수 없|띄울 수 없|재현할 수 없|불가능(하다|합니다|해서|하다고)|(도구|명령|명령어|커맨드|bash|셸|쉘|툴) ?(실행|호출)?[^.]{0,25}(안 ?(된다|돼|됩니다|되고|돌아)|되지 않|실행되지 않|돌지 않|불가|막혀)|cannot (verify|check|run|access|reproduce|execute)|can'"'"'t (verify|check|run|access|reproduce|execute)|unable to (verify|check|run|access|reproduce|execute)|no (access|permission)|tools? (are|is) (not |un)?(available|working|running|broken|failing)|tool calls? (are |is )?(not|fail))'
# 의견형 유보. "나아 보인다"는 설계 의견이지 상태 주장이 아니다. R2b 판정 전에 지운다.
EVALHEDGE='((더 |훨씬 |좀 더 )?(나아|낫|좋아|괜찮아|적절해|맞아|타당해|자연스러워|충분해|깔끔해|안전해|편해|쉬워|무난해|합리적으로|바람직해|유리해|나쁘지 않아) ?보(인다|임|입니다|여요|이네요|이는데|이지만)|(seems?|looks?|appears?|feels?) (like )?(a |the )?(good|better|best|fine|reasonable|appropriate|sensible|cleaner|simpler|safer|right|ok|okay|nice|worth|solid|clean|natural|clearer|preferable))'
cannot=0; printf '%s' "$last" | grep -qiE "$CANNOT" && cannot=1
# 인용은 사용이 아니다. 따옴표·백틱 안(80자 이내)과 공백 없는 괄호 목록("(보인다/보입니다)")은 R2a·R2b 판정 전에 지운다. R1은 원문을 본다.
# shellcheck disable=SC2016,SC1112  # 파이썬 코드는 확장하지 않는다. 곡선 따옴표는 인용 부호를 찾기 위한 것으로 의도적이다
STRIPQ='import sys,re; t=sys.stdin.read(); sys.stdout.write(re.sub(r"\"[^\"\n]{1,80}\"|“[^”\n]{1,80}”|‘[^’\n]{1,80}’|`[^`\n]{1,80}`|「[^」\n]{1,80}」|\([^()\s]{1,40}\)", " ", t))'
# shellcheck disable=SC2019,SC2018  # LC_ALL=C에서 ASCII만 낮춘다. 한글은 그대로 두는 것이 의도다
xform() { py -c "$STRIPQ" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed -E "s/$EVALHEDGE//g"; }
resid=$(printf '%s' "$last" | xform)
# JSON 면제. 답 전체가 JSON 값이면 산문 주장 규칙의 대상이 아니다(판정·비교 출력). py 검증에 실패하면 면제하지 않는다.
jsononly=0; printf '%s' "$last" | sed -E '1s/^[[:space:]]*```(json)?[[:space:]]*//; $s/[[:space:]]*```[[:space:]]*$//' | py -c 'import sys,json
t=sys.stdin.read().strip()
sys.exit(0 if t[:1] in "{[" and isinstance(json.loads(t),(dict,list)) else 1)' 2>/dev/null && jsononly=1
prose=1; { [ "$cannot" -eq 1 ] || [ "$jsononly" -eq 1 ]; } && prose=0
R2b='(probably|likely|approximately|appears? to|seems? to|presumably|I think|maybe|I guess|my guess|I assume|assuming|no indication|아마|것 같|로 보임|보(인다|입니다|여요|이네요|이는데|이지만)|로 추정|추정됨|가정하면|추측|것으로 판단)'
R3='(테스트.{0,6}(통과했|성공했|돌렸|실행했)|검증(했|됐|완료)|동작.{0,4}확인(했|됐)|정상.{0,4}(동작|작동)(함|합니다|한다)|all tests (pass|passed|are passing)|I (ran|executed|checked|verified|confirmed|tested)|works (as expected|correctly))'
NEG='(cannot|can'"'"'t|unable to|did not|didn'"'"'t|have not|haven'"'"'t|not (run|ran|verified|checked|tested)|without (running|checking|verifying)|하지 않았|안 했|못 했|미실행|미확인|없이는|수 없)'
NG2='(추측이 아니|추측이 아닌|추측 아니|추정이 아니|추측하지 않|추측한 것이 아니|추측한 게 아니|실측값|실측한|실측이다|not a guess|is not a guess|isn.t a guess|not guessing|rather than guess)'
v=""
# 차단 뒤 도구 없이 다시 끝내는 답을 따로 막던 R4 는 뺐다. 공식 Reduce hallucinations 는 뒷받침을 못 찾은
# 주장을 철회하라고 하므로, 다시 쓴 답도 아래 규칙으로만 판정한다(V49).
[ "$ntools" -eq 0 ] && [ "$prose" -eq 1 ] && printf '%s' "$prompt" | grep -qiE "$LOCALQ" && v="$v R0"
[ "$ntools" -eq 0 ] && [ "$jsononly" -eq 0 ] && r1_hit && v="$v R1"
# R2a 는 코드베이스 맥락(ctx)에서만 건다. 근거 문장이 "BEFORE answering questions about the codebase" 로 범위를 한정한다.
[ "$ntools" -eq 0 ] && [ "$ctx" -eq 1 ] && [ "$prose" -eq 1 ] && printf '%s' "$resid" | grep -qiE "$R2a" && v="$v R2a"
# R5: 이 턴에 마지막으로 돌린 Bash 가 실패했는데 검증·성공을 주장한다. R3 은 Bash 0건만 보므로
# 돌렸는데 실패한 경우가 비어 있었다. bashres.sh 가 S/F 를 순서대로 남긴다.
lastb=$(tail -c 1 "$s/bashseq" 2>/dev/null || true)
[ "$prose" -eq 1 ] && [ "$lastb" = "F" ] && printf '%s' "$resid" | grep -qiE "$R3" && v="$v R5"
[ "$ctx" -eq 1 ] && [ "$prose" -eq 1 ] && printf '%s' "$resid" | grep -qiE "$R2b" && ! printf '%s' "$last" | grep -qiE "$NG2" && v="$v R2b"
[ "$nbash" -eq 0 ] && printf '%s' "$last" | grep -qiE "$R3" && ! printf '%s' "$last" | grep -qiE "$NEG" && v="$v R3"
v="${v# }"

# 저장소별로 규칙을 끈다. 지금까지는 환경변수로 통째로 끄는 길뿐이었는데, 그것은 한 사람
# 셸에만 있어 팀이 모른다. .check.toml 에 적으면 PR 에 보이고 무엇을 껐는지 로그에 남는다.
# 끄기를 쉽게 만드는 것이 아니라 끄는 행위를 보이게 만드는 것이 목적이다.
off=""; offbad=""
find_root; ngg_conf="$NGG_ROOT/.check.toml"          # cwd 가 아니라 저장소 루트다(common.sh)
# 걸린 것이 없으면 설정을 읽지 않는다. 이 훅은 턴마다 돌아 상시 비용이 된다.
if [ -n "$v" ] && [ -f "$ngg_conf" ]; then
  dr=$(sed -n 's/^[[:space:]]*disabled_rules[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$ngg_conf" | head -1)
  for tok in $(printf '%s' "$dr" | tr ',' ' '); do
    case "$(printf '%s' "$tok" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in
      r0) R=R0;; r1) R=R1;; r2a) R=R2a;; r2b) R=R2b;; r3) R=R3;; r5) R=R5;;
      # 다른 게이트의 항목(done.pr 등)은 같은 줄에 온다. 모르는 이름으로 알리면 오탐이다.
      *) case " $NGG_ITEMS " in *" $(lc "$tok") "*) continue;; esac
         offbad="$offbad $tok"; continue;;
    esac
    off="$off $R"
  done
  off="${off# }"; offbad="${offbad# }"
fi
if [ -n "$off" ] && [ -n "$v" ]; then
  keep=""; dropped=""
  for r in $v; do
    skip=0
    for o in $off; do [ "$r" = "$o" ] && skip=1; done
    if [ "$skip" -eq 1 ]; then dropped="$dropped $r"; else keep="$keep $r"; fi
  done
  v="${keep# }"; off="${dropped# }"
fi
# 수준 2. 정규식이 R2a·R2b만 잡았으면 모델에게 의견인지 상태 주장인지 묻는다. 풀어 줄 수만 있고 새로 막지 못한다.
# R0·R1·R3·R5(도구를 안 돌린 사실, 단정, 검증 주장)는 판정 대상이 아니다. 실패·시간초과면 막은 채로 둔다(fail closed).
JUDGE_DEFAULT=1; judge_note=""; judged=""; judge_log=""
if [ -n "$v" ] && [ "${NGG_JUDGE:-$JUDGE_DEFAULT}" != "0" ] && ! printf '%s' "$v" | grep -qE 'R0|R1|R3|R5'; then
  # 걸린 문장만 뽑아 보낸다. 판정 대상이 분명해지고 입력이 짧아진다.
  flagged=$(printf '%s\n' "$last" | sed -E 's/(\.|!|\?|。)([[:space:]]|$)/\1\n/g' | while IFS= read -r sent; do [ -n "$sent" ] && printf '%s' "$sent" | xform | grep -qiE "$R2a|$R2b" && printf '%s\n' "$sent"; done)
  jt0=$(date +%s)
  why=$(py -c 'import json,sys; print(json.dumps(dict(prompt=sys.argv[1],rules=sys.argv[2],tools=sys.argv[3],bash=sys.argv[4],last=sys.argv[5],flagged=sys.argv[6]),ensure_ascii=False))' "$prompt" "$v" "$ntools" "$nbash" "$last" "$flagged" | PYTHONUTF8=1 PYTHONIOENCODING=utf-8 "$d/judge.py" 2>/dev/null); jr=$?
  jel=$(( $(date +%s) - jt0 ))
  case "$jr" in
    0) judged="(exempt:judge $v)"; judge_log="judge=released ${jel}s"; v="";;
    1) judge_note=$(tn ngg.judgekept "$why"); judge_log="judge=kept ${jel}s";;
    *) judge_note=$(tn ngg.judgefail "$why"); judge_log="judge=failed ${jel}s";;
  esac
fi
tag="$v"; if [ -z "$v" ]; then [ "$jsononly" -eq 1 ] && tag="(exempt:json)"; [ "$cannot" -eq 1 ] && tag="(exempt:cannot)"; [ -n "$judged" ] && tag="$judged"; fi
log "$ctx" "$tag"; if [ -z "$v" ]; then touch "$s/turn_closed"; exit 0; fi
{
  t ngg.head "$v"
  [ -n "$offbad" ] && t ngg.offbad "$offbad"
  case " $v " in *" R0 "*) t ngg.r0;; esac
  case " $v " in *" R1 "*) t ngg.r1;; esac
  case " $v " in *" R2a "*) t ngg.r2a;; esac
  case " $v " in *" R2b "*) t ngg.r2b;; esac
  [ -n "$judge_note" ] && echo "$judge_note"
  case " $v " in *" R3 "*) t ngg.r3;; esac
  case " $v " in *" R5 "*) t ngg.r5;; esac
  t ngg.allowed
  t ngg.noretell
} >&2
exit 2
