# checkride: 게이트와 커맨드 상세

README는 짧게 두고 자세한 내용은 이 문서에 적습니다. 각 게이트가 무엇을 어떻게 막는지, 무엇으로 끄는지, 근거가 어느 문서인지를 다룹니다.

> 게이트를 **왜** 이렇게 만들었는지, 어떤 대안을 버렸는지, 그 판단이 어떤 출처에 기댔는지는 [설계 결정](decisions.md)에 정리했습니다.

## 목차

- [개발을 몰라도 되는 설명](#개발을-몰라도-되는-설명)
- [언제 무엇이 도나](#언제-무엇이-도나)
  - [R0~R5는 매 턴 다 보지 않습니다](#r0r5는-매-턴-다-보지-않습니다)
  - [규칙을 보기 전에 빠지는 면제](#규칙을-보기-전에-빠지는-면제)
  - [훅 열두 개가 각각 하는 일](#훅-열두-개가-각각-하는-일)
- [의미 판정기 설정](#의미-판정기-설정)
  - [메시지 언어](#메시지-언어)
  - [왜 내장 `type: "prompt"` 훅을 쓰지 않나](#왜-내장-type-prompt-훅을-쓰지-않나)
- [항목 하나만 끄기](#항목-하나만-끄기)
- [한 번만 허용하기](#한-번만-허용하기)
- [완료 게이트: 검사가 통과해야 턴이 끝납니다](#완료-게이트-검사가-통과해야-턴이-끝납니다)
  - [PR 본문에 근거가 있어야 PR을 엽니다](#pr-본문에-근거가-있어야-pr을-엽니다)
- [테스트 무결성 게이트: 테스트가 아니라 코드를 고칩니다](#테스트-무결성-게이트-테스트가-아니라-코드를-고칩니다)
- [프로젝트 가드: 지난 기록은 고치지 않습니다](#프로젝트-가드-지난-기록은-고치지-않습니다)
- [저장소 프로필: 세션마다 사실을 실어 줍니다](#저장소-프로필-세션마다-사실을-실어-줍니다)
- [얼마나 느려지나](#얼마나-느려지나)
- [커맨드 여덟 개](#커맨드-여덟-개)
- [근거](#근거)
- [개발](#개발)

## 개발을 몰라도 되는 설명

Claude Code는 코드를 대신 써 주는 AI 조수입니다. 일은 잘합니다. 그런데 가끔 서류를 열어 보지도 않고 "그런 건 없습니다"라고 하고, 검사를 돌리지도 않고 "다 끝냈습니다"라고 합니다.

사람이 그러면 "확인은 했어요?"라고 되물으면 됩니다. 문제는 **매번** 되물어야 한다는 점입니다. 사람은 언젠가 깜빡하고, 깜빡한 그날 사고가 납니다.

이 플러그인은 그 되묻기를 자동으로 만듭니다. 안전벨트를 매지 않으면 차에서 경고음이 나는 것과 같습니다. 운전자가 기억할 필요가 없고, 기억하지 못해도 괜찮습니다.

## 언제 무엇이 도나

게이트 네 개와 저장소 프로필은 서로 다른 훅 이벤트에 걸립니다. **Stop(턴 끝)에서 도는 것은 근거 게이트와 완료 게이트 두 개뿐입니다.** 테스트 무결성과 프로젝트 가드는 턴이 끝날 때가 아니라 편집·Bash를 실행하려는 순간에만 막습니다. 배선은 `plugin/hooks/hooks.json`에 있습니다.

| 이벤트 | 근거 게이트 | 완료 게이트 | 테스트 무결성 | 프로젝트 가드 | 저장소 프로필 |
|---|---|---|---|---|---|
| `SessionStart` | | | | | 저장소 사실을 컨텍스트에 싣습니다 |
| `UserPromptSubmit` | `check allow`를 읽습니다 | | | | |
| `PreToolUse` | 모든 도구의 이름을 남깁니다(막지 않습니다) | Bash | Edit·Write·Bash | Edit·Write | |
| `PostToolUse` | Bash 결과를 S/F로 남깁니다 | Edit·Write | | | |
| `PostToolUseFailure` | Bash 실패를 남깁니다 | | | | |
| `Stop` | R0~R5 | 검사 명령 | | | |
| `SubagentStop` | R0~R5 | | | | |

### R0~R5는 매 턴 다 보지 않습니다

근거 게이트의 Stop 규칙은 조건이 맞는 것만 봅니다. 대부분 **이 턴에 도구를 쓰지 않았을 때**만 걸립니다.

| 규칙 | 언제 검사하나 |
|---|---|
| R0 · R1 | 이 턴에 도구 호출이 0건일 때만 |
| R2a | 도구 호출이 0건이고, 코드베이스 맥락(프롬프트가 저장소·파일을 묻거나, 답에 경로나 "여기 있는 파일" 같은 표현이 있음)일 때만 |
| R3 | Bash 실행이 0건일 때만 |
| R5 | 마지막으로 돌린 Bash가 실패(F)했을 때만 |
| R2b | 도구 호출이 0건이고 코드베이스 맥락일 때만 |

R4(막힌 뒤 도구 없이 다시 끝내면 막음)는 출처 문서와 맞지 않아 뺐습니다. 다시 쓴 답도 위 규칙으로만 판정합니다. 이유는 [설계 결정](decisions.md#6-근거가-없는-규칙은-뺐습니다)에 있습니다.

그래서 도구를 쓰고 근거를 붙여 답한 흔한 턴에서는 걸릴 것이 없어 그대로 통과합니다.

### 규칙을 보기 전에 빠지는 면제

Stop 훅은 규칙을 따지기 전에 두 가지를 먼저 봅니다. 하나라도 맞으면 규칙을 아예 보지 않습니다.

- 답이 질문형이거나, 이 턴에 `AskUserQuestion`을 쓴 경우입니다. 묻는 것은 언제나 허용합니다.
- 판정기가 띄운 중첩 세션인 경우입니다. 게이트가 자기 안에서 또 돌지 않게 막습니다.

규칙을 본 뒤 풀어 주는 면제(불가·JSON·인용·의견)는 [README](../README.md#걸리지-않는-것)에 있습니다.

### 훅 열두 개가 각각 하는 일

배선은 `plugin/hooks/hooks.json`에 있고, 훅은 모두 12개입니다. 하는 일은 **막음**과 **기록**으로 나뉩니다. 기록하는 훅은 막지 않고, 막는 훅이 판정할 때 쓸 정보만 남깁니다. `Stop`(턴 끝)에서 막는 것은 근거 게이트와 완료 게이트 두 개뿐이고, 테스트 무결성과 프로젝트 가드는 편집이나 Bash를 실행하려는 순간(`PreToolUse`)에만 막습니다.


| 게이트 | 이벤트(대상 도구) | 스크립트 | 하는 일 |
| --- | --- | --- | --- |
| **근거** | `UserPromptSubmit` | `no-guess-gate/prompt.sh` | **기록**: 사용자가 보낸 질문을 저장합니다. 턴 끝에 "이 질문이 저장소나 파일을 물었는지" 판단할 때 씁니다. 새 턴이 시작되면 쓴 도구 기록을 비웁니다.<br>줄 첫머리에 `check allow <항목>`이 있으면 그 항목을 이번 한 번만 통과시키도록 적어 둡니다. 사람이 쓴 프롬프트에서만 읽습니다 |
| | `PreToolUse`(모든 도구) | `no-guess-gate/pre.sh` | **기록**: Claude가 이번 턴에 어떤 도구(Read, Grep, Bash 등)를 썼는지 남깁니다. 턴 끝에 "확인하지 않고 답했는지" 판단하는 근거가 됩니다. 막지는 않습니다 |
| | `PostToolUse`·`PostToolUseFailure`(Bash) | `no-guess-gate/bashres.sh` | **기록**: 명령이 성공했는지 실패했는지 순서대로 남깁니다. 마지막 명령이 실패했는데 "통과했다"고 답하면 R5가 이 기록으로 잡습니다 |
| | `Stop`·`SubagentStop` | `no-guess-gate/stop.sh` | **막음**: Claude가 답을 마치려는 순간 답을 검사해, 아래 경우면 턴을 끝내지 못하게 합니다. 서브에이전트가 끝날 때도 같습니다.<br>· R0: 저장소·파일 상태를 물었는데 도구를 하나도 쓰지 않고 답함<br>· R1: 확인하지 않고 파일이 있다·없다고 단정함<br>· R2a·R2b: 도구 없이 "확인이 필요합니다"로 미루거나 "아마 ~일 겁니다"로 추측함<br>· R3: 명령을 하나도 돌리지 않고 "테스트 통과했습니다"라고 함<br>· R5: 마지막 명령이 실패했는데 통과했다고 함<br>확인할 수 없는 이유를 밝히거나 사용자에게 되물으면 막지 않습니다 |
| **완료** | `PreToolUse`(Bash) | `done-gate/pre.sh` | **막음**: `gh pr create` 직전에 PR 본문을 봅니다. "통과했습니다"처럼 성공을 주장하는데 실행한 명령과 출력(코드 블록)이나 스크린샷이 없으면 PR을 열지 못합니다(`done.pr`).<br>**막음**: `git commit` 직전에 전체 검사(`test_command`)를 돌려, 실패하면 커밋하지 못합니다(`done.commit`). 턴 끝 검사를 `fast_test_command`로 따로 나눈 저장소에서만 돕니다 |
| | `PostToolUse`(Edit·Write) | `done-gate/post.sh` | **기록**: 이번 턴에 고친 파일 경로를 남깁니다. 턴 끝에 코드 파일을 고쳤는지 판단할 때 씁니다 |
| | `Stop` | `done-gate/stop.sh` | **막음**: 이번 턴에 코드 파일을 고쳤다면 저장소의 검사 명령을 실제로 돌리고, 실패하면 턴을 끝내지 못하게 합니다(`done.turn`). 문서만 고친 턴은 돌리지 않습니다.<br>검사 명령은 `.check.toml` → `package.json` → `Makefile` → `pyproject.toml` 순으로 찾고, 못 찾거나 시간을 넘기면 알리기만 하고 막지 않습니다 |
| **테스트 무결성** | `PreToolUse`(Edit·Write·Bash) | `test-integrity/pre.sh` | **막음**: 테스트를 통과시키려고 테스트 쪽을 손대는 편집을 실행 전에 막습니다.<br>· `.skip(`·`.only(`·`xit(`·`@pytest.mark.skip` 같은 끄기 표기를 늘릴 때(`ti.skip`)<br>· `expect(`·`assert` 같은 단언을 줄일 때(`ti.assert`)<br>· `rm`·`git rm`으로 테스트 파일을 지울 때(`ti.rm`)<br>· jest·vitest·pytest 설정에 테스트 제외 패턴을 늘릴 때(`ti.exclude`)<br>기댓값을 고치거나 단언을 더하는 편집은 막지 않습니다 |
| **프로젝트 가드** | `PreToolUse`(Edit·Write) | `project-guard/pre.sh` | **막음**: `.check.toml`의 `append_only`에 적은 경로(예: 마이그레이션 폴더)에서 이미 있는 파일을 고치려 하면 막습니다. 새 파일을 추가하거나 파일을 지우는 것은 막지 않습니다. `append_only`를 적지 않으면 아무것도 막지 않습니다 |
| 저장소 프로필(게이트 아님) | `SessionStart` | `repo-profile/session.sh` | **싣기**: 세션을 열 때 패키지 매니저, 스택, 검사 명령, append-only 경로, 끈 규칙, 게이트별 동작 상태를 스무 줄 안팎으로 Claude에게 알려 줍니다. 사실만 싣고 지시는 넣지 않으며, 막지 않습니다 |


스크립트 경로는 `plugin/hooks/` 기준입니다. 의미 판정기 `judge.py`는 훅이 아닙니다. `stop.sh`가 R2a·R2b만 걸렸을 때 부르는 스크립트입니다.

## 의미 판정기 설정

근거 게이트는 R2a·R2b만 걸렸을 때 작은 모델에게 그 문장이 의견인지 상태 주장인지 묻습니다. 판정기는 풀어 줄 수만 있고 새로 막지는 못합니다. 규칙과 면제는 [README](../README.md#무엇이-막히나)에 있습니다.

| 환경변수 | 기본값 | 뜻 |
|---|---|---|
| `NGG_JUDGE` | `1` | `0`이면 판정을 아예 하지 않습니다 |
| `NGG_JUDGE_MODEL` | `haiku` | 판정 모델입니다. 분류 한 번이라 큰 모델이 필요 없지만 바꿀 수 있습니다 |
| `NGG_JUDGE_CMD` | (없음) | 판정 명령 전체를 다른 것으로 바꿉니다. 이 값을 주면 모델 설정은 무시됩니다 |
| `NGG_JUDGE_TIMEOUT` | `40` | 초 |

### 메시지 언어

게이트가 내보내는 문장은 한국어와 영어 두 벌입니다. 규칙 판정은 언어와 상관없이 같습니다.

| 환경변수 | 기본값 | 뜻 |
|---|---|---|
| `NGG_LANG` | (로케일) | `ko` 또는 `en`입니다. 이 값을 주면 다른 설정을 모두 무시합니다 |

`NGG_LANG`이 없으면 저장소 루트 `.check.toml`의 `lang`을 보고, 그것도 없으면 `LC_ALL` → `LC_MESSAGES` → `LANG` 순으로 봅니다. `ko` 계열이면 한국어, 그 밖에는 영어로 냅니다. 문장은 `plugin/hooks/lib/msg.sh` 한 곳에 모여 있습니다.

### 왜 내장 `type: "prompt"` 훅을 쓰지 않나

Claude Code에는 판단이 필요한 자리에 쓰는 [프롬프트 훅](https://code.claude.com/docs/en/hooks)이 있습니다. 셸 명령 대신 모델에게 묻고 `{"ok": bool, "reason": …}`을 받습니다. 이 플러그인이 `judge.py`로 만든 것과 같은 일입니다. 그런데도 쓰지 않는 이유는 **언제 부르느냐**가 다르기 때문입니다.

| 방식 | 언제 도나 | 턴당 비용 |
|---|---|---|
| `type: "prompt"` Stop 훅 | **모든 턴** | 실측 +1.6초 (기준선 4.8초 → 6.4초) |
| 이 플러그인(정규식 + `judge.py`) | 차단의 약 4% | 걸릴 때만 중앙값 8초, 나머지 턴은 0 |

정규식이 비용 없이 바닥을 깔고, 모델은 드물게 부릅니다. 프롬프트 훅으로 옮기면 아무 일 없는 턴까지 느려집니다. `ok:false`로 막는 경로가 실제로 도는 것은 확인했습니다(막힌 뒤 모델이 계속 일해 6턴).

판정이 실패하거나 시간을 넘기면 막은 채로 둡니다. 판정기는 이미 규칙에 걸린 답을 풀어 줄지 정하는 역할이라, 판정을 받지 못하면 풀어 줄 근거도 없기 때문입니다. 결과는 `${CLAUDE_PLUGIN_DATA}/state/events.log`에 `judge=released|kept|failed`와 걸린 초로 남습니다.

## 항목 하나만 끄기

정규식은 의도를 다 읽지 못합니다. 어떤 저장소에서는 한 규칙이 유난히 자주 오탐을 냅니다. 그렇다고 게이트를 통째로 끄면 같은 게이트의 나머지 검사도 함께 꺼집니다.

`.check.toml`에 이름을 적으면 그 항목만 빠집니다.

```toml
# 이 저장소에서는 R2b가 설계 논의마다 걸리고, PR은 사람이 따로 검토해서 끈다
disabled_rules = "R2b, done.pr"
```

쉼표로 여럿 적을 수 있고 대소문자를 가리지 않습니다. 적을 수 있는 이름은 다음과 같습니다.

| 게이트 | 이름 | 끄면 멈추는 것 |
|---|---|---|
| 근거 | `R0`·`R1`·`R2a`·`R2b`·`R3`·`R5` | 그 규칙 하나 |
| 완료 | `done.turn` | 코드를 고친 턴 끝의 검사 |
| | `done.commit` | 커밋 직전의 전체 검사 |
| | `done.pr` | PR 본문의 근거 검사 |
| 테스트 무결성 | `ti.skip` | 무력화 표기 추가 차단 |
| | `ti.assert` | 단언 감소 차단 |
| | `ti.rm` | 테스트 파일 삭제 차단 |
| | `ti.exclude` | 러너 설정의 제외 추가 차단 |

프로젝트 가드의 append-only에는 이름이 없습니다. `append_only`를 적지 않으면 원래 꺼져 있습니다.

**환경변수 대신 파일에 두는 이유가 요점입니다.** `NGG_DONE=0` 같은 환경변수는 그 게이트의 검사를 한꺼번에 끄고, 누가 자기 셸에 넣어 두면 팀은 그 사실을 알 수 없습니다. `.check.toml`은 저장소에 커밋되므로 PR에 보이고, 왜 껐는지가 같은 커밋에 적힙니다. 끄는 것을 쉽게 만드는 장치가 아니라 **끄는 행위를 보이게 만드는 장치**입니다. 환경변수는 급할 때 쓰는 스위치로 남겨 두었습니다.

껐다는 사실은 세 곳에 남습니다.

- `events.log`에 `off=[R2b]`, `off=[done.pr]`처럼 남습니다.
- 세션마다 저장소 프로필이 `끈 규칙: R2b, done.pr`를 컨텍스트에 싣습니다.
- 없는 이름을 적으면 어느 게이트든 막을 때 stderr로 알립니다. 껐다고 믿는데 실제로는 꺼지지 않은 상태가 가장 나쁘기 때문입니다.

설정은 게이트가 막거나 검사를 돌리기 직전에만 읽습니다. 그냥 지나가는 도구 호출에는 비용이 붙지 않습니다.

## 한 번만 허용하기

설정으로 끄면 그 검사는 계속 꺼져 있습니다. 오탐 한 건만 넘기고 싶을 때는 다음 프롬프트에 이렇게 한 줄을 씁니다.

```
check allow ti.skip
```

그 턴 안에서 해당 검사가 **한 번** 통과하고, 허용은 바로 사라집니다. 쓰지 않은 허용도 다음 프롬프트가 오면 사라집니다. 게이트가 막을 때 무엇을 쓰면 되는지 항목 이름과 함께 알려 줍니다.

- **사람만 쓸 수 있습니다.** 허용은 `UserPromptSubmit` 훅이 사용자 프롬프트에서만 읽습니다. 모델이 답에 같은 글을 적어도 풀리지 않습니다. 백그라운드 작업 알림도 사람의 프롬프트로 치지 않습니다.
- **줄 첫머리에 와야 합니다.** 문장 가운데 적은 것은 인용으로 봅니다. 대소문자를 가리지 않고, 쉼표로 여럿 적을 수 있습니다.
- **이름은 위 표의 게이트 항목만 받습니다.** 근거 게이트의 `R0`~`R5`는 대상이 아닙니다. 근거 게이트에는 확인할 수 없는 이유를 밝히면 풀리는 면제가 따로 있습니다.
- 통과시킨 사실은 `events.log`에 `allowed=[ti.skip]`으로 남습니다.

Probity의 `enforceTdd`에서 가져온 방식입니다. "reply in the session asking for the change to be let through, and it's allowed on the next attempt."

## 완료 게이트: 검사가 통과해야 턴이 끝납니다

코드 파일을 고친 턴은 저장소의 검사를 실제로 돌린 뒤에야 끝납니다. "다 끝냈습니다"라는 말이 아니라 검사 결과로 턴의 끝을 판정하기 위해서입니다. 공식 문서가 지정한 방법도 이것입니다.

> "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes."
> (결정적 게이트로: Stop 훅이 검사를 스크립트로 돌리고, 통과할 때까지 턴이 끝나는 것을 막는다.)

검사 명령은 다음 순서로 찾습니다.

| 순서 | 출처 |
|---|---|
| 1 | 저장소 루트의 `.check.toml`에 적은 `test_command` |
| 2 | `package.json`의 `scripts.test` → `npm test` |
| 3 | `Makefile`의 `test` 타깃 → `make test` |
| 4 | `pyproject.toml` → `python3 -m pytest -q` |

```toml
# .check.toml
fast_test_command = "npm test -- --changed"   # 턴 끝에는 이것만
test_command      = "npm test"                # 커밋 직전에 이것
```

**턴마다 전체 스위트를 돌리지 않습니다.** 공식 CLAUDE.md 예시가 그렇게 권합니다. "Prefer running single tests, and not the whole test suite, for performance." `fast_test_command`를 적으면 턴 끝에는 그것만 돌리고, 전체는 `git commit` 직전에 한 번 돌립니다. 나누지 않으면 `test_command` 하나로 둘 다 합니다. 검사가 30초를 넘으면 나누라고 알려 줍니다.

설계 원칙은 셋입니다. **모르는 것으로 막지 않습니다.** 검사 명령을 찾지 못하면 알리고 통과시킵니다. 돌릴 검사가 없는데 막으면 Claude가 풀 방법이 없어, 연속 차단 상한까지 같은 차단만 되풀이하기 때문입니다. **조용히 실패하지 않습니다.** 시간을 넘기면 그 사실을 알리고 막지 않습니다. 결과를 모르는 상태이고, 막아서 다시 돌리게 해도 같은 시간을 또 넘기기 쉽기 때문입니다. **코드가 아닌 변경은 대상이 아닙니다.** 문서만 고친 턴은 검사하지 않고, 저장소 밖 파일도 세지 않습니다.

끄려면 `NGG_DONE=0`을 쓰고, 제한 시간은 `DONE_TIMEOUT`(기본 180초)입니다.

이 저장소도 스스로에게 이 게이트를 적용합니다. `.check.toml`이 자기 테스트를 가리키고 있어서, 훅을 고치면 훅이 자기를 검사합니다.

### PR 본문에 근거가 있어야 PR을 엽니다

`gh pr create` 직전에 본문을 봅니다. 본문이 테스트 통과나 검증을 **주장하는데** 돌린 명령과 그 출력이 없으면 PR을 열지 못합니다. 성공을 주장하지 않는 본문은 막지 않습니다(V51). 리뷰어는 "테스트 통과"라는 문장만으로는 실제로 돌렸는지 확인할 수 없기 때문입니다. 공식 문서가 근거로 드는 것도 바로 그것입니다.

> "Have Claude show evidence rather than asserting success: the test output, the command it ran and what it returned, or a screenshot of the result."
> (성공을 주장하는 대신 근거를 보여 주게 하라. 테스트 출력, 돌린 명령과 그 결과, 또는 결과 스크린샷이다.)

근거로 치는 것은 **닫힌 코드 블록**(여는 줄과 닫는 줄이 다 있는 것)이나 **이미지**입니다. 본문은 `--body`, `--body-file`, `-F -`로 넘긴 heredoc에서 읽습니다. 에이전트가 흔히 쓰는 `--body "$(cat <<'EOF' … EOF)"` 모양도 읽습니다.

| 경우 | 판정 |
|---|---|
| 본문에 코드 블록이나 이미지가 있는 경우 | 통과 |
| 본문이 "테스트 전부 통과했습니다"뿐인 경우 | 막습니다 |
| 본문이 성공을 주장하지 않고 변경만 설명하는 경우 | 통과 |
| 기준 브랜치 대비 코드 파일을 바꾸지 않은 경우(문서만) | 통과 |
| `--fill`·`--web`처럼 본문이 명령에 없는 경우 | 통과. 볼 수 없는 것으로는 막지 않습니다 |
| 커밋 메시지나 문서 안에 `gh pr create`라고 적은 경우 | 통과. 인용은 사용이 아닙니다 |
| 기준 브랜치를 찾지 못한 경우 | 코드를 바꿨는지 모르므로 본문만 보고 판정합니다 |

기준 브랜치는 `--base`가 있으면 그것을 씁니다. 없으면 `origin/HEAD` → `origin/main` → `origin/master` → `main` → `master` 순으로 찾습니다. 로컬 git만 쓰고 네트워크에는 나가지 않습니다.

**형식만 봅니다.** 붙인 출력이 실제로 돌린 결과인지는 가리지 못합니다. 막힌 모델에게 돌리지 않은 출력을 지어내지 말라고 알리는 데서 그칩니다. `gh pr edit --body`로 본문을 나중에 바꾸는 것도 보지 않습니다.

변경만 설명하는 본문은 통과합니다. 근거 문장은 성공을 **주장하는 대신** 근거를 보이라는 것이라, 주장이 없으면 뒷받침할 것도 없기 때문입니다. 성공 주장은 "통과"·"검증했"·"passed"·"verified" 같은 표현으로 알아봅니다.

이 검사만 끄려면 `disabled_rules`에 `done.pr`을 적습니다. 완료 게이트 전체는 `NGG_DONE=0`으로 끕니다.

## 테스트 무결성 게이트: 테스트가 아니라 코드를 고칩니다

완료 게이트는 테스트가 통과해야 턴을 끝냅니다. 그런데 테스트를 끄거나 지우면 코드를 고치지 않고도 그 게이트를 통과할 수 있습니다. 그래서 Kent Beck이 에이전트의 부정행위로 지목한 것을 그대로 막습니다.

> "Any indication that the genie was cheating, for example by disabling or deleting tests."
> (지니가 속임수를 쓴다는 낌새, 예컨대 테스트를 비활성화하거나 지우는 것.)

막는 것은 셋뿐입니다. 테스트 파일에 **무력화 표기가 늘어날 때**(`.skip(`, `.only(`, `xit(`, `@pytest.mark.skip`, `#[ignore]`, `t.Skip(` 등), **단언이 줄어들 때**, 그리고 **테스트 파일을 지우는 명령**입니다.

**테스트 러너 설정도 봅니다.** `jest.config.*`·`vitest.config.*`·`pytest.ini`·`pyproject.toml`·`.mocharc.*` 같은 파일에서 제외 지시어(`testPathIgnorePatterns`, `--ignore=`, `exclude`, `norecursedirs` 등)가 **늘면** 막습니다. 테스트 파일을 건드리지 않고 설정으로 테스트를 빼는 길이 있었기 때문입니다. EvilGenie(arXiv [2511.21654](https://arxiv.org/abs/2511.21654))가 "Modified Testing Procedures"로 분류한 행동입니다. 제외를 줄이거나 그와 무관한 편집은 통과합니다.

**테스트 수정 전반을 막지는 않습니다.** 기댓값을 고치거나 단언을 더하는 것은 통과합니다. TDD는 테스트를 먼저 쓰고 고치는 방법론이라, 그것까지 막으면 문서가 권하는 바와 반대로 갑니다. 끄려면 `NGG_TESTGUARD=0`을 씁니다.

## 프로젝트 가드: 지난 기록은 고치지 않습니다

공식 문서의 훅 예시가 가리키는 자리입니다.

> "Write a hook that blocks writes to the migrations folder."
>
> 번역: 마이그레이션 폴더에 쓰는 것을 막는 훅을 작성하라.

Rails 가이드도 이미 커밋한 마이그레이션은 고치지 말라고 적습니다.

> "In general, editing existing migrations that have been already committed to source control is not a good idea."
>
> 번역: 이미 소스 관리에 커밋한 마이그레이션을 고치는 것은 대체로 좋은 생각이 아니다.

이 가드는 두 문장보다 좁습니다. **새 파일 추가는 허용하고 기존 파일의 수정만 막습니다.** 마이그레이션은 계속 새로 써야 하기 때문입니다. 반면 이미 적용된 마이그레이션 파일을 고치면, 적용을 마친 데이터베이스에서는 그 파일이 다시 돌지 않아 환경마다 스키마가 달라집니다.

**삭제와 이동은 막지 않습니다.** 두 출처 모두 쓰기와 수정까지만 말하고, Rails 가이드는 스키마 파일이 기준이 되면 오래된 마이그레이션 파일을 지워도("delete or prune") 된다고 설명합니다. 예전에는 `rm`·`git rm` 삭제도 막았지만 근거가 없어 뺐습니다(V50). 원문은 2026-09-16에 확인했습니다.

```toml
# .check.toml
append_only = "supabase/migrations, db/migrate"
```

설정이 없으면 아무것도 막지 않습니다. 끄려면 `NGG_GUARD=0`을 씁니다.

예전에는 커밋 훅을 건너뛰는 `git commit --no-verify`도 막았습니다(`pg.noverify`). 막으라고 권하는 문서를 찾지 못해 뺐습니다([설계 결정](decisions.md#6-근거가-없는-규칙은-뺐습니다)).

## 저장소 프로필: 세션마다 사실을 실어 줍니다

게이트는 무엇을 막을지 알아야 하고, Claude는 이 저장소에서 무엇을 돌려야 하는지 알아야 합니다. 세션이 시작될 때 `SessionStart` 훅이 스무 줄 안팎의 사실을 컨텍스트에 넣습니다.

```
[check 프로필] checkride  (브랜치 main)
패키지 매니저: pnpm
스택: next, react, typescript, vitest
검사 명령: pnpm test   (출처: package.json scripts.test → vitest run)
append-only 경로: supabase/migrations
게이트: 근거(항상) · 완료(켜짐) · 테스트 무결성(항상) · 프로젝트 가드(켜짐)
```

공식 문서가 이 이벤트의 stdout을 컨텍스트로 넣는다고 밝힙니다. "The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`, where Claude Code adds plain-text stdout as context that Claude can see and act on."

**싣는 것은 사실뿐이고 행동 지시는 넣지 않습니다.** 컨텍스트에 넣은 지시는 권고에 그쳐 지켜진다는 보장이 없고, 최신 모델에게는 검증 지시가 오히려 과잉 검증을 부르기 때문입니다([설계 결정](decisions.md#한눈에-보기)). 꼭 지켜야 하는 규칙은 게이트가 맡습니다. 모델을 부르지 않고 파일만 읽으며, `.env` 같은 비밀 파일의 값은 읽지 않습니다. 마지막 줄이 어느 게이트가 놀고 있는지 알려 주므로, 설정을 빼먹으면 바로 드러납니다. 끄려면 `NGG_PROFILE=0`을 씁니다.

## 얼마나 느려지나

설치하면 매 턴에 비용이 붙습니다. 숨기지 않고 적습니다. macOS(arm64), bash 3.2, python 3.13에서 훅마다 같은 입력으로 20회씩 돌린 중앙값입니다. 측정 스크립트는 [V38](VERIFICATION.md)에 있습니다.

| 훅 | 언제 도나 | 실측 |
|---|---|---|
| `no-guess-gate/prompt.sh` | 턴마다 1회 | 51ms |
| `no-guess-gate/stop.sh` | 턴 끝 | 161ms |
| `done-gate/stop.sh` | 턴 끝 | 44ms |
| `no-guess-gate/pre.sh` | 도구 호출마다 | 17ms |
| `test-integrity/pre.sh` | Edit·Write·Bash마다 | 46ms. 삭제 글자가 없는 Bash는 12ms |
| `project-guard/pre.sh` | Edit·Write마다 | 41ms. V50부터 Bash에서는 돌지 않습니다 |
| `done-gate/pre.sh` | Bash마다 | 커밋·PR 생성이 아니면 12ms |
| `no-guess-gate/bashres.sh` | Bash마다 | 17ms |
| `done-gate/post.sh` | Edit·Write마다 | 44ms |
| `repo-profile/session.sh` | 세션 1회 | 65ms |

**턴마다 붙는 바닥은 약 256ms**(`prompt` + `stop` 둘)입니다. 도구를 쓸 때 더 붙는 비용은 도구마다 다릅니다. Bash 한 번에 약 70ms이고, 삭제·이동·커밋·PR 생성 명령이면 훅이 끝까지 검사해서 약 170ms가 됩니다. 이 두 값은 프로젝트 가드가 Bash에서도 돌던 때의 측정이라, 지금은 그 훅 몫(보통 13ms, 삭제 명령이면 41ms)만큼 짧습니다. 다시 재지는 않았습니다. Edit·Write 한 번에 약 155ms, 그 밖의 도구 한 번에 17ms입니다. Bash 쪽 훅 세 개는 도구 이름과 관련 글자를 먼저 보고, 관계없는 명령에서는 파이썬을 띄우지 않습니다(V40). 세션을 열 때는 65ms가 한 번 듭니다.

처음 잰 V28에서는 바닥이 326ms였습니다. 같은 스크립트로 v1.5.0을 번갈아 재니 258ms가 나왔습니다. 숫자가 줄어든 것은 코드 때문이 아니라 측정 조건이 달라서입니다. 1.6.0에서 기능을 넷 더했지만 훅별 차이는 5ms 안이었습니다.

짧은 프롬프트 하나로 세션 전체를 재면 훅 없이 1,416ms, 훅을 켜고 2,367ms였습니다(V28, 각 3회 중앙값). 이 값은 다시 재지 않았습니다.

비용의 대부분은 파이썬 기동입니다. `stop.sh`는 파이썬을 3회 부르고, 기동에만 회당 26.9ms가 듭니다(V28). 하나로 합치면 50ms 안팎을 줄일 수 있지만, 판정의 입력을 만드는 자리라 아직 손대지 않았습니다.

느리면 `NGG_PROFILE=0`으로 프로필을 끄고, 게이트별로 `NGG_DONE=0`·`NGG_TESTGUARD=0`·`NGG_GUARD=0`을 쓸 수 있습니다.

## 커맨드 여덟 개

게이트는 저절로 돌지만, 언제 할지와 비용을 사용자가 정해야 하는 일은 커맨드로 둡니다. 전부 **사용자가 직접 쳐야만** 돕니다(`disable-model-invocation: true`). 공식 문서가 그렇게 권합니다. "Use `disable-model-invocation: true` for workflows with side effects that you want to trigger manually."

| 커맨드 | 하는 일 |
|---|---|
| `/checkride:spec` | 큰 기능 전에 `AskUserQuestion`으로 사용자를 인터뷰해 `SPEC.md`를 씁니다 |
| `/checkride:setup-checks` | 검사 명령을 실제로 돌려 보고 `.check.toml`에 확정합니다. 기준선·append-only·비밀 파일 차단도 제안합니다 |
| `/checkride:tdd` | 실패 테스트 먼저, RED 확인, 최소 구현 순서로 진행합니다 |
| `/checkride:finish` | 검사·린트를 돌리고 커밋·푸시·PR 을 만듭니다. PR 본문에 돌린 명령과 출력을 근거로 넣습니다 |
| `/checkride:handoff` | 다음 세션이 읽을 인수인계를 씁니다 |
| `/checkride:status` | 게이트 상태를 전부 실측해 보고합니다 |
| `/checkride:full-cycle` | 탐색 → 계획 → 구현 → 검토 → PR 을 순서대로 진행합니다 |
| `/checkride:config` | 게이트 항목마다 무엇을 막고 어디서 온 규칙인지 보여 주고, 끌 것을 골라 `disabled_rules`에 적습니다. 게이트 언어도 저장소(`.check.toml`의 `lang`)나 전역(`~/.claude/settings.json`의 `env.NGG_LANG`)에 고정합니다 |

**커맨드는 한국어로 쓰여 있고, 사용자가 쓴 언어로 답합니다.** `SKILL.md`는 로케일로 가를 수 없는 파일입니다. 게이트 문장은 `msg.sh`가 언어별로 가르지만 커맨드는 그럴 수 없어서, 배포 대상을 한국어 사용자로 정하고 본문과 `description`을 한국어로 씁니다. 사람이 읽는 것은 커맨드 목록에 뜨는 `description`이므로, 그것이 한국어여야 무엇을 고르는지 읽을 수 있습니다. 한국어로 쓰여 있어도 영어권 사용자가 부를 수 있도록 본문에 "내가 쓰는 언어로 답한다"는 지시를 남겨 두었습니다. 인용한 공식 문서의 원문은 영어 그대로 두고 번역을 붙입니다. 2026-09-11(`71147c3`)에는 반대로 영어로 썼는데, 그 결정과 2026-09-22에 뒤집은 이유는 [검증 기록](VERIFICATION.md)의 V31·V57에 있습니다.

**없는 커맨드가 더 많습니다.** 계획은 내장 plan mode가, 탐색은 내장 Explore가, 리뷰는 `/code-review`가, 실행 확인은 `/verify`가, 반복은 `/goal`이 이미 맡습니다. 전수 조사에서 후보 23개를 7개로 줄였고, 검사를 고르는 `config`를 뒤에 더했습니다. 같은 일을 하는 것을 새로 만들지 않습니다.

## 근거

규칙마다 어디서 왔는지 밝힙니다. 기준은 **무엇을 막는지가 출처 문서에 있어야 한다**는 것입니다. 어떻게 알아내는지(정규식·판정기)는 구현이라, 출처 대신 테스트와 [검증 기록](VERIFICATION.md)으로 뒷받침합니다. 아래 문장은 모두 2026-09-15에 원문을 열어 확인했습니다. 규칙을 고른 과정과 버린 대안은 [설계 결정](decisions.md)에 있습니다.

| 문서 | 가져온 것 |
|---|---|
| [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) "Minimizing hallucinations in agentic coding" | R0·R1·R2a·R2b. "Never speculate about code you have not opened. (…) Make sure to investigate and read relevant files BEFORE answering questions about the codebase. Never make any claims about code before investigating unless you are certain of the correct answer" (열어 보지 않은 코드를 추측하지 마라. 코드베이스에 관한 질문에는 답하기 전에 관련 파일을 조사하고 읽어라. 정답을 확신하지 않는 한 조사하기 전에 코드에 대해 주장하지 마라). 근거 문장이 코드베이스 질문으로 범위를 한정하므로 R2a·R2b도 그 맥락에서만 봅니다 |
| [Reduce hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) | 불가 면제. "Allow Claude to say "I don't know"" (Claude가 모른다고 말할 수 있게 하라). 막힌 뒤 할 일로 안내하는 철회도 이 문서에서 왔습니다. "If it can't find a quote, it must retract the claim" (인용을 찾지 못하면 그 주장을 철회해야 한다) |
| [Best practices](https://code.claude.com/docs/en/best-practices) | R3·R5, 완료 게이트의 Stop 훅 방식, 성공을 주장하는 PR 본문 검사(`done.pr`). "Have Claude show evidence rather than asserting success" (성공을 주장하는 대신 근거를 보여 주게 하라). 프로젝트 가드의 append-only(기존 파일 수정 차단). "Write a hook that blocks writes to the migrations folder." (마이그레이션 폴더에 쓰는 것을 막는 훅을 작성하라) |
| [Rails 마이그레이션 가이드](https://guides.rubyonrails.org/active_record_migrations.html) | append-only 의 수정 차단. "In general, editing existing migrations that have been already committed to source control is not a good idea." (이미 커밋한 마이그레이션을 고치는 것은 대체로 좋은 생각이 아니다). 같은 가이드가 오래된 마이그레이션 파일을 지워도 된다고 설명하므로 삭제는 막지 않습니다 |
| [Hooks](https://code.claude.com/docs/en/hooks) · [Hooks guide](https://code.claude.com/docs/en/hooks-guide) | 구현 수단입니다. exit 2 차단, 8회 상한, 타임아웃, R5가 실패한 명령을 알아내는 `PostToolUseFailure` 이벤트 |
| Kent Beck, [Augmented Coding](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes) | `ti.skip`·`ti.rm`. "cheating, for example by disabling or deleting tests" (속임수, 예컨대 테스트를 비활성화하거나 지우는 것). `done.commit`. "Only commit when: 1. ALL tests are passing" (모든 테스트가 통과할 때만 커밋하라) |
| Gabor 외, [EvilGenie](https://arxiv.org/abs/2511.21654) (v2, 2026-05-17) "Modified Testing Procedure" | `ti.assert`·`ti.exclude`. "The agent modifies the test cases or the code that runs the testing procedure. Such modifications could change the accepted answers to test cases, or simply delete or ignore test cases." (에이전트가 테스트 케이스나 테스트를 돌리는 코드를 고친다. 테스트 케이스가 받아들이는 답을 바꾸거나 테스트 케이스를 지우거나 무시할 수 있다) |

Simon Willison의 [Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/)는 게이트 규칙이 아니라 커맨드(`/checkride:setup-checks`·`/checkride:tdd`·`/checkride:finish`)의 근거로 씁니다. 한 번만 허용하기는 막는 규칙이 아니라 푸는 장치이고, Probity에서 가져왔습니다.

훅을 쓰는 이유도 공식 문서에 있습니다.

> "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens."
> (권고에 그치는 CLAUDE.md 지시와 달리, 훅은 결정적이고 그 동작이 반드시 일어나게 보장한다.)

## 개발

```bash
claude --plugin-dir .                         # 설치본 대신 이 폴더를 그 세션에 로드
claude plugin validate .                      # 매니페스트와 훅 배선 검사
for g in lib no-guess-gate done-gate test-integrity project-guard repo-profile; do
  tests/$g/unit.sh || break; done && tests/skills-unit.sh && tests/attack-surface.sh && tests/invariants.sh   # 합계 425건. 모델을 부르지 않는다
tests/fuzz.sh                                 # 망가진 입력 24종 × 훅 10개 = 240회
tests/no-guess-gate/selftest.sh               # 실제 프롬프트 회귀 12케이스, 몇 분
tests/no-guess-gate/judge-accuracy.sh         # 판정기 정확도·소요 시간, 몇 분
shellcheck -x -s bash plugin/hooks/*/*.sh tests/*.sh tests/*/*.sh
```

게이트가 내보내는 문장은 훅 안이 아니라 `plugin/hooks/lib/msg.sh` 한 곳에 있습니다. 새 문장은 한국어와 영어를 함께 넣습니다. 한쪽만 넣으면 `tests/lib/unit.sh`가 잡습니다.

모든 검증은 실행 명령과 출력 원문을 [`docs/VERIFICATION.md`](VERIFICATION.md)에 남깁니다. 기여는 [CONTRIBUTING.md](../CONTRIBUTING.md)를, 보안은 [SECURITY.md](../SECURITY.md)를 봐 주세요.
