---
name: full-cycle
description: 탐색부터 PR까지 전 과정을 돈다. 검토에서 결함이 나오면 구현으로 돌아가 고치고 다시 검토받는다.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Task, AskUserQuestion
---

# 처음부터 끝까지

$ARGUMENTS 를 처음부터 끝까지 진행한다.

**내가 쓰는 언어로 답한다.**

공식 best practices 의 네 단계를 따른다. 탐색 → 계획 → 구현 → 커밋이다. **검토에서 결함이 나오면 구현으로 돌아간다(최대 두 번).** 단계를 새로 만들지 말고 이미 있는 것을 부른다.

## 0. 크기를 먼저 잰다

diff 를 한 문장으로 설명할 수 있으면 계획을 건너뛴다. 공식 문서의 문장이다. "If you could describe the diff in one sentence, skip the plan." (번역: diff 를 한 문장으로 설명할 수 있다면 계획을 건너뛰라.) 작은 일에 절차를 두르면 사람들이 이 커맨드를 쓰지 않게 된다.

그보다 큰 일이면 아래 단계를 밟는다.

## 1. 탐색

**내장 Explore 서브에이전트**에 넘긴다. 자기 컨텍스트에서 돌고 결론만 돌려주므로 이 대화가 파일 내용으로 차지 않는다. 공식 문서의 문장이다. "Use subagents to keep research out of it." (번역: 조사 내용이 컨텍스트에 들어오지 않도록 서브에이전트를 써라.)

## 2. 계획

**plan mode** (`Shift+Tab`) 로 들어가 계획을 쓴다. 승인 전에는 코드를 바꾸지 않는다. 계획해 보니 큰 기능이라면 `/check:spec` 으로 스펙부터 확정하자고 제안한다.

## 3. 구현

`/check:tdd` 의 순환을 따른다. 실패 테스트 먼저, RED 확인, 최소 구현, GREEN 확인이다.

이 단계 내내 게이트 네 개가 모두 살아 있다. 근거 없이 단정하면 근거 게이트가 막고, 검사를 돌리지 않고 끝내려 하면 완료 게이트가 막고, 테스트를 무력화하려 하면 무결성 게이트가 막고, 이력을 다시 쓰려 하면 프로젝트 가드가 막는다. **게이트가 막으면 게이트가 옳다고 전제하고 가서 실측한다.**

## 4. 검토

**내장 `/code-review`** 를 부른다. 새 서브에이전트가 diff 를 판정하므로 작성자가 자기 작업을 스스로 채점하지 않게 된다.

지적을 받으면 **정확성이나 명시된 요구사항에 영향을 주는 것만** 고른다. 공식 문서의 주의가 그것이다.

> "Tell the reviewer to flag only gaps that affect correctness or the stated requirements, and treat the rest as optional."
>
> 번역: 정확성이나 명시된 요구사항에 영향을 주는 결함만 지적하고 나머지는 선택 사항으로 다루라고 리뷰어에게 일러라.

**고를 것이 있으면 3단계로 돌아간다.** 고치고 다시 `/code-review` 를 부른다. 선택 사항으로 분류한 지적으로는 돌아가지 않는다. 모든 지적을 쫓아다니면 과잉 설계로 끝난다.

**돌아가는 것은 두 번까지다.** 두 번 돌고도 같은 지적이 남으면 멈추고, 무엇을 시도했고 무엇이 안 됐는지 보고한다. 공식 best practices 가 같은 숫자를 든다.

> "After two failed corrections, `/clear` and write a better initial prompt incorporating what you learned."
>
> 번역: 두 번 고쳐서 실패하면 `/clear` 하고, 배운 것을 반영한 더 나은 첫 프롬프트를 써라.

실패한 접근이 쌓이면 그다음 판단까지 흐려진다.

**지적을 직접 확인하고 나서 고친다.** 리뷰어도 틀린다. 지적받은 자리를 열어 읽고, 사실이면 고치고, 사실이 아니면 왜 아닌지 한 줄로 적는다.

화면이 바뀌었으면 **내장 `/verify`** 를 돌려 직접 보라고 알린다. 이 커맨드가 대신 눌러 볼 수는 없다.

## 5. 마무리

검사와 커밋과 PR 은 `/check:finish` 로 한다. 세션이 여기서 끝난다면 `/check:handoff` 도 돌린다.

## 단계마다

각 단계를 마치면 **무엇을 했고 무엇이 남았는지**를 한 줄로 보고한다. 어느 쪽으로도 갈 수 있는 판단은 혼자 정하지 말고 `AskUserQuestion` 으로 묻는다.
