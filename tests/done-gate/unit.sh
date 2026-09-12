#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 완료 게이트 단위 테스트. 모델을 부르지 않는다. 사용: ./unit.sh
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
# 테스트는 주변 환경에 기대지 않는다. 게이트가 자식에게 물려주는 변수가 남아 있으면
# 폴백 검사 같은 것이 조용히 뒤집힌다(2026-09-10 도그푸딩에서 실측).
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_JUDGE_CMD NGG_JUDGE_TIMEOUT NGG_DONE DONE_TIMEOUT
# 메시지 언어를 못 박는다. 로케일에 따라 문장이 바뀌면 이 아래 문자열 단언이 기계마다 달라진다.
export NGG_LANG=ko
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/done-gate"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/scripts"; mkdir -p "$W" "$T/lib"; cp "$G"/../lib/common.sh "$G"/../lib/msg.sh "$T/lib/"; cp "$G"/post.sh "$G"/stop.sh "$G"/pre.sh "$W"/
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
# 한글이 섞였는지는 python3 로 본다. grep 의 [가-힣] 는 LC_ALL=C 에서 바이트 범위가 되어
# 영어 문장의 가운뎃점(·)이나 화살표(→)까지 잡는다. 테스트가 로케일에 흔들리면 안 된다.
nohangul() { printf '%s' "$1" | python3 -c 'import sys,re; sys.exit(1 if re.search(r"[\uac00-\ud7a3]", sys.stdin.read()) else 0)'; }
isfile() { [ -f "$1" ]; }
empty()  { [ ! -s "$1" ]; }

# 프로젝트 뼈대를 만든다. cwd는 훅 입력으로 전달된다.
newproj() { local p="$T/$1"; mkdir -p "$p"; printf '%s' "$p"; }
post() { printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "${4:-Edit}" "$3"; }
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","cwd":"%s","stop_hook_active":false,"last_assistant_message":"고쳤습니다."}' "$1" "$2"; }

# 1. 바꾼 파일이 없으면 검사하지 않는다
P=$(newproj p1); S="$T/s1"
printf '%s' "$(stop t1 "$P")" | NGG_STATE="$S" "$W/stop.sh" 2>/dev/null; check 0 $? "바꾼 파일 없음 → exit 0"

# 2. post.sh가 바꾼 파일을 기록한다
printf '%s' "$(post t1 "$P" "$P/src/a.ts")" | NGG_STATE="$S" "$W/post.sh"; check 0 $? "post.sh exit 0"
isfile "$S/state/t1/changed"; check 0 $? "changed 파일 생성"
grep -q 'a.ts' "$S/state/t1/changed"; check 0 $? "바꾼 파일 경로 기록"

# 3. 검사 명령을 못 찾으면 막지 않는다 (모르는 것으로 막지 않는다)
printf '%s' "$(stop t1 "$P")" | NGG_STATE="$S" "$W/stop.sh" 2>"$T/e3"; check 0 $? "검사 명령 없음 → exit 0"
grep -q '검사 명령' "$T/e3"; check 0 $? "stderr에 안내(막지는 않음)"

# 4. .checked-practices.toml의 test_command를 쓴다. 통과하면 턴이 끝난다
P2=$(newproj p2); S2="$T/s2"
printf 'test_command = "true"\n' > "$P2/.checked-practices.toml"
printf '%s' "$(post t2 "$P2" "$P2/src/a.ts")" | NGG_STATE="$S2" "$W/post.sh"
printf '%s' "$(stop t2 "$P2")" | NGG_STATE="$S2" "$W/stop.sh" 2>/dev/null; check 0 $? "검사 통과 → exit 0"

# 5. 검사가 실패하면 턴을 막고 출력 꼬리를 준다
P3=$(newproj p3); S3="$T/s3"
printf 'test_command = "echo FAIL_MARKER_LINE >&2; exit 1"\n' > "$P3/.checked-practices.toml"
printf '%s' "$(post t3 "$P3" "$P3/src/a.ts")" | NGG_STATE="$S3" "$W/post.sh"
printf '%s' "$(stop t3 "$P3")" | NGG_STATE="$S3" "$W/stop.sh" 2>"$T/e5"; check 2 $? "검사 실패 → exit 2"
grep -q '완료 게이트' "$T/e5"; check 0 $? "stderr에 완료 게이트 헤더"
grep -q 'FAIL_MARKER_LINE' "$T/e5"; check 0 $? "stderr에 검사 출력 꼬리"

# 6. 문서만 고친 턴은 대상이 아니다
P4=$(newproj p4); S4="$T/s4"
printf 'test_command = "exit 1"\n' > "$P4/.checked-practices.toml"
printf '%s' "$(post t4 "$P4" "$P4/docs/README.md")" | NGG_STATE="$S4" "$W/post.sh"
printf '%s' "$(stop t4 "$P4")" | NGG_STATE="$S4" "$W/stop.sh" 2>/dev/null; check 0 $? "문서만 변경 → 검사 안 함, exit 0"

# 7. package.json scripts.test 자동 탐지
P5=$(newproj p5); S5="$T/s5"
printf '{"scripts":{"test":"exit 3"}}\n' > "$P5/package.json"
printf '%s' "$(post t5 "$P5" "$P5/src/a.js")" | NGG_STATE="$S5" "$W/post.sh"
printf '%s' "$(stop t5 "$P5")" | NGG_STATE="$S5" "$W/stop.sh" 2>"$T/e7"; check 2 $? "package.json 자동 탐지 → 실패 시 exit 2"
grep -qi 'npm test\|package.json' "$T/e7"; check 0 $? "stderr에 어떤 명령을 돌렸는지"

# 8. Makefile test 타깃 자동 탐지
P6=$(newproj p6); S6="$T/s6"
printf 'test:\n\t@exit 1\n' > "$P6/Makefile"
printf '%s' "$(post t6 "$P6" "$P6/src/a.go")" | NGG_STATE="$S6" "$W/post.sh"
printf '%s' "$(stop t6 "$P6")" | NGG_STATE="$S6" "$W/stop.sh" 2>/dev/null; check 2 $? "Makefile 자동 탐지 → 실패 시 exit 2"

# 9. NGG_DONE=0 이면 끈다
printf '%s' "$(stop t3 "$P3")" | NGG_DONE=0 NGG_STATE="$S3" "$W/stop.sh" 2>/dev/null; check 0 $? "NGG_DONE=0 → 검사하지 않음"

# 10. 통과한 뒤에는 changed를 비워 다음 턴에 다시 돌지 않게 한다
P7=$(newproj p7); S7="$T/s7"
printf 'test_command = "true"\n' > "$P7/.checked-practices.toml"
printf '%s' "$(post t7 "$P7" "$P7/src/a.ts")" | NGG_STATE="$S7" "$W/post.sh"
printf '%s' "$(stop t7 "$P7")" | NGG_STATE="$S7" "$W/stop.sh" 2>/dev/null
empty "$S7/state/t7/changed"; check 0 $? "통과 후 changed 비움"

# 11. 검사가 오래 걸리면 막지 않고 알린다 (조용한 실패 금지)
P8=$(newproj p8); S8="$T/s8"
printf 'test_command = "sleep 5"\n' > "$P8/.checked-practices.toml"
printf '%s' "$(post t8 "$P8" "$P8/src/a.ts")" | NGG_STATE="$S8" "$W/post.sh"
printf '%s' "$(stop t8 "$P8")" | DONE_TIMEOUT=1 NGG_STATE="$S8" "$W/stop.sh" 2>"$T/e11"; check 0 $? "검사 시간초과 → 막지 않음"
grep -q '시간' "$T/e11"; check 0 $? "stderr에 시간초과 안내"

# 12. cwd 밖 경로는 무시한다 (다른 저장소 파일을 근거로 검사하지 않는다)
P9=$(newproj p9); S9="$T/s9"
printf 'test_command = "exit 1"\n' > "$P9/.checked-practices.toml"
printf '%s' "$(post t9 "$P9" "$T/elsewhere/x.ts")" | NGG_STATE="$S9" "$W/post.sh"
printf '%s' "$(stop t9 "$P9")" | NGG_STATE="$S9" "$W/stop.sh" 2>/dev/null; check 0 $? "cwd 밖 파일만 변경 → 검사 안 함"

# 13. 턴마다 전체 스위트를 돌리면 사람들이 게이트를 끈다.
#     공식 CLAUDE.md 예시: "Prefer running single tests, and not the whole test suite, for performance."
#     fast_test_command이 있으면 턴 끝에는 그것만 쓰고, 전체는 커밋 직전에 한 번 돌린다.
PA=$(newproj pa); SA="$T/sa"
printf 'fast_test_command = "echo FAST; true"\ntest_command = "echo FULL; true"\n' > "$PA/.checked-practices.toml"
printf '%s' "$(post ta "$PA" "$PA/src/a.ts")" | NGG_STATE="$SA" "$W/post.sh"
printf '%s' "$(stop ta "$PA")" | NGG_STATE="$SA" "$W/stop.sh" 2>/dev/null; check 0 $? "빠른 검사 통과 → exit 0"
grep -q FAST "$SA/state/ta/done-out"; check 0 $? "턴 끝에는 fast_test_command를 돌린다"
grep -q FULL "$SA/state/ta/done-out"; r=$?; check 1 "$r" "턴 끝에 전체 검사는 돌리지 않는다"

PB=$(newproj pb); SB="$T/sb"
printf 'fast_test_command = "true"\ntest_command = "echo FULLFAIL >&2; exit 1"\n' > "$PB/.checked-practices.toml"
printf '%s' "$(post tb "$PB" "$PB/src/a.ts")" | NGG_STATE="$SB" "$W/post.sh"
printf '%s' "$(stop tb "$PB")" | NGG_STATE="$SB" "$W/stop.sh" 2>/dev/null; check 0 $? "빠른 검사만 보므로 턴은 끝난다"
commit() { printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" "$3"; }
printf '%s' "$(commit tb "$PB" "git commit -m x")" | NGG_STATE="$SB" "$W/pre.sh" 2>"$T/e13"; check 2 $? "커밋 직전 전체 검사 실패 → exit 2"
grep -q FULLFAIL "$T/e13"; check 0 $? "stderr에 전체 검사 출력"
printf '%s' "$(commit tb "$PB" "git status")" | NGG_STATE="$SB" "$W/pre.sh" 2>/dev/null; check 0 $? "커밋이 아닌 명령 → 통과"

# 분리하지 않았으면 커밋 때 두 번 돌리지 않는다
PC=$(newproj pc); SC="$T/sc"
printf 'test_command = "echo ONCE >&2; exit 1"\n' > "$PC/.checked-practices.toml"
printf '%s' "$(commit tc "$PC" "git commit -m x")" | NGG_STATE="$SC" "$W/pre.sh" 2>/dev/null; check 0 $? "fast 분리 없으면 커밋 때 중복 검사 안 함"

# 14. 느린 검사는 분리하라고 알린다
PD=$(newproj pd); SD="$T/sd"
printf 'test_command = "sleep 2"\n' > "$PD/.checked-practices.toml"
printf '%s' "$(post td "$PD" "$PD/src/a.ts")" | NGG_STATE="$SD" "$W/post.sh"
printf '%s' "$(stop td "$PD")" | DONE_SLOW=1 NGG_STATE="$SD" "$W/stop.sh" 2>"$T/e14"; check 0 $? "느려도 통과는 통과"
grep -q 'fast_test_command' "$T/e14"; check 0 $? "느리면 fast_test_command 분리를 권한다"

# 메시지 언어. 같은 실패가 두 언어에서 같게 걸리고 문장만 바뀐다.
PL="$T/lang"; mkdir -p "$PL/src"; printf 'x\n' > "$PL/src/a.ts"
printf 'test_command = "exit 1"\n' > "$PL/.checked-practices.toml"
for L in ko en; do
  SL="$T/sl-$L"
  printf '%s' "$(post "tl$L" "$PL" "$PL/src/a.ts")" | NGG_STATE="$SL" "$W/post.sh"
  printf '%s' "$(stop "tl$L" "$PL")" | NGG_LANG="$L" NGG_STATE="$SL" "$W/stop.sh" 2>"$T/el-$L"
  check 2 $? "$L: 검사 실패 → exit 2"
done
grep -q '완료 게이트' "$T/el-ko"; check 0 $? "ko: 한국어 머리글"
grep -q 'Completion gate' "$T/el-en"; check 0 $? "en: 영어 머리글"
nohangul "$(cat "$T/el-en")"; check 0 $? "en: 한글이 섞이지 않는다"

# 심링크로 갈린 경로. macOS 에서 PostToolUse 는 /private/var/... 를 주는데 cwd 는 /var/... 다.
# 문자열로만 비교하면 코드 파일을 0개로 세고 조용히 통과한다. 실제 세션에서 그렇게 새어 나갔다.
# 플랫폼에 기대지 않도록 진짜 심링크를 만들어 두 형태를 만든다.
PS="$T/sym"; mkdir -p "$PS/src"
printf '{"name":"s","scripts":{"test":"exit 1"}}' > "$PS/package.json"
printf 'module.exports=1;\n' > "$PS/src/a.js"
LN="$T/symlink"; ln -sfn "$PS" "$LN"
SS="$T/symstate"
symrun() { rm -rf "$SS"; mkdir -p "$SS/state/sy"; printf '%s\n' "$1" > "$SS/state/sy/changed"
  # 입력 JSON 은 printf 로 만든다. Git Bash 에서 네이티브 파이썬에 POSIX 경로를
  # 인자로 넘기면 MSYS 가 C:/Users/... 로 바꿔 버려, cwd 만 Windows 경로가 되고
  # changed 는 POSIX 경로로 남아 접두가 안 맞는다. CI 에서 이 케이스만 빨갰던 이유다.
  printf '%s' "$(stop sy "$2")" | NGG_STATE="$SS" "$W/stop.sh" >/dev/null 2>"$T/symerr"; }
# 실패하면 무엇을 보고 그렇게 판단했는지 남긴다. 이 케이스가 CI 에서만 빨갰고
# 로그에 결과만 있어 원인을 못 봤다.
# 실패하면 훅이 무엇을 보고 그렇게 판단했는지 남긴다. 이 케이스가 Windows CI 에서만
# 빨갰는데 로그에 결과만 있어 원인을 못 봤다. 훅이 파싱한 cwd 를 찍고서야 보였다.
symdiag() { echo "    root=$1"
  echo "    changed=$(cat "$SS/state/sy/changed" 2>/dev/null)"
  echo "    stderr=$(tr '\n' ' ' < "$T/symerr" 2>/dev/null | cut -c1-400)"
  local J; J=$(stop sy "$1")
  # IN 은 common.sh 의 read_in 이 읽는다. shellcheck 는 파일이 갈려 있어 쓰임을 못 본다.
  # shellcheck disable=SC2034,SC1091
  echo "    hookview=$( ( IN="$J"; . "$T/lib/common.sh"; read_in; printf 'SID=[%s] CWD=[%s]' "$SESSION_ID" "$CWD" ) | od -c | tr '\n' ' ' | cut -c1-400)"; }
b=$fail; symrun "$PS/src/a.js" "$PS"; check 2 $? "심링크: 둘 다 실경로면 막는다(기준선)"
[ "$fail" -ne "$b" ] && symdiag "$PS"
# Git Bash 는 권한에 따라 ln -s 가 심링크 대신 사본을 만든다. 그러면 검사할 상황 자체가 없다.
if [ -L "$LN" ]; then
  symrun "$LN/src/a.js" "$PS"; check 2 $? "심링크: changed 만 링크 경로여도 막는다"
  symrun "$PS/src/a.js" "$LN"; check 2 $? "심링크: cwd 만 링크 경로여도 막는다"
  symrun "$LN/src/a.js" "$LN"; check 2 $? "심링크: 둘 다 링크 경로여도 막는다"
else
  echo "⏭  심링크 3건: 이 플랫폼에서 ln -s 가 심링크를 만들지 않아 건너뛴다"
fi
symrun "$T/elsewhere/a.js" "$PS"; check 0 $? "심링크: 정말 저장소 밖이면 세지 않는다"

# 15. PR 본문에 근거가 있어야 PR 을 연다.
#     공식 best practices: "Have Claude show evidence rather than asserting success:
#     the test output, the command it ran and what it returned, or a screenshot of the result."
#     입력 JSON 은 printf 로 만든다. 명령에는 따옴표와 개행이 들어가므로 그 문자열만 파이프로
#     파이썬에 넘겨 이스케이프한다. 파이프는 Git Bash 가 경로를 바꾸지 않는다.
pr() { local c; c=$(printf '%s' "$3" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read(), ensure_ascii=False))')
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$1" "$2" "$c"; }
prrun() { printf '%s' "$(pr "$1" "$2" "$3")" | NGG_STATE="$T/prs" "$W/pre.sh" 2>"$T/epr"; }
# 사용자 전역 설정(서명, 커밋 훅)이 테스트 저장소에 끼어들지 않게 한다.
gitc() { local r="$1"; shift; git -C "$r" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=.nohooks "$@"; }
newrepo() { local r; r=$(newproj "$1"); git init -q "$r"; gitc "$r" checkout -qb main
  printf 'x\n' > "$r/README.md"; gitc "$r" add .; gitc "$r" commit -qm init
  gitc "$r" checkout -qb feat; mkdir -p "$r/$(dirname "$2")"; printf 'x\n' > "$r/$2"
  gitc "$r" add .; gitc "$r" commit -qm feat; printf '%s' "$r"; }
PRC=$(newrepo prcode src/a.ts)
PRD=$(newrepo prdocs docs/guide.md)

prrun p1 "$PRC" "gh pr create --title t --body '테스트 전부 통과했습니다.'"; check 2 $? "PR: 말로만 통과 → exit 2"
grep -q '완료 게이트' "$T/epr"; check 0 $? "PR: stderr에 완료 게이트 머리글"
grep -q 'PR' "$T/epr"; check 0 $? "PR: stderr에 무엇을 막았는지"

# 에이전트가 가장 흔히 쓰는 모양. heredoc 본문의 작은따옴표 하나에 셸 파서가 죽으면 안 된다.
IFS= read -r -d '' c <<'CMD'
gh pr create --title "t" --body "$(cat <<'EOF'
## 검증

```
$ npm test
Tests: 3 passed
```
It's reviewed.
EOF
)"
CMD
prrun p2 "$PRC" "$c"; check 0 $? "PR: heredoc 본문에 코드 블록 → 통과"

IFS= read -r -d '' c <<'CMD'
gh pr create --title "t" --body "$(cat <<'EOF'
## 요약
It's done. 테스트 전부 통과했습니다.
EOF
)"
CMD
prrun p3 "$PRC" "$c"; check 2 $? "PR: heredoc 본문에 근거 없음 → exit 2"

# shellcheck disable=SC2016  # 백틱과 $ 는 PR 본문에 들어갈 글자다. 셸이 펼치면 안 된다
printf '## 검증\n\n```\n$ npm test\nok\n```\n' > "$PRC/body-ok.md"
printf '## 요약\n통과했습니다.\n' > "$PRC/body-no.md"
prrun p4 "$PRC" "gh pr create --title t --body-file body-ok.md"; check 0 $? "PR: --body-file 에 코드 블록 → 통과"
prrun p5 "$PRC" "gh pr create --title t --body-file body-no.md"; check 2 $? "PR: --body-file 에 근거 없음 → exit 2"

IFS= read -r -d '' c <<'CMD'
gh pr create --title t -F - <<'EOF'
## 검증
```
$ npm test
ok
```
EOF
CMD
prrun p6 "$PRC" "$c"; check 0 $? "PR: -F - 로 넘긴 heredoc 에 코드 블록 → 통과"

prrun p7 "$PRC" "gh pr create --title t --body '![화면](shot.png)'"; check 0 $? "PR: 스크린샷 → 통과"
prrun p8 "$PRC" "git push -u origin HEAD && gh pr create --title t --body '통과'"; check 2 $? "PR: 앞 명령에 이어 붙어도 → exit 2"

# 모르는 것으로 막지 않는다. 본문이 명령에 없으면 볼 수 없다.
prrun p9 "$PRC" "gh pr create --fill"; check 0 $? "PR: --fill 은 본문을 볼 수 없어 → 통과"

# 인용은 사용이 아니다.
prrun p10 "$PRC" 'echo "gh pr create --body x" >> notes.md'; check 0 $? "PR: 문서에 적는 것은 사용이 아니다"
prrun p11 "$PRC" "git commit -m 'docs: gh pr create 게이트'"; check 0 $? "PR: 커밋 메시지에 든 것은 사용이 아니다"

# 코드가 아닌 변경은 대상이 아니다. 완료 게이트의 원칙과 같다.
prrun p12 "$PRD" "gh pr create --title t --body '오타 수정'"; check 0 $? "PR: 문서만 바꾼 브랜치 → 통과"
# 기준 브랜치를 못 찾으면 코드인지 가릴 수 없다. 본문만 보고 판정한다.
PRN=$(newproj prnogit)
prrun p13 "$PRN" "gh pr create --title t --body '통과'"; check 2 $? "PR: 기준 브랜치를 모르면 본문만 본다 → exit 2"

# 셸은 개행도 문장 구분자로 읽는다. 공백으로 읽으면 둘째 줄의 gh 가 명령 자리에 있다는 걸 놓친다.
prrun p16 "$PRC" "$(printf 'git push -u origin HEAD\ngh pr create --title t --body %s' "'통과'")"; check 2 $? "PR: 줄을 바꿔 이어 써도 → exit 2"
# 줄 이음(\)으로 플래그를 다음 줄에 써도 읽어야 한다. 못 읽으면 본문이 없는 것으로 보고 통과시킨다.
IFS= read -r -d '' c <<'CMD'
gh pr create --title t \
  --body-file body-no.md
CMD
prrun p17 "$PRC" "$c"; check 2 $? "PR: 줄 이음으로 나눠 쓴 --body-file 도 읽는다 → exit 2"

printf '%s' "$(pr p14 "$PRC" "gh pr create --title t --body '통과'")" | NGG_DONE=0 NGG_STATE="$T/prs" "$W/pre.sh" 2>/dev/null; check 0 $? "PR: NGG_DONE=0 → 통과"

printf '%s' "$(pr p15 "$PRC" "gh pr create --title t --body 'passed'")" | NGG_LANG=en NGG_STATE="$T/prs" "$W/pre.sh" 2>"$T/epr-en"; check 2 $? "PR en: 말로만 통과 → exit 2"
grep -q 'Completion gate' "$T/epr-en"; check 0 $? "PR en: 영어 머리글"
nohangul "$(cat "$T/epr-en")"; check 0 $? "PR en: 한글이 섞이지 않는다"

# 16. 항목 하나만 끄기. disabled_rules 가 근거 게이트 밖의 항목 이름도 받는다.
#     환경변수 NGG_DONE=0 은 세 검사를 한꺼번에 끄고 팀에 보이지 않는다.
PO=$(newrepo proff src/a.ts)
printf 'disabled_rules = "done.pr"\n' > "$PO/.checked-practices.toml"
prrun q1 "$PO" "gh pr create --title t --body '통과'"; check 0 $? "끄기: done.pr 을 끄면 PR 본문을 보지 않는다"
grep -q 'off=\[done.pr\]' "$T/prs/state/events.log"; check 0 $? "끄기: 끈 사실이 events.log 에 남는다"
# 오타는 조용히 넘어가면 안 된다. 껐다고 믿는데 안 꺼진 상태가 제일 나쁘다.
printf 'disabled_rules = "done.pt"\n' > "$PO/.checked-practices.toml"
prrun q2 "$PO" "gh pr create --title t --body '통과'"; check 2 $? "끄기: 없는 이름은 아무것도 끄지 않는다"
grep -q 'done.pt' "$T/epr"; check 0 $? "끄기: 없는 이름을 막을 때 알린다"

PT=$(newproj pturn); ST="$T/sturn"
printf 'test_command = "exit 1"\ndisabled_rules = "done.turn"\n' > "$PT/.checked-practices.toml"
printf '%s' "$(post tt "$PT" "$PT/src/a.ts")" | NGG_STATE="$ST" "$W/post.sh"
printf '%s' "$(stop tt "$PT")" | NGG_STATE="$ST" "$W/stop.sh" 2>/dev/null; check 0 $? "끄기: done.turn 을 끄면 턴 끝 검사를 돌리지 않는다"

PM=$(newproj pcommit); SM="$T/scommit"
printf 'fast_test_command = "true"\ntest_command = "exit 1"\ndisabled_rules = "done.commit"\n' > "$PM/.checked-practices.toml"
printf '%s' "$(commit tm "$PM" "git commit -m x")" | NGG_STATE="$SM" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: done.commit 을 끄면 커밋 전 검사를 돌리지 않는다"
# 한 항목을 끈 것이 다른 항목까지 끄면 안 된다.
printf 'fast_test_command = "true"\ntest_command = "exit 1"\ndisabled_rules = "done.pr"\n' > "$PM/.checked-practices.toml"
printf '%s' "$(commit tm "$PM" "git commit -m x")" | NGG_STATE="$SM" "$W/pre.sh" 2>/dev/null; check 2 $? "끄기: done.pr 만 끄면 커밋 전 검사는 그대로다"

# 17. 한 번만 허용하기. 허용 목록은 prompt.sh 가 사람의 프롬프트에서만 적는다. 여기서는 그 결과를 둔다.
mkdir -p "$T/prs/state/a1"; printf 'done.pr\n' > "$T/prs/state/a1/allow"
prrun a1 "$PRC" "gh pr create --title t --body '통과'"; check 0 $? "허용: done.pr 을 허용하면 PR 이 한 번 열린다"
prrun a1 "$PRC" "gh pr create --title t --body '통과'"; check 2 $? "허용: 두 번째는 막는다"
grep -q 'checked-practices allow done.pr' "$T/epr"; check 0 $? "허용: 막을 때 사람이 허용하는 법을 알린다"

PW=$(newproj pallow); SW="$T/sallow"
printf 'test_command = "exit 1"\n' > "$PW/.checked-practices.toml"
mkdir -p "$SW/state/tw"; printf 'done.turn\n' > "$SW/state/tw/allow"
printf '%s' "$(post tw "$PW" "$PW/src/a.ts")" | NGG_STATE="$SW" "$W/post.sh"
printf '%s' "$(stop tw "$PW")" | NGG_STATE="$SW" "$W/stop.sh" 2>/dev/null; check 0 $? "허용: done.turn 을 허용하면 검사가 실패해도 턴이 한 번 끝난다"
printf '%s' "$(stop tw "$PW")" | NGG_STATE="$SW" "$W/stop.sh" 2>/dev/null; check 2 $? "허용: 다음 턴 끝에서는 다시 막는다"

# 18. 저장소 루트는 cwd 가 아니다. 훅 입력의 cwd 는 Claude 가 cd 하면 따라간다(공식 hooks 문서).
#     cwd 에서만 .checked-practices.toml 을 찾으면 하위 폴더에 들어간 뒤 검사를 돌리지 않고 조용히 통과했다.
PS=$(newproj psub); SSB="$T/ssub"; mkdir -p "$PS/src" "$PS/pkg/api"
printf 'test_command = "echo ROOTCHECK >&2; exit 1"\n' > "$PS/.checked-practices.toml"
printf '%s' "$(post r1 "$PS/pkg/api" "$PS/src/a.ts")" | NGG_STATE="$SSB" "$W/post.sh"
printf '%s' "$(stop r1 "$PS/pkg/api")" | NGG_STATE="$SSB" "$W/stop.sh" 2>"$T/esub"; check 2 $? "루트: 하위 폴더에 있어도 저장소 설정으로 검사한다"
grep -q ROOTCHECK "$T/esub"; check 0 $? "루트: 루트의 검사 명령을 돌린다"
printf 'fast_test_command = "true"\ntest_command = "echo FULLROOT >&2; exit 1"\n' > "$PS/.checked-practices.toml"
printf '%s' "$(commit r2 "$PS/pkg/api" "git commit -m x")" | NGG_STATE="$SSB" "$W/pre.sh" 2>/dev/null; check 2 $? "루트: 하위 폴더에서 커밋해도 전체 검사를 돌린다"
# .git 이 있는 곳에서 멈춘다. 다른 저장소의 경계를 넘어 그 위의 설정을 빌려 쓰지 않는다.
PN=$(newproj pnest); mkdir -p "$PN/inner/src"; git init -q "$PN/inner"
printf 'test_command = "exit 1"\n' > "$PN/.checked-practices.toml"
printf '%s' "$(post r3 "$PN/inner" "$PN/inner/src/a.ts")" | NGG_STATE="$SSB" "$W/post.sh"
printf '%s' "$(stop r3 "$PN/inner")" | NGG_STATE="$SSB" "$W/stop.sh" 2>/dev/null; check 0 $? "루트: .git 경계를 넘어 위의 설정을 쓰지 않는다"
# 명령 안의 상대 경로는 셸이 있는 cwd 기준이다. 루트 기준으로 풀면 다른 파일을 읽는다.
mkdir -p "$PRC/sub"; printf '## 요약\n통과했습니다.\n' > "$PRC/sub/body-sub.md"
prrun r4 "$PRC/sub" "gh pr create --title t --body-file body-sub.md"; check 2 $? "루트: 하위 폴더의 --body-file 은 그 폴더 기준으로 읽는다"

# 19. 서브에이전트가 고친 코드도 턴 끝 검사 대상이다. post.sh 가 agent-<id> 폴더에 적어 메인 턴이 보지 못했다.
PE=$(newproj pagent); SE="$T/sagent"
printf 'test_command = "exit 1"\n' > "$PE/.checked-practices.toml"
printf '{"session_id":"ag","hook_event_name":"PostToolUse","cwd":"%s","agent_id":"sub1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PE" "$PE/src/a.ts" | NGG_STATE="$SE" "$W/post.sh"
printf '%s' "$(stop ag "$PE")" | NGG_STATE="$SE" "$W/stop.sh" 2>/dev/null; check 2 $? "서브에이전트: 서브에이전트의 편집도 메인 턴 끝에 검사한다"

# 20. 빠른 경로. pre.sh 는 Bash 호출마다 돌지만 보는 것은 커밋과 PR 생성뿐이다. 그 글자가 없으면
#     파이썬을 띄우지 않는다. 불리면 소리를 내는 가짜 python3 를 PATH 앞에 두고 확인한다.
# 훅은 파이썬의 stderr 를 버린다. 그래서 가짜 python3 는 불린 사실을 파일로 남긴다.
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/usr/bin/env bash\necho called >> "%s/called"\nexit 97\n' "$FB" > "$FB/python3"; chmod +x "$FB/python3"
rm -f "$FB/called"; printf '%s' "$(commit fp "$PB" "ls -la && npm test")" | PATH="$FB:$PATH" NGG_STATE="$SB" "$W/pre.sh" 2>/dev/null; check 0 $? "빠른 경로: 관계없는 Bash 명령은 파이썬 없이 통과한다"
[ -e "$FB/called" ]; r=$?; check 1 "$r" "빠른 경로: 관계없는 Bash 명령에는 파이썬을 띄우지 않는다"
rm -f "$FB/called"; printf '%s' "$(commit fp "$PB" "git commit -m x")" | PATH="$FB:$PATH" NGG_STATE="$SB" "$W/pre.sh" 2>/dev/null
[ -e "$FB/called" ]; check 0 $? "빠른 경로: 커밋 명령은 끝까지 검사한다"

echo; echo "실패 ${fail}건"; exit "$fail"
