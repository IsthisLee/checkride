#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 프로젝트 가드 단위 테스트. 모델을 부르지 않는다.
set -u
# Windows 의 파이썬은 기본 인코딩이 UTF-8 이 아니다. 테스트는 우리 것이라 환경에 건다.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_GUARD
# 메시지 언어를 못 박는다. 로케일에 따라 문장이 바뀌면 이 아래 문자열 단언이 기계마다 달라진다.
export NGG_LANG=ko
# 이 스크립트는 tests/ 에 있고 검사 대상은 plugin/ 에 있다. G 를 훅 폴더로 맞춰 두면
# 아래의 "$G/..." 참조가 옮기기 전과 똑같이 동작한다.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
G="$ROOT/plugin/hooks/project-guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/scripts"; mkdir -p "$W" "$T/lib"; cp "$G"/../lib/common.sh "$G"/../lib/msg.sh "$T/lib/"; cp "$G"/pre.sh "$W"/
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
# 한글이 섞였는지는 python3 로 본다. grep 의 [가-힣] 는 LC_ALL=C 에서 바이트 범위가 되어
# 영어 문장의 가운뎃점(·)이나 화살표(→)까지 잡는다. 테스트가 로케일에 흔들리면 안 된다.
nohangul() { printf '%s' "$1" | python3 -c 'import sys,re; sys.exit(1 if re.search(r"[\uac00-\ud7a3]", sys.stdin.read()) else 0)'; }
edit() { python3 -c 'import json,sys; print(json.dumps({"session_id":"pg","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":sys.argv[2],"tool_input":{"file_path":sys.argv[3]}},ensure_ascii=False))' "$1" "$2" "$3"; }
bash_() { python3 -c 'import json,sys; print(json.dumps({"session_id":"pg","hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}},ensure_ascii=False))' "$1" "$2"; }
P="$T/proj"; mkdir -p "$P/supabase/migrations" "$P/src"
printf 'create table a();\n' > "$P/supabase/migrations/0001_init.sql"
printf 'append_only = "supabase/migrations, db/migrate"\n' > "$P/.checked-practices.toml"

# 1. 설정이 없으면 아무것도 막지 않는다
P0="$T/noconf"; mkdir -p "$P0/supabase/migrations"; printf 'x\n' > "$P0/supabase/migrations/0001.sql"
edit "$P0" Edit "$P0/supabase/migrations/0001.sql" | "$W/pre.sh" 2>/dev/null; check 0 $? "설정 없음 → 통과"

# 2. append-only 경로의 기존 파일 수정을 막는다
edit "$P" Edit "$P/supabase/migrations/0001_init.sql" | "$W/pre.sh" 2>"$T/e2"; check 2 $? "기존 마이그레이션 수정 → exit 2"
grep -q '프로젝트 가드' "$T/e2"; check 0 $? "stderr에 게이트 이름"
grep -q 'append-only\|추가만' "$T/e2"; check 0 $? "stderr에 규칙 설명"

# 3. 새 파일 추가는 허용한다 (마이그레이션은 계속 써야 한다)
edit "$P" Write "$P/supabase/migrations/0002_add.sql" | "$W/pre.sh" 2>/dev/null; check 0 $? "새 마이그레이션 추가 → 통과"

# 4. 지정 밖 경로는 대상이 아니다
edit "$P" Edit "$P/src/app.ts" | "$W/pre.sh" 2>/dev/null; check 0 $? "지정 밖 파일 수정 → 통과"

# 5. 삭제 명령을 막는다
bash_ "$P" "rm supabase/migrations/0001_init.sql" | "$W/pre.sh" 2>"$T/e5"; check 2 $? "마이그레이션 rm → exit 2"
grep -q '삭제' "$T/e5"; check 0 $? "stderr에 삭제 차단"
bash_ "$P" "rm src/app.ts" | "$W/pre.sh" 2>/dev/null; check 0 $? "지정 밖 rm → 통과"

# 6. 검사를 건너뛰는 커밋을 막는다
bash_ "$P" "git commit --no-verify -m x" | "$W/pre.sh" 2>"$T/e6"; check 2 $? "git commit --no-verify → exit 2"
grep -q 'no-verify' "$T/e6"; check 0 $? "stderr에 no-verify 설명"
bash_ "$P" "git commit -m x" | "$W/pre.sh" 2>/dev/null; check 0 $? "일반 커밋 → 통과"

# 7. 여러 경로를 쉼표로 적을 수 있다
mkdir -p "$P/db/migrate"; printf 'x\n' > "$P/db/migrate/001.rb"
edit "$P" Edit "$P/db/migrate/001.rb" | "$W/pre.sh" 2>/dev/null; check 2 $? "둘째 경로도 적용 → exit 2"

# 8. 끄기
edit "$P" Edit "$P/supabase/migrations/0001_init.sql" | NGG_GUARD=0 "$W/pre.sh" 2>/dev/null; check 0 $? "NGG_GUARD=0 → 통과"

# 9. 건너뛸 훅이 없는 저장소에서는 --no-verify를 막지 않는다.
#    설치만 했는데 남의 저장소의 git 동작이 바뀌면 과하다.
P8="$T/plain"; mkdir -p "$P8"
bash_ "$P8" "git commit --no-verify -m x" | "$W/pre.sh" 2>/dev/null; check 0 $? "설정도 커밋 훅도 없음 → --no-verify 통과"
bash_ "$P" "git commit --no-verify -m x" | "$W/pre.sh" 2>/dev/null; check 2 $? ".checked-practices.toml 있으면 → 차단"
P9="$T/husky"; mkdir -p "$P9/.husky"; printf '#!/bin/sh\nnpm test\n' > "$P9/.husky/pre-commit"
bash_ "$P9" "git commit --no-verify -m x" | "$W/pre.sh" 2>/dev/null; check 2 $? ".husky/pre-commit 있으면 → 차단"
P10="$T/githook"; mkdir -p "$P10/.git/hooks"; printf '#!/bin/sh\n' > "$P10/.git/hooks/pre-commit"; chmod +x "$P10/.git/hooks/pre-commit"
bash_ "$P10" "git commit --no-verify -m x" | "$W/pre.sh" 2>/dev/null; check 2 $? ".git/hooks/pre-commit 있으면 → 차단"

# 10. 따옴표로 감싼 경로도 잡아야 한다.
mkdir -p "$P/supabase/migrations"; printf 'x\n' > "$P/supabase/migrations/0002 new.sql"
bash_ "$P" 'rm "supabase/migrations/0002 new.sql"' | "$W/pre.sh" 2>/dev/null; check 2 $? "따옴표+공백 마이그레이션 rm → exit 2"
bash_ "$P" "rm 'supabase/migrations/0001_init.sql'" | "$W/pre.sh" 2>/dev/null; check 2 $? "홑따옴표 마이그레이션 rm → exit 2"
bash_ "$P" 'rm "src/my app.ts"' | "$W/pre.sh" 2>/dev/null; check 0 $? "따옴표라도 지정 밖이면 통과"

# 메시지 언어
for L in ko en; do
  edit "$P" Edit "$P/supabase/migrations/0001_init.sql" | NGG_LANG="$L" "$W/pre.sh" 2>"$T/pl-$L"
  check 2 $? "$L: append-only 수정 → exit 2"
done
grep -q '프로젝트 가드' "$T/pl-ko"; check 0 $? "ko: 한국어 머리글"
grep -q 'Project guard' "$T/pl-en"; check 0 $? "en: 영어 머리글"
nohangul "$(cat "$T/pl-en")"; check 0 $? "en: 한글이 섞이지 않는다"

# 문서에 플래그 이름을 적는 것은 사용이 아니다.
# 근거 게이트에는 인용 면제가 있는데 프로젝트 가드에는 없어서, README 표에 적다가 막혔다.
bash_ "$P" 'echo '\''use --no-verify to skip'\'' > doc.md' | "$W/pre.sh" 2>/dev/null; check 0 $? "인용: 문서에 플래그를 적는 것은 사용이 아니다"
bash_ "$P" 'printf '\''%s'\'' '\''| 가드 | --no-verify 차단 |'\'' >> README.md' | "$W/pre.sh" 2>/dev/null; check 0 $? "인용: 표에 적는 것도 사용이 아니다"
bash_ "$P" 'git commit -m '\''docs: --no-verify 설명 추가'\''' | "$W/pre.sh" 2>/dev/null; check 0 $? "인용: 커밋 메시지에 든 것은 사용이 아니다"
bash_ "$P" 'git commit --no-verify -m x' | "$W/pre.sh" 2>/dev/null; check 2 $? "인용: 진짜 사용은 그대로 막는다"
bash_ "$P" 'echo hi; git commit --no-verify -m x' | "$W/pre.sh" 2>/dev/null; check 2 $? "인용: 뒤 문장의 진짜 사용도 막는다"
bash_ "$P" 'git commit -m x' | "$W/pre.sh" 2>/dev/null; check 0 $? "인용: 평범한 커밋은 통과"

# 항목 하나만 끄기. NGG_GUARD=0 은 append-only 까지 같이 끈다.
PX="$T/off"; mkdir -p "$PX/supabase/migrations"; printf 'x\n' > "$PX/supabase/migrations/0001.sql"
printf 'append_only = "supabase/migrations"\ndisabled_rules = "pg.noverify"\n' > "$PX/.checked-practices.toml"
bash_ "$PX" "git commit --no-verify -m x" | NGG_STATE="$T/pgs" "$W/pre.sh" 2>/dev/null; check 0 $? "끄기: pg.noverify 를 끄면 --no-verify 를 막지 않는다"
grep -q 'off=\[pg.noverify\]' "$T/pgs/state/events.log"; check 0 $? "끄기: 끈 사실이 events.log 에 남는다"
edit "$PX" Edit "$PX/supabase/migrations/0001.sql" | NGG_STATE="$T/pgs" "$W/pre.sh" 2>/dev/null; check 2 $? "끄기: pg.noverify 만 끄면 append-only 는 그대로다"

# 한 번만 허용하기. 허용 목록은 prompt.sh 가 사람의 프롬프트에서만 적는다. 여기서는 그 결과를 둔다.
AL="$T/allow"; mkdir -p "$AL/state/pg"; printf 'pg.noverify\n' > "$AL/state/pg/allow"
bash_ "$P" "git commit --no-verify -m x" | NGG_STATE="$AL" "$W/pre.sh" 2>/dev/null; check 0 $? "허용: pg.noverify 를 허용하면 한 번 통과한다"
bash_ "$P" "git commit --no-verify -m x" | NGG_STATE="$AL" "$W/pre.sh" 2>"$T/eal"; check 2 $? "허용: 두 번째는 막는다"
grep -q 'checked-practices allow pg.noverify' "$T/eal"; check 0 $? "허용: 막을 때 사람이 허용하는 법을 알린다"

# 저장소 루트는 cwd 가 아니다. 하위 폴더에 들어가 있어도 루트의 .checked-practices.toml 을 쓴다.
edit "$P/src" Edit "$P/supabase/migrations/0001_init.sql" | "$W/pre.sh" 2>/dev/null; check 2 $? "루트: 하위 폴더에서도 append-only 수정을 막는다"
bash_ "$P/supabase" "rm migrations/0001_init.sql" | "$W/pre.sh" 2>/dev/null; check 2 $? "루트: 하위 폴더 기준 상대 경로 삭제도 막는다"
bash_ "$P/src" "git commit --no-verify -m x" | "$W/pre.sh" 2>/dev/null; check 2 $? "루트: 하위 폴더에서도 --no-verify 를 막는다"

# 빠른 경로. Bash 에서 보는 것은 삭제·이동과 --no-verify 커밋뿐이라, 그 글자가 없으면 파이썬을 띄우지 않는다.
# 불리면 소리를 내는 가짜 python3 를 PATH 앞에 두고 확인한다.
# 훅은 파이썬의 stderr 를 버린다. 그래서 가짜 python3 는 불린 사실을 파일로 남긴다.
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/usr/bin/env bash\necho called >> "%s/called"\nexit 97\n' "$FB" > "$FB/python3"; chmod +x "$FB/python3"
rm -f "$FB/called"; bash_ "$P" "ls -la && npm test" | PATH="$FB:$PATH" "$W/pre.sh" 2>/dev/null; check 0 $? "빠른 경로: 관계없는 Bash 명령은 파이썬 없이 통과한다"
[ -e "$FB/called" ]; r=$?; check 1 "$r" "빠른 경로: 관계없는 Bash 명령에는 파이썬을 띄우지 않는다"
rm -f "$FB/called"; bash_ "$P" "git commit --no-verify -m x" | PATH="$FB:$PATH" "$W/pre.sh" 2>/dev/null
[ -e "$FB/called" ]; check 0 $? "빠른 경로: 커밋 명령은 끝까지 검사한다"

echo; echo "실패 ${fail}건"; exit "$fail"
