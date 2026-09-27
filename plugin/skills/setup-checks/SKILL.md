---
name: setup-checks
description: 이 저장소의 검사 명령과 지킬 폴더를 확정한다. 검사를 실제로 돌려 보고 checkride.toml에 쓰고, append-only 경로와 비밀 파일 차단을 제안한다.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion
---

# 이 저장소에 맞춘다

게이트가 여기서 실제로 일하도록 설정한다. **파일을 덮어쓰기 전에 반드시 diff 를 보여 주고 승인을 받는다.**

Codex에서도 이 설정을 읽는다. 다만 자동 게이트가 실행되려면 Checkride 플러그인 훅을 설치하고 Codex에서 신뢰하거나, 저장소 관리 훅을 설치한 뒤 저장소 설정과 훅을 신뢰해야 한다. `/hooks` 에서 Checkride 훅이 활성인지 확인하기 전에는 자동 차단이 적용된다고 말하지 않는다.

**내가 쓰는 언어로 답하고,** 설정 파일의 주석도 그 언어로 쓴다.

## 1. 현재 상태를 측정한다

`SessionStart` 프로필이 이미 사실을 실어 왔다면 거기서 출발한다. 그렇지 않으면 직접 확인한다. 패키지 매니저(락파일), 스택, 기존 `checkride.toml` 의 존재 여부, `.claude/settings.json` 의 권한 설정이 대상이다.

## 2. 검사 명령을 확정한다

완료 게이트는 이 순서로 찾는다. `checkride.toml` → `package.json` 의 `scripts.test` → `Makefile` 의 `test` 타깃 → `pyproject.toml`.

**자동으로 찾아낸 것을 실제로 돌려 보고** 출력을 보여 준 뒤, 이것이 맞는지 묻는다. 돌려 보지 않고 적어 두지 않는다. 몇 분씩 걸릴 만큼 느리면 빠른 부분집합을 함께 제안한다. 공식 best practices 의 CLAUDE.md 예시가 정확히 그것을 권한다. "Prefer running single tests, and not the whole test suite, for performance." (번역: 성능을 위해 전체 테스트 스위트보다 개별 테스트를 돌리는 쪽을 택하라.)

```toml
# checkride.toml
test_command = "pnpm test"
fast_test_command = "pnpm test -- --changed"
```

## 3. 기준선을 기록한다

지금 실패하는 테스트가 있으면 목록으로 적는다. 원래 깨져 있던 것 때문에 매 턴이 막히면 사람은 게이트를 꺼 버린다. 그것부터 고칠지, 이 상태에서 출발할지 묻는다.

Willison 의 조언도 같다. "Any time I start a new session with an agent against an existing project I'll start by prompting a variant of the following: First run the tests." (번역: 기존 프로젝트에서 에이전트와 새 세션을 시작할 때마다 나는 다음과 같은 취지의 프롬프트로 시작한다. 먼저 테스트를 돌려라.)

## 4. append-only 경로를 제안한다

이력을 다시 써서는 안 되는 폴더를 찾는다. 마이그레이션이 대표적이다. `supabase/migrations`, `prisma/migrations`, `db/migrate` 가 있으면 지목한다. 없으면 그냥 넘어간다. **없는 것을 지어내지 않는다.**

```toml
append_only = "supabase/migrations, db/migrate"
```

## 5. 설정과 훅 코드 보호를 안내한다

에이전트가 검사 명령을 바꾸거나 프로젝트 훅을 끄지 못하도록 `checkride.toml`, `.claude/settings.json`, `.codex/hooks.json`, `.checkride/hooks/`를 보호할 방법을 설명한다.

- Claude Code에서는 `Read` deny가 파일 도구의 읽기와 쓰기를 함께 막으므로, 설정을 보호하면서 에이전트가 읽어야 할 `checkride.toml`에는 그대로 적용하지 않는다. 편집만 막으려면 `Edit` deny를 쓰고, 임의 프로세스까지 막아야 하면 OS 샌드박스를 쓴다. 도구 권한 규칙만으로 모든 자식 프로세스를 막는다고 말하지 않는다.
- Codex의 `sandbox_workspace_write.writable_roots`는 추가 쓰기 허용 경로다. `.checkride/`나 설정 파일을 거부 목록처럼 쓰지 않는다. 강한 경계가 필요하면 `read-only` 샌드박스 등 Codex의 지원 정책으로 설명하고, 작업 디렉터리 전체 쓰기가 필요한 경우 훅 신뢰가 그 경계를 대신하지 않는다고 알린다.
- 저장소 공유 훅은 실행 코드다. 팀이 코드를 검토하고 커밋한 뒤, 각 팀원이 프로젝트를 신뢰하고 Codex의 `/hooks`에서 현재 훅 정의를 검토·신뢰해야 실행된다. 설정이나 훅 정의가 바뀌면 다시 검토 대상이 될 수 있다.

참고한 공식 문서: [Claude Code 권한 규칙](https://code.claude.com/docs/en/permissions), [Claude Code 훅과 작업공간 신뢰](https://code.claude.com/docs/en/hooks), [Codex 설정](https://developers.openai.com/codex/config-reference), [Codex 훅](https://developers.openai.com/codex/hooks). 확인일: 2026-09-28.

## 6. 마무리

표로 보고한다. 무엇을 바꿨는지, 이제 어떤 게이트가 살아 있는지, 아직 놀고 있는 게이트는 무엇이고 왜 그런지를 적는다. 다음 세션의 프로필이 같은 내용을 보여 줄 것이다.
