# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# Windows 의 파이썬은 stdio 와 파일 기본 인코딩이 UTF-8 이 아니라 레거시 코드페이지다.
# 한국어가 한 번이라도 지나가면 UnicodeDecodeError 로 훅이 죽는다. 우리 호출에만 UTF-8 을 못 박는다.
# 전역으로 export 하지 않는 이유: done-gate 가 남의 테스트 명령을 eval 로 돌린다. 그 파이썬까지 바꾸면 안 된다.
py() { PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python3 "$@"; }
# IN이 이미 채워져 있으면 그것을 쓴다. 빠른 경로가 stdin을 먼저 읽고 폴백할 때 필요하다.
read_in() { [ -n "${IN:-}" ] || IN=$(cat); local parsed
  parsed=$(printf '%s' "$IN" | py -c '
import sys,json,shlex
d=json.load(sys.stdin)
for k in ("session_id","prompt_id","agent_id","tool_name","stop_hook_active","hook_event_name","cwd"):
    print(k.upper()+"="+shlex.quote(str(d.get(k,""))))
print("LAST="+shlex.quote(str(d.get("last_assistant_message",""))))
print("PROMPT="+shlex.quote(str(d.get("prompt",""))))
ti=d.get("tool_input") or {}
print("FILE_PATH="+shlex.quote(str(ti.get("file_path","") if isinstance(ti,dict) else "")))
print("COMMAND="+shlex.quote(str(ti.get("command","") if isinstance(ti,dict) else "")))
for k in ("old_string","new_string","content"):
    print(k.upper()+"="+shlex.quote(str(ti.get(k,"") if isinstance(ti,dict) else "")))' 2>/dev/null) || {
    t err.python3 >&2; exit 1; }
  eval "$parsed"; }
# 메시지 언어. NGG_LANG이 우선하고, 없으면 로케일(LC_ALL > LC_MESSAGES > LANG)이 ko 계열일 때만 한국어다.
# 서브셸을 쓰지 않는다. 이 파일은 도구 호출마다 읽힌다.
# NGG_L 은 msg.sh 가 읽는다. 파일이 갈려 있어 shellcheck 가 쓰임을 못 본다.
# shellcheck disable=SC2034
ngg_lang() {
  case "${NGG_LANG:-}" in ko|en) NGG_L="$NGG_LANG"; return 0;; esac
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ko|ko_*|ko.*) NGG_L=ko;; *) NGG_L=en;; esac
}
NGG_LIB="${BASH_SOURCE[0]%/*}"; [ "$NGG_LIB" = "${BASH_SOURCE[0]}" ] && NGG_LIB=.
ngg_lang
# t <키> [인자...] — 카탈로그의 문장을 찍는다. 카탈로그는 처음 쓸 때만 읽는다.
# tn은 줄바꿈 없이 찍는다. 키가 없으면 키를 그대로 내보내 조용히 사라지지 않게 한다.
tn() { [ -n "${NGG_MSG_LOADED:-}" ] || {
    # shellcheck source=plugin/hooks/lib/msg.sh
    . "$NGG_LIB/msg.sh"; NGG_MSG_LOADED=1
    # 차단해서 메시지를 처음 낼 때만 .check.toml 의 lang 을 본다(env 다음, 로케일보다 셈).
    ngg_lang_cfg; }
  # M 은 여기서 비운다. msg 가 없을 때(카탈로그 파일이 사라진 경우) msg 안의 초기화에 기대면
  # 앞 호출의 값이 남아 모든 줄이 같은 키로 나온다.
  local k="$1"; shift; M=""
  command -v msg >/dev/null 2>&1 && msg "$k"
  [ -n "$M" ] || M="$k"
  # shellcheck disable=SC2059
  printf -- "$M" "$@"; }
t() { tn "$@"; echo; }

state_root() { printf '%s' "${NGG_STATE:-$1}"; }

# 저장소 루트. 훅 입력의 cwd 는 Claude 가 cd 하면 따라간다(공식 hooks 문서: "follows cd commands").
# cwd 에서만 .check.toml 을 찾으면 하위 폴더에 들어간 뒤 설정을 놓치고 완료 게이트가 조용히
# 통과했다(V39). cwd 에서 위로 올라가며 .check.toml 이나 .git 이 있는 첫 폴더를 루트로 쓴다.
# .git 에서 멈추므로 다른 저장소나 워크트리 바깥의 설정을 빌려 쓰지 않는다. 세션을 연 폴더
# (CLAUDE_PROJECT_DIR) 위로는 올라가지 않는다. 찾지 못하면 cwd 다. 결과는 NGG_ROOT 에 담는다.
# 명령 안의 상대 경로는 이 루트가 아니라 cwd 기준으로 풀어야 한다. 파라미터 확장만 쓴다.
find_root() { local d="${CWD:-$PWD}" p
  NGG_ROOT="$d"
  while :; do
    if [ -f "$d/.check.toml" ] || [ -e "$d/.git" ]; then NGG_ROOT="$d"; return 0; fi
    [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ "$d" = "$CLAUDE_PROJECT_DIR" ] && return 0
    p="${d%/*}"; [ -z "$p" ] && p=/
    [ "$p" = "$d" ] && return 0
    d="$p"
  done; }

# 빠른 경로용. 입력에서 tool_name 값만 파라미터 확장으로 뽑아 QT 에 담는다(프로세스 0개).
# no-guess-gate/pre.sh 의 _jstr 와 같은 안전 조건이다. "tool_name" 이 정확히 한 번 나오고 값이
# 식별자 꼴일 때만 답한다. 아니면 실패하고, 부른 쪽은 파이썬을 쓰는 느린 경로로 간다.
# 8KB 를 넘으면 쓰지 않는다. ${IN#*패턴} 은 입력 길이의 제곱으로 느려질 수 있고,
# 이 훅들은 Edit·Write 의 긴 본문도 받는다.
# QT 는 이 파일을 읽는 훅들이 쓴다. 파일이 갈려 있어 shellcheck 가 쓰임을 못 본다.
# shellcheck disable=SC2034
quick_tool() { local r
  QT=""
  [ "${#IN}" -lt 8192 ] || return 1
  r="${IN#*\"tool_name\"}"
  [ "$r" != "$IN" ] || return 1
  case "$r" in *'"tool_name"'*) return 1;; esac
  r="${r#*:}"; while :; do case "$r" in " "*|"	"*) r="${r#?}";; *) break;; esac; done
  case "$r" in "\""*) r="${r#\"}";; *) return 1;; esac
  r="${r%%\"*}"; case "$r" in ""|*[!A-Za-z0-9_.-]*) return 1;; esac
  QT="$r"; }

# 항목 하나만 끄기. .check.toml 의 disabled_rules 한 줄에 근거 게이트의 규칙(R0~R5)과
# 다른 게이트의 항목이 같이 온다. 환경변수는 한 사람 셸에만 있어 팀이 모르므로 파일에 둔다.
# 막기 직전에만 부른다. 이 파일은 도구 호출마다 읽히므로 걸린 것이 없으면 설정을 읽지 않는다.
NGG_ITEMS="rb.write done.turn done.commit done.pr ti.skip ti.assert ti.rm ti.exclude pg.noverify"
off_list() { local conf; [ -n "${NGG_ROOT:-}" ] || find_root; conf="$NGG_ROOT/.check.toml"; [ -f "$conf" ] || return 0
  sed -n 's/^[[:space:]]*disabled_rules[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$conf" | head -1 | tr ',' ' '; }

# .check.toml 의 lang 으로 NGG_L 을 덮는다. NGG_LANG 이 있으면 건드리지 않는다(env 가 이긴다).
# 로케일보다 세다. off_list 처럼 막기 직전에만 부른다. 도구 호출마다 읽지 않는다.
# NGG_L 은 msg.sh 가 읽는다. 파일이 갈려 있어 shellcheck 가 쓰임을 못 본다.
# shellcheck disable=SC2034
ngg_lang_cfg() { local conf cl; case "${NGG_LANG:-}" in ko|en) return 0;; esac
  [ -n "${NGG_ROOT:-}" ] || find_root; conf="$NGG_ROOT/.check.toml"; [ -f "$conf" ] || return 0
  cl=$(sed -n 's/^[[:space:]]*lang[[:space:]]*=[[:space:]]*"\{0,1\}\([A-Za-z_.-]*\)"\{0,1\}[[:space:]]*$/\1/p' "$conf" | head -1)
  case "$cl" in ko|ko_*|ko.*) NGG_L=ko;; en|en_*|en.*) NGG_L=en;; esac; }
lc() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }
# item_off <이름> — 꺼져 있으면 끈 사실을 events.log 에 남기고 0 을 돌려준다.
# 남기지 않으면 왜 안 막았는지 나중에 알 수 없다. /check:status 가 이 줄을 읽는다.
item_off() { local tok sd
  for tok in $(off_list); do
    [ "$(lc "$tok")" = "$1" ] || continue
    sd="$(state_root "${d:-$NGG_LIB}")/state"
    mkdir -p "$sd" 2>/dev/null && echo "$HOOK_EVENT_NAME${AGENT_ID:+/agent} off=[$1] tool=$TOOL_NAME" >> "$sd/events.log"
    return 0
  done
  return 1; }
# 막을 때 부른다. 없는 이름이 있으면 알린다. 껐다고 믿는데 안 꺼진 상태가 제일 나쁘다.
off_bad() { local tok bad=""
  for tok in $(off_list); do
    case " r0 r1 r2a r2b r3 r4 r5 $NGG_ITEMS " in *" $(lc "$tok") "*) ;; *) bad="$bad $tok";; esac
  done
  [ -z "$bad" ] || t ngg.offbad "${bad# }"; }

# 한 번만 허용하기. 사람이 프롬프트에 "check allow <이름>" 을 한 줄로 쓰면 prompt.sh 가
# 이 파일에 적는다. 게이트는 막기 직전에 보고, 있으면 그 줄을 지우고 한 번 통과시킨다.
# 설정으로 끄는 것과 달리 오탐 한 건만 넘긴다. 허용은 UserPromptSubmit 에서만 들어오므로
# 모델이 쓴 글로는 풀리지 않는다. 같은 턴의 서브에이전트도 쓰도록 세션 폴더에 둔다.
allow_file() { printf '%s/state/%s/allow' "$(state_root "${d:-$NGG_LIB}")" "$SESSION_ID"; }
allow_once() { local f; f=$(allow_file)
  [ -s "$f" ] && grep -qFx "$1" "$f" || return 1
  { grep -vFx "$1" "$f" || true; } > "$f.tmp" && mv "$f.tmp" "$f"
  echo "$HOOK_EVENT_NAME${AGENT_ID:+/agent} allowed=[$1] tool=$TOOL_NAME" >> "$(state_root "${d:-$NGG_LIB}")/state/events.log"
  return 0; }
allow_hint() { t line.allow "$1"; }
state_dir() { local d; d="$(state_root "$1")/state/$SESSION_ID"; [ -n "$AGENT_ID" ] && d="$d/agent-$AGENT_ID"; mkdir -p "$d"; printf '%s' "$d"; }
