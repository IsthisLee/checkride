# check

Claude Code 공식 문서가 권하는 모범 사례를 지켰는지 **턴마다 검사한다.** 설치하면 `settings.json`도 `CLAUDE.md`도 그대로다. 검사는 걸릴 때만 나타난다.

## 지금 설치된 것

파일 25개다. 실제로 도는 것은 훅 열과 커맨드 여덟뿐이다.

| 검사하는 모범 사례 | 게이트가 보는 것 | 끄기 |
|---|---|---|
| 근거 없이 주장하지 않는다 | 도구를 안 쓰고 상태를 단정하거나, 확인을 미루거나, 실패한 명령을 통과라고 주장하는 턴(R0~R5). 이번 세션에 읽지 않은 기존 파일을 Write로 통째로 덮어쓰기(`rb.write`) | `.check.toml`의 `disabled_rules`로 규칙별(`R0`~`R5`·`rb.write`), `NGG_JUDGE=0`은 의미 판정만 |
| 성공을 주장하지 말고 근거를 보여 준다 | 코드를 고친 턴이 저장소 검사를 통과하지 않은 채 끝나는 것, 돌린 명령과 출력 없이 여는 PR | `disabled_rules`에 `done.turn`·`done.commit`·`done.pr`, 전체는 `NGG_DONE=0` |
| 테스트를 비활성화하거나 지우지 않는다 | `.skip` 추가, 단언 감소, 테스트 파일 삭제, 러너 설정에 제외 추가 | `disabled_rules`에 `ti.skip`·`ti.assert`·`ti.rm`·`ti.exclude`, 전체는 `NGG_TESTGUARD=0` |
| 쌓인 기록은 고치지 않는다 | `append_only` 경로의 기존 파일 수정·삭제, 커밋 훅을 건너뛰는 `--no-verify` 커밋 | `disabled_rules`에 `pg.noverify`, 전체는 `NGG_GUARD=0` |

넷 다 이 플러그인이 정한 규칙이 아니다. 어느 문장에서 왔는지는 저장소의 근거 표에 있다.

오탐 한 건만 넘기려면 다음 프롬프트에 `check allow <항목>`을 한 줄로 쓴다. 한 번 통과하고 사라진다.

세션마다 저장소 사실을 컨텍스트에 싣는 프로필도 있다(`NGG_PROFILE=0`).

## 커맨드 여덟

전부 **직접 쳐야만** 돈다. Claude가 알아서 부르지 않는다.

`/check:init` · `config` · `spec` · `tdd` · `ship` · `handoff` · `status` · `auto`

어떤 검사를 강제할지 고르려면 `/check:config`를 친다. 항목마다 출처를 보여 주고 고른 것만 끈다.

막힌 이유가 궁금하면 `/check:status`가 최근 판정을 보여 준다.

커맨드는 **내가 쓴 언어로 답한다.** 게이트 문장이 로케일을 따르는 것과 같다.

## 처음 할 일

```
/check:init
```

검사 명령을 찾아 `.check.toml`에 확정하고 `append_only` 경로를 제안한다. 쓰기 전에 물어본다.

## 메시지 언어

`NGG_LANG=ko` 또는 `en`. 주지 않으면 `.check.toml`의 `lang`을 보고, 그것도 없으면 `LC_ALL` → `LC_MESSAGES` → `LANG` 순으로 보고 `ko` 계열일 때만 한국어다. 저장소마다 정하려면 `.check.toml`에 `lang`을, 모든 저장소에 걸려면 `~/.claude/settings.json`의 `env`에 `NGG_LANG`을 둔다. `/check:config`로 둘 다 고를 수 있다.

## 끄기

```
claude plugin disable check@did-you-check --scope project
```

상태는 `~/.claude/plugins/data/check-did-you-check/`에 있고 지워도 된다.

## 더 읽기

전체 문서, 규칙마다의 근거, 실측 기록은 저장소에 있다.

**https://github.com/IsthisLee/did-you-check**

설치한 코드를 직접 확인하는 법은 [SECURITY.md](https://github.com/IsthisLee/did-you-check/blob/main/SECURITY.md)에 있다. 릴리스 태그는 서명돼 있다.

---

## English

Checks, every turn, whether the best practices the Claude Code docs recommend were actually followed. Your `settings.json` and `CLAUDE.md` are not touched.

25 files. Four gates run on `Stop` and `PreToolUse`, plus a session repo profile and eight user-only commands. Pick which checks to enforce with `/check:config`.

| Practice checked | What the gate looks at | Off switch |
|---|---|---|
| Never claim what you did not check | Asserting state with no tool call, deferring, or claiming a failed command passed (R0–R5). Overwriting an existing file with Write before reading it this session (`rb.write`) | `R0`–`R5` and `rb.write` in `disabled_rules`; `NGG_JUDGE=0` for the semantic judge only |
| Show evidence instead of asserting success | A turn that changed code ending before the repo check passes, and a PR opened with no command output in its body | `done.turn`, `done.commit`, `done.pr` in `disabled_rules`; `NGG_DONE=0` for all |
| Never disable or delete a test | Adding `.skip`, dropping assertions, deleting tests, adding runner-config exclusions | `ti.skip`, `ti.assert`, `ti.rm`, `ti.exclude` in `disabled_rules`; `NGG_TESTGUARD=0` for all |
| Never rewrite what already landed | Editing or deleting existing files under `append_only`, commits that skip the commit hooks | `pg.noverify` in `disabled_rules`; `NGG_GUARD=0` for all |

To get past one false positive, write `check allow <item>` on its own line in your next prompt; it lets one action through and is gone.

Start with `/check:init`. Ask `/check:status` when something blocks you.

Messages follow your locale; `NGG_LANG=ko|en` overrides. Full docs, the source for every rule, and the measurement log: **https://github.com/IsthisLee/did-you-check**
