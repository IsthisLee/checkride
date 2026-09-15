#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# PreToolUse(Edit|Write|Bash): 테스트를 통과시키려고 무력화하는 편집을 막는다.
#
# Kent Beck, Augmented Coding: "Any indication that the genie was cheating,
# for example by disabling or deleting tests."
#
# 막는 것은 셋뿐이다. 무력화 표기 추가, 단언 개수 감소, 테스트 파일 삭제.
# it.todo 는 아직 쓰지 않은 테스트의 자리라 표기 목록에 넣지 않는다(V51).
# **테스트 수정 전반을 막지 않는다.** 기댓값을 고치거나 단언을 더하는 것은 통과한다.
# TDD는 테스트를 먼저 쓰고 고치는 방법론이라 그것까지 막으면 문서가 권하는 바와 반대로 간다.
#
# 끄기: NGG_TESTGUARD=0
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"
IN=$(cat)
# 빠른 경로. 이 훅은 Bash 호출마다 돈다. Bash 에서 보는 것은 테스트 파일 삭제뿐이라, 입력에 삭제
# 글자가 없으면 파이썬을 띄우지 않고 끝낸다(V40). 도구 이름이 애매하면 느린 경로로 간다.
if quick_tool && [ "$QT" = Bash ]; then case "$IN" in *rm[[:space:]\"\\]*) ;; *) exit 0;; esac; fi
read_in
[ "${NGG_TESTGUARD:-1}" = "0" ] && exit 0

TESTPATH='(\.(test|spec)\.[a-z]+$|(^|/)__tests__/|(^|/)tests?/|(^|/)test_[^/]+\.py$|_test\.(go|py|rb|ex)$|(^|/)spec/)'
DISABLE='(\.skip\(|\.only\(|\bxit\(|\bxdescribe\(|\bxtest\(|@pytest\.mark\.(skip|xfail)|#\[ignore\]|\bt\.Skip\(|@Ignore\b|\bpending\(|describe\.skip\()'
# 테스트 러너 설정. 테스트 파일을 건드리지 않고 여기에 제외를 넣어 테스트를 빼는 길이 있었다.
# EvilGenie(arXiv 2511.21654)가 "Modified Testing Procedures"로 분류한 행동이다.
RUNNERCFG='((^|/)(jest|vitest|karma|playwright|cypress|webpack)\.config\.[a-z]+$|(^|/)(pytest\.ini|tox\.ini|setup\.cfg|pyproject\.toml|phpunit\.xml|\.mocharc\.[a-z]+|\.nycrc)$|(^|/)jest\.config$)'
# 제외를 뜻하는 지시어. 늘어나면 막는다.
EXCLUDE='(testPathIgnorePatterns|testPathIgnore|modulePathIgnorePatterns|coveragePathIgnorePatterns|--ignore(-glob)?=|norecursedirs|collect_ignore|testpaths *=|(^|[^a-zA-Z])exclude *[:=]|excludeSpecPattern|ignorePatterns|skipFiles|--deselect)'
is_runner_cfg() { printf '%s' "$1" | grep -qE "$RUNNERCFG"; }
ASSERT='(expect\(|assert[A-Za-z_(]|\bassert\b|should\.|\.toBe\(|\.toEqual\(|\.toHaveBeenCalled|require\.(NoError|Equal)|XCTAssert)'

# 빌드 산출물은 테스트 파일이 아니다. tests/ 아래라는 이유만으로 __pycache__ 삭제가 막혔다.
# 이 저장소를 옮기는 작업 중 실제로 세 번 걸렸고, 사용자가 겪으면 게이트를 꺼 버릴 만한 오탐이다.
ARTIFACT='((^|/)(__pycache__|node_modules|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|\.nyc_output|coverage|dist|build|target)(/|$)|\.(pyc|pyo|class|o)$)'
is_artifact() { printf '%s' "$1" | grep -qE "$ARTIFACT"; }
is_test() { is_artifact "$1" && return 1; printf '%s' "$1" | grep -qE "$TESTPATH"; }
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

count() { printf '%s' "$2" | grep -oE "$1" | grep -c . || true; }

# block <항목> <머리> <내용>. 항목 이름은 사람에게 허용하는 법을 알릴 때 쓴다.
block() { local it="$1"; shift; { t ti.prefix "$1"; off_bad; echo "$2"; t ti.advice; allow_hint "$it"; } >&2; exit 2; }

case "$TOOL_NAME" in
  Bash)
    # 테스트 파일 삭제를 막는다. 인자만 보고 판단한다.
    printf '%s' "$COMMAND" | grep -qE '(^|[;&|]|\s)(rm|git[[:space:]]+rm)\b' || exit 0
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      if is_test "$tok"; then
        item_off ti.rm && exit 0          # 항목 하나만 끄기
        allow_once ti.rm && exit 0        # 한 번만 허용하기
        block ti.rm "$(tn ti.rm)" "$(t line.cmd "$COMMAND"; tn line.target "$tok")"
      fi
    done <<EOF
$(rm_targets "$COMMAND")
EOF
    exit 0 ;;
  Edit|Write)
    if is_runner_cfg "$FILE_PATH"; then
      if [ "$TOOL_NAME" = "Write" ]; then
        [ -f "$FILE_PATH" ] || exit 0
        cb=$(cat "$FILE_PATH" 2>/dev/null); ca="$CONTENT"
      else cb="$OLD_STRING"; ca="$NEW_STRING"; fi
      eb=$(count "$EXCLUDE" "$cb"); ea=$(count "$EXCLUDE" "$ca")
      if [ "$ea" -gt "$eb" ] && ! item_off ti.exclude && ! allow_once ti.exclude; then
        block ti.exclude "$(tn ti.exclude "$eb" "$ea")" "$(t line.file "$FILE_PATH"; tn ti.excludehint)"
      fi
      exit 0
    fi
    is_test "$FILE_PATH" || exit 0 ;;
  *) exit 0 ;;
esac

if [ "$TOOL_NAME" = "Write" ]; then
  [ -f "$FILE_PATH" ] || exit 0          # 새 파일 생성은 통과
  before=$(cat "$FILE_PATH" 2>/dev/null); after="$CONTENT"
else
  before="$OLD_STRING"; after="$NEW_STRING"
fi

db=$(count "$DISABLE" "$before"); da=$(count "$DISABLE" "$after")
if [ "$da" -gt "$db" ] && ! item_off ti.skip && ! allow_once ti.skip; then
  added=$(printf '%s' "$after" | grep -oE "$DISABLE" | sort -u | tr '\n' ' ')
  block ti.skip "$(tn ti.disable "$db" "$da")" "$(t line.file "$FILE_PATH"; tn ti.markers "$added")"
fi

ab=$(count "$ASSERT" "$before"); aa=$(count "$ASSERT" "$after")
if [ "$aa" -lt "$ab" ] && ! item_off ti.assert && ! allow_once ti.assert; then
  block ti.assert "$(tn ti.assert "$ab" "$aa")" "$(tn line.file "$FILE_PATH")"
fi
exit 0
