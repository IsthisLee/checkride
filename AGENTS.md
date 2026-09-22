# checkride

**이 파일이 이 저장소 지침의 정본이다.** 코딩 에이전트가 공유하는 `AGENTS.md` 규약을 따른다. `CLAUDE.md` 는 이 파일을 `@` 로 불러오는 포인터일 뿐이므로, 규칙을 고칠 때는 그쪽이 아니라 이 파일을 고친다. Claude Code 전용 규칙이 생기면 `CLAUDE.md` 의 import 아래에 적는다.

Claude Code 공식 best practices와 검증된 문서의 권고를 **훅으로 강제**하는 플러그인이다. 게이트 네 개(근거·완료·테스트 무결성·프로젝트 가드), 저장소 프로필, 사용자 전용 커맨드 여덟 개로 이뤄진다.

## 검사 명령

- `tests/lib/unit.sh` — 메시지 카탈로그 26건. 두 언어의 키가 맞는지, 언어 결정 순서(NGG_LANG · .check.toml lang · 로케일)가 맞는지, 카탈로그가 사라져도 조용히 통과하지 않는지 본다.
- `tests/no-guess-gate/unit.sh` — 근거 게이트 170건. 모델을 부르지 않는다.
- `tests/done-gate/unit.sh` — 완료 게이트 83건. PR 본문 근거 23건 포함.
- `tests/test-integrity/unit.sh` — 테스트 무결성 69건.
- `tests/project-guard/unit.sh` — 프로젝트 가드 23건.
- `tests/repo-profile/unit.sh` — 저장소 프로필 29건. 커밋 가드가 꺼진 저장소를 세션 머리에 알리는지 6건 포함.
- `tests/setup/unit.sh` — 활성화 스크립트 14건. 남이 잡은 `core.hooksPath` 를 덮지 않는지 본다.
- `tests/skills-unit.sh` — 스킬 정의 5건.
- `tests/attack-surface.sh` — SECURITY.md가 적은 공격면과 코드가 맞는지 9건.
- `tests/invariants.sh` — 매니페스트·CHANGELOG·문서의 숫자, 셸 인용, 하네스의 카탈로그 복사, 메시지 키 커버리지, `setup.sh` 배선, 옛 이름 잔존 21건.  **합계 449건.**
- `tests/fuzz.sh` — 망가진 입력을 열 훅에 던져 조용히 통과하지 않는지 본다. 모델을 부르지 않는다.
- `tests/no-guess-gate/selftest.sh` — 실제 프롬프트 회귀 12케이스. Haiku를 부르고 몇 분 걸린다.
- `tests/no-guess-gate/ab.sh` — 게이트 켠 채와 끈 채를 비교해 효과를 잰다. `SET=hard`가 압박 프롬프트.
- `tests/no-guess-gate/judge-accuracy.sh` — 판정기 정확도와 소요 시간. 의견 여섯·상태 주장 여섯. README가 인용하는 숫자가 여기서 나온다. 모델을 부르고 몇 분 걸린다.
- `tests/acceptance.sh` — 새 사용자 관점. 빈 프로젝트를 만들어 플러그인을 걸고 게이트와 스킬을 실제로 돌린다. 모델을 부르고 몇 분 걸린다. **단위 테스트가 못 보는 것, 곧 설치한 사람이 겪는 것을 본다.**
- `shellcheck -x -s bash plugin/hooks/*/*.sh tests/*.sh tests/*/*.sh` · `actionlint`
- `claude plugin validate .` · `claude --plugin-dir .`

## 규칙

- 훅을 고치면 **테스트를 먼저 쓴다.** RED를 보고 나서 구현하고, `unit.sh` 전건 통과를 확인한다. 회귀 로직을 건드렸으면 `selftest.sh`도 돌린다.
- 모든 검증은 실행 명령과 출력 원문을 `docs/VERIFICATION.md`에 남긴다. "확인했다"는 말만으로는 기록하지 않는다.
- 게이트 규칙은 공식 문서나 검증된 문서에 근거가 있어야 한다. 근거 없는 규칙은 넣지 않는다. **무엇을 막는지가 출처 문장에 있어야 하고, 규칙의 범위가 그 문장의 범위를 넘지 않아야 한다.** 탐지 방법(정규식·판정기)은 구현이라 테스트와 VERIFICATION 으로 뒷받침한다. 출처 문장은 원문을 열어 확인하고 확인일을 적는다(V49에서 R4·`pg.noverify`, V50에서 마이그레이션 삭제 차단, V51에서 `rb.write` 를 이 기준으로 뺐다). **최신 문서에 정확한 근거가 없으면 범위를 좁혀 보수적으로 적용한다.**
- 커밋에 개인 정보를 넣지 않는다. 홈 경로, 이메일, 사적인 저장소 이름이 들어가면 `.githooks/pre-commit`이 막는다. `git config core.hooksPath .githooks`로 켠다.
- `.private/`는 별도 저장소다. 검토 초안과 스펙이 있고 공개 저장소에는 올리지 않는다.
- 커밋 메시지는 `type(scope): 요약` 형식이고 본문에 무엇을 왜 바꿨는지 적는다.
- **병합은 squash 로 한다.** PR 하나가 `main` 의 커밋 하나가 되므로 **되돌릴 단위는 커밋이 아니라 PR 이다.** 그래서 **PR 을 기능 단위로 쪼개서 올린다.** 관련 없는 변경을 한 PR 에 묶으면 그중 하나만 되돌릴 수 없다. 저장소 설정이 `squash` 만 허용하므로 `--rebase` 와 `--merge` 는 거부된다.
- **`main` 의 이력에 남는 것은 PR 의 제목과 본문이다.** 브랜치의 커밋 메시지는 작업용이고 남지 않는다. 그러므로 **PR 제목을 `type(scope): 요약` 형식으로 쓰고, 본문을 이력에 그대로 남을 글로 쓴다.** 브랜치 안에서 커밋을 어떻게 나누든 자유다. 이것은 저장소 설정에 달려 있으므로 의심스러우면 실제로 확인한다.

  ```
  $ gh api repos/IsthisLee/checkride --jq '{merge:.allow_merge_commit, rebase:.allow_rebase_merge, squash:.allow_squash_merge, title:.squash_merge_commit_title, message:.squash_merge_commit_message}'
  {"merge":false,"message":"PR_BODY","rebase":false,"squash":true,"title":"PR_TITLE"}
  ```

## 구조

**저장소는 두 층이다.** `plugin/` 만 사용자에게 실린다. 설치본은 25개 파일이고 그중 도는 것은 훅 열 개와 스킬 여덟 개다.
공식 마켓플레이스와 tdd-guard 가 같은 방식이다(`source: "./plugin"`). 플러그인 설치는 폴더를 통째로 복사하고 제외 방법이 없다.
**테스트·도구·문서·CI 를 `plugin/` 안에 두지 않는다.** 두면 사용자가 그것까지 내려받는다.

- `plugin/hooks/hooks.json` — SessionStart · UserPromptSubmit · PreToolUse(넷) · PostToolUse · Stop(둘) · SubagentStop 배선. 상태는 `${CLAUDE_PLUGIN_DATA}`.
- `plugin/hooks/no-guess-gate/bashres.sh` — `PostToolUse`·`PostToolUseFailure`(Bash)에서 이 턴의 Bash 결과를 `S`/`F`로 남긴다. R5가 마지막 글자만 본다.
- `plugin/hooks/lib/common.sh` — 모든 훅이 공유하는 입력 파서와 메시지 함수 `t`·`tn`, 항목 끄기(`item_off`)와 한 번 허용(`allow_once`). 허용 목록은 `no-guess-gate/prompt.sh`가 사용자 프롬프트에서만 적는다. `no-guess-gate/pre.sh`는 도구 호출마다 돌아 파라미터 확장만 쓰는 빠른 경로가 따로 있다.
- `plugin/hooks/lib/msg.sh` — 사람과 모델에게 나가는 문장 62개를 한국어와 영어로 담는다. 차단이 일어날 때만 읽는다. **훅 안에 문장을 직접 쓰지 않는다.** 한쪽 언어에만 넣으면 `tests/lib/unit.sh`가 잡는다.
- `plugin/hooks/no-guess-gate/stop.sh` — 규칙 R0~R5와 면제 다섯. `judge.py`가 R2a·R2b만 걸렸을 때 의견인지 상태 주장인지 작은 모델에게 묻는다(`NGG_JUDGE_MODEL`, 기본 haiku).
- `.check.toml` 이 읽는 키는 다섯이다. `test_command`·`fast_test_command`(완료 게이트), `append_only`(프로젝트 가드), `disabled_rules`(근거 게이트의 규칙과 다른 게이트의 항목을 하나씩 끄기. 이름 목록은 `common.sh`의 `NGG_ITEMS`), `lang`(게이트 메시지 언어. `common.sh`의 `ngg_lang_cfg`가 차단 메시지를 낼 때만 읽고, `NGG_LANG`이 있으면 무시한다). **파서는 한 줄에 키 하나다.** macOS 기본 파이썬(3.9)에 `tomllib` 이 없어 온전한 TOML 파서를 쓰지 않는다.
- `plugin/hooks/done-gate/` — 코드를 고친 턴에 저장소 검사를 돌린다. 이 저장소의 `.check.toml`이 자기 테스트를 가리킨다.
- `plugin/hooks/test-integrity/` — 테스트 무력화 편집, 테스트 파일 삭제, 러너 설정의 제외 추가를 막는다.
- `plugin/hooks/project-guard/` — `append_only` 경로의 기존 파일 수정을 막는다. 새 파일 추가와 삭제는 막지 않는다(V50). Edit·Write 에만 배선한다.
- `plugin/hooks/repo-profile/` — `SessionStart`에 저장소 사실을 컨텍스트로 싣는다. 사실만 싣고 행동 지시는 넣지 않는다.
- `skills/` — 사용자 전용 커맨드 여덟 개. 내장과 겹치는 것은 만들지 않는다. 새 스킬을 넣으면 `tests/skills-unit.sh`가 정의를 검사한다.
- **훅을 임시 폴더로 복사해 돌리는 하네스는 `lib/`를 통째로 옮긴다.** `msg.sh`를 빠뜨리면 게이트는 여전히 막지만 모델이 받는 문장이 `ngg.r0` 같은 키 이름이 된다. 막히기만 하고 무엇을 하라는지 모르니 측정값이 통째로 달라진다. `tests/invariants.sh`가 `cp` 줄을 본다.
- **중괄호 없는 변수 뒤에 한글을 붙이지 않는다.** `"$n개"`는 bash가 `n개`를 변수 이름으로 읽고, `set -u` 아래서는 그 자리에서 죽는다. 실패 분기에 있으면 통과할 때는 안 보이다가 정작 실패를 알려야 할 때 죽는다. **이 저장소에서 세 번 났다.** `${n}개`로 쓴다. `tests/invariants.sh`가 전수로 막는다.
- **테스트가 훅에 넣는 입력 JSON 은 `printf` 로 만든다.** Git Bash 는 네이티브 파이썬에 POSIX 경로를 **인자로** 넘길 때 `C:/Users/...` 로 바꾼다. 그러면 `cwd` 만 Windows 경로가 되고 `changed` 는 `/tmp/...` 로 남아 접두가 안 맞고, 게이트가 코드 파일을 0개로 세어 조용히 통과한다. **로컬에서는 안 보이고 Windows CI 에서만 빨갛다.** 파이프로 넘기는 것은 변환되지 않으므로 무방하다.
- **정규식의 대괄호 안에 멀티바이트 문자를 넣지 않는다.** `[.!?。]`처럼 쓰면 `LC_ALL=C`에서 `grep`·`sed`가 바이트로 매칭해 한국어 글자를 한가운데서 자르고 R1이 조용히 안 걸린다. 교체(`|`)로 쓴다.
- **메시지 언어는 로케일을 따른다.** `NGG_LANG`이 우선하고, 없으면 `.check.toml`의 `lang`, 그것도 없으면 `LC_ALL` → `LC_MESSAGES` → `LANG` 순으로 본다. `ko` 계열이면 한국어, 그 외에는 영어다. 단위 테스트는 머리에서 `NGG_LANG=ko`를 못 박아 기계마다 결과가 달라지지 않게 한다.
- **테스트는 주변 환경에 기대지 않는다.** `unit.sh`가 머리에서 `NGG_*`를 `unset`한다. 게이트가 자식에게 물려주는 변수 때문에 폴백 검사가 조용히 뒤집힌 적이 있다. **테스트를 돌리는 폴더도 환경이다.** `tests/lib/unit.sh`의 `run`은 `CWD`를 빈 폴더로 준다. 이 저장소 `.check.toml`에 `lang`을 넣자 로케일 폴백 검사 네 건이 뒤집힌 적이 있다.
- 요구 사항: bash, python3. macOS · Linux · Windows 셋 다 CI 매트릭스에 있다. Windows는 Git Bash가 있어야 한다.
- **우리 파이썬 호출에는 `py`를 쓴다.** Windows 파이썬은 기본 인코딩이 UTF-8이 아니라 한국어가 지나가면 죽는다. `common.sh`의 `py()`가 `PYTHONUTF8=1`을 붙인다. 전역으로 export하지 않는 이유는 `done-gate`가 남의 테스트 명령을 그대로 돌리기 때문이다.

