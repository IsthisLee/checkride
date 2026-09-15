# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# 게이트가 사람과 모델에게 내보내는 문장만 모았다. 규칙 판정에는 쓰이지 않는다.
# 언어는 common.sh의 ngg_lang()이 정한다. NGG_LANG이 우선하고, 없으면 로케일이 ko 계열일 때만 한국어다.
# msg()는 값을 M에 담는다. 되돌려 주는 대신 전역에 넣는 이유는 서브셸을 피하기 위해서다.

# M 은 common.sh 의 tn() 이 읽는다. 파일이 갈려 있어 shellcheck 가 못 본다.
# shellcheck disable=SC2034
msg() { M=""; [ "${NGG_L:-en}" = ko ] && { msg_ko "$1"; return 0; }; msg_en "$1"; }

msg_ko() { case "$1" in
  err.python3)   M="no-guess-gate: python3로 훅 입력을 읽지 못했다. 이 턴은 판정하지 않았다. python3 설치와 PATH를 확인하라." ;;

  ngg.head)      M="근거 없는 결론 게이트 [%s]. 턴을 끝낼 수 없다." ;;
  ngg.offbad)    M="  (.check.toml 의 disabled_rules 에 없는 규칙 이름이 있다: %s. 아무것도 끄지 않았다.)" ;;
  ngg.r0)        M="- R0: 사용자가 이 디렉터리/파일/코드의 상태를 물었는데 도구를 한 번도 실행하지 않았다. 지금 Read/Grep/Glob/Bash로 확인하라." ;;
  ngg.r1)        M="- R1: 도구 실행 없이 특정 경로/파일의 상태를 단정했다. 지금 실제로 확인하라." ;;
  ngg.r2a)       M="- R2a: 도구를 한 번도 쓰지 않고 '확인이 필요하다'류의 유보 표현으로 끝냈다. 지금 확인하라. 정말 확인할 수 없는 상황이면 왜 불가능한지 답에 적어라. 모른다고 말하는 것은 허용되지만, 확인할 수 있는데 미루는 것은 안 된다." ;;
  ngg.r2b)       M="- R2b: 로컬 상태에 대해 추정 표현('아마', 'probably', 'appears')을 썼다. 실측해서 단정하라." ;;
  ngg.r3)        M="- R3: 테스트/검증/확인을 했다고 주장하지만 이 턴에 Bash 실행이 0건이다. 실제로 실행하고 그 출력을 근거로 답하라." ;;
  ngg.r4)        M="- R4: 직전 차단 이후 도구를 하나도 실행하지 않았다. 사과나 설명으로 턴을 끝낼 수 없다. 지금 실측하거나 AskUserQuestion으로 물어라." ;;
  ngg.r5)        M="- R5: 이 턴에 마지막으로 돌린 명령이 실패했는데 검증·성공을 주장했다. 실패한 출력을 근거로 삼을 수는 없다. 고쳐서 다시 돌리거나, 무엇이 실패했는지 답에 적어라." ;;
  ngg.judgekept) M="- 모델 판정: 상태 주장으로 봄(%s). 규칙 판정을 유지한다." ;;
  ngg.judgefail) M="- 모델 판정 실패 또는 시간초과(%s). 규칙 판정을 유지한다." ;;
  ngg.allowed)   M="허용되는 행동은 둘뿐이다. (1) 지금 실측한다 (2) 실측이 불가능한 이유를 답에 적는다(예: '이 세션에서는 도구 실행이 안 된다'). 그러면 R0·R2a·R4는 걸리지 않는다. 사용자가 '명령 실행하지 말라'고 했더라도 추측으로 답할 수는 없다. 필요하면 AskUserQuestion으로 물어라." ;;
  ngg.noretell)  M="앞의 막힌 답은 화면에 남아 있다. **최종 답을 그 자체로 완결되게 다시 써라.** 실측한 내용을 반영해 사용자가 마지막 답 하나만 읽어도 전부 파악되게 한다. 앞 답이 틀렸으면 고쳐서 담아라. 게이트에 대한 불평은 답변에 내지 마라." ;;
  rb.write)      M="근거 게이트: 이번 세션에 읽은 적 없는 기존 파일을 Write 로 통째로 덮어쓰려 했다." ;;
  rb.writet)     M="- 먼저 Read 도구로 읽고 다시 써라. 일부만 바꾸려면 Edit 도구를 써라. 파일 전체를 새로 쓰는 것이 맞으면 읽은 뒤에 덮어써라." ;;

  done.prefix)   M="완료 게이트: %s" ;;
  done.nocmd)    M="코드 파일 %s개를 고쳤지만 검사 명령을 찾지 못했다. .check.toml에 test_command를 적으면 이 턴부터 검사한다. 막지 않는다." ;;
  done.timeout)  M="검사가 제한 시간 %s초를 넘겨 시간초과로 중단했다(%s: %s). 판정하지 못했으므로 막지 않는다." ;;
  done.slow)     M="검사에 %s초 걸렸다. 턴마다 이만큼 기다리면 게이트를 꺼 버리게 된다. .check.toml에 fast_test_command로 빠른 검사를 따로 적으면 턴 끝에는 그것만 돌리고 전체는 커밋 직전에 한 번 돌린다." ;;
  done.failhead) M="완료 게이트: 검사가 실패했다(exit %s). 턴을 끝낼 수 없다." ;;
  done.ran)      M="- 돌린 명령: %s   (출처: %s)" ;;
  done.files)    M="- 고친 코드 파일: %s개 (이 턴 변경 %s개 중)" ;;
  done.tail)     M="- 출력 꼬리:" ;;
  done.fixcode)  M="테스트를 고쳐서 통과시키지 마라. 코드를 고쳐라. 요구가 바뀌어 테스트가 틀린 것이면 그 이유를 밝히고 확인받아라." ;;
  done.setup)    M="출력이 'command not found', 'Cannot find module', 'No such file' 같은 것이면 코드가 아니라 검사 설정 문제다. .check.toml의 test_command나 프로젝트 설정을 보라." ;;
  done.pretime)  M="완료 게이트: 커밋 전 전체 검사가 %s초를 넘겨 중단했다. 판정하지 못했으므로 막지 않는다." ;;
  done.prehead)  M="완료 게이트: 커밋 전 전체 검사가 실패했다(exit %s). 커밋할 수 없다." ;;
  done.preran)   M="- 돌린 명령: %s   (.check.toml test_command)" ;;
  done.fixshort) M="테스트를 고쳐서 통과시키지 마라. 코드를 고쳐라." ;;
  done.prhead)   M="완료 게이트: PR 본문에 근거가 없다. 이 PR을 열 수 없다." ;;
  done.prfiles)  M="- 이 브랜치가 바꾼 코드 파일: %s개 (기준: %s)" ;;
  done.prnobase) M="- 기준 브랜치를 찾지 못해 코드를 바꿨는지 가리지 못했다. 본문만 보고 판정했다." ;;
  done.prfix)    M="본문에 실제로 돌린 검사 명령과 그 출력을 코드 블록(\`\`\`)으로 붙여라. 화면을 바꿨으면 스크린샷을 넣어라. 통과했다는 말만으로는 근거가 되지 않는다. 돌리지 않은 출력을 지어내지 마라." ;;

  ti.prefix)     M="테스트 무결성 게이트: %s" ;;
  ti.advice)     M="테스트가 아니라 코드를 고쳐라. 요구가 바뀌어 테스트가 틀린 것이면, 무엇이 바뀌어 그 테스트가 이제 틀렸는지 밝히고 확인받아라." ;;
  ti.rm)         M="테스트 파일 삭제 명령이다." ;;
  ti.disable)    M="테스트를 무력화하는 표기가 늘었다(%s → %s)." ;;
  ti.assert)     M="단언이 줄었다(%s → %s)." ;;
  ti.exclude)    M="테스트 러너 설정에서 제외 지시어가 늘었다(%s → %s)." ;;
  ti.excludehint) M="- 설정으로 테스트를 빼지 마라. 실패하는 테스트가 있으면 코드를 고쳐라. 정말 그 테스트가 더 이상 맞지 않으면 이유를 밝히고 확인받아라." ;;
  ti.markers)    M="- 걸린 표기: %s" ;;

  pg.prefix)     M="프로젝트 가드: %s" ;;
  pg.noverify)   M="git commit --no-verify로 커밋 훅을 건너뛰려 했다." ;;
  pg.noverifyt)  M="- 검사를 건너뛰지 말고 통과시켜라. 정말 비상이면 사람이 직접 실행한다." ;;
  pg.appendedit) M="이 경로는 추가만 가능하다(append-only). 기존 파일은 고칠 수 없다." ;;
  pg.appendrm)   M="이 경로는 추가만 가능하다(append-only). 삭제나 이동을 막는다." ;;
  pg.conf)       M="- 설정: append_only = \"%s\"  (.check.toml)" ;;
  pg.appendtail) M="- 고쳐야 할 내용이 있으면 지난 파일을 바꾸지 말고 새 파일을 더해라." ;;

  line.cmd)      M="- 명령: %s" ;;
  line.file)     M="- 파일: %s" ;;
  line.target)   M="- 대상: %s" ;;
  line.allow)    M="- 사람이 이번 한 번만 넘기려면 다음 프롬프트에 check allow %s 를 한 줄로 쓴다. 한 번 쓰면 사라진다." ;;

  rp.head)       M="[check 프로필] %s" ;;
  rp.branch)     M="  (브랜치 %s)" ;;
  rp.pm)         M="패키지 매니저: %s" ;;
  rp.stack)      M="스택: %s" ;;
  rp.cmd)        M="검사 명령: %s   (출처: %s)" ;;
  rp.nocmd)      M="검사 명령을 찾지 못했다. .check.toml에 test_command를 적으면 완료 게이트가 이 저장소에서 동작한다." ;;
  rp.appendonly) M="append-only 경로: %s" ;;
  rp.gates)      M="게이트: 근거(항상) · 완료(%s) · 테스트 무결성(항상) · 프로젝트 가드(%s)" ;;
  rp.on)         M="켜짐" ;;
  rp.wait)       M="검사 명령 없어 대기" ;;
  rp.noconf)     M="설정 없어 --no-verify만 차단" ;;
  rp.disabled)   M="끈 규칙: %s  (.check.toml 의 disabled_rules)" ;;
esac ; }

msg_en() { case "$1" in
  err.python3)   M="no-guess-gate: could not read the hook input with python3. This turn was not judged. Check that python3 is installed and on PATH." ;;

  ngg.head)      M="Evidence gate [%s]. This turn cannot end." ;;
  ngg.offbad)    M="  (disabled_rules in .check.toml names an unknown rule: %s. Nothing was disabled.)" ;;
  ngg.r0)        M="- R0: the user asked about the state of this directory/file/code and you ran no tool at all. Check it now with Read/Grep/Glob/Bash." ;;
  ngg.r1)        M="- R1: you asserted the state of a specific path or file without running a tool. Go check it now." ;;
  ngg.r2a)       M="- R2a: you ended on a hedge like 'this needs to be verified' without running a single tool. Verify it now. If verification is genuinely impossible, say in your answer why. Saying you don't know is allowed; deferring what you could have checked is not." ;;
  ngg.r2b)       M="- R2b: you guessed at local state with words like 'probably' or 'appears'. Measure it, then say what is true." ;;
  ngg.r3)        M="- R3: you claim you tested or verified something, but this turn has zero Bash calls. Actually run it and answer from the output." ;;
  ngg.r4)        M="- R4: you have run no tool since the last block. An apology or an explanation cannot end this turn. Measure something now, or ask with AskUserQuestion." ;;
  ngg.r5)        M="- R5: the last command you ran this turn failed, yet you are claiming it verified or passed. A failed run is not evidence. Fix it and run again, or say in your answer what failed." ;;
  ngg.judgekept) M="- Judge: read as a claim about state (%s). The rule verdict stands." ;;
  ngg.judgefail) M="- Judge failed or timed out (%s). The rule verdict stands." ;;
  ngg.allowed)   M="Only two moves are allowed: (1) measure it now, or (2) state in your answer why measuring is impossible (for example, 'tool execution is disabled in this session'). Either one clears R0, R2a and R4. Even if the user told you not to run commands, you still may not answer by guessing. Ask with AskUserQuestion if you need to." ;;
  ngg.noretell)  M="The blocked answer above stays on screen. **Write your final answer so it stands on its own.** Fold in what you measured so the user gets everything from this last answer alone. Correct anything the earlier answer got wrong. Do not argue with the gate in your answer." ;;
  rb.write)      M="Evidence gate: this Write would overwrite an existing file you have not read this session." ;;
  rb.writet)     M="- Read it with the Read tool first, then write. To change only part of it, use the Edit tool. If replacing the whole file is right, read it before you overwrite it." ;;

  done.prefix)   M="Completion gate: %s" ;;
  done.nocmd)    M="%s code file(s) changed, but no check command was found. Add test_command to .check.toml and the check runs from the next turn. Not blocking." ;;
  done.timeout)  M="The check ran past its %ss limit and was stopped (%s: %s). There is no verdict, so this is not blocking." ;;
  done.slow)     M="The check took %ss. Waiting that long every turn is how a gate ends up switched off. Put a quick check in .check.toml as fast_test_command: the end of a turn then runs only that, and the full suite runs once, right before a commit." ;;
  done.failhead) M="Completion gate: the check failed (exit %s). This turn cannot end." ;;
  done.ran)      M="- Command: %s   (from: %s)" ;;
  done.files)    M="- Code files changed: %s (of %s changed this turn)" ;;
  done.tail)     M="- Tail of the output:" ;;
  done.fixcode)  M="Do not make it pass by editing the test. Fix the code. If the requirement changed and the test is now wrong, say why and get that confirmed first." ;;
  done.setup)    M="If the output says 'command not found', 'Cannot find module' or 'No such file', this is the check setup, not your code. Look at test_command in .check.toml, or at the project setup." ;;
  done.pretime)  M="Completion gate: the pre-commit full check ran past %ss and was stopped. There is no verdict, so this is not blocking." ;;
  done.prehead)  M="Completion gate: the pre-commit full check failed (exit %s). This commit cannot go through." ;;
  done.preran)   M="- Command: %s   (.check.toml test_command)" ;;
  done.fixshort) M="Do not make it pass by editing the test. Fix the code." ;;
  done.prhead)   M="Completion gate: the PR body carries no evidence. This PR cannot be opened." ;;
  done.prfiles)  M="- Code files this branch changes: %s (against %s)" ;;
  done.prnobase) M="- No base branch was found, so it is unknown whether code changed. Judged on the body alone." ;;
  done.prfix)    M="Paste the check command you actually ran and its output into the body as a code block (\`\`\`). If the screen changed, add a screenshot. Saying it passed is not evidence. Do not make up output you did not run." ;;

  ti.prefix)     M="Test-integrity gate: %s" ;;
  ti.advice)     M="Fix the code, not the test. If the requirement changed and the test is now wrong, say what changed and get that confirmed first." ;;
  ti.rm)         M="This command deletes a test file." ;;
  ti.disable)    M="Markers that disable tests went up (%s → %s)." ;;
  ti.assert)     M="Assertions went down (%s → %s)." ;;
  ti.exclude)    M="Exclusion directives in the test-runner config went up (%s → %s)." ;;
  ti.excludehint) M="- Do not remove tests through config. If a test fails, fix the code. If the test is genuinely wrong now, say why and get that confirmed." ;;
  ti.markers)    M="- Markers found: %s" ;;

  pg.prefix)     M="Project guard: %s" ;;
  pg.noverify)   M="This skips the commit hooks with git commit --no-verify." ;;
  pg.noverifyt)  M="- Make the checks pass instead of skipping them. If it is a real emergency, a human runs it." ;;
  pg.appendedit) M="This path is append-only. Existing files cannot be edited." ;;
  pg.appendrm)   M="This path is append-only. Deleting and moving are blocked." ;;
  pg.conf)       M="- Setting: append_only = \"%s\"  (.check.toml)" ;;
  pg.appendtail) M="- If something has to change, add a new file instead of editing a past one." ;;

  line.cmd)      M="- Command: %s" ;;
  line.file)     M="- File: %s" ;;
  line.target)   M="- Target: %s" ;;
  line.allow)    M="- To let this through once, a human writes check allow %s on its own line in the next prompt. It is used up after one pass." ;;

  rp.head)       M="[check profile] %s" ;;
  rp.branch)     M="  (branch %s)" ;;
  rp.pm)         M="Package manager: %s" ;;
  rp.stack)      M="Stack: %s" ;;
  rp.cmd)        M="Check command: %s   (from: %s)" ;;
  rp.nocmd)      M="No check command found. Add test_command to .check.toml to turn the completion gate on for this repo." ;;
  rp.appendonly) M="Append-only paths: %s" ;;
  rp.gates)      M="Gates: evidence (always) · completion (%s) · test integrity (always) · project guard (%s)" ;;
  rp.on)         M="on" ;;
  rp.wait)       M="idle, no check command" ;;
  rp.noconf)     M="unconfigured, blocks only --no-verify" ;;
  rp.disabled)   M="Disabled rules: %s  (disabled_rules in .check.toml)" ;;
esac ; }
