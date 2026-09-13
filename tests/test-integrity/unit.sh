#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 테스트 무결성 게이트 단위 테스트. 모델을 부르지 않는다.
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_TESTGUARD
# 메시지 언어를 못 박는다. 로케일에 따라 문장이 바뀌면 이 아래 문자열 단언이 기계마다 달라진다.
export NGG_LANG=ko
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/test-integrity"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/scripts"; mkdir -p "$W" "$T/lib"; cp "$G"/../lib/common.sh "$G"/../lib/msg.sh "$T/lib/"; cp "$G"/pre.sh "$W"/
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
# 한글이 섞였는지는 python3 로 본다. grep 의 [가-힣] 는 LC_ALL=C 에서 바이트 범위가 되어
# 영어 문장의 가운뎃점(·)이나 화살표(→)까지 잡는다. 테스트가 로케일에 흔들리면 안 된다.
nohangul() { printf '%s' "$1" | python3 -c 'import sys,re; sys.exit(1 if re.search(r"[\uac00-\ud7a3]", sys.stdin.read()) else 0)'; }
edit() { python3 -c 'import json,sys; print(json.dumps({"session_id":"ti","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Edit","tool_input":{"file_path":sys.argv[2],"old_string":sys.argv[3],"new_string":sys.argv[4]}},ensure_ascii=False))' "$1" "$2" "$3" "$4"; }
write() { python3 -c 'import json,sys; print(json.dumps({"session_id":"ti","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Write","tool_input":{"file_path":sys.argv[2],"content":sys.argv[3]}},ensure_ascii=False))' "$1" "$2" "$3"; }
bash_() { python3 -c 'import json,sys; print(json.dumps({"session_id":"ti","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}},ensure_ascii=False))' "$1" "$2"; }
P="$T/proj"; mkdir -p "$P/src" "$P/tests"

# 1. 테스트 파일에 skip을 넣으면 막는다
edit "$P" "$P/src/a.test.ts" "it('works', () => { expect(x).toBe(1) })" "it.skip('works', () => { expect(x).toBe(1) })" | "$W/pre.sh" 2>"$T/e1"; check 2 $? "test 파일에 .skip 추가 → exit 2"
grep -q '테스트 무결성' "$T/e1"; check 0 $? "stderr에 게이트 이름"
grep -q 'skip' "$T/e1"; check 0 $? "stderr에 무엇이 걸렸는지"

# 2. 여러 표기를 잡는다
for pat in "xit('a', () => {})" "describe.only('a', () => {})" "@pytest.mark.skip" "#[ignore]" "t.Skip()"; do
  edit "$P" "$P/tests/x_test.go" "assert(1)" "$pat assert(1)" | "$W/pre.sh" 2>/dev/null; check 2 $? "무력화 표기 차단: ${pat:0:18}"
done

# 3. 단언을 지우면 막는다
edit "$P" "$P/src/a.test.ts" "expect(a).toBe(1); expect(b).toBe(2);" "expect(a).toBe(1);" | "$W/pre.sh" 2>"$T/e3"; check 2 $? "단언 개수 감소 → exit 2"
grep -q '단언' "$T/e3"; check 0 $? "stderr에 단언 감소 표시"

# 4. 정상적인 테스트 수정은 통과한다
edit "$P" "$P/src/a.test.ts" "expect(a).toBe(1);" "expect(a).toBe(2);" | "$W/pre.sh" 2>/dev/null; check 0 $? "기댓값만 바꿈 → 통과"
edit "$P" "$P/src/a.test.ts" "expect(a).toBe(1);" "expect(a).toBe(1); expect(b).toBe(2);" | "$W/pre.sh" 2>/dev/null; check 0 $? "단언 추가 → 통과"
edit "$P" "$P/src/a.test.ts" "// skip this" "// skip that" | "$W/pre.sh" 2>/dev/null; check 0 $? "이미 있던 skip 단어는 늘지 않음 → 통과"

# 5. 테스트가 아닌 파일은 대상이 아니다
edit "$P" "$P/src/app.ts" "run()" "// it.skip is fine here\nrun()" | "$W/pre.sh" 2>/dev/null; check 0 $? "테스트 파일이 아니면 통과"

# 6. 테스트 파일을 지우는 명령을 막는다
bash_ "$P" "rm src/a.test.ts" | "$W/pre.sh" 2>"$T/e6"; check 2 $? "rm 테스트 파일 → exit 2"
grep -q '삭제' "$T/e6"; check 0 $? "stderr에 삭제 차단"
bash_ "$P" "git rm tests/x_test.go" | "$W/pre.sh" 2>/dev/null; check 2 $? "git rm 테스트 파일 → exit 2"
bash_ "$P" "rm build/out.js" | "$W/pre.sh" 2>/dev/null; check 0 $? "테스트가 아닌 파일 rm → 통과"
bash_ "$P" "npm test" | "$W/pre.sh" 2>/dev/null; check 0 $? "일반 명령 → 통과"

# 7. Write로 통째로 덮어써 단언을 없애면 막는다
printf 'it("a", () => { expect(x).toBe(1); expect(y).toBe(2); })\n' > "$P/src/b.test.ts"
write "$P" "$P/src/b.test.ts" 'it("a", () => { expect(x).toBe(1); })' | "$W/pre.sh" 2>/dev/null; check 2 $? "Write로 단언 감소 → exit 2"
write "$P" "$P/src/b.test.ts" 'it("a", () => { expect(x).toBe(1); expect(y).toBe(2); expect(z).toBe(3); })' | "$W/pre.sh" 2>/dev/null; check 0 $? "Write로 단언 추가 → 통과"
write "$P" "$P/src/new.test.ts" 'it("a", () => { expect(x).toBe(1); })' | "$W/pre.sh" 2>/dev/null; check 0 $? "새 테스트 파일 생성 → 통과"

# 8. 끄기
edit "$P" "$P/src/a.test.ts" "it('w', () => {})" "it.skip('w', () => {})" | NGG_TESTGUARD=0 "$W/pre.sh" 2>/dev/null; check 0 $? "NGG_TESTGUARD=0 → 통과"

# 9. 따옴표로 감싼 경로도 잡아야 한다. 공백이 든 파일명은 반드시 따옴표가 붙는다.
bash_ "$P" 'rm "src/my test.test.ts"' | "$W/pre.sh" 2>/dev/null; check 2 $? "따옴표+공백 테스트 파일 rm → exit 2"
bash_ "$P" "rm 'tests/a b_test.go'" | "$W/pre.sh" 2>/dev/null; check 2 $? "홑따옴표 테스트 파일 rm → exit 2"
bash_ "$P" 'git rm "src/x.spec.ts"' | "$W/pre.sh" 2>/dev/null; check 2 $? "따옴표 git rm → exit 2"
bash_ "$P" 'rm "build/my out.js"' | "$W/pre.sh" 2>/dev/null; check 0 $? "따옴표라도 테스트가 아니면 통과"

# 메시지 언어
for L in ko en; do
  edit "$P" "$P/src/a.test.ts" "it('works', () => { expect(x).toBe(1) })" "it.skip('works', () => { expect(x).toBe(1) })" \
    | NGG_LANG="$L" "$W/pre.sh" 2>"$T/tl-$L"; check 2 $? "$L: .skip 추가 → exit 2"
done
grep -q '테스트 무결성 게이트' "$T/tl-ko"; check 0 $? "ko: 한국어 머리글"
grep -q 'Test-integrity gate' "$T/tl-en"; check 0 $? "en: 영어 머리글"
nohangul "$(cat "$T/tl-en")"; check 0 $? "en: 한글이 섞이지 않는다"

# 테스트 러너 설정으로 테스트를 빼는 것을 막는다.
# EvilGenie(arXiv 2511.21654)가 "Modified Testing Procedures"로 분류한 행동이다.
# 테스트 파일을 건드리지 않고 설정에 제외 패턴만 넣으면 지금까지 그냥 통과했다.
C="$T/cfg"; mkdir -p "$C"
cfg() { printf '%s' "$2" > "$C/$1"; }

cfg jest.config.js 'module.exports = { testMatch: ["**/*.test.ts"] };'
edit "$C" "$C/jest.config.js" 'module.exports = { testMatch: ["**/*.test.ts"] };' \
  'module.exports = { testMatch: ["**/*.test.ts"], testPathIgnorePatterns: ["src/auth"] };' \
  | "$W/pre.sh" 2>"$T/c1"; check 2 $? "설정: jest 에 testPathIgnorePatterns 추가 → exit 2"
grep -q '테스트 무결성 게이트' "$T/c1"; check 0 $? "설정: 게이트 이름이 나온다"

cfg pytest.ini '[pytest]'
edit "$C" "$C/pytest.ini" '[pytest]' '[pytest]
addopts = --ignore=tests/auth' | "$W/pre.sh" 2>/dev/null; check 2 $? "설정: pytest 에 --ignore 추가 → exit 2"

cfg vitest.config.ts 'export default { test: {} }'
edit "$C" "$C/vitest.config.ts" 'export default { test: {} }' 'export default { test: { exclude: ["src/auth/**"] } }' \
  | "$W/pre.sh" 2>/dev/null; check 2 $? "설정: vitest 에 exclude 추가 → exit 2"

# 제외를 줄이거나 그대로면 통과한다
cfg jest.config.js 'module.exports = { testPathIgnorePatterns: ["a","b"] };'
edit "$C" "$C/jest.config.js" 'module.exports = { testPathIgnorePatterns: ["a","b"] };' \
  'module.exports = { testPathIgnorePatterns: ["a"] };' | "$W/pre.sh" 2>/dev/null; check 0 $? "설정: 제외를 줄이면 통과"
cfg jest.config.js 'module.exports = { testMatch: ["**/*.test.ts"] };'
edit "$C" "$C/jest.config.js" 'module.exports = { testMatch: ["**/*.test.ts"] };' \
  'module.exports = { testMatch: ["**/*.test.ts"], verbose: true };' | "$W/pre.sh" 2>/dev/null; check 0 $? "설정: 제외와 무관한 편집은 통과"

# 설정 파일이 아니면 대상이 아니다
printf '%s' 'const exclude = ["a"];' > "$C/app.ts"
edit "$C" "$C/app.ts" 'const exclude = ["a"];' 'const exclude = ["a","b"]; const testPathIgnorePatterns = 1;' \
  | "$W/pre.sh" 2>/dev/null; check 0 $? "설정: 일반 소스 파일은 대상이 아니다"

# 빌드 산출물은 테스트 파일이 아니다.
# tests/ 아래라는 이유만으로 __pycache__ 삭제가 막혔다. 실제로 이 저장소 작업 중 세 번 걸렸다.
A="$T/art"; mkdir -p "$A/tests/__pycache__" "$A/tests/node_modules" "$A/tests/.pytest_cache"
printf 'x' > "$A/tests/unit.sh"
bash_ "$A" 'rm -rf tests/__pycache__' | "$W/pre.sh" 2>/dev/null; check 0 $? "산출물: __pycache__ 삭제는 통과"
bash_ "$A" 'rm -rf tests/node_modules' | "$W/pre.sh" 2>/dev/null; check 0 $? "산출물: node_modules 삭제는 통과"
bash_ "$A" 'rm -rf tests/.pytest_cache' | "$W/pre.sh" 2>/dev/null; check 0 $? "산출물: .pytest_cache 삭제는 통과"
bash_ "$A" 'rm -f tests/a.pyc' | "$W/pre.sh" 2>/dev/null; check 0 $? "산출물: .pyc 삭제는 통과"
bash_ "$A" 'rm tests/unit.sh' | "$W/pre.sh" 2>/dev/null; check 2 $? "산출물 아님: 진짜 테스트 파일 삭제는 여전히 막힌다"

# rm 은 자기 인자하고만 짝지어야 한다.
# 지금까지 명령 어디엔가 rm 이 있고 다른 문장에 테스트 경로가 있으면 삭제로 읽었다.
# 이 저장소 작업 중 다섯 번 걸렸다. 사용자는 한 번이면 게이트를 끈다.
bash_ "$P" 'rm -rf /tmp/xyz; printf x > src/a.test.ts' | "$W/pre.sh" 2>/dev/null; check 0 $? "문장 분리: 다른 문장의 테스트 경로와 짝짓지 않는다(;)"
bash_ "$P" 'mkdir -p src && printf x > src/a.test.ts && rm -rf /tmp/xyz' | "$W/pre.sh" 2>/dev/null; check 0 $? "문장 분리: && 로 이어진 경우"
bash_ "$P" 'cat src/a.test.ts | grep x; rm -rf /tmp/xyz' | "$W/pre.sh" 2>/dev/null; check 0 $? "문장 분리: 파이프와 세미콜론"
bash_ "$P" 'rm -rf /tmp/xyz' | "$W/pre.sh" 2>/dev/null; check 0 $? "문장 분리: 테스트와 무관한 삭제는 통과"
bash_ "$P" 'echo hi; rm src/a.test.ts' | "$W/pre.sh" 2>/dev/null; check 2 $? "문장 분리: 진짜 삭제는 여전히 막는다"
bash_ "$P" 'rm -rf build && git rm src/a.test.ts' | "$W/pre.sh" 2>/dev/null; check 2 $? "문장 분리: 뒤쪽 git rm 도 잡는다"

# 항목 하나만 끄기. NGG_TESTGUARD=0 은 넷을 한꺼번에 끄고 팀에 보이지 않는다.
Q="$T/off"; mkdir -p "$Q/src" "$Q/tests"
offc() { printf 'disabled_rules = "%s"\n' "$1" > "$Q/.check.toml"; }
# 무력화 표기가 든 픽스처는 실행할 때 만든다. 소스에 그 글자를 적으면 이 파일을 고칠 때
# 설치된 테스트 무결성 게이트가 픽스처를 무력화로 읽고 편집을 막는다. 실제로 막혔다.
SKIP_OLD="it('w', () => { expect(x).toBe(1) })"; SKIP_NEW=$(printf '%s' "$SKIP_OLD" | sed 's/^it/&.skip/')
offc ti.skip
edit "$Q" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: ti.skip 을 끄면 무력화 표기를 막지 않는다"
grep -q 'off=\[ti.skip\]' "$T/tis/state/events.log"; check 0 $? "끄기: 끈 사실이 events.log 에 남는다"
edit "$Q" "$Q/src/a.test.ts" "expect(a).toBe(1); expect(b).toBe(2);" "expect(a).toBe(1);" | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 2 $? "끄기: ti.skip 만 끄면 단언 감소는 그대로 막는다"
offc ti.assert
edit "$Q" "$Q/src/a.test.ts" "expect(a).toBe(1); expect(b).toBe(2);" "expect(a).toBe(1);" | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: ti.assert 를 끄면 단언 감소를 막지 않는다"
offc ti.rm
bash_ "$Q" "rm tests/x_test.go" | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: ti.rm 을 끄면 테스트 삭제를 막지 않는다"
offc ti.exclude
edit "$Q" "$Q/vitest.config.ts" 'export default { test: {} }' 'export default { test: { exclude: ["src/auth/**"] } }' \
  | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: ti.exclude 를 끄면 러너 설정의 제외를 막지 않는다"
# 오타는 조용히 넘어가면 안 된다. 껐다고 믿는데 안 꺼진 상태가 제일 나쁘다.
offc ti.skp
edit "$Q" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$T/tis" "$W/pre.sh" 2>"$T/eoff"; check 2 $? "끄기: 없는 이름은 아무것도 끄지 않는다"
grep -q 'ti.skp' "$T/eoff"; check 0 $? "끄기: 없는 이름을 막을 때 알린다"

# 한 번만 허용하기. 허용 목록은 prompt.sh 가 사람의 프롬프트에서만 적는다. 여기서는 그 결과를 둔다.
rm -f "$Q/.check.toml"; AL="$T/allow"; mkdir -p "$AL/state/ti"
printf 'ti.skip\n' > "$AL/state/ti/allow"
edit "$Q" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$AL" "$W/pre.sh" 2>/dev/null; check 0 $? "허용: 허용한 항목은 한 번 통과한다"
grep -q 'allowed=\[ti.skip\]' "$AL/state/events.log"; check 0 $? "허용: 통과시킨 사실이 events.log 에 남는다"
edit "$Q" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$AL" "$W/pre.sh" 2>"$T/eal"; check 2 $? "허용: 두 번째는 막는다(한 번 쓰면 사라진다)"
grep -q 'check allow ti.skip' "$T/eal"; check 0 $? "허용: 막을 때 사람이 허용하는 법을 알린다"
printf 'ti.rm\n' > "$AL/state/ti/allow"
edit "$Q" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$AL" "$W/pre.sh" 2>/dev/null; check 2 $? "허용: 다른 항목의 허용으로는 통과하지 않는다"

# 저장소 루트는 cwd 가 아니다. 하위 폴더에 들어가 있어도 루트의 disabled_rules 를 읽는다.
offc ti.skip; mkdir -p "$Q/src/deep"
edit "$Q/src/deep" "$Q/src/a.test.ts" "$SKIP_OLD" "$SKIP_NEW" | NGG_STATE="$T/tis" "$W/pre.sh" 2>/dev/null; check 0 $? "루트: 하위 폴더에서도 루트의 disabled_rules 를 읽는다"
# 빠른 경로가 Edit 을 Bash 로 잘못 읽으면 안 된다. 본문에 Bash 라는 글자가 있어도 Edit 검사는 그대로다.
rm -f "$Q/.check.toml"
edit "$Q" "$Q/src/a.test.ts" "run('Bash')" "$SKIP_NEW run('Bash')" | "$W/pre.sh" 2>/dev/null; check 2 $? "빠른 경로: 본문에 Bash 가 있어도 Edit 은 끝까지 검사한다"

# 빠른 경로. 이 훅은 Bash 호출마다 돈다. Bash 에서 보는 것은 테스트 파일 삭제뿐이라, 삭제 글자가 없으면
# 파이썬을 띄우지 않고 끝낸다. 불리면 소리를 내는 가짜 python3 를 PATH 앞에 두고 확인한다.
# 훅은 파이썬의 stderr 를 버린다. 그래서 가짜 python3 는 불린 사실을 파일로 남긴다.
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/usr/bin/env bash\necho called >> "%s/called"\nexit 97\n' "$FB" > "$FB/python3"; chmod +x "$FB/python3"
rm -f "$FB/called"; bash_ "$P" "ls -la && npm test" | PATH="$FB:$PATH" "$W/pre.sh" 2>/dev/null; check 0 $? "빠른 경로: 관계없는 Bash 명령은 파이썬 없이 통과한다"
[ -e "$FB/called" ]; r=$?; check 1 "$r" "빠른 경로: 관계없는 Bash 명령에는 파이썬을 띄우지 않는다"
rm -f "$FB/called"; bash_ "$P" "rm src/a.test.ts" | PATH="$FB:$PATH" "$W/pre.sh" 2>/dev/null
[ -e "$FB/called" ]; check 0 $? "빠른 경로: 삭제 명령은 끝까지 검사한다"

echo; echo "실패 ${fail}건"; exit "$fail"
