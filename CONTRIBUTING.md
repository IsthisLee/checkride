# 기여 안내

한국어 · **[English](CONTRIBUTING.en.md)**

이 저장소의 규칙은 하나로 요약된다. **주장에는 근거를 붙인다.** 플러그인이 Claude에게 요구하는 것과 같은 기준을 기여자에게도 적용한다.

참여하는 모든 사람은 [행동 강령](CODE_OF_CONDUCT.md)을 따른다.

## 개발 환경

필요한 것은 `bash`, `python3`, 그리고 Claude Code다. macOS와 Linux, 그리고 Git Bash가 있는 Windows에서 돌아간다.

```bash
git clone https://github.com/IsthisLee/did-you-check
cd did-you-check
./setup.sh                            # 개인 정보 커밋을 막는 훅을 켠다
claude --plugin-dir .                 # 설치본 대신 이 폴더를 그 세션에 로드
```

## 검사

바꾸기 전과 후에 돌린다.

```bash
for g in lib no-guess-gate done-gate test-integrity project-guard repo-profile; do tests/$g/unit.sh; done
tests/skills-unit.sh && tests/attack-surface.sh && tests/invariants.sh
tests/fuzz.sh                                  # 망가진 입력을 열 훅에 던진다
shellcheck -x -s bash plugin/hooks/*/*.sh tests/*.sh tests/*/*.sh
python3 -m py_compile plugin/hooks/no-guess-gate/judge.py
claude plugin validate . --strict
```

모델을 부르는 둘은 몇 분 걸려 CI에 넣지 않았다.

```bash
tests/no-guess-gate/selftest.sh         # 실제 프롬프트 회귀 12케이스
tests/no-guess-gate/judge-accuracy.sh   # 판정기 정확도와 소요 시간
```

CI는 문법 검사, `shellcheck -x`, actionlint, 단위 스위트를 ubuntu·macos·windows 셋에서 돌린다. 훅 판정 로직을 건드렸으면 **모델을 부르는 쪽은 직접 돌리고 결과를 PR에 붙인다.**

## 게이트 규칙을 고칠 때

1. **테스트를 먼저 쓴다.** 해당 `unit.sh`에 케이스를 넣고 RED를 눈으로 본다. 실패하지 않는 테스트는 아무것도 지키지 못한다.
2. 구현하고 전건 통과를 확인한다.
3. 판정 로직을 건드렸으면 `selftest.sh`도 돌린다.
4. `docs/VERIFICATION.md`에 **실행한 명령과 출력 원문**을 남긴다. "확인했다"는 말만으로는 기록하지 않는다.

새 규칙이나 면제를 넣으려면 **공식 문서나 검증된 문서에 근거가 있어야 한다.** 근거를 PR 본문에 원문으로 인용한다. 근거가 없으면 그 사실을 적고 왜 필요한지 설명한다. 근거 없는 규칙은 그 자체로 이 플러그인이 막으려는 것이다.

오탐을 고칠 때는 실제로 걸린 사례를 함께 낸다. `events.log`의 해당 줄이면 충분하다.

## 커밋과 PR

커밋 메시지는 `type(scope): 요약` 형식이고, 본문에 무엇을 왜 바꿨는지 적는다. 바꾼 이유가 실측이면 그 숫자를 적는다.

PR에는 실행한 검사의 출력을 붙인다. 직접 검토하지 않은 코드로 PR을 올리지 않는다.

## 올리면 안 되는 것

`.githooks/pre-commit`이 홈 경로, 이메일, 사적인 경로가 든 커밋을 막는다. `./setup.sh`로 켜 두면 실수해도 걸린다. 켜는 방법과 패턴 목록을 두는 곳은 [docs/PUBLIC-REPO-GUARD.md](docs/PUBLIC-REPO-GUARD.md)에 있다. 훅이 막았는데 오탐이라고 판단되면 `--no-verify` 대신 이슈로 알려 달라.
