@AGENTS.md

# Claude Code 전용

**이 저장소 지침의 정본은 `AGENTS.md` 다.** 맨 윗줄이 그 파일을 통째로 불러온다. 규칙을 고칠 때는 이 파일이 아니라 `AGENTS.md` 를 고친다. 같은 사실을 두 곳에 두면 한쪽만 정정되고 틀린 쪽이 계속 주입된다.

Claude Code 에만 해당하는 규칙이 생기면 이 줄 아래에 적는다. 지금은 없다.

## 왜 심링크가 아니라 import 인가

`AGENTS.md` 와 `CLAUDE.md` 가 둘 다 있으면 Claude Code 는 `CLAUDE.md` 만 읽는다. 공식 문서의 표가 그렇게 정하고 있어서, 정본을 `AGENTS.md` 에 두려면 여기서 불러오는 수밖에 없다.

불러오는 방법은 `@` import 와 심링크 둘인데 이 저장소는 import 를 쓴다. 공식 문서가 이유를 적는다.

> "**Windows**: if you or anyone who clones the repository works on Windows, use the `@AGENTS.md` import instead. Creating a symlink there needs Administrator privileges or Developer Mode, and Git checks a committed symlink out as a plain text file unless `core.symlinks` is enabled, which leaves that clone with a one-line `CLAUDE.md` in place of your instructions"
>
> 번역: 당신이나 저장소를 클론하는 누군가가 Windows 에서 작업한다면 `@AGENTS.md` import 를 쓰십시오. 거기서 심링크를 만들려면 관리자 권한이나 개발자 모드가 필요하고, `core.symlinks` 가 켜져 있지 않으면 Git 이 커밋된 심링크를 평범한 텍스트 파일로 체크아웃해서 그 클론에는 지침 대신 한 줄짜리 `CLAUDE.md` 가 남습니다.

이 저장소는 Windows 를 CI 매트릭스에 두고 기여를 받으므로 그 경우에 해당한다. 출처는 [How Claude remembers your project](https://code.claude.com/docs/en/memory), 2026-09-22 확인.
