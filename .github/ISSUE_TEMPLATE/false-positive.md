---
name: 오탐 신고 / False positive (blocked when it shouldn't be)
about: 근거를 댔거나 댈 필요가 없는 답이 게이트에 막혔을 때 / An answer that was grounded, or needed no grounding, got blocked
labels: false-positive
---

<!-- 한국어 또는 영어, 편한 쪽으로 적어 주세요. / Write in Korean or English, whichever is easier. -->

## 무엇이 막혔나 / What got blocked

막힌 답의 해당 문장을 붙여 주세요. 전문이 아니어도 됩니다.
Paste the sentence that was flagged. The whole answer is not needed.

## events.log 줄 / The `events.log` line

`${CLAUDE_PLUGIN_DATA}/state/events.log`의 마지막 줄이면 충분합니다. 어느 규칙이 걸렸는지 `viol=[...]`에 있습니다.
The last line of that file is enough. `viol=[...]` names the rule that fired.

```
여기에 붙여 주세요 / paste here
```

## 왜 오탐이라고 보시나요 / Why you think it is a false positive

예를 들어 "설계 의견이라 확인할 로컬 상태가 없다", "이미 도구로 확인한 내용이다" 같은 것입니다.
For example: "it was a design opinion, so there is no local state to check", or "a tool had already confirmed it".

## 환경 / Environment

- OS:
- Claude Code 버전 / version:
- `NGG_JUDGE` 켜짐 / 꺼짐 · on / off:
- `.checked-practices.toml`의 `disabled_rules` (있다면 / if any):
