#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse(Edit|Write|Bash): 저장소가 정한 구조 규칙을 그 순간에 강제한다.
#
# 공식 best practices의 훅 예시가 같은 자리를 가리킨다.
#   "Write a hook that blocks writes to the migrations folder."
# 이 가드는 그보다 정밀하다. **새 파일 추가는 허용하고 기존 파일의 수정·삭제만 막는다.**
# 마이그레이션은 계속 써야 하기 때문이다.
#
# 설정: 저장소 루트 .check.toml
#   append_only = "supabase/migrations, db/migrate"
# 설정이 없으면 아무것도 막지 않는다. 끄기: NGG_GUARD=0
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"
IN=$(cat)
# 빠른 경로. 이 훅은 Bash 호출마다 돈다. Bash 에서 보는 것은 삭제·이동과 --no-verify 커밋뿐이라,
# 그 글자가 없으면 파이썬을 띄우지 않고 끝낸다(V40). 도구 이름이 애매하면 느린 경로로 간다.
if quick_tool && [ "$QT" = Bash ]; then case "$IN" in *rm[[:space:]\"\\]*|*mv[[:space:]\"\\]*|*commit*) ;; *) exit 0;; esac; fi
read_in
[ "${NGG_GUARD:-1}" = "0" ] && exit 0
find_root; root="$NGG_ROOT"; conf="$root/.check.toml"          # cwd 가 아니라 저장소 루트다(common.sh)

# block <머리> <내용> [항목]. 항목이 있으면 사람에게 한 번만 허용하는 법을 알린다.
block() { { t pg.prefix "$1"; off_bad; echo "$2"; [ -z "${3:-}" ] || allow_hint "$3"; } >&2; exit 2; }
# 명령에서 파일 인자를 뽑는다. 따옴표로 감싼 경로(공백이 든 파일명은 반드시 그렇다)를 살린다.
# 따옴표 안의 공백은 구분자가 아니므로 셸과 같은 방식으로 쪼갠다.
# 삭제 명령의 인자만 뽑는다. 명령 어디엔가 rm 이 있고 다른 문장에 경로가 있다고 짝지으면
# 임시 폴더를 치우는 명령이 테스트 삭제로 읽힌다. 실제로 이 저장소 작업 중 다섯 번 그랬다.
# 셸처럼 ; && || | 개행으로 문장을 나눈 뒤, 삭제로 시작하는 문장의 인자만 본다.
rm_targets() {
  printf '%s' "$1" | py -c 'import re,shlex,sys
t = sys.stdin.read()
for stmt in re.split(r"[;&|\n]+", t):
    try: toks = shlex.split(stmt, posix=True)
    except ValueError: toks = stmt.split()
    if not toks: continue
    i = 0
    if toks[0] == "sudo": i = 1
    if i >= len(toks): continue
    head = toks[i]
    if head == "git" and i + 1 < len(toks) and toks[i+1] == "rm": i += 2
    elif head == "rm": i += 1
    else: continue
    for x in toks[i:]:
        if x and not x.startswith("-"): print(x)'
}


# 검사를 건너뛰는 커밋을 막는다. 다만 **건너뛸 훅이 실제로 있을 때만** 막는다.
# 설치만 했는데 남의 저장소의 git 동작이 바뀌면 과하다. 비상 통로는 사람이 직접 쓰는 것이지
# 에이전트가 게이트를 우회하는 길이 아니다.
has_hooks() {
  [ -f "$conf" ] && return 0
  [ -f "$root/.husky/pre-commit" ] && return 0
  [ -x "$root/.git/hooks/pre-commit" ] && return 0
  hp=$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)
  [ -n "$hp" ] && [ -e "$root/$hp/pre-commit" ] && return 0
  return 1
}
# 플래그가 '쓰였는지' 는 토큰으로 봐야 한다. 명령 문자열을 통째로 훑으면
# 커밋 메시지 안에 플래그 이름을 적기만 해도 걸린다. 실제로 README 표에 적다가 막혔다.
# 문장을 나눈 뒤 git commit 으로 시작하는 문장의 인자에 플래그가 토큰으로 있는지만 본다.
skips_hooks() {
  printf '%s' "$1" | py -c 'import re,shlex,sys
t = sys.stdin.read()
for stmt in re.split(r"[;&|\n]+", t):
    try: toks = shlex.split(stmt, posix=True)
    except ValueError: continue
    if len(toks) < 2 or toks[0] != "git" or toks[1] != "commit": continue
    if "--no-verify" in toks[2:] or "-n" in toks[2:]:
        print("yes"); break' | grep -q yes
}
if [ "$TOOL_NAME" = "Bash" ] && has_hooks && skips_hooks "$COMMAND" && ! item_off pg.noverify && ! allow_once pg.noverify; then
  block "$(tn pg.noverify)" "$(t line.cmd "$COMMAND"; tn pg.noverifyt)" pg.noverify
fi

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

case "$TOOL_NAME" in
  Edit|Write)
    [ -n "$FILE_PATH" ] || exit 0
    guarded "$FILE_PATH" || exit 0
    [ -f "$FILE_PATH" ] || exit 0     # 새 파일 추가는 허용
    block "$(tn pg.appendedit)" "$(t line.file "$FILE_PATH"; t pg.conf "$paths"; tn pg.appendtail)" ;;
  Bash)
    printf '%s' "$COMMAND" | grep -qE '(^|[;&|]|\s)(rm|git[[:space:]]+rm|mv)\b' || exit 0
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case "$tok" in /*) f="$tok";; *) f="${CWD:-$root}/$tok";; esac          # 상대 경로는 셸이 있는 곳 기준
      if guarded "$f" && [ -f "$f" ]; then
        block "$(tn pg.appendrm)" "$(t line.cmd "$COMMAND"; t line.target "$tok"; tn pg.conf "$paths")"
      fi
    done <<EOF
$(rm_targets "$COMMAND")
EOF
    ;;
esac
exit 0
