---
name: 미탐 신고 / False negative (should have been blocked)
about: 근거 없는 단정이 그대로 통과했을 때 / An ungrounded claim went through
labels: false-negative
---

<!-- 한국어 또는 영어, 편한 쪽으로 적어 주세요. / Write in Korean or English, whichever is easier. -->

## 통과한 답 / The answer that passed

근거 없이 단정한 문장을 붙여 주세요.
Paste the sentence that was asserted without evidence.

## 그 턴에 도구를 썼나요 / Were any tools run that turn

`events.log`의 `tools=` `bash=` 값이면 충분합니다.
The `tools=` and `bash=` values from `events.log` are enough.

```
여기에 붙여 주세요 / paste here
```

## 어느 규칙이 잡았어야 한다고 보시나요 / Which rule should have caught it

- **R0** 상태 질문에 도구 0회 / asked about local state, zero tools run
- **R1** 경로 단정 / asserted a path or file state
- **R2a** 확인 미룸 / deferred verification
- **R2b** 추정으로 메움 / filled in checkable state with a guess
- **R3** 검증 주장 / claimed tests or verification ran
- **R5** 마지막 명령이 실패했는데 통과 주장 / last command failed, yet success was claimed
