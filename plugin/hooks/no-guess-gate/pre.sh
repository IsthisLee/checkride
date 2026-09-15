#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse: 이 턴에서 실행된 도구 기록 (서브에이전트는 agent_id 하위)
[ -n "${NGG_INNER:-}" ] && { cat >/dev/null; exit 0; }  # 판정기가 띄운 중첩 세션에서는 돌지 않는다
d="$(cd "$(dirname "$0")" && pwd)"
IN=$(cat)

# 빠른 경로. 이 훅은 도구 호출마다 돌기 때문에 바깥 프로세스를 하나라도 띄우면
# 도구를 많이 쓰는 턴에서 초 단위 지연이 된다. 필요한 값은 단순한 문자열 셋뿐이라
# 파라미터 확장만으로 뽑는다(프로세스 0개).
# 안전 조건: 입력이 작고, "tool_name"이 정확히 한 번만 나오고, 값이 식별자 꼴일 때만 쓴다.
# 하나라도 어긋나면 느린 경로(python3)로 넘어가 같은 결과를 낸다.
_jstr() {  # $1 JSON, $2 키 → 단순 문자열 값
  local r="${1#*\""$2"\"}"
  [ "$r" = "$1" ] && return 1
  r="${r#*:}"
  while :; do case "$r" in " "*|"	"*) r="${r#?}";; *) break;; esac; done
  case "$r" in "\""*) r="${r#\"}";; *) return 1;; esac
  r="${r%%\"*}"
  case "$r" in ""|*[!A-Za-z0-9_.-]*) return 1;; esac
  printf '%s' "$r"
}
_rest="${IN#*\"tool_name\"}"
if [ "${#IN}" -lt 4096 ] && [ "$_rest" != "$IN" ] && case "$_rest" in *'"tool_name"'*) false;; *) true;; esac; then
  if _tool=$(_jstr "$IN" tool_name) && _sid=$(_jstr "$IN" session_id); then
    _aid=$(_jstr "$IN" agent_id) || _aid=""
    _s="${NGG_STATE:-$d}/state/$_sid"; [ -n "$_aid" ] && _s="$_s/agent-$_aid"
    mkdir -p "$_s" && printf '%s\n' "$_tool" >> "$_s/tools" && exit 0
  fi
fi

# shellcheck source=../lib/common.sh
. "$d/../lib/common.sh"; read_in; s=$(state_dir "$d")
echo "$TOOL_NAME" >> "$s/tools"; exit 0
