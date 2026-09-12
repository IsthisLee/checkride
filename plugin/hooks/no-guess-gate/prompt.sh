#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# UserPromptSubmit: 프롬프트 저장. 도구 카운터는 "턴이 닫힌 뒤 첫 프롬프트"에서만 초기화한다.
# 예외 1: 백그라운드 작업 완료 알림(<task-notification>)은 같은 턴의 내부 재호출이다. 카운터 유지.
# 예외 2: 턴이 열려 있는 동안(직전 Stop이 통과하지 않음) 들어온 사용자 메시지는 턴 중간 메시지다.
#         카운터를 지우면 이미 실행한 도구가 사라져 R0·R1·R3 오탐이 난다(실측 2026-09-09). 유지한다.
[ -n "${NGG_INNER:-}" ] && { cat >/dev/null; exit 0; }  # 판정기가 띄운 중첩 세션에서는 돌지 않는다
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"; read_in; s=$(state_dir "$d")
case "$PROMPT" in
  '<task-notification>'*) echo "continuation" >> "$s/continuations"; exit 0 ;;
esac
printf '%s' "$PROMPT" > "$s/prompt"
# 한 번만 허용하기. 사람의 프롬프트마다 지난 허용을 지우고 "checked-practices allow <이름>" 줄을 새로 적는다.
# 백그라운드 알림은 위에서 빠져나갔다. 사람이 쓴 것이 아니므로 허용을 건드리지 않는다.
# 줄 첫머리에 온 것만 받는다. 문장 가운데 적은 것은 인용이다. 받는 이름은 게이트 항목뿐이고
# 근거 규칙(R0~R5)은 대상이 아니다. 프롬프트마다 도는 훅이라 allow 글자가 없으면 아무것도 띄우지 않는다.
af="$(state_root "$d")/state/$SESSION_ID/allow"; : > "$af" 2>/dev/null
case "$PROMPT" in *[Aa][Ll][Ll][Oo][Ww]*)
  set -f
  for n in $(printf '%s\n' "$PROMPT" | grep -iE '^[[:space:]]*checked-practices[[:space:]]+allow[[:space:]]' \
      | sed -E 's/^[[:space:]]*[Gg][Rr][Oo][Uu][Nn][Dd][Ee][Dd][[:space:]]+[Aa][Ll][Ll][Oo][Ww]//' \
      | tr ',' ' ' | LC_ALL=C tr '[:upper:]' '[:lower:]'); do
    case " $NGG_ITEMS " in *" $n "*) echo "$n" >> "$af";; esac
  done
  set +f ;;
esac
if [ -f "$s/tools" ] && [ ! -f "$s/turn_closed" ]; then
  echo "midturn" >> "$s/continuations"
else
  : > "$s/tools"; : > "$s/changed"; rm -f "$s/continuations" "$s/blocked_at" "$s/turn_closed"
fi
find "$(state_root "$d")/state" -mindepth 1 -maxdepth 1 -type d -mmin +720 -exec rm -rf {} + 2>/dev/null; exit 0
