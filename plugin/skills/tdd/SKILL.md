---
name: tdd
description: 실패하는 테스트를 먼저 쓰고, 실패를 눈으로 확인한 뒤 구현한다.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Red / Green

$ARGUMENTS 를 테스트부터 만든다.

**내가 쓰는 언어로 답한다.**

Willison 의 지침에서 가장 중요한 문장은 이것이다.

> "It's important to confirm that the tests fail before implementing the code to make them pass."
>
> 번역: 테스트를 통과시킬 코드를 구현하기 전에 그 테스트가 실패하는지 확인하는 것이 중요하다.

Kent Beck 도 같은 말을 한다. "Write the simplest failing test first" (가장 단순한 실패 테스트를 먼저 써라), "Implement the minimum code needed to make tests pass—no more." (테스트를 통과시키는 데 필요한 최소한의 코드만 구현하라. 그 이상은 안 된다.)

## 순환

1. **가장 단순한 실패 테스트 하나**를 쓴다. 여러 개를 한꺼번에 쓰지 않는다.
2. **돌려서 RED 를 확인한다.** 출력을 그대로 붙인다. 이것을 건너뛰면 그 테스트가 무엇을 지키는지 아무도 모른다. 이미 통과한다면 그 테스트가 틀린 것이므로 테스트를 고친다.
3. 통과시키는 **최소한의 코드**를 쓴다.
4. 돌려서 GREEN 을 확인한다. 출력을 그대로 붙인다.
5. 중복을 없앤다. 테스트는 건드리지 않고 구조만 바꾼다.
6. 다음 테스트로 돌아간다.

## 막혔을 때

통과하지 않는 테스트는 **테스트를 고칠 이유가 되지 않는다.** Claude Code에서는 테스트 무결성 게이트가 `.skip` 추가와 단언 삭제를 막는다. Codex에서는 게이트가 실행되지 않으므로 이 지침을 직접 따른다.

요구사항이 실제로 바뀌어서 그 테스트가 이제 틀린 것이라면, **무엇이 바뀌어서 틀렸는지**를 한 줄로 적고 확인을 받은 뒤에만 고친다.

## 관련

`superpowers` 플러그인이 설치돼 있으면 `superpowers:test-driven-development` 를 대신 따른다. 그쪽이 더 촘촘하다. 이 커맨드는 RED 확인을 강제하는 얇은 껍데기다.
