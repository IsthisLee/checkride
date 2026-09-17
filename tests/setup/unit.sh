#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# setup.sh 단위 테스트. 모델을 부르지 않는다.
# core.hooksPath 는 값을 하나만 가진다. 덮어쓰면 앞의 것이 사라지고, 그 저장소가 쓰던
# 훅이 조용히 죽는다. husky·lefthook 을 쓰는 저장소에서 실제로 그렇게 됐다(V55).
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_STATE NGG_INNER NGG_JUDGE NGG_PROFILE
export NGG_LANG=ko
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }

# 훅 폴더와 setup.sh 를 갖춘 새 git 저장소를 만든다.
mkrepo() {
  local d="$1" hooks="${2:-.githooks}"
  mkdir -p "$d"; git init -q "$d"
  git -C "$d" config user.name t; git -C "$d" config user.email t@example.invalid
  mkdir -p "$d/$hooks"; printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/$hooks/pre-commit"
  chmod +x "$d/$hooks/pre-commit"
  cp "$ROOT/setup.sh" "$d/setup.sh"; chmod +x "$d/setup.sh"
}

# 1. 기준선: 설정이 비어 있으면 건다
R1="$T/fresh"; mkrepo "$R1"
out=$(cd "$R1" && ./setup.sh 2>&1); check 0 $? "빈 설정 → exit 0"
check ".githooks" "$(git -C "$R1" config core.hooksPath)" "빈 설정 → hooksPath 를 건다"

# 2. 멱등: 같은 값이 이미 있으면 그대로 통과한다
out=$(cd "$R1" && ./setup.sh 2>&1); check 0 $? "같은 값 → exit 0 (멱등)"
check ".githooks" "$(git -C "$R1" config core.hooksPath)" "같은 값 → 그대로 둔다"

# 3. 남의 값이 있으면 덮지 않고 멈춘다. 이게 이 파일의 존재 이유다.
R2="$T/taken"; mkrepo "$R2"
git -C "$R2" config core.hooksPath .husky/_
out=$(cd "$R2" && ./setup.sh 2>&1); r=$?
check 1 "$r" "남의 hooksPath → exit 1 (조용히 덮지 않는다)"
check ".husky/_" "$(git -C "$R2" config core.hooksPath)" "남의 hooksPath → 값을 건드리지 않는다"
printf '%s' "$out" | grep -q '.husky/_'; check 0 $? "차단 메시지에 기존 값을 보인다"
printf '%s' "$out" | grep -q 'pre-commit'; check 0 $? "차단 메시지에 공존하는 법을 보인다"
printf '%s' "$out" | grep -q '\-\-force'; check 0 $? "차단 메시지에 덮어쓰는 법을 보인다"

# 4. --force 는 사람이 의도해서 줄 때만 덮는다
out=$(cd "$R2" && ./setup.sh --force 2>&1); check 0 $? "--force → exit 0"
check ".githooks" "$(git -C "$R2" config core.hooksPath)" "--force → 덮는다"

# 5. 훅 폴더가 없으면 멈춘다
R3="$T/nohooks"; mkdir -p "$R3"; git init -q "$R3"
cp "$ROOT/setup.sh" "$R3/setup.sh"; chmod +x "$R3/setup.sh"
out=$(cd "$R3" && ./setup.sh 2>&1); r=$?; check 1 "$r" "훅 폴더 없음 → exit 1"

# 6. git 저장소가 아니면 멈춘다
R4="$T/notgit"; mkdir -p "$R4"; cp "$ROOT/setup.sh" "$R4/setup.sh"; chmod +x "$R4/setup.sh"
out=$(cd "$R4" && ./setup.sh 2>&1); r=$?; check 1 "$r" "git 저장소 아님 → exit 1"

# 7. 모르는 인자는 조용히 무시하지 않는다
R5="$T/badarg"; mkrepo "$R5"
out=$(cd "$R5" && ./setup.sh --nope 2>&1); r=$?; check 1 "$r" "모르는 인자 → exit 1"

echo; echo "실패 ${fail}건"; exit "$fail"
