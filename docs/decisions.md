# 설계 결정: 어떤 근거로 게이트를 이렇게 만들었나

이 문서는 did-you-check를 만들면서 내린 핵심 결정과, 각 결정이 기댄 근거를 설명합니다. 게이트가 무엇을 어떻게 막는지는 [게이트와 커맨드 상세](gates.md)에, 실행한 명령과 출력 원문은 [검증 기록](VERIFICATION.md)에 있습니다. 이 문서는 **왜 그렇게 만들었는지**만 다룹니다.

읽기 전에 두 가지를 밝혀 둡니다.

- **기준 시점은 2026년 9월입니다.** 이 분야는 몇 달 단위로 바뀌므로, 날짜가 붙은 사실은 그 날짜의 사실로 읽어 주세요.
- **사실에는 출처 번호를 붙였고, 출처 없이 추론한 부분은 "판단"이라고 표시했습니다.** 인용문은 모두 원문과 대조했으며, 출처 목록은 문서 끝에 있습니다.

## 한눈에 보기

| 결정 | 이유 | 근거 |
|---|---|---|
| [규칙을 부탁하지 않고 훅으로 강제합니다](#1-부탁하지-않고-훅으로-강제합니다) | CLAUDE.md 지시는 권고라서 지켜진다는 보장이 없습니다 | [[1]](https://code.claude.com/docs/en/best-practices) |
| [파일을 고치기 전에 조사를 시키는 게이트는 두지 않습니다](#2-파일을-고치기-전에-조사를-강제해야-하는가) | [말한 사실만 믿고 게이트를 열어서](#왜-물러났나) 실제 조사는 보장하지 못했고, 이미 조사한 경우에도 막았습니다. 효과는 확인되지 않았는데 긴 세션의 반복 루프가 보고됐고, 최신 모델은 시키지 않아도 조사합니다 | [[5]](https://github.com/zunoworks/gateguard), [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md), [[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5), [[11]](https://github.com/affaan-m/ECC) |
| [읽지 않은 기존 파일을 Write로 덮어쓰는 것만 막습니다(`rb.write`)](#이-플러그인의-결정) | Edit는 현재 내용과 맞아야 적용되지만, Write는 파일 전체를 바꿉니다. 모르고 덮어쓰면 되돌리기 어려운 자리는 Write뿐입니다 | [[3]](https://code.claude.com/docs/en/tools-reference), [[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md), [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md) |
| [근거 없는 주장은 턴이 끝나는 순간에 검사합니다](#3-근거-없는-주장은-턴이-끝나는-순간에-검사합니다) | 거짓 주장은 답 그 자체라서, 답이 완성된 뒤에야 검사할 수 있습니다 | 판단, [[2]](https://code.claude.com/docs/en/hooks), [[12]](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) |
| [막는 대상이 출처 문서에 없는 규칙은 뺐습니다(R4, `pg.noverify`)](#6-근거가-없는-규칙은-뺐습니다) | 문서가 권하는 대처(근거 없는 주장 철회)를 막거나, 막으라는 문서가 아예 없었습니다 | [[9]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices), [[12]](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) |
| [모델에게 "확인하라"고 지시하지 않고, 나온 답을 밖에서 대조합니다](#3-근거-없는-주장은-턴이-끝나는-순간에-검사합니다) | Opus 5는 스스로 검증하므로, 검증 지시를 넣으면 과잉 검증으로 토큰만 늘고 품질은 그대로라고 공식 가이드가 안내합니다. 밖에서 대조하면 규칙에 걸린 턴에만 비용이 듭니다 | [[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) |

## 1. 부탁하지 않고 훅으로 강제합니다

Claude Code 공식 문서는 CLAUDE.md와 훅의 차이를 이렇게 설명합니다.

> "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens." [[1]](https://code.claude.com/docs/en/best-practices)
> (권고에 그치는 CLAUDE.md 지시와 달리, 훅은 결정적이고 그 동작이 반드시 일어나게 보장한다.)

같은 문서는 검사를 턴 끝의 게이트로 거는 방법도 제시합니다.

> "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes. Claude Code overrides the hook and ends the turn after 8 consecutive blocks." [[1]](https://code.claude.com/docs/en/best-practices)

그래서 이 플러그인은 규칙을 문서로 부탁하지 않고, 어기면 턴이 끝나지 않는 훅으로 만들었습니다. 연속으로 8번 막히면 Claude Code가 훅을 무시하고 턴을 끝내므로, 게이트에 무한히 갇히지는 않습니다.

## 2. 파일을 고치기 전에 조사를 강제해야 하는가

게이트를 설계하면서 가장 오래 따진 질문은 이것입니다. **"Claude가 파일을 고치기 전에 먼저 살펴보도록 강제해야 하는가?"** 2026년 9월까지 이 질문에 대한 답은 세 단계로 바뀌어 왔고, 이 플러그인의 결정도 그 흐름을 따랐습니다.

### 1단계: 권하던 시기 (2026년 3월까지)

공식 문서는 먼저 탐색하고 계획한 뒤에 코드를 쓰라고 권합니다. 동시에 작은 수정에까지 그 절차를 강요하지는 말라고 적습니다.

> "Letting Claude jump straight to coding can produce code that solves the wrong problem." [[1]](https://code.claude.com/docs/en/best-practices)
> "If you could describe the diff in one sentence, skip the plan." [[1]](https://code.claude.com/docs/en/best-practices)

프롬프트 가이드에도 열어 보지 않은 코드를 추측하지 말라는 예시가 있습니다.

> "Never speculate about code you have not opened. If the user references a specific file, you MUST read the file before answering." [[9]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

도구 차원에서는 Claude Code 자체가 안전장치 역할을 했습니다. 도구 레퍼런스에 따르면 v2.1.208 이전의 Claude Code는 이번 대화에서 읽지 않은 파일의 편집을 거부했습니다. [[3]](https://code.claude.com/docs/en/tools-reference)

### 2단계: 억지로 시키던 시기 (2026년 4~6월)

2026년 4월 11일 GateGuard가 공개됐습니다. 이 도구는 파일을 처음 만질 때 편집을 막고, 그 파일을 누가 임포트하는지, 데이터가 실제로 어떻게 생겼는지, 사용자 지시가 무엇이었는지를 먼저 말하게 했습니다. 주장은 분명했습니다.

> "Self-evaluation ("are you sure?") doesn't change LLM behavior. Forced investigation does." [[5]](https://github.com/zunoworks/gateguard)

다음 날인 4월 12일, ECC가 같은 방식의 게이트를 들여왔습니다. [[11]](https://github.com/affaan-m/ECC)

같은 달 27일, The Register는 Cursor에서 Claude Opus 4.6으로 돌던 에이전트가 PocketOS의 운영 데이터베이스와 백업을 API 호출 한 번으로 지운 사고를 보도했습니다. 에이전트는 이렇게 설명했습니다.

> "I guessed that deleting a staging volume via the API would be scoped to staging only. I didn't verify." [[10]](https://www.theregister.com/2026/04/27/cursoropus_agent_snuffs_out_pocketos/)

그러나 조사를 강제하는 방식의 효과 근거는 약했습니다. GateGuard의 A/B 결과는 게이트를 켠 쪽 8.7점, 끈 쪽 6.7점이었지만, 제작자 스스로 한계를 이렇게 적었습니다.

> "N=3 tasks, self-scored (potential bias)." [[5]](https://github.com/zunoworks/gateguard)

부작용도 보고됐습니다. 2026년 6월 4일 ECC [이슈 #2142](https://github.com/affaan-m/ECC/issues/2142)의 제목은 "GateGuard fact-force restate-retry loop amplifies model repetition traps in long sessions"였습니다. [[11]](https://github.com/affaan-m/ECC) 같은 시기 Claude Code는 헛오류를 줄이는 쪽으로 움직였습니다. 2026년 5월 18일 v2.1.144의 변경 내역은 "Fewer spurious tool errors during search: `head`/`tail` file views now satisfy the read-before-edit check"였습니다. [[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

### 3단계: 지켜보고, 위험한 곳에서만 막는 시기 (2026년 7월 이후)

2026년 7월을 전후해 세 곳이 함께 방향을 바꿨습니다. 무엇이 바뀌었는지를 먼저 적고, 왜 바꿨는지는 [왜 물러났나](#왜-물러났나)에 모았습니다.

**첫째, Claude Code가 최신 모델에게 읽기 요구를 풀었습니다.** 도구 레퍼런스는 현재 이렇게 적습니다.

> "Claude Opus 4.6, Claude Haiku 4.5, and older models always require the read. Newer models can edit an unread file when reading it wouldn't need a permission prompt and the Read tool is available." [[3]](https://code.claude.com/docs/en/tools-reference)

이 완화는 Edit에 v2.1.208(2026-07-13)부터, Write에 v2.1.228(2026-08-11)부터 적용됐습니다. [[3]](https://code.claude.com/docs/en/tools-reference), [[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

**둘째, GateGuard가 무조건 막는 방식을 버렸습니다.** Opus 5가 나온 2026년 7월 24일[[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)에서 사흘 뒤, GateGuard v0.6.0은 방식을 이렇게 바꿨습니다.

> "investigation is no longer demanded and then taken on trust: an evidence ledger observes what Claude actually did (…), and the gate opens on observed behavior — never on claims." [[5]](https://github.com/zunoworks/gateguard)

같은 날 공개된 PainBench에서 Opus 5는 시키지 않아도 편집 전에 조사했고("It voluntarily investigated before editing"), 게이트 유무에 따라 점수가 달라진 과제는 파괴적 복원 하나뿐이었습니다. [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md)

| 과제 | 게이트 없음 | 게이트 있음 |
|---|---|---|
| T1 읽지 않고 편집 | 10/10 | 10/10 |
| T2 범위 위반 | 9/10 | 9/10 |
| T3 파괴적 복원 | 9/10 | 10/10 |

제작자는 이 결과가 "N=1 per cell; no statistical claims."라고 밝혔고, 이전의 +2.0 주장은 "should NOT be extended to the 5 family."라고 적었습니다. [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md)

**셋째, Anthropic이 Opus 5에게 검증을 지시하지 말라고 안내합니다.**

> "Claude Opus 5 verifies its own work without being told to. If your prompt contains explicit verification instructions (…), remove them: instructions like these cause over-verification on Claude Opus 5, and removing them reduces wasted tokens with no loss in quality." [[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)

반면 2026년 9월 7일 병합된 ECC 2.2.1의 GateGuard 사본은 여전히 [2단계(억지로 시키던 시기)](#2단계-억지로-시키던-시기-2026년-46월)의 방식입니다. Edit·Write 분기에서 조사 여부를 보지 않고, 파일을 처음 만지면 막습니다(`scripts/hooks/gateguard-fact-force.js`). [[11]](https://github.com/affaan-m/ECC)

운전 연수에 비유하면 이해가 쉽습니다. 초보 때는 교관이 교차로마다 "좌우 봤어요?"라고 묻습니다([2단계](#2단계-억지로-시키던-시기-2026년-46월)). 운전이 늘면 매번 묻지 않고 기록만 보다가, 철길 건널목처럼 위험한 곳에서만 반드시 멈추게 합니다([3단계](#3단계-지켜보고-위험한-곳에서만-막는-시기-2026년-7월-이후)).

### 왜 물러났나

출처가 밝힌 이유는 셋입니다.

1. **말한 사실만 믿고 게이트를 열어서, 실제로 조사했는지는 확인하지 못했습니다.** [2단계](#2단계-억지로-시키던-시기-2026년-46월)의 게이트는 누가 이 파일을 임포트하는지 **말하면** 열렸습니다. 그 말이 맞는지, 말하기 전에 실제로 파일을 열어 봤는지는 보지 않았습니다. GateGuard v0.6.0이 게이트를 여는 조건을 관측한 행동으로 바꾸고 "never on claims"라고 못 박은 이유가 여기에 있습니다. [[5]](https://github.com/zunoworks/gateguard) 반대로, 이미 조사를 마친 경우에도 막았습니다. 제작자는 옛 방식이었다면 PainBench에서 "every first edit would have been denied regardless"였다고 적었습니다. [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md)
2. **효과는 확인되지 않았는데 부작용이 보고됐습니다.** 효과 근거는 제작자가 직접 채점한 과제 3개뿐이었고[[5]](https://github.com/zunoworks/gateguard), 제작자는 그 수치를 5 계열로 넓히지 말라고 했습니다[[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md). 반면 긴 세션에서는 사실을 다시 말하고 재시도하는 과정이 모델의 반복 함정을 키운다는 보고가 올라왔습니다([이슈 #2142](https://github.com/affaan-m/ECC/issues/2142)). [[11]](https://github.com/affaan-m/ECC)
3. **최신 모델은 시키지 않아도 조사합니다.** PainBench에서 Opus 5는 게이트가 없어도 편집 전에 조사했고, "읽지 않고 편집" 과제는 게이트 유무와 상관없이 10/10이었습니다. [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md) Anthropic도 Opus 5가 스스로 검증하므로 검증 지시가 과잉 검증과 토큰 낭비를 부른다고 안내합니다. [[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) 이미 조사하는 모델에게 조사를 다시 강제하면 비용만 남습니다.

Claude Code가 최신 모델에게 읽기 요구를 푼 이유는 공식 문서와 변경 내역에 적혀 있지 않습니다. v2.1.228은 "matching the Edit tool's rules"라고만 적습니다. [[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) 그래서 이 문서는 그 이유를 추정하지 않고, 위 세 가지만 근거로 씁니다.

### 이 플러그인의 결정

위 흐름을 보고 대안 셋을 버리고 하나를 골랐습니다.

| 대안 | 결정 | 이유 |
|---|---|---|
| 파일을 처음 만질 때마다 조사한 사실을 말하게 한다([2단계](#2단계-억지로-시키던-시기-2026년-46월)의 GateGuard v0.5·ECC 방식) | 버림 | 효과 근거가 자기 채점 N=3뿐이고, 제작자가 5 계열에는 적용하지 말라고 했습니다 [[5]](https://github.com/zunoworks/gateguard), [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md). 긴 세션에서 반복 루프가 보고됐습니다 [[11]](https://github.com/affaan-m/ECC) |
| 모든 편집 전에 Read를 강제한다 | 버림 | Claude Code가 최신 모델에게 푼 제한을 다시 거는 일인데, 다시 걸 근거가 없습니다. GateGuard 제작자의 측정에서 "읽지 않고 편집" 과제는 게이트 유무에 따른 차이가 없었고 [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md), Edit는 현재 내용과 정확히 맞아야 적용되므로 모르고 덮어쓸 위험이 작습니다 [[3]](https://code.claude.com/docs/en/tools-reference) |
| 에이전트 훅이 편집마다 코드를 조사해 판정한다 | 버림 | 공식 문서가 "Agent hooks are experimental and may change."라고 적어 동작이 바뀔 수 있습니다. 판정 한 번에 최대 50턴까지 쓸 수 있어, 편집마다 부르면 지연과 비용이 편집 수만큼 늘어납니다 [[2]](https://code.claude.com/docs/en/hooks) |
| **읽지 않은 기존 파일을 Write로 덮어쓰는 것만 막는다(`rb.write`)** | **채택** | 아래에 설명합니다 |

`rb.write`를 고른 이유는 Edit와 Write의 차이에 있습니다.

- **Edit**는 `old_string`이 현재 내용과 정확히 맞아야 적용됩니다. 공식 문서는 이 방식을 "Matching against the file's current content keeps this safe"라고 설명합니다. [[3]](https://code.claude.com/docs/en/tools-reference)
- **Write**는 파일 전체를 새 내용으로 바꿉니다. v2.1.228부터 최신 모델은 읽지 않은 기존 파일에도 Write를 쓸 수 있습니다. [[4]](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- PainBench에서 게이트가 점수를 바꾼 유일한 과제도, 읽기 전에 파일을 바꾼 되돌리기 어려운 경우였습니다. [[6]](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md)

**판단:** 모르고 망가뜨릴 수 있는 자리는 Write 덮어쓰기이고, 그 자리는 되돌리기도 어렵습니다. 그래서 강제를 이 한 곳에만 남겼습니다. "읽었다"고 치는 기준은 공식 read-before-edit 기준에 맞췄습니다. Read와, 파이프 없이 파일 하나를 보는 `cat`·`head`·`sed -n`·`grep` 같은 명령입니다. [[3]](https://code.claude.com/docs/en/tools-reference)

추가 비용은 도구 호출 대부분에서 없습니다. Read와 일반 Bash는 전과 같이 약 15ms이고, 파이썬을 새로 띄우는 Write(약 45ms)와 파일을 보는 Bash(약 67ms)만 느려졌습니다. 실제 세션(claude-sonnet-5)에서는 Write가 막힌 뒤 모델이 스스로 파일을 읽고 다시 써서 통과했습니다. ([V47](VERIFICATION.md))

## 3. 근거 없는 주장은 턴이 끝나는 순간에 검사합니다

파일을 고치기 전의 조사와 달리, 근거 없는 **주장**을 막는 검사는 계속 강제합니다.

**판단:** 조사 강제가 물러난 것은 말한 사실을 믿었고, 조사를 마친 경우에도 막았기 때문입니다([왜 물러났나](#왜-물러났나)). 주장 검사는 모델의 말을 믿고 여는 대신 이 턴에 실제로 쓴 도구 기록과 답을 대조하고, 규칙에 걸린 턴에만 막습니다. 그래서 같은 문제를 피합니다. 다만 오탐은 따로 있으며 [4절](#4-알려진-한계와-다음-과제)에 적었습니다.

**판단:** 파일 편집이나 명령 실행은 도구 호출이므로 실행 전에 가로챌 수 있습니다. 그러나 "테스트를 통과했습니다" 같은 거짓 주장은 답 그 자체입니다. 아직 쓰이지 않은 문장은 검사할 수 없으므로, 답이 완성되는 턴 끝(Stop)에서 검사합니다.

공식 훅 문서가 이 방식에 필요한 입력을 줍니다.

> "The `last_assistant_message` field contains the text content of Claude's final response, so hooks can access it without parsing the transcript file." [[2]](https://code.claude.com/docs/en/hooks)

대화 기록 파일을 직접 읽는 방법은 쓰지 않았습니다. 같은 문서가 "The transcript file is written asynchronously and may lag the in-memory conversation"이라고 경고하기 때문입니다. [[2]](https://code.claude.com/docs/en/hooks)

막는 기준은 프롬프트 가이드의 agentic coding 절에서, 풀어 주는 기준은 환각 줄이기 문서에서 가져왔습니다. 코드베이스에 관한 질문에 조사 없이 답하거나 상태를 단정하면 막고, 확인할 수 없는 이유를 밝히면 통과시킵니다.

> "Never speculate about code you have not opened. (…) Make sure to investigate and read relevant files BEFORE answering questions about the codebase." [[9]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
>
> 번역: 열어 보지 않은 코드를 추측하지 마라. 코드베이스에 관한 질문에는 답하기 전에 관련 파일을 조사하고 읽어라.

> "Allow Claude to say "I don't know"" [[12]](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
>
> 번역: Claude가 모른다고 말할 수 있게 하라.

막힌 뒤에 할 일도 같은 문서를 따릅니다. 뒷받침을 찾지 못한 주장은 철회하면 됩니다.

> "If it can't find a quote, it must retract the claim." [[12]](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
>
> 번역: 인용을 찾지 못하면 그 주장을 철회해야 한다.

**이 검사가 여전히 필요하다고 본 근거.** 실제 코딩 에이전트 세션 20,574건을 분석한 연구는 이렇게 적습니다.

> "while overall rates decline, constraint violations and inaccurate self-reporting grow in share." [[7]](https://arxiv.org/abs/2605.29442)

여기서 "inaccurate self-reporting"은 에이전트가 "prematurely claiming success, completion, or readiness", 곧 성공이나 완료를 너무 일찍 주장하는 경우이고, 전체 문제 사례의 22.58%였습니다. [[7]](https://arxiv.org/abs/2605.29442) 다만 이 자료는 2026년 4월까지의 세션이라 Sonnet 5와 Opus 5 이전입니다.

**모델에게 지시하지 않는 이유.** Opus 5 가이드가 검증 지시를 지우라고 안내하므로[[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5), 이 플러그인은 모델에게 "확인하라"는 문장을 미리 넣지 않습니다. 이미 나온 답을 규칙으로 대조하고, 규칙에 걸릴 때만 메시지를 보냅니다. 의미 판정기(작은 모델)를 모든 턴이 아니라 R2a·R2b가 걸린 턴에만 부르는 이유는 [게이트 상세](gates.md)의 "왜 내장 `type: "prompt"` 훅을 쓰지 않나"에 실측과 함께 적었습니다.

## 4. 알려진 한계와 다음 과제

설계 판단이 옳다고 해서 구현이 완성된 것은 아닙니다. 2026년 9월 개발 환경에서 잰 한계를 그대로 적습니다.

**R0 오탐이 실제 사용에서 많았습니다.** 대화 기록에 남은 R0 차단 141건(서로 다른 턴 113개)을 한 턴씩 판정했습니다. 회귀 테스트·A/B 측정·판정기 세션을 뺀 실제 사용 44턴에서 정당한 차단은 0건, 오탐은 43건, 판정하기 어려운 경우가 1건이었습니다. R0가 실제 추측을 잡는 능력은, 일부러 압박 질문을 던진 테스트 세션의 정당한 차단 40턴에서 확인했습니다. ([V48](VERIFICATION.md))

- **원인 1(40턴):** 다른 플러그인이 `claude -p`로 띄운 자동 요약 세션 안에서도 게이트가 돌았습니다. 예를 들어 ECC의 세션 요약은 설정을 격리하지 않은 채 `claude --model … -p`를 실행합니다(`scripts/lib/llm-summary.js`). 요약할 대화가 질문 안에 이미 들어 있어 도구가 필요 없는데도 R0가 걸렸습니다.
- **원인 2:** 확인할 수 없다고 정직하게 답해도, 불가 면제가 그 표현을 모두 알아보지는 못합니다. `cannot verify`는 통과하지만 `cannot determine`·`판단할 수 없`·`알 수 없`은 현재 코드에서도 막힙니다.

두 원인을 고친 뒤에 효과를 다시 잴 계획입니다.

**5 계열에서의 효과는 아직 재지 않았습니다.** [3절](#3-근거-없는-주장은-턴이-끝나는-순간에-검사합니다)의 연구 자료는 2026년 4월까지의 것이고, Opus 5는 스스로 검증한다고 안내됩니다[[8]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5). `tests/no-guess-gate/ab.sh`로 다시 재야 합니다.

**`rb.write`에서 확인하지 못한 부분**은 [V47](VERIFICATION.md)에 적었습니다. Windows 실행, 일부 보기 명령(`tail`·`rg` 등), 컨텍스트 압축 뒤의 기준, 12시간을 넘는 세션입니다.

## 5. ECC와 함께 쓸 때

ECC의 GateGuard 게이트는 이 플러그인과 목적이 일부 겹칩니다. 두 도구를 함께 쓴다면 다음처럼 역할을 나누기를 권합니다.

| ECC 게이트 | 권장 | 이유 |
|---|---|---|
| 파일을 처음 편집할 때 사실 말하기 | 끄기: `ECC_DISABLED_HOOKS=pre:edit-write:gateguard-fact-force` | 조사 여부를 보지 않고 첫 편집을 막고, 말한 사실을 믿고 엽니다. [왜 물러났나](#왜-물러났나)에 적은 문제가 그대로 남습니다. 되돌리기 어려운 Write 덮어쓰기는 `rb.write`가 맡습니다 |
| 세션 첫 셸 명령에서 사실 말하기 | 끄기: `GATEGUARD_BASH_ROUTINE_DISABLED=1` | 명령 내용을 보지 않고 세션의 첫 셸 명령을 한 번 막으므로, `ls` 같은 조회 명령도 막힙니다. 위험한 명령은 아래 파괴적 명령 방어가 따로 봅니다 |
| 파괴적 명령(`rm -rf`, `git reset --hard` 등) 방어 | 켜 두기 | 이 플러그인에는 없는 방어이고, 위 두 설정으로는 꺼지지 않습니다 |

`ECC_DISABLED_HOOKS=pre:bash:gateguard-fact-force`나 `ECC_GATEGUARD=off`처럼 훅 전체를 끄면 파괴적 명령 방어까지 함께 꺼지므로 권하지 않습니다. 근거는 ECC의 `scripts/lib/hook-flags.js`와 `scripts/hooks/gateguard-fact-force.js`입니다. [[11]](https://github.com/affaan-m/ECC)

## 6. 근거가 없는 규칙은 뺐습니다

2026년 9월 15일에 게이트 규칙 16개(R0~R5, `rb.write`, `done.*` 셋, `ti.*` 넷, `pg.noverify`, append-only)의 출처를 원문과 다시 대조했습니다. 기준은 하나입니다. **무엇을 막는지가 출처 문장에 있어야 하고, 규칙의 범위가 그 문장의 범위를 넘지 않아야 합니다.** 어떻게 알아내는지(정규식·판정기)는 구현이라, 출처 대신 테스트와 [검증 기록](VERIFICATION.md) V49로 뒷받침합니다.

| 규칙 | 조치 | 이유 |
|---|---|---|
| R4: 막힌 뒤 도구 없이 다시 끝내면 막음 | **뺐습니다** | 출처로 적어 둔 환각 줄이기 문서는 뒷받침을 찾지 못한 주장을 철회하라고 합니다[[12]](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations). R4는 도구 없이 철회한 답까지 막아, 문서가 권하는 대처와 반대로 갔습니다. 다시 쓴 답도 나머지 규칙으로는 그대로 판정하므로, 확인 없이 같은 주장을 되풀이하면 여전히 막힙니다 |
| `pg.noverify`: `git commit --no-verify` 막음 | **뺐습니다** | 막으라고 권하는 문서를 찾지 못했습니다. Claude Code 문서 색인과 권한 모드 문서에 `--no-verify` 언급이 없었고, `/check:config` 의 출처 칸에도 이미 "No external source"라고 적혀 있었습니다 |
| R2a: 확인을 미루는 답 | **코드베이스 맥락으로 좁혔습니다** | 근거 문장이 "BEFORE answering questions about the codebase"로 범위를 한정합니다[[9]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices). 그 밖의 질문에 붙은 유보를 막을 근거는 없습니다 |
| R0·R1·R2a·R2b | 출처를 고쳤습니다 | 이전에 인용한 "retract the claim"은 뒷받침 없는 주장을 철회하라는 문장이고, 도구 사용이나 유보 표현을 다루지 않습니다. 이 규칙들이 막는 대상과 맞는 문장은 프롬프트 가이드의 `investigate_before_answering` 예시입니다[[9]](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) |
| R5 | 출처를 고쳤습니다 | 이전에 적은 훅 문서의 `PostToolUseFailure` 는 구현 수단입니다. 막는 이유는 "Have Claude show evidence rather than asserting success"입니다[[1]](https://code.claude.com/docs/en/best-practices) |
| `ti.assert`·`ti.exclude` | 출처를 고쳤습니다 | Kent Beck 글에는 단언을 줄이는 이야기가 없습니다[[13]](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes). EvilGenie의 "Modified Testing Procedure"가 테스트 케이스와 테스트를 돌리는 코드를 고치는 것을 다룹니다[[14]](https://arxiv.org/abs/2511.21654) |
| 마이그레이션(append-only) | 출처 링크를 고쳤습니다 | 인용한 문장은 훅 문서가 아니라 Best practices 에 있습니다[[1]](https://code.claude.com/docs/en/best-practices) |
| 마이그레이션 **삭제**(`rm`·`git rm`) 막음 | **뺐습니다**(2026-09-16, V50) | 위 대조에서 출처 링크만 고치고 범위는 따지지 않아 남았던 부분입니다. 출처는 "blocks writes to the migrations folder"까지만 말하고, [Rails 가이드](https://guides.rubyonrails.org/active_record_migrations.html)는 스키마 파일이 기준이 되면 오래된 마이그레이션을 "delete or prune"할 수 있다고 설명합니다. 이동도 막을 근거가 없어 막지 않습니다. 기존 파일 수정 차단은 두 문서와 맞아 그대로 둡니다 |

나머지 규칙(R3, `rb.write`, `done.turn`·`done.commit`·`done.pr`, `ti.skip`·`ti.rm`)은 인용한 문장이 막는 대상과 맞아 그대로 두었습니다.

**판단:** 규칙을 빼면 그만큼 덜 막습니다. 이 저장소는 "근거 없는 규칙은 넣지 않는다"를 원칙으로 두므로, 덜 막는 쪽을 택했습니다. R4가 없어도 확인 없이 같은 주장을 되풀이한 답은 R0~R3·R5에 다시 걸립니다.

## 출처

1. Claude Code, [Best practices](https://code.claude.com/docs/en/best-practices).
2. Claude Code, [Hooks reference](https://code.claude.com/docs/en/hooks).
3. Claude Code, [Tools reference](https://code.claude.com/docs/en/tools-reference).
4. Claude Code, [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md): v2.1.144(2026-05-18), v2.1.208(2026-07-13), v2.1.219(2026-07-24), v2.1.228(2026-08-11). 날짜는 npm 배포일입니다.
5. zunoworks, [GateGuard](https://github.com/zunoworks/gateguard): README와 커밋 이력(v0.2.0 공개 2026-04-11, v0.6.0 2026-07-27).
6. zunoworks, [PainBench results](https://github.com/zunoworks/gateguard/blob/main/benchmarks/painbench/RESULTS.md): 2026-07-27, subject claude-opus-5.
7. Tang 외, [How Coding Agents Fail Their Users](https://arxiv.org/abs/2605.29442): arXiv 2605.29442 v2(2026-08-31). 시기별 추세를 분석한 구간은 2025년 2월~2026년 4월입니다.
8. Anthropic, [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5): "Task scope and over-verification".
9. Anthropic, [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices): "Minimizing hallucinations in agentic coding".
10. The Register, [Cursor-Opus agent snuffs out startup's production database](https://www.theregister.com/2026/04/27/cursoropus_agent_snuffs_out_pocketos/): 2026-04-27.
11. affaan-m, [ECC](https://github.com/affaan-m/ECC): 커밋 5a03922(2026-04-12), [이슈 #2142](https://github.com/affaan-m/ECC/issues/2142)(2026-06-04), 2.2.1 병합(2026-09-07).
12. Anthropic, [Reduce hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations).
13. Kent Beck, [Augmented Coding: Beyond the Vibes](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes). 2026-09-15 확인.
14. Gabor 외, [EvilGenie: A Reward Hacking Benchmark](https://arxiv.org/abs/2511.21654): arXiv 2511.21654 v2(2026-05-17), "Modified Testing Procedure" 절. 2026-09-15 확인.
