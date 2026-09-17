#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 저장소 프로필 단위 테스트. 모델을 부르지 않는다.
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_PROFILE
# 메시지 언어를 못 박는다. 로케일에 따라 문장이 바뀌면 이 아래 문자열 단언이 기계마다 달라진다.
export NGG_LANG=ko
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/repo-profile"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/scripts"; mkdir -p "$W" "$T/lib"; cp "$G"/../lib/common.sh "$G"/../lib/msg.sh "$T/lib/"; cp "$G"/session.sh "$W"/
fail=0
lt() { [ "$1" -lt "$2" ]; }
blank() { [ -z "$1" ]; }
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
# 한글이 섞였는지는 python3 로 본다. grep 의 [가-힣] 는 LC_ALL=C 에서 바이트 범위가 되어
# 영어 문장의 가운뎃점(·)이나 화살표(→)까지 잡는다. 테스트가 로케일에 흔들리면 안 된다.
nohangul() { printf '%s' "$1" | python3 -c 'import sys,re; sys.exit(1 if re.search(r"[\uac00-\ud7a3]", sys.stdin.read()) else 0)'; }
run() { python3 -c 'import json,sys; print(json.dumps({"session_id":"rp","hook_event_name":"SessionStart","cwd":sys.argv[1]},ensure_ascii=False))' "$1" | "$W/session.sh"; }

# 1. 빈 폴더에서도 죽지 않는다
P0="$T/empty"; mkdir -p "$P0"
out=$(run "$P0"); check 0 $? "빈 폴더 → exit 0"
printf '%s' "$out" | grep -q 'check'; check 0 $? "출력에 프로필 표시"

# 2. 패키지 매니저를 락파일로 가린다
P1="$T/pnpm"; mkdir -p "$P1"; printf '{"name":"web","dependencies":{"next":"15.0.0","react":"19.0.0"}}\n' > "$P1/package.json"; : > "$P1/pnpm-lock.yaml"
out=$(run "$P1")
printf '%s' "$out" | grep -q 'pnpm'; check 0 $? "pnpm-lock.yaml → pnpm 탐지"
printf '%s' "$out" | grep -qi 'next'; check 0 $? "의존성에서 스택 탐지"

P2="$T/npm"; mkdir -p "$P2"; printf '{"name":"a","scripts":{"test":"vitest run"}}\n' > "$P2/package.json"; : > "$P2/package-lock.json"
out=$(run "$P2")
printf '%s' "$out" | grep -q 'npm'; check 0 $? "package-lock.json → npm 탐지"
printf '%s' "$out" | grep -q 'vitest\|npm test'; check 0 $? "scripts.test에서 검사 명령 탐지"

# 3. .check.toml 설정을 읽는다
P3="$T/conf"; mkdir -p "$P3"
printf 'test_command = "make check"\nappend_only = "supabase/migrations"\n' > "$P3/.check.toml"
out=$(run "$P3")
printf '%s' "$out" | grep -q 'make check'; check 0 $? "설정의 test_command 표시"
printf '%s' "$out" | grep -q 'supabase/migrations'; check 0 $? "설정의 append_only 표시"

# 4. 검사 명령을 못 찾으면 그 사실을 알린다 (완료 게이트가 놀고 있음을 드러낸다)
out=$(run "$P0"); printf '%s' "$out" | grep -q '검사 명령을 찾지 못'; check 0 $? "명령 없음을 명시"

# 5. 비밀은 싣지 않는다
P4="$T/secret"; mkdir -p "$P4"; printf 'API_KEY=super-secret-value-123\n' > "$P4/.env"
printf '{"name":"s"}\n' > "$P4/package.json"
out=$(run "$P4")
printf '%s' "$out" | grep -q 'super-secret-value-123'; r=$?; check 1 "$r" ".env 값을 출력하지 않음"

# 6. 공식 상한(10,000자)을 넘지 않는다
P5="$T/big"; mkdir -p "$P5"
python3 -c 'import json;print(json.dumps({"name":"b","dependencies":{f"pkg{i}":"1.0.0" for i in range(500)}}))' > "$P5/package.json"
out=$(run "$P5"); n=${#out}
lt "$n" 10000; check 0 $? "출력 ${n}자 < 10000"

# 7. 끄기
out=$(NGG_PROFILE=0 run "$P1"); blank "$out"; check 0 $? "NGG_PROFILE=0 → 출력 없음"

# 8. 다른 생태계도 가린다
P6="$T/go"; mkdir -p "$P6"; printf 'module x\n' > "$P6/go.mod"; printf 'test:\n\t@go test ./...\n' > "$P6/Makefile"
out=$(run "$P6"); printf '%s' "$out" | grep -qi 'go'; check 0 $? "go.mod 탐지"
printf '%s' "$out" | grep -q 'make test'; check 0 $? "Makefile test 타깃 탐지"
P7="$T/py"; mkdir -p "$P7"; printf '[project]\nname="p"\n' > "$P7/pyproject.toml"
out=$(run "$P7"); printf '%s' "$out" | grep -qi 'python\|pytest'; check 0 $? "pyproject.toml 탐지"

# 9. 게이트 상태를 알린다
out=$(run "$P3"); printf '%s' "$out" | grep -q '게이트'; check 0 $? "켜져 있는 게이트 표시"

# 메시지 언어. 프로필은 컨텍스트에 실리는 글이라 언어가 맞아야 읽힌다.
out=$(NGG_LANG=ko run "$P3"); printf '%s' "$out" | grep -q 'check 프로필'; check 0 $? "ko: 한국어 머리글"
out=$(NGG_LANG=en run "$P3"); printf '%s' "$out" | grep -q 'check profile'; check 0 $? "en: 영어 머리글"
out=$(NGG_LANG=en run "$P3"); nohangul "$out"; check 0 $? "en: 한글이 섞이지 않는다"

# 규칙을 끈 저장소는 세션마다 그 사실이 보여야 한다. 설정 파일에만 있으면 아무도 안 읽는다.
PD="$T/pd"; mkdir -p "$PD"
printf 'test_command = "true"\ndisabled_rules = "R2b"\n' > "$PD/.check.toml"
out=$(run "$PD"); printf '%s' "$out" | grep -q 'R2b'; check 0 $? "끈 규칙을 프로필에 싣는다"
out=$(NGG_LANG=en run "$PD"); nohangul "$out"; check 0 $? "en: 끈 규칙 줄에도 한글이 없다"

PE="$T/pe"; mkdir -p "$PE"
printf 'test_command = "true"\n' > "$PE/.check.toml"
out=$(run "$PE"); printf '%s' "$out" | grep -q 'disabled_rules'; r=$?; check 1 "$r" "끈 규칙이 없으면 그 줄을 넣지 않는다"

# 세션을 하위 폴더에서 열어도 저장소 루트의 설정을 싣는다. 훅 입력의 cwd 는 루트가 아닐 수 있다.
mkdir -p "$PD/sub/deeper"
out=$(run "$PD/sub/deeper"); printf '%s' "$out" | grep -q 'R2b'; check 0 $? "루트: 하위 폴더에서 열어도 루트의 설정을 싣는다"

# 훅 폴더는 커밋되지만 core.hooksPath 는 .git/config 에 있어 클론과 함께 오지 않는다.
# 그래서 가드가 꺼진 저장소는 막히는 일이 없어 사람도 에이전트도 모른다. 워크트리와 새
# 클론에서 조용히 꺼지는 문제가 이 한 줄로 드러나야 한다.
gitrepo() { git init -q "$1" && git -C "$1" config user.name t && git -C "$1" config user.email t@example.invalid; }

PG1="$T/guard-off"; mkdir -p "$PG1"; gitrepo "$PG1"; mkdir -p "$PG1/.githooks"; : > "$PG1/.githooks/pre-commit"
out=$(run "$PG1"); printf '%s' "$out" | grep -q '커밋 가드: 꺼짐'; check 0 $? "가드: 훅 폴더가 있는데 hooksPath 가 없으면 꺼짐으로 싣는다"
printf '%s' "$out" | grep -q 'setup.sh\|core.hooksPath'; check 0 $? "가드: 켜는 법을 함께 싣는다"

PG2="$T/guard-on"; mkdir -p "$PG2"; gitrepo "$PG2"; mkdir -p "$PG2/.githooks"; : > "$PG2/.githooks/pre-commit"
git -C "$PG2" config core.hooksPath .githooks
out=$(run "$PG2"); printf '%s' "$out" | grep -q '커밋 가드: 켜짐'; check 0 $? "가드: hooksPath 가 있으면 켜짐으로 싣는다"

PG3="$T/guard-none"; mkdir -p "$PG3"; gitrepo "$PG3"
out=$(run "$PG3"); printf '%s' "$out" | grep -q '커밋 가드'; r=$?; check 1 "$r" "가드: 훅 폴더가 없으면 그 줄을 넣지 않는다"

PG4="$T/guard-husky"; mkdir -p "$PG4"; gitrepo "$PG4"; mkdir -p "$PG4/.husky"; : > "$PG4/.husky/pre-commit"
out=$(run "$PG4"); printf '%s' "$out" | grep -q '커밋 가드: 꺼짐'; check 0 $? "가드: .husky 도 훅 폴더로 인식한다"

out=$(NGG_LANG=en run "$PG1"); nohangul "$out"; check 0 $? "en: 가드 줄에도 한글이 없다"

echo; echo "실패 ${fail}건"; exit "$fail"
