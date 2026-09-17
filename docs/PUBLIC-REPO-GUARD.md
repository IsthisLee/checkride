# 공개 저장소 개인 정보 가드

공개 저장소에 홈 경로, 이메일, 사내 도메인, 사적인 저장소 이름이 섞여 들어가는 것을 커밋 시점에 막는 장치다.
Node 를 요구하지 않고 `bash` 와 `git` 만으로 돈다. 다른 저장소에도 그대로 옮길 수 있다.

## 무엇을 막는가

`.githooks/pre-commit` 이 `pre-commit` 단계에서 스테이징된 파일만 검사한다. 두 축이다.

1. **경로**: 내부 문서 폴더가 스테이징되면 막는다. 이 저장소에서는 `.private/`, `docs/design-plan-review*`, `docs/README-review*`, `docs/README-preview*`, `docs/superpowers/` 다. 저장소마다 다르므로 옮길 때 고치는 곳이다.
2. **내용**: 스테이징된 내용에 개인 식별 문자열이 있으면 막는다. 홈 경로(`/Users/<이름>`, `/home/<이름>`)는 훅에 박혀 있고, 나머지는 패턴 파일에서 읽는다.

검사 대상은 작업 트리가 아니라 `git show ":<파일>"`, 곧 인덱스에 올라간 내용이다. 스테이징하지 않은 변경은 커밋되지 않으므로 보지 않는다.

## 패턴 목록을 두는 곳이 둘이다

여러 저장소에 적용하려면 패턴을 한 곳에서 관리해야 한다. 그래서 출처가 둘이다.

| 출처 | 경로 | 쓰는 때 |
|---|---|---|
| 공용 | `$GIT_GUARD_PATTERNS`, 없으면 `${XDG_CONFIG_HOME:-$HOME/.config}/git-guard/patterns` | 이메일처럼 **모든 저장소에서** 막을 값. 저장소 밖에 있어 한 번 적으면 전부에 적용된다. |
| 저장소별 | `<저장소>/.private/guard-patterns` | 그 저장소에만 해당하는 값. `.gitignore` 에 `.private/` 가 있어 커밋되지 않는다. |

둘 다 있으면 합쳐 적용하고, 둘 다 없으면 홈 경로만 막는다. 형식은 한 줄에 하나이고 `grep -E` 정규식으로 읽히므로, 점처럼 정규식에서 뜻이 있는 글자는 `me@example\.com` 처럼 escape 한다. `#` 로 시작하는 줄과 빈 줄은 버린다.

**패턴 파일 자체는 절대 커밋하지 않는다.** 막으려는 값이 그 안에 평문으로 들어 있기 때문이다.

## 켜려면 `core.hooksPath` 를 설정해야 한다

훅 파일을 저장소에 두어도 그것만으로는 아무 일도 일어나지 않는다. git 2.53.0 의 공식 문서(`git help config`, 2026-09-16 확인)가 기본 탐색 위치를 이렇게 적는다.

> "By default Git will look for your hooks in the $GIT_DIR/hooks directory. Set this to different path, e.g. /etc/git/hooks, and Git will try to find your hooks in that directory, e.g. /etc/git/hooks/pre-receive instead of in $GIT_DIR/hooks/pre-receive."
>
> 번역: 기본적으로 Git 은 훅을 `$GIT_DIR/hooks` 디렉터리에서 찾습니다. 이 값을 `/etc/git/hooks` 같은 다른 경로로 설정하면, Git 은 `$GIT_DIR/hooks/pre-receive` 대신 그 디렉터리에서, 즉 `/etc/git/hooks/pre-receive` 에서 훅을 찾으려 합니다.

훅을 커밋하려면 `.git/` 밖에 두어야 하므로 `.githooks/` 에 둔다. 그 위치는 기본 탐색 대상이 아니니 `core.hooksPath` 로 알려 줘야 한다.

**이 설정은 클론과 함께 전달되지 않는다.** `.git/config` 에 저장되고 `.git/` 은 커밋되지 않기 때문이다. 클론한 사람이 직접 한 번 실행해야 한다. 클론만으로 남이 쓴 스크립트가 실행되면 위험하므로 git 이 의도한 설계다.

그 한 번을 `setup.sh` 가 맡는다. 설정하고, 훅 파일의 실행 비트를 채우고, 설정을 되읽어 확인하고, 어떤 패턴 출처가 잡히는지 알린다.

```bash
./setup.sh                  # 훅을 켠다
./setup.sh --init-patterns  # 공용 패턴 파일의 견본을 만든다(없을 때만)
./setup.sh --force          # 이미 다른 훅 관리자가 잡고 있어도 덮어쓴다
./setup.sh --help           # 이 설명을 본다
```

**이미 husky 나 lefthook 을 쓰는 저장소라면 덮어쓰지 않습니다.** `core.hooksPath` 는 값을 하나만 가지므로,
덮으면 그쪽 훅이 조용히 죽습니다. `setup.sh` 가 그 상황을 감지하면 멈추고 공존하는 방법을 알려 줍니다.
그쪽 관리자의 `pre-commit` 에 한 줄을 넣으면 둘 다 돕니다.

```bash
"$(git rev-parse --show-toplevel)"/.githooks/pre-commit || exit 1
```

## husky 를 쓰지 않는 이유

husky 9.1.7 을 빈 저장소에 설치해 `npx husky init` 을 돌려 확인했다(2026-09-16).

```
$ git config --show-origin core.hooksPath
file:.git/config	.husky/_
```

**husky 도 같은 `core.hooksPath` 를 같은 `.git/config` 에 쓴다.** 설정이 전달되지 않는 성질은 husky 로 바꿔도 그대로다. husky 가 더하는 것은 `package.json` 에 `"prepare": "husky"` 를 넣어 `npm install` 이 끝날 때 그 설정을 자동으로 걸어 주는 한 단계뿐이다.

그 한 단계는 Node 프로젝트에서만 값을 낸다. 이 저장소는 `bash` 와 `python3` 로만 돌고 `package.json` 이 없으므로, 얹을 `npm install` 이 없다. husky 를 들이면 훅 하나를 켜기 위해 Node 런타임 요구와 `package.json` 과 락파일이 새로 생긴다. 얻는 것은 명령 한 줄을 덜 치는 것이고, 잃는 것은 Node 없이 도는 성질이다. 그래서 같은 일을 `setup.sh` 가 직접 한다.

덧붙여, 패턴 목록이 전달되지 않는 문제는 husky 로도 해결되지 않는다. 그 원인은 훅 관리 도구가 아니라 "개인 패턴은 공개할 수 없다"는 성질 자체다.

## 다른 저장소에 적용하는 절차

1. 이 저장소에서 `.githooks/pre-commit` 과 `setup.sh` 를 대상 저장소 루트로 복사한다.
2. 훅의 `case` 문에 있는 경로 목록을 그 저장소에 맞게 고친다. 해당하는 폴더가 없으면 `.private/*` 만 남긴다.
3. 대상 저장소의 `.gitignore` 에 `.private/` 를 넣는다. 이 줄이 없으면 패턴 파일이 커밋될 수 있다.
4. `./setup.sh --init-patterns` 를 실행하고, 만들어진 공용 패턴 파일에 자신의 값을 적는다. 공용 파일은 저장소 밖에 있으므로 두 번째 저장소부터는 `./setup.sh` 만 실행하면 된다.
5. 실제로 막히는지 확인한다. 막히지 않으면 켜지지 않은 것이다.

```bash
printf 'contact me@example.com\n' > /tmp/guard-probe.txt
cp /tmp/guard-probe.txt ./guard-probe.txt && git add guard-probe.txt
git commit -m probe   # 여기서 막혀야 정상이다
git reset HEAD -- guard-probe.txt && rm guard-probe.txt
```

## 한계

이 장치가 지키지 못하는 것을 분명히 해 둔다.

- **이미 푸시된 것은 되돌리지 못한다.** 커밋 전에만 작동한다. 값이 이미 공개됐으면 기록에서 지우려 하기보다 발급처에서 폐기하는 것이 유일하게 확실한 조치다.
- **`--no-verify` 로 우회된다.** 의도한 탈출구다. 사람이 판단해 쓰는 것이고, 자동화가 습관적으로 붙이는 자리가 아니다.
- **패턴에 적은 것만 막는다.** 목록에 없는 값은 지나간다. 토큰이나 키 형태를 막고 싶으면 그 패턴을 직접 넣어야 한다.
- **클론한 사람이 `setup.sh` 를 돌리지 않으면 꺼진 상태다.** 이것은 git 의 설계이고 husky 로도 달라지지 않는다.
- **패턴 파일이 없는 기계에서는 홈 경로만 막힌다.** 공용 파일을 그 기계에도 두어야 전부 막힌다.

## 파일

`setup.sh` 는 고칠 곳이 없어 그대로 복사한다. 훅은 경로 목록을 고쳐야 하므로 본문을 아래에 둔다.
저장소의 실제 파일이 정본이고, 이 인용과 어긋나면 `tests/invariants.sh` 가 잡는다.

```bash
#!/usr/bin/env bash
# 공개 저장소 가드: 내부 문서와 개인 식별 정보가 커밋에 섞이는 것을 막는다.
#   - 경로: .private/ 아래, docs/design-plan-review*, docs/README-review*, docs/superpowers/ 는 커밋 금지
#     (저장소마다 다르므로 아래 case 문을 그 저장소에 맞게 고친다)
#   - 내용: 홈 경로(/Users/<이름>, /home/<이름>) + 개인 패턴(한 줄에 하나). 패턴 출처는 둘이다.
#       1) 공용: $GIT_GUARD_PATTERNS, 없으면 ${XDG_CONFIG_HOME:-$HOME/.config}/git-guard/patterns
#          저장소 밖에 있으므로 여러 저장소가 한 목록을 공유한다. 이쪽에 적으면 저장소마다 복사하지 않아도 된다.
#       2) 저장소별: .private/guard-patterns
#          git 무시 폴더라 커밋되지 않는다. 그 저장소에만 해당하는 패턴을 적는다.
#     둘 다 있으면 합쳐서 적용한다. 둘 다 없으면 홈 경로만 막는다.
# 우회는 git commit --no-verify 뿐이며, 사람이 의도적으로 할 때만 쓴다.
set -u
root="$(git rev-parse --show-toplevel)"
fail=0
paths=$(git diff --cached --name-only --diff-filter=ACMR)
for f in $paths; do
  case "$f" in
    .private/*|docs/design-plan-review*|docs/README-review*|docs/README-preview*|docs/superpowers/*)
      echo "pre-commit: 내부 문서는 공개 저장소에 올리지 않는다: $f"; fail=1;;
  esac
done
pattern='/Users/[A-Za-z]|/home/[A-Za-z]'
# 패턴 파일 한 개를 읽어 pattern 에 덧붙인다. 주석 줄과 빈 줄은 버린다.
add_patterns() {
  local file="$1" extra
  [ -f "$file" ] || return 0
  extra=$(grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' | paste -sd '|' -)
  [ -n "$extra" ] && pattern="$pattern|$extra"
  return 0
}
add_patterns "${GIT_GUARD_PATTERNS:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/git-guard/patterns}"
add_patterns "$root/.private/guard-patterns"
for f in $paths; do
  [ -f "$f" ] || continue
  if git show ":$f" | grep -n -E "$pattern" >/dev/null; then
    echo "pre-commit: 개인 식별 정보가 있다: $f"
    git show ":$f" | grep -n -E "$pattern" | head -3 | sed 's/^/    /'
    fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "커밋을 막았다. 파일을 .private/로 옮기거나 문자열을 지워라."; exit 1; }
exit 0
```
