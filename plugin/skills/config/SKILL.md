---
name: config
description: 이 저장소가 무엇을 강제할지 고르고 게이트 언어를 정한다. 항목과 출처를 보여 준 뒤 checkride.toml에 disabled_rules와 lang을, 또는 전역 설정에 언어를 쓴다.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, AskUserQuestion
---

# 무엇을 강제할지 고른다

checkride 가 이 저장소에서 무엇을 강제할지 검사 하나씩 고르게 한다. **모든 검사는 켜진 채로 시작한다.** 무언가를 끄는 것은 `checkride.toml` 에 적히는 결정이고, 그래서 풀 리퀘스트에 드러나 팀이 볼 수 있다.

Codex에서 이 스킬을 쓸 때 `checkride.toml` 변경은 설정 기록일 뿐이다. 자동 게이트는 Claude Code 플러그인을 설치해 훅이 실행될 때만 적용된다. Codex에서는 이 저장소에 적용할 규칙과 언어를 정리하되, Codex에서 강제된다고 말하지 않는다. `~/.claude/settings.json`은 Codex의 전역 설정이 아니므로 수정하지 않는다.

**내가 쓰는 언어로 답하고,** 설정 파일의 주석도 그 언어로 쓴다.

## 1. 현재 상태를 읽는다

저장소 루트의 `checkride.toml` 을 읽는다. `disabled_rules` 줄과 `lang` 줄이 있으면 가져온다. **이 커맨드가 바꾸는 것은 그 두 줄, 그리고 전역 언어를 고를 때의 `~/.claude/settings.json` 의 `env.NGG_LANG` 뿐이다.** 나머지 키와 주석은 그대로 둔다.

Claude Code에서는 환경도 확인한다. `NGG_DONE`, `NGG_TESTGUARD`, `NGG_GUARD`, `NGG_JUDGE` 중 `0` 인 것이 있으면 그 스위치가 파일과 무관하게 게이트 하나를 통째로 끈다. 그 사실을 알린다. `NGG_LANG` 이 `ko` 나 `en` 이면 파일과 무관하게 게이트 언어를 강제하므로, 그것이 설정돼 있는 동안 파일의 `lang` 은 효력이 없다고 알린다. Codex에서는 이 환경변수를 게이트 상태로 해석하지 않는다.

`NGG_LANG` 은 `~/.claude/settings.json` 의 `env` 블록에도 있을 수 있다. 거기서는 그 키 하나만 본다. **그 파일에는 토큰이 들어 있을 수 있으므로 절대 통째로 출력하지 않는다.**

## 2. 항목을 전부 보여 준다

표 하나에 다섯 열을 둔다. **게이트, 이름, 막는 것, 출처, 켜짐/꺼짐**이다. 아래 행을 쓰고 출처는 적힌 그대로 옮긴다.

**출처 열을 절대 빼지 않는다.** 이 커맨드가 존재하는 이유가 그것이다. 규칙을 끄기 전에 그 규칙이 어디서 왔는지 보여야 한다. 출처 없는 표는 이 커맨드가 약속한 표가 아니다.

| 게이트 | 이름 | 막는 것 | 출처 |
|---|---|---|---|
| 근거 | `R0` | 도구를 돌리지 않고 이 저장소의 상태에 답하는 것 | Prompting best practices, "investigate and read relevant files BEFORE answering questions about the codebase" (코드베이스에 관한 질문에 답하기 전에 관련 파일을 조사하고 읽어라) |
| 근거 | `R1` | 열어 보지 않고 파일의 상태를 단정하는 것 | Prompting best practices, "Never make any claims about code before investigating unless you are certain of the correct answer" (정답을 확신하지 않는 한 조사하기 전에 코드에 대해 주장하지 마라) |
| 근거 | `R2a` | 코드베이스에 관한 질문에서 도구를 돌리지 않고 "확인이 필요하다"로 끝내는 것 | Prompting best practices, "investigate and read relevant files BEFORE answering questions about the codebase" (위와 같다). 확인할 수 없는 이유를 밝히는 것은 면제다. Reduce hallucinations, "Allow Claude to say I don't know" (Claude 가 모른다고 말할 수 있게 하라) |
| 근거 | `R2b` | 도구를 한 번도 쓰지 않고 로컬 상태를 추측하는 것("아마") | Prompting best practices, "Never speculate about code you have not opened" (열어 보지 않은 코드를 추측하지 마라) |
| 근거 | `R3` | Bash 실행 0건인데 테스트가 통과했다고 주장하는 것 | Best practices, "Have Claude show evidence rather than asserting success" (성공을 주장하는 대신 근거를 보여 주게 하라) |
| 근거 | `R5` | 마지막 명령이 실패했는데 성공을 주장하는 것 | Best practices, 위와 같은 문장 |
| 완료 | `done.turn` | 코드를 바꾼 턴을 검사 통과 전에 끝내는 것 | Best practices, "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes." (결정적 게이트로서, Stop 훅이 검사를 스크립트로 돌리고 통과할 때까지 턴이 끝나는 것을 막는다) |
| 완료 | `done.commit` | 전체 검사 통과 전에 커밋하는 것 | Kent Beck, "Only commit when ALL tests are passing." (모든 테스트가 통과할 때만 커밋하라) |
| 완료 | `done.pr` | 명령 출력 없이 테스트 통과나 검증을 주장하는 PR 본문 | Best practices, "Have Claude show evidence rather than asserting success" (성공을 주장하는 대신 근거를 보여 주게 하라) |
| 테스트 무결성 | `ti.skip` | 테스트에 `.skip` 계열 표시를 붙이는 것 | Kent Beck, "disabling or deleting tests" (테스트를 비활성화하거나 지우는 것) |
| 테스트 무결성 | `ti.assert` | 단언을 지우는 것 | EvilGenie (arXiv 2511.21654), "Modified Testing Procedure": "The agent modifies the test cases or the code that runs the testing procedure." (에이전트가 테스트 케이스나 테스트를 돌리는 코드를 고친다) |
| 테스트 무결성 | `ti.rm` | 테스트 파일을 지우는 것 | Kent Beck, 위와 같은 문장 |
| 테스트 무결성 | `ti.exclude` | 테스트 러너 설정에 제외를 추가하는 것 | EvilGenie (arXiv 2511.21654), 위와 같은 절 |

append-only 경로에는 여기 이름이 없다. `append_only` 가 설정돼 있을 때만 켜지고, 그것은 `/checkride:setup-checks` 가 맡는다.

## 3. 무엇을 끌지 묻는다

`AskUserQuestion` 의 다중 선택으로 묻는다. 게이트마다 질문 하나씩 두고 그 게이트의 항목을 나열한다. 질문은 **무엇을 끌 것인가**이지 무엇을 남길 것인가가 아니다. 한 질문에 선택지가 넷까지만 되므로 근거 게이트의 여섯 항목은 두 질문으로 나눈다. 게이트 하나만 바꾸고 싶다고 하면 그 하나만 묻는다.

묻기 전에 한 번 알린다. 오탐이 한 번뿐이라면 다음 프롬프트에 `check allow <항목>` 을 한 줄로 적어서 아무것도 끄지 않고 그 동작 하나만 통과시킬 수 있다. 다만 이것은 `R0`~`R5` 에는 적용되지 않는다.

## 4. 쓴다

`disabled_rules` 줄의 전과 후를 보여 주고 승낙을 받은 뒤에 쓴다. 그다음은 이렇다.

- 파일이 있으면 그 한 줄만 바꾸고, 없던 줄이면 더한다.
- 파일이 없으면 그 줄과 왜 그런지를 적은 주석 한 줄로 새로 만든다.
- 꺼 둔 것이 더는 없으면 그 줄을 지운다.

이름은 쉼표로 구분하고 대소문자는 가리지 않는다. 위 표에 없는 이름은 쓰지 않는다. 게이트는 모르는 이름을 보고하기만 할 뿐 아무것도 끄지 않는다.

## 5. 언어

게이트는 저장소의 언어로 말한다. 현재 언어를 이 순서로 판정하고 어느 것이 적용되는지 알린다.

1. `NGG_LANG` (`ko`/`en`) 이 설정돼 있으면 그것이다. 파일이 바꿀 수 없는 환경 우선값이다. 셸에서 왔는지 `~/.claude/settings.json` 에서 왔는지 밝힌다.
2. `checkride.toml` 의 `lang` (`ko`/`en`) 이 설정돼 있으면 그것이다.
3. 둘 다 없으면 로케일이다(`LC_ALL` > `LC_MESSAGES` > `LANG`). `ko` 계열이면 한국어, 그 밖에는 영어다.

Claude Code에서는 `AskUserQuestion` 두 질문으로 고정할지 제안한다. Codex에서는 대화로 묻는다. 먼저 언어를 묻고(한국어, 영어, 로케일을 따름), 그다음 어디에 쓸지 묻는다. Codex에서는 저장소 설정만 제안하고 Claude 전역 설정은 선택지로 내지 않는다.

- **이 저장소.** `checkride.toml` 의 `lang` 줄만 바꾼다. `lang = "ko"` 또는 `lang = "en"` 을 더하거나 바꾸고, 로케일을 따르려면 그 줄을 지운다. 풀 리퀘스트에 드러나고 이 저장소를 여는 모든 사람에게 적용된다. `NGG_LANG` 이 설정돼 있으면 그것을 지워야 파일 변경이 효력을 낸다고 알린다.
- **전역.** `~/.claude/settings.json` 의 `env.NGG_LANG` 만 바꾼다. `ko` / `en` 으로 설정하거나, 로케일을 따르려면 그 키를 지운다. 절충점을 선택지 설명에 적는다. 이 기계의 모든 저장소에 적용되고, 저장소마다의 `lang` 을 이기며, 어떤 풀 리퀘스트에도 드러나지 않는다. 나머지 키와 파일의 형식은 그대로 두고 **파일을 출력하지 않는다.** 바꾼 뒤에도 게이트가 옛 언어로 말하면 새 세션을 시작하라고 알린다.

쓰기 전에 승낙을 받고, 바뀌는 줄이나 키의 전과 후를 보여 준다.

## 6. 보고

2 단계와 같은 표를 새 상태로 다시 내고, 게이트의 실효 언어를 적는다. 그다음 이 변경이 어디에서 보이는지 말한다. `checkride.toml` 의 diff, 매 세션 머리의 저장소 프로필, 그리고 꺼 둔 검사가 막았을 상황마다 `events.log` 에 남는 `off=[...]` 다. 전역 언어는 어떤 diff 에도 없고 `~/.claude/settings.json` 에만 있다.
