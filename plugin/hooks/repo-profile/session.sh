#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# shellcheck source-path=SCRIPTDIR
# SessionStart: 이 저장소의 사실을 20줄 안팎으로 요약해 Claude의 컨텍스트에 싣는다.
#
# 공식 hooks 레퍼런스: "The exceptions are UserPromptSubmit, UserPromptExpansion, SessionStart,
# and PostModelSwitch, where Claude Code adds plain-text stdout as context that Claude can see."
# 공식 best practices의 CLAUDE.md 포함 목록: "Bash commands Claude can't guess".
#
# 싣는 것은 **사실뿐**이다. 행동 지시는 넣지 않는다. 그건 게이트의 일이다.
# 모델을 부르지 않고 파일만 읽는다. 비밀 파일의 값은 읽지 않는다. 끄기: NGG_PROFILE=0
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/../lib/common.sh"; read_in
[ "${NGG_PROFILE:-1}" = "0" ] && exit 0
find_root; root="$NGG_ROOT"; cd "$root" 2>/dev/null || exit 0          # cwd 가 아니라 저장소 루트다(common.sh)

name=$(basename "$root")
branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

pm=""; [ -f pnpm-lock.yaml ] && pm=pnpm
[ -z "$pm" ] && [ -f yarn.lock ] && pm=yarn
[ -z "$pm" ] && [ -f bun.lockb ] && pm=bun
[ -z "$pm" ] && [ -f package-lock.json ] && pm=npm

stack=""
if [ -f package.json ]; then
  stack=$(py - <<'PY' 2>/dev/null || true
import json
d = json.load(open("package.json"))
deps = {**(d.get("dependencies") or {}), **(d.get("devDependencies") or {})}
known = ["next","nuxt","react","vue","svelte","@angular/core","express","fastify","nestjs",
         "@nestjs/core","vite","typescript","vitest","jest","playwright","prisma","@supabase/supabase-js"]
hit = [k.split("/")[-1] for k in known if k in deps]
print(", ".join(hit[:8]))
PY
)
fi
[ -z "$stack" ] && [ -f go.mod ] && stack="Go ($(sed -n 's/^go \(.*\)$/\1/p' go.mod | head -1))"
[ -z "$stack" ] && [ -f Cargo.toml ] && stack="Rust"
[ -z "$stack" ] && [ -f pyproject.toml ] && stack="Python (pyproject)"
[ -z "$stack" ] && [ -f requirements.txt ] && stack="Python (requirements)"

# 검사 명령. 완료 게이트와 같은 순서로 찾는다.
cmd=""; src=""
if [ -f checkride.toml ]; then
  cmd=$(sed -n 's/^[[:space:]]*test_command[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' checkride.toml | head -1)
  [ -n "$cmd" ] && src="checkride.toml"
fi
if [ -z "$cmd" ] && [ -f package.json ]; then
  t=$(py -c 'import json;print((json.load(open("package.json")).get("scripts") or {}).get("test",""))' 2>/dev/null || true)
  [ -n "$t" ] && { cmd="${pm:-npm} test"; src="package.json scripts.test → $t"; }
fi
if [ -z "$cmd" ] && [ -f Makefile ] && grep -qE '^test:' Makefile; then cmd="make test"; src="Makefile"; fi
if [ -z "$cmd" ] && [ -f pyproject.toml ]; then cmd="py -m pytest -q"; src="pyproject.toml"; fi

appendonly=""
[ -f checkride.toml ] && appendonly=$(sed -n 's/^[[:space:]]*append_only[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' checkride.toml | head -1)
# 끈 규칙은 세션마다 보여야 한다. 설정 파일에만 있으면 아무도 안 읽고, 그러면 환경변수로
# 끄던 시절과 다를 것이 없다.
disabled=""
[ -f checkride.toml ] && disabled=$(sed -n 's/^[[:space:]]*disabled_rules[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' checkride.toml | head -1)

# 훅 폴더는 커밋되지만 core.hooksPath 는 .git/config 에 있어 클론과 함께 오지 않는다.
# 그래서 가드가 꺼진 저장소는 막히는 일이 없어 사람도 에이전트도 모른 채 지나간다.
# 워크트리와 새 클론에서 조용히 꺼지는 것이 이 배선의 유일한 실패 방식이라 세션마다 보인다.
hooksdir=""
for d in .githooks .husky; do [ -d "$d" ] && { hooksdir="$d"; break; }; done
hookspath=""
[ -n "$hooksdir" ] && hookspath=$(git -C "$root" config core.hooksPath 2>/dev/null || true)

{
  tn rp.head "$name"
  [ -n "$branch" ] && tn rp.branch "$branch"
  echo
  [ -n "$pm" ] && t rp.pm "$pm"
  [ -n "$stack" ] && t rp.stack "$stack"
  if [ -n "$cmd" ]; then t rp.cmd "$cmd" "$src"
  else t rp.nocmd; fi
  [ -n "$appendonly" ] && t rp.appendonly "$appendonly"
  [ -n "$disabled" ] && t rp.disabled "$disabled"
  if [ -n "$hooksdir" ]; then
    if [ -n "$hookspath" ]; then t rp.guardon "$hookspath"
    else t rp.guardoff "$hooksdir" "$hooksdir"; fi
  fi
  if [ -n "$cmd" ]; then g1=$(tn rp.on); else g1=$(tn rp.wait); fi
  if [ -n "$appendonly" ]; then g2=$(tn rp.on); else g2=$(tn rp.noconf); fi
  t rp.gates "$g1" "$g2"
} | cut -c1-400 | head -30
exit 0
