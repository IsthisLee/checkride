---
name: status
description: 어떤 게이트가 살아 있고 이 저장소가 무엇을 설정했으며 최근에 무엇이 막혔는지 보여 준다. 전부 실측하고 아무것도 가정하지 않는다.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# 상태

checkride 가 이 저장소에서 실제로 무엇을 하고 있는지 보고한다. **전부 실측한다.** 이 질문에 추측으로 답하는 커맨드는 그 자체로 자기모순이다.

현재 에이전트가 Codex라면 Claude Code 훅은 실행되지 않는다. 이 경우 훅이 동작 중이라고 보고하지 말고, Codex에서 확인할 수 없는 Claude 플러그인 상태와 `events.log`는 확인 불가로 표시한다. `checkride.toml`의 저장소 설정은 별도로 읽어서 보고한다.

**내가 쓰는 언어로 답한다.**

## 무엇을 확인하는가

1. **설치와 배선.** Claude Code에서는 설치 상태를 `claude plugin list`로, 이벤트 배선을 `hooks/hooks.json`으로 확인한다. Codex에서는 이 훅들이 실행되지 않는다고 보고한다.
2. **저장소 설정.** `checkride.toml` 이 있으면 읽어서 `test_command`, `fast_test_command`, `append_only`, `disabled_rules` 를 보여 준다. 없으면 없다고 말하고, 그래서 어떤 게이트가 놀고 있는지 이름을 댄다.
3. **꺼짐 스위치.** `NGG_JUDGE`, `NGG_DONE`, `NGG_TESTGUARD`, `NGG_GUARD`, `NGG_PROFILE` 중에 환경에서 꺼진 것이 있는지 확인한다.
4. **최근 판정.** Claude Code에서는 상태 폴더의 `events.log` 마지막 20줄을 읽고 요약한다. 위치는 `${CLAUDE_PLUGIN_DATA}/state/events.log` 다. Codex에서는 이 로그를 사용할 수 없다고 말한다.

## 어떻게 보고하는가

표 하나로 낸다. 게이트마다 **켜짐 / 설정이 없어 놀고 있음 / 꺼짐** 중 하나와 그렇게 판단한 근거를 적는다.

막힌 기록이 있으면 규칙별로 세어서 함께 보여 준다. 오탐을 내고 있는 것으로 보이는 규칙이 있으면 지목하고, 그에 대해 할 수 있는 일 두 가지를 알린다. 하나는 `checkride.toml` 의 `disabled_rules` 로 그 규칙이나 검사 하나만 끄는 것이고(규칙은 `R0`~`R5`, 게이트 항목은 `done.pr`·`ti.exclude` 같은 이름이다), 다른 하나는 이슈를 열어 규칙 자체를 고치게 하는 것이다.

`events.log` 에 `off=[...]` 가 보이면 이 저장소가 어떤 규칙이나 검사를 언제부터 껐는지 **설정 파일이 아니라 로그에 근거해서** 말한다.

`allowed=[...]` 가 있는 줄은 사람이 프롬프트에 `check allow <항목>` 을 적어 한 번만 허용한 기록이다. 막힌 기록이나 꺼 둔 검사와 구분해서 따로 나열한다.
