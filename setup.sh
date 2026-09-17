#!/usr/bin/env bash
# 이 저장소의 git 훅을 켠다. 필요한 것은 bash 와 git 뿐이다.
#
# git 은 훅을 .git/hooks 에서만 찾는다. 이 저장소의 훅은 커밋해 두어야 하므로
# .githooks/ 에 있고, 그 위치는 git 의 기본 탐색 대상이 아니다. core.hooksPath 를
# 설정해야 git 이 그곳을 본다. 그 설정은 .git/config 에 저장되고 .git/ 은 커밋되지
# 않으므로, 클론한 사람마다 한 번 실행해야 한다. 이 스크립트가 그 한 번이다.
#
# husky 도 같은 core.hooksPath 를 쓴다. 다른 점은 husky 가 npm install 의 prepare
# 단계에 그 설정을 얹는다는 것뿐이다. 이 저장소는 Node 를 쓰지 않으므로 얹을
# npm install 이 없고, 그래서 Node 의존을 들이지 않고 같은 일을 직접 한다.
#
# 사용법:
#   ./setup.sh                  훅을 켠다
#   ./setup.sh --init-patterns  공용 개인 패턴 파일의 견본을 만든다(없을 때만)
#   ./setup.sh --force          이미 다른 훅 관리자가 잡고 있어도 덮어쓴다
set -u

HOOKS_DIR=.githooks
GLOBAL_PATTERNS="${GIT_GUARD_PATTERNS:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/git-guard/patterns}"

die() { printf '%s\n' "setup: $1" >&2; exit 1; }

init_patterns=0
force=0
for arg in "$@"; do
  case "$arg" in
    --init-patterns) init_patterns=1;;
    --force) force=1;;
    -h|--help) awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0;;
    *) die "모르는 인자: ${arg}";;
  esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "git 저장소 안에서 실행해라."
cd "$root" || die "저장소 루트로 이동하지 못했다: ${root}"

[ -d "$HOOKS_DIR" ] || die "${HOOKS_DIR}/ 가 없다. 훅 폴더를 먼저 두어라."

# 훅 파일에 실행 비트가 없으면 git 이 조용히 건너뛴다. 세어서 채운다.
hooks=0
for h in "$HOOKS_DIR"/*; do
  [ -f "$h" ] || continue
  hooks=$((hooks + 1))
  [ -x "$h" ] || { chmod +x "$h" && printf '%s\n' "실행 비트를 채웠다: ${h}"; }
done
[ "$hooks" -gt 0 ] || die "${HOOKS_DIR}/ 에 훅 파일이 없다."

# core.hooksPath 는 값을 하나만 가진다. 이미 다른 훅 관리자(husky·lefthook 등)가 잡고 있는데
# 덮으면 그쪽 훅이 조용히 죽는다. 막히는 일이 없어지므로 아무도 눈치채지 못한다.
# 실측: husky 가 잡은 저장소를 덮자 husky 의 pre-commit 이 돌지 않고 커밋이 통과했다.
existing=$(git config core.hooksPath 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "$HOOKS_DIR" ] && [ "$force" -eq 0 ]; then
  printf '%s\n' "setup: core.hooksPath 가 이미 '${existing}' 다. 덮으면 그쪽 훅이 조용히 죽는다." >&2
  printf '%s\n' "  공존하려면 그쪽 관리자의 pre-commit 에 이 한 줄을 넣어라:" >&2
  printf '%s\n' "      \"\$(git rev-parse --show-toplevel)\"/${HOOKS_DIR}/pre-commit || exit 1" >&2
  printf '%s\n' "  기존 훅을 버리고 덮어쓰려면: ./setup.sh --force" >&2
  exit 1
fi

git config core.hooksPath "$HOOKS_DIR" || die "core.hooksPath 설정에 실패했다."

# 설정했다고 적용된 것이 아니다. 되읽어 확인한다.
got=$(git config core.hooksPath || true)
[ "$got" = "$HOOKS_DIR" ] || die "설정이 되읽히지 않는다(값: '${got}')."
printf '%s\n' "core.hooksPath = ${got}  (훅 ${hooks}개)"

if [ "$init_patterns" -eq 1 ] && [ ! -f "$GLOBAL_PATTERNS" ]; then
  mkdir -p "$(dirname "$GLOBAL_PATTERNS")" || die "패턴 폴더를 만들지 못했다."
  cat > "$GLOBAL_PATTERNS" <<'TEMPLATE'
# 커밋에 들어가면 안 되는 개인 패턴. 한 줄에 하나, grep -E 문법.
# 이 파일은 저장소 밖에 있어 여러 저장소가 함께 쓴다. 커밋되지 않는다.
# 예시를 지우고 자신의 값을 적어라.
# me@example.com
# my-private-repo-name
TEMPLATE
  printf '%s\n' "패턴 견본을 만들었다: ${GLOBAL_PATTERNS}  (내용을 채워라)"
fi

# 어떤 패턴 출처가 실제로 잡히는지 알린다. 없으면 홈 경로만 막힌다.
sources=0
[ -f "$GLOBAL_PATTERNS" ] && { printf '%s\n' "공용 패턴: ${GLOBAL_PATTERNS}"; sources=$((sources + 1)); }
[ -f .private/guard-patterns ] && { printf '%s\n' "저장소 패턴: .private/guard-patterns"; sources=$((sources + 1)); }
if [ "$sources" -eq 0 ]; then
  printf '%s\n' "주의: 개인 패턴 파일이 없어 홈 경로만 막는다. './setup.sh --init-patterns' 로 공용 목록을 만들어라."
fi
exit 0
