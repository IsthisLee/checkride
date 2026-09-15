#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse: 이 턴에서 실행된 도구 기록 (서브에이전트는 agent_id 하위)
#
# 막는 검사가 하나 있다. rb.write: 이번 세션에 읽지 않은 기존 파일을 Write 로 통째로 덮어쓰지 못한다.
#   공식 도구 레퍼런스: "Claude Opus 4.6, Claude Haiku 4.5, and older models always require the read."
#   v2.1.228 부터 최신 모델은 읽지 않은 기존 파일도 Write 로 덮어쓸 수 있다. Edit 는 old_string 이 현재
#   내용과 정확히 맞아야 적용되므로 모르고 망가뜨리기 어렵지만, Write 는 파일 전체를 갈아엎는다.
#   그래서 편집 전체가 아니라 되돌리기 어려운 이 자리만 다시 막는다.
#   읽은 것으로 치는 것은 같은 문서의 read-before-edit 기준을 따른다. Read, 파이프·리디렉션 없이 파일 하나를
#   보는 Bash(cat·nl·bat·head·tail·sed -n 'X,Yp'·grep·egrep·fgrep·rg), 이번 세션에 Write 로 직접 쓴 파일이다.
#   기록은 턴마다 비우지 않고 세션 동안 남긴다(state/<세션>/seen).
[ -n "${NGG_INNER:-}" ] && { cat >/dev/null; exit 0; }  # 판정기가 띄운 중첩 세션에서는 돌지 않는다
d="$(cd "$(dirname "$0")" && pwd)"
IN=$(cat)

# 빠른 경로. 이 훅은 도구 호출마다 돌기 때문에 바깥 프로세스를 하나라도 띄우면
# 도구를 많이 쓰는 턴에서 초 단위 지연이 된다. 필요한 값은 단순한 문자열 몇 개뿐이라
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
# 경로 값. 경로에는 / 가 들어가 _jstr 를 쓸 수 없다. 키가 정확히 한 번 나오고 값에 JSON 이스케이프(\)가
# 하나도 없을 때만 답한다. 그때는 원문 바이트가 곧 값이다. Windows 경로처럼 \ 가 있으면 느린 경로로 넘긴다.
_jpath() {  # $1 JSON, $2 키 → 경로 문자열
  local r="${1#*\""$2"\"}"
  [ "$r" = "$1" ] && return 1
  case "$r" in *\""$2"\"*) return 1;; esac
  r="${r#*:}"
  while :; do case "$r" in " "*|"	"*) r="${r#?}";; *) break;; esac; done
  case "$r" in "\""*) r="${r#\"}";; *) return 1;; esac
  r="${r%%\"*}"
  case "$r" in ""|*\\*) return 1;; esac
  printf '%s' "$r"
}
# Bash 명령의 첫 낱말. 파일을 보는 명령인지만 가르면 된다. 판정은 느린 경로의 파이썬이 다시 한다.
_jcmd1() {  # $1 JSON → 첫 낱말
  local r="${1#*\"command\"}"
  [ "$r" = "$1" ] && return 1
  case "$r" in *'"command"'*) return 1;; esac
  r="${r#*:}"
  while :; do case "$r" in " "*|"	"*) r="${r#?}";; *) break;; esac; done
  case "$r" in "\""*) r="${r#\"}";; *) return 1;; esac
  r="${r%%[ \"\\]*}"
  [ -n "$r" ] || return 1
  printf '%s' "$r"
}
VIEWCMDS=" cat nl bat batcat head tail sed grep egrep fgrep rg "
_rest="${IN#*\"tool_name\"}"
if [ "${#IN}" -lt 4096 ] && [ "$_rest" != "$IN" ] && case "$_rest" in *'"tool_name"'*) false;; *) true;; esac; then
  if _tool=$(_jstr "$IN" tool_name) && _sid=$(_jstr "$IN" session_id); then
    _aid=$(_jstr "$IN" agent_id) || _aid=""
    _s="${NGG_STATE:-$d}/state/$_sid"; [ -n "$_aid" ] && _s="$_s/agent-$_aid"
    # Write, 파일을 보는 Bash, 경로를 못 읽은 Read 만 느린 경로로 보낸다. 나머지는 여기서 끝난다.
    _fast=1; _p=""
    case "$_tool" in
      Write) _fast=0 ;;
      Read) _p=$(_jpath "$IN" file_path) || _fast=0 ;;
      Bash) if _w=$(_jcmd1 "$IN"); then case "$VIEWCMDS" in *" $_w "*) _fast=0;; esac; else _fast=0; fi ;;
    esac
    if [ "$_fast" = 1 ] && mkdir -p "$_s" && printf '%s\n' "$_tool" >> "$_s/tools"; then
      [ -z "$_p" ] || printf '%s\n' "$_p" >> "$_s/seen"
      exit 0
    fi
  fi
fi

# shellcheck source=../lib/common.sh
. "$d/../lib/common.sh"; read_in; s=$(state_dir "$d")
echo "$TOOL_NAME" >> "$s/tools"

# 파일 하나를 보는 Bash 면 그 파일의 절대 경로를 찍는다. 아니면 아무것도 찍지 않는다.
# 공식 도구 레퍼런스의 기준과 같다. "on a single file with no pipes or redirects".
rb_view() {
  py -c 'import os, re, shlex, sys
cmd, cwd = sys.argv[1], sys.argv[2] or os.getcwd()
if re.search(r"[|<>;&`\n]|\$\(", cmd): sys.exit(0)
try: t = shlex.split(cmd)
except ValueError: sys.exit(0)
if not t: sys.exit(0)
VAL = {"head": {"-n", "-c"}, "tail": {"-n", "-c"},
       "grep": {"-e", "-f", "-A", "-B", "-C", "-m", "--regexp", "--file", "--max-count"},
       "rg": {"-e", "-f", "-A", "-B", "-C", "-m", "-g", "-t", "-T", "--regexp", "--file", "--max-count", "--glob", "--type", "--type-not"}}
VAL["egrep"] = VAL["fgrep"] = VAL["grep"]
name, args = t[0], t[1:]
if name not in ("cat", "nl", "bat", "batcat", "head", "tail", "sed", "grep", "egrep", "fgrep", "rg"): sys.exit(0)
pos, flags, pattern_given, i = [], [], False, 0
while i < len(args):
    a = args[i]
    if a == "--":
        pos += args[i + 1:]
        break
    if a.startswith("-") and a != "-":
        flags.append(a)
        if a in ("-e", "--regexp") or a.startswith("--regexp="): pattern_given = True
        i += 2 if a in VAL.get(name, ()) else 1
        continue
    pos.append(a)
    i += 1
if name == "sed":
    if "-n" not in flags or len(pos) != 2 or not re.fullmatch(r"\d+(,\d+)?p", pos[0]): sys.exit(0)
    files = pos[1:]
elif name in ("grep", "egrep", "fgrep", "rg"):
    files = pos if pattern_given else pos[1:]
else:
    files = pos
if len(files) != 1: sys.exit(0)
p = files[0] if os.path.isabs(files[0]) else os.path.join(cwd, files[0])
if os.path.isfile(p): print(p)' "$COMMAND" "${CWD:-$PWD}" 2>/dev/null
}

# 읽은 기록에 그 파일이 있나. 먼저 글자 그대로 찾고, 없으면 실경로로 한 번 더 본다.
# macOS 는 같은 폴더를 /var 와 /private/var 로 주고, 경로에 ../ 가 섞이기도 한다.
rb_seen() {  # $1 기록 파일, $2 대상 경로
  [ -s "$1" ] || return 1
  grep -qFx -- "$2" "$1" && return 0
  py -c 'import os, sys
def n(x): return os.path.normcase(os.path.realpath(x))
want = n(sys.argv[2])
with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
    sys.exit(0 if any(n(l.rstrip("\n")) == want for l in f if l.strip()) else 1)' "$1" "$2"
}

# 새 파일과 빈 파일은 잃을 것이 없어 막지 않는다. 통과한 Write 는 Claude 가 쓴 내용이므로 읽은 것으로 남긴다.
rb_write() {
  local wp="$FILE_PATH"
  [ -n "$wp" ] || return 0
  case "$wp" in /*|[A-Za-z]:*) ;; *) wp="${CWD:-$PWD}/$wp";; esac
  if [ -f "$wp" ] && [ -s "$wp" ] && ! rb_seen "$s/seen" "$wp" && ! item_off rb.write && ! allow_once rb.write; then
    { t rb.write; off_bad; t line.file "$wp"; t rb.writet; allow_hint rb.write; } >&2
    exit 2
  fi
  printf '%s\n' "$wp" >> "$s/seen"
}

case "$TOOL_NAME" in
  Read) [ -z "$FILE_PATH" ] || printf '%s\n' "$FILE_PATH" >> "$s/seen" ;;
  Bash) v=$(rb_view) && [ -n "$v" ] && printf '%s\n' "$v" >> "$s/seen" ;;
  Write) rb_write ;;
esac
exit 0
