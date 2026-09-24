# 보안 정책

한국어 · **[English](SECURITY.en.md)**

## 이 플러그인의 공격면

훅은 **당신의 권한으로 셸 명령을 실행한다.** 이 플러그인을 설치한다는 것은 그 코드를 신뢰한다는 뜻이므로, 무엇을 하는지 적어 둔다.

| 무엇                                             | 어디                                                  | 위험                                              |
| ------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------- |
| 매 프롬프트·도구 호출·턴 종료에 셸 스크립트 실행 | `hooks/hooks.json` → `hooks/no-guess-gate/*.sh`       | 스크립트가 바뀌면 임의 코드가 돈다                |
| Claude의 마지막 답 전문을 읽음                   | `stop.sh`가 훅 입력의 `last_assistant_message`를 받음 | 답에 담긴 내용이 판정 로직을 지난다               |
| 프롬프트·도구 이름·판정 로그를 파일에 씀         | `${CLAUDE_PLUGIN_DATA}/state/`                        | 프롬프트 앞부분과 답 80자가 `events.log`에 남는다 |
| 모델 호출 (선택)                                 | `judge.py`가 `claude -p --model haiku` 실행           | 걸린 문장이 모델에 전달된다                       |

**네트워크로 나가는 것은 판정기 하나뿐이고, 그것도 당신의 Claude Code를 거친다.** 외부 서비스로 보내는 것은 없다. 판정기를 끄려면 `NGG_JUDGE=0`이다.

`events.log`가 남기는 것은 프롬프트 일부와 답의 처음 80자다. 민감한 내용을 다루는 저장소라면 `${CLAUDE_PLUGIN_DATA}/state/`를 주기적으로 지우거나 게이트를 그 저장소에서 끄면 된다(`claude plugin disable checkride@checkride --scope project`).

## 설치할 것을 직접 확인하는 법

이 플러그인은 당신의 권한으로 셸을 실행한다. 그러니 무엇을 받는지 스스로 확인할 수 있어야 한다.

**릴리스 태그는 서명돼 있다.** 받아서 검증할 수 있다.

```bash
git clone https://github.com/IsthisLee/checkride
cd checkride
git tag -v v1.4.1        # Good "git" signature 가 나와야 한다
```

**실리는 것은 `plugin/` 뿐이다.** 28개 파일이며 Claude Code와 Codex용 매니페스트·훅 어댑터, 기존 훅과 스킬이 들어 있다. 테스트·문서·CI는 설치본에 들어가지 않는다.

```bash
git ls-files plugin | wc -l          # 28
cat plugin/hooks/hooks.json          # Claude Code 훅 이벤트
cat plugin/hooks/hooks.codex.json    # Codex 훅 이벤트
```

**`main` 브랜치는 강제 푸시와 삭제를 막아 두었다.** 당신이 어제 읽은 코드가 오늘 조용히 바뀌지 않는다.

**공격면이 코드와 맞는지는 검사로 확인한다.** `tests/attack-surface.sh` 가 이 문서의 약속을 매번 대조한다. 네트워크 명령 없음, 모델 호출은 `judge.py` 하나, 판정기 격리 플래그 셋, 프로필이 `.env` 값을 안 읽음, 시스템 경로에 안 씀, 훅 전부 타임아웃.

## 우리가 이미 막은 것

[![CodeQL](https://github.com/IsthisLee/checkride/actions/workflows/codeql.yml/badge.svg)](https://github.com/IsthisLee/checkride/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/IsthisLee/checkride/badge)](https://scorecard.dev/viewer/?uri=github.com/IsthisLee/checkride)

**판정기 프롬프트 주입.** 판정기는 Claude의 답을 모델에게 넘긴다. 답 안에 판정 JSON을 심어 두면 판정으로 읽혀 게이트가 풀릴 수 있었다. 답 텍스트를 데이터 블록으로 감싸고, 중괄호와 판정 키워드를 중화하고, 응답의 마지막 JSON만 읽도록 고쳤다. 회귀 테스트가 `unit.sh` 12군에 있다. 기록은 `docs/VERIFICATION.md` V4f.

**조용한 무력화.** `python3`가 없거나 훅이 시간을 넘기면 게이트가 아무 말 없이 통과시킬 수 있었다. 지금은 stderr로 알리고 exit 1로 끝내며, 배선에 타임아웃을 못 박았다. V4b, V4g.

## 신고

취약점을 찾으면 **공개 이슈로 올리지 말고** 저장소 소유자에게 GitHub 비공개 취약점 신고(Security → Report a vulnerability)로 알려 달라. 재현 절차와 영향 범위를 적어 주면 좋다.

다음은 취약점으로 다룬다.

- 게이트를 무력화하는 입력. 특히 Claude의 답이나 사용자 프롬프트로 판정을 뒤집는 것
- 훅이나 판정기를 통해 의도하지 않은 명령이 실행되는 경로
- `events.log`나 상태 파일이 의도보다 많은 것을 남기는 경우

다음은 취약점이 아니다.

- 오탐과 미탐. 이슈로 올려 달라. 실제로 걸린 `events.log` 줄을 같이 주면 빠르다
- 훅을 설치한 사람이 스스로 스크립트를 고치는 것. 훅은 원래 그 사람의 권한으로 돈다
