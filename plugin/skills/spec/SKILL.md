---
name: spec
description: 코드를 쓰기 전에 나를 인터뷰하고 SPEC.md를 쓴다. 공식 best practices의 "Let Claude interview you"를 실행한다.
disable-model-invocation: true
allowed-tools: AskUserQuestion, Read, Grep, Glob, Write
---

# 스펙 인터뷰

지금부터 $ARGUMENTS 를 만든다. 코드를 쓰기 전에 나를 인터뷰해서 스펙을 확정한다.

**내가 쓰는 언어로 답한다.** `SPEC.md` 도 그 언어로 쓴다.

공식 best practices 가 이 방식을 권한다.

> "For larger features, have Claude interview you first. Claude asks about things you might not have considered yet, including technical implementation, UI/UX, edge cases, and tradeoffs."
>
> 번역: 규모가 큰 기능에서는 Claude 가 먼저 당신을 인터뷰하게 하라. Claude 는 기술적 구현, UI/UX, 예외 상황, 절충점을 비롯해 당신이 아직 고려하지 못한 것들을 묻는다.

## 무엇을 하는가

1. 저장소를 먼저 훑어서 이 작업이 어느 파일을 건드리고 어떤 패턴이 이미 있는지 파악한다. 이 대화의 컨텍스트를 지키려면 서브에이전트로 탐색한다.
2. **`AskUserQuestion` 으로 나를 인터뷰한다.** 뻔한 것은 건너뛴다. 내가 아직 생각하지 못한 것을 파고든다. 기술적 구현, 화면과 흐름, 예외 상황, 실패했을 때 벌어지는 일, 절충점이 대상이다.
3. 질문을 한꺼번에 쏟아내지 않는다. 답이 들어오는 대로 범위를 좁힌다. 앞의 답과 모순되는 답이 나오면 그 자리에서 지적한다.
4. 다 덮이면 `SPEC.md` 를 쓴다.

## 스펙에 반드시 들어가야 하는 것

공식 문서가 좋은 스펙의 조건을 셋으로 제시한다. "The most useful specs are self-contained: they name the files and interfaces involved, state what is out of scope, and end with an end-to-end verification step that proves the feature works." (번역: 가장 쓸모 있는 스펙은 그 자체로 완결된다. 관련된 파일과 인터페이스의 이름을 대고, 무엇이 범위 밖인지 밝히며, 기능이 동작함을 증명하는 종단 검증 단계로 끝맺는다.)

- **건드리는 파일과 인터페이스를 이름으로 적는다.** 추측하지 말고 실제로 읽는다.
- **범위 밖인 것을 적는다.** 이번에 하지 않을 일을 밝힌다.
- **마지막에 종단 검증 단계를 둔다.** 기능이 동작함을 증명하는 명령과 그 명령이 내놓아야 할 출력이다. 이것이 없으면 스펙이 아니라 메모다.

## 끝낸 뒤에

**새 세션에서 실행하라고 알린다.** 인터뷰로 채워진 컨텍스트를 구현까지 끌고 가는 것은 이득이 아니라 손해다. 공식 문서는 이렇게 적는다. "Once the spec is complete, start a fresh session to execute it." (번역: 스펙이 완성되면 그것을 실행할 새 세션을 시작하라.)
