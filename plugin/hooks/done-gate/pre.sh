#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse(Bash): 두 순간을 본다. PR 을 열기 직전과 커밋하기 직전이다.
#
# 1. gh pr create 직전에 PR 본문에 근거가 있는지 본다.
#    공식 best practices: "Have Claude show evidence rather than asserting success:
#    the test output, the command it ran and what it returned, or a screenshot of the result."
#    닫힌 코드 블록이나 이미지가 없으면 막는다. 형식만 본다. 붙인 출력이 진짜인지는 가리지 못한다.
#    본문을 명령에서 볼 수 없으면(--fill, --web, 파이프로 넘긴 본문) 막지 않는다.
#    기준 브랜치 대비 문서만 바꿨으면 대상이 아니다. stop.sh 의 원칙과 같다.
# 2. git commit 직전에 전체 검사를 한 번 돌린다.
#    턴 끝에는 빠른 검사만 돌리므로(stop.sh) 전체는 여기서 본다.
#    Kent Beck: "Only commit when ALL tests are passing."
#    fast_test_command으로 나누지 않았다면 stop.sh가 이미 전체를 돌렸으니 여기서는 아무것도 하지 않는다.
#
# 끄기: NGG_DONE=0 · 제한 시간: DONE_FULL_TIMEOUT 초(기본 600)
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"
IN=$(cat)
# 빠른 경로. 이 훅은 Bash 호출마다 돌지만 보는 것은 커밋과 PR 생성뿐이다. 그 글자가 없으면
# 파이썬을 띄우지 않고 끝낸다(V40). 도구 이름이 애매하면 느린 경로로 간다.
if quick_tool && [ "$QT" = Bash ]; then case "$IN" in *commit*|*create*) ;; *) exit 0;; esac; fi
read_in
[ "${NGG_DONE:-1}" = "0" ] && exit 0
[ "$TOOL_NAME" = "Bash" ] || exit 0
find_root; root="$NGG_ROOT"          # 설정과 git 은 저장소 루트, 명령 안의 상대 경로는 cwd 기준

# 도구 호출마다 도는 파일이다. 글자로도 없으면 파이썬을 띄우지 않는다.
# grep 대신 case 로 거른다. 프로세스를 하나 덜 띄워 PR 이 아닌 명령의 비용이 그대로다.
# 느슨하게 거르고 정확한 판정은 아래 파이썬이 한다.
case "$COMMAND" in *gh*pr*create*) pr_cmd=1;; *) pr_cmd=0;; esac
if [ "$pr_cmd" = 1 ]; then
  # stop.sh 와 같은 목록이다.
  CODE_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|java|kt|swift|c|h|cc|cpp|cs|php|scala|ex|exs|sh|bash|sql|vue|svelte)$'
  # 막을 때만 한 줄을 찍는다. "files<TAB>개수<TAB>기준" 또는 "nobase". 통과면 아무것도 찍지 않는다.
  v=$(printf '%s' "$COMMAND" | py -c 'import os, re, shlex, subprocess, sys
root, code_re, cwd = sys.argv[1], re.compile(sys.argv[2]), sys.argv[3]
cmd = sys.stdin.read().replace("\\\n", " ")        # 줄 이음은 셸처럼 지운다
# heredoc 본문을 먼저 떼어 둔다. shlex 는 heredoc 을 모르고, 본문의 작은따옴표 하나에 죽는다.
docs = []
def cut(m):
    docs.append(m.group(3))
    return " __NGG_HD%d__ " % (len(docs) - 1)
flat = re.sub(r"<<-?[ \t]*([\x27\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", cut, cmd, flags=re.S)
# 개행도 문장 구분자다. 공백으로 읽으면 둘째 줄의 gh 가 명령 자리에 있다는 걸 놓친다.
try:
    lx = shlex.shlex(flat, posix=True, punctuation_chars="();<>|&\n")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    toks = list(lx)
except ValueError:
    sys.exit(0)        # 따옴표가 안 닫혔으면 명령으로 읽지 못한다. 모르는 것으로 막지 않는다
OPS = set(";&|()\n")
def is_op(x):
    return x != "" and set(x) <= OPS
# 인용은 사용이 아니다. 명령 자리에 온 gh pr create 만 본다.
args = None
for i in range(len(toks) - 2):
    if toks[i:i + 3] == ["gh", "pr", "create"] and (i == 0 or is_op(toks[i - 1])):
        args = []
        for x in toks[i + 3:]:
            if is_op(x): break
            args.append(x)
        break
if args is None: sys.exit(0)
def val(names):
    for k, a in enumerate(args):
        if a in names: return args[k + 1] if k + 1 < len(args) else ""
        for n in names:
            if n.startswith("--") and a.startswith(n + "="): return a[len(n) + 1:]
    return None
def unhd(s):
    return re.sub(r"__NGG_HD(\d+)__", lambda m: docs[int(m.group(1))], s)
body, bfile = val(("--body", "-b")), val(("--body-file", "-F"))
if body is not None:
    text = unhd(body)
elif bfile == "-":
    if not docs: sys.exit(0)        # 파이프로 넘긴 본문은 볼 수 없다
    text = "\n".join(docs)
elif bfile:
    p = bfile if os.path.isabs(bfile) else os.path.join(cwd, bfile)        # 셸이 있는 곳 기준
    try: text = open(p, encoding="utf-8", errors="replace").read()
    except OSError: sys.exit(0)
else:
    sys.exit(0)        # --fill, --web, 대화형: 본문을 볼 수 없다
# 근거: 닫힌 코드 블록(여는 줄과 닫는 줄) 또는 이미지. 큰따옴표 안에서는 백틱이 \` 로 온다.
if len(re.findall(r"^[ \t]*(?:(?:\\?`){3}|~~~)", text, re.M)) >= 2: sys.exit(0)
if re.search(r"!\[[^\]]*\]\([^)\s]+|<img\s", text, re.I): sys.exit(0)
# 코드가 아닌 변경은 대상이 아니다. 기준 브랜치 대비 바뀐 파일을 본다. 로컬 git 만 쓴다.
base = val(("--base", "-B"))
cands = ["origin/" + base, base] if base else ["origin/HEAD", "origin/main", "origin/master", "main", "master"]
def git(*a):
    try:
        r = subprocess.run(["git", "-C", root] + list(a), capture_output=True, text=True, timeout=5)
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None
for c in cands:
    if git("rev-parse", "--verify", "--quiet", c + "^{commit}") is None: continue
    out = git("diff", "--name-only", c + "...HEAD")
    if out is None: break
    n = sum(1 for f in out.splitlines() if code_re.search(f))
    if n == 0: sys.exit(0)
    print("files\t%d\t%s" % (n, c)); sys.exit(0)
print("nobase")' "$root" "$CODE_RE" "${CWD:-$PWD}" 2>/dev/null) || v=""
  case "$v" in
    files*|nobase)
      item_off done.pr && exit 0
      allow_once done.pr && exit 0
      {
        t done.prhead
        off_bad
        if [ "$v" = nobase ]; then t done.prnobase
        else t done.prfiles "$(printf '%s' "$v" | cut -f2)" "$(printf '%s' "$v" | cut -f3)"; fi
        t done.prfix
        allow_hint done.pr
      } >&2
      exit 2 ;;
  esac
fi

printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+commit\b' || exit 0

conf="$root/.check.toml"
[ -f "$conf" ] || exit 0
fast=$(sed -n 's/^[[:space:]]*fast_test_command[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$conf" | head -1)
[ -n "$fast" ] || exit 0                      # 나누지 않았으면 stop.sh가 이미 전체를 돌렸다
full=$(sed -n 's/^[[:space:]]*test_command[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$conf" | head -1)
[ -n "$full" ] || exit 0
# 항목 하나만 끄기(done.commit). 전체 검사를 돌리기 전에 본다.
item_off done.commit && exit 0

out=$(mktemp); trap 'rm -f "$out"' EXIT
to="${DONE_FULL_TIMEOUT:-600}"
( cd "$root" && eval "$full" ) > "$out" 2>&1 &
pid=$!; i=0
while kill -0 "$pid" 2>/dev/null; do
  i=$((i+1)); [ "$i" -ge "$((to*10))" ] && { kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    t done.pretime "$to" >&2; exit 0; }
  sleep 0.1
done
wait "$pid"; rc=$?
[ "$rc" -eq 0 ] && exit 0
allow_once done.commit && exit 0
{
  t done.prehead "$rc"
  off_bad
  t done.preran "$full"
  t done.tail
  tail -n 40 "$out" | sed 's/^/    /'
  t done.fixshort
  allow_hint done.commit
} >&2
exit 2
