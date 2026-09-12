# checked-practices — 게이트와 커맨드 상세

README는 짧게 두고 자세한 것은 여기 적는다. 각 게이트가 무엇을 어떻게 막는지, 무엇으로 끄는지, 근거가 어느 문서인지.

## 개발을 몰라도 되는 설명

Claude Code는 코드를 대신 써 주는 AI 조수다. 일은 잘한다. 그런데 가끔 서류를 열어 보지도 않고 "그런 건 없습니다"라고 하고, 검사를 돌리지도 않고 "다 끝냈습니다"라고 한다.

사람이 그러면 "확인은 했어요?"라고 되물으면 된다. 문제는 **매번** 되물어야 한다는 것이다. 사람은 언젠가 깜빡하고, 깜빡한 그날 사고가 난다.

이 플러그인은 그 되묻기를 자동으로 만든다. 안전벨트를 안 매면 차에서 경고음이 나는 것과 같다. 운전자가 기억할 필요가 없고, 기억하지 못해도 괜찮다.

## 의미 판정기 설정

근거 게이트는 R2a·R2b만 걸렸을 때 작은 모델에게 의견인지 상태 주장인지 묻는다. 판정기는 풀어 줄 수만 있고 새로 막지 못한다. 규칙과 면제는 [README](../README.md#무엇이-막히나)에 있다.

| 환경변수 | 기본값 | 뜻 |
|---|---|---|
| `NGG_JUDGE` | `1` | `0`이면 판정을 아예 하지 않는다 |
| `NGG_JUDGE_MODEL` | `haiku` | 판정 모델. 분류 한 번이라 큰 모델이 필요 없지만 바꿀 수 있다 |
| `NGG_JUDGE_CMD` | (없음) | 판정 명령 전체를 다른 것으로 바꾼다. 이걸 주면 모델 설정은 무시된다 |
| `NGG_JUDGE_TIMEOUT` | `40` | 초 |

### 메시지 언어

게이트가 내보내는 문장은 한국어와 영어 두 벌이다. 규칙 판정은 언어와 상관없이 같다.

| 환경변수 | 기본값 | 뜻 |
|---|---|---|
| `NGG_LANG` | (로케일) | `ko` 또는 `en`. 주면 로케일을 무시한다 |

`NGG_LANG`이 없으면 `LC_ALL` → `LC_MESSAGES` → `LANG` 순으로 보고, `ko` 계열이면 한국어, 그 밖에는 영어다. 문장은 `plugin/hooks/lib/msg.sh` 한 곳에 모여 있다.

### 왜 내장 `type: "prompt"` 훅을 쓰지 않나

Claude Code에는 판단이 필요한 자리에 쓰는 [프롬프트 훅](https://code.claude.com/docs/en/hooks)이 있다. 셸 명령 대신 모델에게 묻고 `{"ok": bool, "reason": …}`을 받는다. 우리가 `judge.py`로 만든 것과 같은 일이다. 그런데도 쓰지 않는 이유는 **언제 부르느냐**가 다르기 때문이다.

| 방식 | 언제 도나 | 턴당 비용 |
|---|---|---|
| `type: "prompt"` Stop 훅 | **모든 턴** | 실측 +1.6초 (기준선 4.8초 → 6.4초) |
| 우리 방식(정규식 + `judge.py`) | 차단의 약 4% | 걸릴 때만 중앙값 8초, 나머지 턴은 0 |

정규식이 공짜로 바닥을 깔고 모델은 드물게 부른다. 프롬프트 훅으로 옮기면 아무 일 없는 턴까지 느려진다. `ok:false` 로 막는 경로가 실제로 도는 것은 확인했다(막힌 뒤 모델이 계속 일해 6턴).

실패하거나 시간을 넘기면 막은 채로 둔다. 결과는 `${CLAUDE_PLUGIN_DATA}/state/events.log`에 `judge=released|kept|failed`와 걸린 초로 남는다.

## 항목 하나만 끄기

정규식은 의도를 다 읽지 못한다. 어떤 저장소에서는 한 규칙이 유난히 자주 오탐을 낸다. 그렇다고 게이트를 통째로 끄면 같은 게이트의 나머지 검사도 같이 죽는다.

`.checked-practices.toml`에 이름을 적으면 그것만 빠진다.

```toml
# 이 저장소에서는 R2b가 설계 논의마다 걸리고, PR은 사람이 따로 검토해서 끈다
disabled_rules = "R2b, done.pr"
```

쉼표로 여럿 적을 수 있고 대소문자를 가리지 않는다. 적을 수 있는 이름은 이렇다.

| 게이트 | 이름 | 끄면 멈추는 것 |
|---|---|---|
| 근거 | `R0`·`R1`·`R2a`·`R2b`·`R3`·`R4`·`R5` | 그 규칙 하나 |
| 완료 | `done.turn` | 코드를 고친 턴 끝의 검사 |
| | `done.commit` | 커밋 직전의 전체 검사 |
| | `done.pr` | PR 본문의 근거 검사 |
| 테스트 무결성 | `ti.skip` | 무력화 표기 추가 차단 |
| | `ti.assert` | 단언 감소 차단 |
| | `ti.rm` | 테스트 파일 삭제 차단 |
| | `ti.exclude` | 러너 설정의 제외 추가 차단 |
| 프로젝트 가드 | `pg.noverify` | `--no-verify` 커밋 차단 |

append-only에는 이름이 없다. `append_only`를 적지 않으면 원래 꺼져 있다.

**환경변수 대신 파일에 두는 이유가 요점이다.** `NGG_DONE=0` 같은 환경변수는 그 게이트의 검사를 한꺼번에 끄고, 누가 자기 셸에 박아 두면 팀은 그 사실을 모른다. `.checked-practices.toml`은 저장소에 커밋되므로 PR에 보이고, 왜 껐는지 같은 커밋에 적힌다. 끄는 것을 쉽게 만드는 장치가 아니라 **끄는 행위를 보이게 만드는 장치**다. 환경변수는 급할 때 쓰는 스위치로 남겨 두었다.

껐다는 사실은 세 곳에 남는다.

- `events.log`에 `off=[R2b]`, `off=[done.pr]`
- 세션마다 저장소 프로필이 `끈 규칙: R2b, done.pr`를 컨텍스트에 싣는다
- 없는 이름을 적으면 어느 게이트든 막을 때 stderr로 알린다. 껐다고 믿는데 안 꺼진 상태가 제일 나쁘다

설정은 게이트가 막거나 검사를 돌리기 직전에만 읽는다. 그냥 지나가는 도구 호출에는 비용이 붙지 않는다.

## 한 번만 허용하기

설정으로 끄면 그 검사는 계속 꺼져 있다. 오탐 한 건만 넘기고 싶을 때는 다음 프롬프트에 이렇게 한 줄을 쓴다.

```
checked-practices allow ti.skip
```

그 턴 안에서 해당 검사가 **한 번** 통과하고 허용은 바로 사라진다. 쓰지 않은 허용도 다음 프롬프트가 오면 사라진다. 게이트가 막을 때 무엇을 쓰면 되는지 항목 이름과 함께 알려 준다.

- **사람만 쓸 수 있다.** 허용은 `UserPromptSubmit` 훅이 사용자 프롬프트에서만 읽는다. 모델이 답에 같은 글을 적어도 풀리지 않는다. 백그라운드 작업 알림도 사람의 프롬프트로 치지 않는다.
- **줄 첫머리에 와야 한다.** 문장 가운데 적은 것은 인용으로 본다. 대소문자를 가리지 않고 쉼표로 여럿 적을 수 있다.
- **이름은 위 표의 게이트 항목뿐이다.** 근거 게이트의 `R0`~`R5`는 대상이 아니다. 근거 게이트에는 확인할 수 없는 이유를 밝히면 풀리는 면제가 따로 있다.
- 통과시킨 사실은 `events.log`에 `allowed=[ti.skip]`으로 남는다.

Probity의 `enforceTdd`에서 가져온 방식이다. "reply in the session asking for the change to be let through, and it's allowed on the next attempt."

## 완료 게이트: 검사가 통과해야 턴이 끝난다

코드 파일을 고친 턴은 저장소의 검사를 실제로 돌린 뒤에야 끝난다. 공식 문서가 지정한 방법 그대로다.

> "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes."
> (결정적 게이트로: Stop 훅이 검사를 스크립트로 돌리고, 통과할 때까지 턴이 끝나는 것을 막는다.)

검사 명령은 이 순서로 찾는다.

| 순서 | 출처 |
|---|---|
| 1 | 저장소 루트의 `.checked-practices.toml`에 적은 `test_command` |
| 2 | `package.json`의 `scripts.test` → `npm test` |
| 3 | `Makefile`의 `test` 타깃 → `make test` |
| 4 | `pyproject.toml` → `python3 -m pytest -q` |

```toml
# .checked-practices.toml
fast_test_command = "npm test -- --changed"   # 턴 끝에는 이것만
test_command      = "npm test"                # 커밋 직전에 이것
```

**턴마다 전체 스위트를 돌리지 않는다.** 공식 CLAUDE.md 예시가 그렇게 권한다. "Prefer running single tests, and not the whole test suite, for performance." `fast_test_command`을 적으면 턴 끝에는 그것만 돌리고 전체는 `git commit` 직전에 한 번 돌린다. 나누지 않으면 `test_command` 하나로 둘 다 한다. 검사가 30초를 넘으면 나누라고 알려 준다.

설계 원칙 셋이다. **모르는 것으로 막지 않는다** — 검사 명령을 못 찾으면 알리고 통과시킨다. **조용히 실패하지 않는다** — 시간을 넘기면 그 사실을 알리고 막지 않는다. **코드가 아닌 변경은 대상이 아니다** — 문서만 고친 턴은 검사하지 않고, 저장소 밖 파일도 세지 않는다.

끄려면 `NGG_DONE=0`, 제한 시간은 `DONE_TIMEOUT`(기본 180초)이다.

이 저장소도 스스로에게 적용한다. `.checked-practices.toml`이 자기 테스트를 가리키고 있어서, 훅을 고치면 훅이 자기를 검사한다.

### PR 본문에 근거가 있어야 PR을 연다

`gh pr create` 직전에 본문을 본다. 돌린 명령과 그 출력이 없으면 PR을 열지 못한다. 공식 문서가 근거로 드는 것이 바로 그것이다.

> "Have Claude show evidence rather than asserting success: the test output, the command it ran and what it returned, or a screenshot of the result."
> (성공을 주장하는 대신 근거를 보여 주게 하라. 테스트 출력, 돌린 명령과 그 결과, 또는 결과 스크린샷이다.)

근거로 치는 것은 **닫힌 코드 블록**(여는 줄과 닫는 줄이 다 있는 것)이나 **이미지**다. 본문은 `--body`, `--body-file`, `-F -`로 넘긴 heredoc에서 읽는다. 에이전트가 흔히 쓰는 `--body "$(cat <<'EOF' … EOF)"` 모양도 읽는다.

| 경우 | 판정 |
|---|---|
| 본문에 코드 블록이나 이미지가 있다 | 통과 |
| 본문이 "테스트 전부 통과했습니다"뿐이다 | 막는다 |
| 기준 브랜치 대비 코드 파일을 바꾸지 않았다(문서만) | 통과 |
| `--fill`·`--web`처럼 본문이 명령에 없다 | 통과. 볼 수 없는 것으로 막지 않는다 |
| 커밋 메시지나 문서 안에 `gh pr create`라고 적었다 | 통과. 인용은 사용이 아니다 |
| 기준 브랜치를 찾지 못했다 | 코드를 바꿨는지 모르므로 본문만 보고 판정한다 |

기준 브랜치는 `--base`가 있으면 그것을 쓴다. 없으면 `origin/HEAD` → `origin/main` → `origin/master` → `main` → `master` 순으로 찾는다. 로컬 git만 쓰고 네트워크에는 나가지 않는다.

**형식만 본다.** 붙인 출력이 실제로 돌린 결과인지는 가리지 못한다. 막힌 모델에게 돌리지 않은 출력을 지어내지 말라고 알리는 데서 그친다. `gh pr edit --body`로 본문을 나중에 바꾸는 것도 보지 않는다.

한 줄짜리 코드 수정도 대상이다. 작은 수정은 제목만으로 PR을 여는 관행과 부딪히는 자리인데, 코드를 바꿨으면 검사 출력 한 블록은 붙이는 쪽을 택했다. 문서만 바꾼 PR은 걸리지 않는다.

이 검사만 끄려면 `disabled_rules`에 `done.pr`을 적는다. 완료 게이트 전체는 `NGG_DONE=0`으로 끈다.

## 테스트 무결성 게이트: 테스트가 아니라 코드를 고친다

Kent Beck이 에이전트의 부정행위로 지목한 것을 그대로 막는다.

> "Any indication that the genie was cheating, for example by disabling or deleting tests."
> (지니가 속임수를 쓴다는 낌새, 예컨대 테스트를 비활성화하거나 지우는 것.)

막는 것은 셋뿐이다. 테스트 파일에 **무력화 표기가 늘어날 때**(`.skip(`, `.only(`, `xit(`, `@pytest.mark.skip`, `#[ignore]`, `t.Skip(` 등), **단언이 줄어들 때**, 그리고 **테스트 파일을 지우는 명령**이다.

**테스트 러너 설정도 본다.** `jest.config.*`·`vitest.config.*`·`pytest.ini`·`pyproject.toml`·`.mocharc.*` 같은 파일에서 제외 지시어(`testPathIgnorePatterns`, `--ignore=`, `exclude`, `norecursedirs` 등)가 **늘면** 막는다. 테스트 파일을 건드리지 않고 설정으로 테스트를 빼는 길이 있었다. EvilGenie(arXiv [2511.21654](https://arxiv.org/abs/2511.21654))가 "Modified Testing Procedures"로 분류한 행동이다. 제외를 줄이거나 그와 무관한 편집은 통과한다.

**테스트 수정 전반을 막지 않는다.** 기댓값을 고치거나 단언을 더하는 것은 통과한다. TDD는 테스트를 먼저 쓰고 고치는 방법론이라, 그것까지 막으면 문서가 권하는 바와 반대로 간다. 끄려면 `NGG_TESTGUARD=0`이다.

## 프로젝트 가드: 지난 기록은 고치지 않는다

공식 문서의 훅 예시가 가리키는 자리다.

> "Write a hook that blocks writes to the migrations folder."

이 가드는 그보다 정밀하다. **새 파일 추가는 허용하고 기존 파일의 수정·삭제만 막는다.** 마이그레이션은 계속 써야 하기 때문이다.

```toml
# .checked-practices.toml
append_only = "supabase/migrations, db/migrate"
```

설정이 없으면 아무것도 막지 않는다. `git commit --no-verify`는 **건너뛸 커밋 훅이 실제로 있을 때만** 막는다(`.checked-practices.toml`, `.husky/pre-commit`, `.git/hooks/pre-commit`, `core.hooksPath` 중 하나). 설치만 했는데 남의 저장소의 git 동작이 바뀌면 과하기 때문이다. 끄려면 `NGG_GUARD=0`이다.

## 저장소 프로필: 세션마다 사실을 실어 준다

게이트는 무엇을 막을지 알아야 하고, Claude는 이 저장소에서 무엇을 돌려야 하는지 알아야 한다. 세션이 시작될 때 `SessionStart` 훅이 스무 줄 안팎의 사실을 컨텍스트에 넣는다.

```
[checked-practices 프로필] checked-practices  (브랜치 main)
패키지 매니저: pnpm
스택: next, react, typescript, vitest
검사 명령: pnpm test   (출처: package.json scripts.test → vitest run)
append-only 경로: supabase/migrations
게이트: 근거(항상) · 완료(켜짐) · 테스트 무결성(항상) · 프로젝트 가드(켜짐)
```

공식 문서가 이 이벤트의 stdout을 컨텍스트로 넣는다고 밝힌다. "The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`, where Claude Code adds plain-text stdout as context that Claude can see and act on."

**싣는 것은 사실뿐이고 행동 지시는 넣지 않는다.** 그건 게이트의 일이다. 모델을 부르지 않고 파일만 읽으며, `.env` 같은 비밀 파일의 값은 읽지 않는다. 마지막 줄이 어느 게이트가 놀고 있는지 알려 주므로 설정을 빼먹으면 바로 보인다. 끄려면 `NGG_PROFILE=0`이다.

## 얼마나 느려지나

설치하면 매 턴에 비용이 붙는다. 숨기지 않고 적는다. macOS(arm64), bash 3.2, python 3.13 에서 훅마다 같은 입력으로 20회씩 돌린 중앙값이다. 측정 스크립트는 [V38](VERIFICATION.md)에 있다.

| 훅 | 언제 도나 | 실측 |
|---|---|---|
| `no-guess-gate/prompt.sh` | 턴마다 1회 | 51ms |
| `no-guess-gate/stop.sh` | 턴 끝 | 161ms |
| `done-gate/stop.sh` | 턴 끝 | 44ms |
| `no-guess-gate/pre.sh` | 도구 호출마다 | 17ms |
| `test-integrity/pre.sh` | Edit·Write·Bash마다 | 46ms. 삭제 글자가 없는 Bash는 12ms |
| `project-guard/pre.sh` | Edit·Write·Bash마다 | 41ms. 삭제·이동·커밋 글자가 없는 Bash는 13ms |
| `done-gate/pre.sh` | Bash마다 | 커밋·PR 생성이 아니면 12ms |
| `no-guess-gate/bashres.sh` | Bash마다 | 17ms |
| `done-gate/post.sh` | Edit·Write마다 | 44ms |
| `repo-profile/session.sh` | 세션 1회 | 65ms |

**턴마다 붙는 바닥은 약 256ms**(`prompt` + `stop` 둘)다. 도구를 쓸 때 더 붙는 비용은 도구마다 다르다. Bash 한 번에 약 70ms다. 삭제·이동·커밋·PR 생성 명령이면 훅이 끝까지 검사해서 약 170ms가 된다. Edit·Write 한 번에 약 155ms, 그 밖의 도구 한 번에 17ms다. Bash 쪽 훅 셋은 도구 이름과 관련 글자를 먼저 보고 관계없는 명령에서는 파이썬을 띄우지 않는다(V40). 세션을 열 때 65ms가 한 번 든다.

처음 잰 V28에서는 바닥이 326ms였다. 같은 스크립트로 v1.5.0을 번갈아 재니 258ms가 나왔다. 숫자가 줄어든 것은 코드 때문이 아니고 측정 조건이 달라서다. 1.6.0에서 기능을 넷 더했지만 훅별 차이는 5ms 안이었다.

짧은 프롬프트 하나로 세션 전체를 재면 훅 없이 1,416ms, 켜고 2,367ms였다(V28, 각 3회 중앙값). 이 값은 다시 재지 않았다.

비용의 대부분은 파이썬 기동이다. `stop.sh` 는 파이썬을 3회 부르고 기동만 회당 26.9ms다(V28). 하나로 합치면 50ms 안팎을 줄일 수 있지만, 판정의 입력을 만드는 자리라 아직 손대지 않았다.

느리면 `NGG_PROFILE=0` 으로 프로필을 끄고, 게이트별로 `NGG_DONE=0`·`NGG_TESTGUARD=0`·`NGG_GUARD=0` 을 쓸 수 있다.
## 커맨드 여덟

게이트는 저절로 돌지만, 언제 할지와 비용을 내가 정해야 하는 일은 커맨드로 둔다. 전부 **내가 쳐야만** 돈다(`disable-model-invocation: true`). 공식 문서가 그렇게 권한다. "Use `disable-model-invocation: true` for workflows with side effects that you want to trigger manually."

| 커맨드 | 하는 일 |
|---|---|
| `/checked-practices:spec` | 큰 기능 전에 `AskUserQuestion`으로 나를 인터뷰해 `SPEC.md`를 쓴다 |
| `/checked-practices:init` | 검사 명령을 실제로 돌려 보고 `.checked-practices.toml`에 확정. 기준선·append-only·비밀 파일 차단 제안 |
| `/checked-practices:tdd` | 실패 테스트 먼저, RED 확인, 최소 구현 |
| `/checked-practices:ship` | 검사를 돌리고 그 출력을 PR 본문에 근거로 넣는다 |
| `/checked-practices:handoff` | 다음 세션이 읽을 인수인계를 쓴다 |
| `/checked-practices:status` | 게이트 상태를 전부 실측해 보고한다 |
| `/checked-practices:auto` | 탐색 → 계획 → 구현 → 검토 → 배포를 순서대로 |
| `/checked-practices:config` | 게이트 항목마다 무엇을 막고 어디서 온 규칙인지 보여 주고, 끌 것을 골라 `disabled_rules`에 적는다 |

**커맨드는 내가 쓴 언어로 답한다.** `SKILL.md`는 로케일로 가를 수 없는 파일이라 영어로 쓰고, 본문에 사용자의 언어로 답하라는 지시를 박아 두었다. 게이트 문장이 `msg.sh`에서 갈리는 것과 같은 원칙이다.

**없는 커맨드가 더 많다.** 계획은 내장 plan mode가, 탐색은 내장 Explore가, 리뷰는 `/code-review`가, 실행 확인은 `/verify`가, 반복은 `/goal`이 이미 한다. 전수 조사에서 23개 후보를 7개로 줄였고, 검사를 고르는 `config`를 뒤에 더했다. 같은 일을 하는 것을 새로 만들지 않는다.

## 근거

규칙마다 어디서 왔는지 밝힌다. 링크 없는 규칙은 두지 않는다.

| 문서 | 가져온 것 |
|---|---|
| [Reduce hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) | R0·R1·R2a·R2b·R4와 면제. "If it can't find a quote, it must retract the claim" (인용을 못 찾으면 그 주장을 철회해야 한다). R2a는 "Allow Claude to say I don't know"(모른다고 말하게 하라)에 맞춰 도구를 한 번도 안 쓴 경우로 좁혔다 |
| [Best practices](https://code.claude.com/docs/en/best-practices) | R3, 완료 게이트의 Stop 훅 방식, PR 본문 검사(`done.pr`). "Have Claude show evidence rather than asserting success" (성공을 주장하는 대신 근거를 보여 주게 하라) |
| [Hooks](https://code.claude.com/docs/en/hooks) · [Hooks guide](https://code.claude.com/docs/en/hooks-guide) | exit 2 차단, 8회 상한, 타임아웃, 판단이 필요한 결정은 모델에게. R5가 실패한 명령을 알아내는 `PostToolUseFailure` 이벤트 |

훅을 쓰는 이유도 문서에 있다.

> "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens."
> (권고에 그치는 CLAUDE.md 지시와 달리, 훅은 결정적이고 그 동작이 반드시 일어나게 보장한다.)

## 개발

```bash
claude --plugin-dir .                         # 설치본 대신 이 폴더를 그 세션에 로드
claude plugin validate .                      # 매니페스트와 훅 배선 검사
for g in lib no-guess-gate done-gate test-integrity project-guard repo-profile; do
  hooks/$g/unit.sh || break; done && tests/skills-unit.sh    # 합계 252건. 모델을 부르지 않는다
tests/fuzz.sh                                 # 망가진 입력 24종 × 훅 열 = 240회 = 216회
tests/no-guess-gate/selftest.sh               # 실제 프롬프트 회귀 12케이스, 몇 분
tests/no-guess-gate/judge-accuracy.sh         # 판정기 정확도·소요 시간, 몇 분
shellcheck -x -s bash hooks/*/*.sh skills/unit.sh
```

게이트가 내보내는 문장은 훅이 아니라 `plugin/hooks/lib/msg.sh` 한 곳에 있다. 새 문장은 한국어와 영어를 함께 넣는다. 한쪽만 넣으면 `tests/lib/unit.sh`가 잡는다.

모든 검증은 실행 명령과 출력 원문을 [`docs/VERIFICATION.md`](VERIFICATION.md)에 남긴다. 기여는 [CONTRIBUTING.md](../CONTRIBUTING.md), 보안은 [SECURITY.md](../SECURITY.md)를 보라.
