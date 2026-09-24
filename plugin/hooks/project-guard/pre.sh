#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse(Edit|Write): append_only 경로의 기존 파일을 고치지 못하게 한다.
#
# 공식 best practices의 훅 예시가 같은 자리를 가리킨다.
#   "Write a hook that blocks writes to the migrations folder."
# Rails 가이드도 "editing existing migrations that have been already committed to source control is not a good idea" 라고 적는다.
# 이 가드는 그보다 좁다. **새 파일 추가는 허용하고 기존 파일의 수정만 막는다.** 마이그레이션은 계속 써야 하기 때문이다.
# 삭제(rm)는 막지 않는다. 출처는 쓰기까지만 말하고, Rails 가이드는 스키마 파일이 기준이 되면 오래된 마이그레이션을
# "delete or prune" 할 수 있다고 설명한다. 이동을 막을 근거도 없다(V50).
#
# 설정: 저장소 루트 checkride.toml
#   append_only = "supabase/migrations, db/migrate"
# 설정이 없으면 아무것도 막지 않는다. 끄기: NGG_GUARD=0
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"
IN=$(cat)
# 빠른 경로. 배선은 Edit|Write 뿐이지만, 다른 도구 입력이 오면 파이썬을 띄우지 않고 끝낸다.
if quick_tool; then case "$QT" in Edit|Write) ;; *) exit 0;; esac; fi
read_in
[ "${NGG_GUARD:-1}" = "0" ] && exit 0
case "$TOOL_NAME" in Edit|Write) ;; *) exit 0;; esac
find_root; root="$NGG_ROOT"; conf="$root/checkride.toml"          # cwd 가 아니라 저장소 루트다(common.sh)

# block <머리> <내용> [항목]. 항목이 있으면 사람에게 한 번만 허용하는 법을 알린다.
block() { { t pg.prefix "$1"; off_bad; echo "$2"; [ -z "${3:-}" ] || allow_hint "$3"; } >&2; exit 2; }

[ -f "$conf" ] || exit 0
paths=$(sed -n 's/^[[:space:]]*append_only[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$conf" | head -1)
[ -n "$paths" ] || exit 0

# 설정된 경로 아래에 있고 이미 존재하는 파일인가
guarded() {
  local f="$1" rel p
  case "$f" in "$root"/*) rel="${f#"$root"/}";; *) rel="$f";; esac
  # printf '%s'는 마지막 줄에 개행을 안 붙여 read가 마지막 항목을 버린다. '%s\\n'을 쓴다.
  printf '%s\n' "$paths" | tr ',' '\n' | while IFS= read -r p; do
    p=$(printf '%s' "$p" | sed 's#^[[:space:]]*##; s#[[:space:]]*$##; s#/*$##')
    [ -n "$p" ] || continue
    case "$rel" in "$p"/*) echo hit;; esac
  done | grep -q hit
}

[ -n "$FILE_PATH" ] || exit 0
guarded "$FILE_PATH" || exit 0
[ -f "$FILE_PATH" ] || exit 0     # 새 파일 추가는 허용
block "$(tn pg.appendedit)" "$(t line.file "$FILE_PATH"; t pg.conf "$paths"; tn pg.appendtail)"
