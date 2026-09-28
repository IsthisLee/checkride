#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Codex 어댑터의 이벤트 계약을 모델 호출 없이 확인한다.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
unset NGG_INNER NGG_JUDGE NGG_JUDGE_CMD NGG_JUDGE_PROVIDER NGG_STATE PLUGIN_DATA CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
W="$ROOT/plugin/hooks"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$1" = "$2" ]; then echo "✅ $3"; else echo "❌ $3 (기대=$1 실측=$2)"; fail=$((fail+1)); fi; }
mkrepo() { mkdir -p "$1"; git init -q "$1"; }
event_file() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
path, tool, session, cwd, command = sys.argv[1:]
event = {"session_id": session, "cwd": cwd, "hook_event_name": "PreToolUse",
         "tool_name": tool, "tool_input": {"command": command}}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(event, stream)
PY
}
run_event() { env NGG_STATE="$2" python3 "$W/codex.py" "$3" < "$1"; }

# apply_patch 의 command 가 빠지면 훅은 변경 대상을 알아낼 수 없으므로 차단한다.
P="$T/repo"; mkrepo "$P"
python3 - "$T/missing.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"missing","cwd":sys.argv[2],"tool_name":"apply_patch",
           "hook_event_name":"PreToolUse","tool_input":{}}, open(sys.argv[1],"w"))
PY
run_event "$T/missing.json" "$T/state" pre-patch 2>"$T/missing.err"; r=$?
check 2 "$r" "apply_patch 입력 command 누락 → exit 2"
grep -qi 'command' "$T/missing.err"; check 0 $? "누락된 패치 입력을 stderr 로 설명한다"

# 새 테스트 파일에도 비활성화 표기를 추가할 수 없어야 한다.
PATCH='*** Begin Patch
*** Add File: tests/new.test.js
+it.skip("pending", () => {});
*** End Patch'
event_file "$T/add.json" apply_patch add-skip "$P" "$PATCH"
run_event "$T/add.json" "$T/state" pre-patch 2>"$T/add.err"; r=$?
check 2 "$r" "apply_patch 로 새 테스트에 .skip 추가 → exit 2"

# Update + Move 표기의 목적지를 읽지 못하면 테스트 대상에 우회 편집이 생길 수 있으므로 막는다.
MOVE_PATCH='*** Begin Patch
*** Update File: source.md
*** Move to: tests/new.test.js
@@
+it.skip("pending", () => {});
*** End Patch'
event_file "$T/move.json" apply_patch move-skip "$P" "$MOVE_PATCH"
run_event "$T/move.json" "$T/state" pre-patch 2>"$T/move.err"; r=$?
check 2 "$r" "해석할 수 없는 apply_patch 이동 목적지는 차단한다"
grep -qi 'move' "$T/move.err"; check 0 $? "이동 목적지를 추적할 수 없다고 알린다"

# MCP/local function 이벤트는 tool_name 과 명시적인 파일 경로만 사용한다.
mkdir -p "$P/db/migrate"; printf 'create table old;\n' > "$P/db/migrate/001.sql"
printf 'append_only = "db/migrate"\n' > "$P/checkride.toml"
python3 - "$T/write.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"mcp-write","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
           "tool_name":"mcp__filesystem__write_file",
           "tool_input":{"path":"db/migrate/001.sql","content":"changed"}},
          open(sys.argv[1],"w"))
PY
run_event "$T/write.json" "$T/state" pre-other 2>"$T/write.err"; r=$?
check 2 "$r" "파일 경로를 노출하는 MCP 쓰기 도구가 append_only 편집을 차단한다"

python3 - "$T/read.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"mcp-read","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
           "tool_name":"mcp__filesystem__read_file","tool_input":{"path":"db/migrate/001.sql"}},
          open(sys.argv[1],"w"))
PY
run_event "$T/read.json" "$T/state" pre-other >/dev/null 2>"$T/read.err"; r=$?
check 0 "$r" "읽기 전용 MCP 도구는 파일 경로를 이유로 차단하지 않는다"
grep -qx 'mcp__filesystem__read_file' "$T/state/state/mcp-read/tools" 2>/dev/null
check 0 $? "Codex의 비Bash 도구 호출도 근거 게이트에 기록한다"

# 비-Git Codex 프로젝트가 상위 디렉터리의 무관한 checkride.toml 을 읽지 않게 한다.
NONGIT="$T/nonrepo"; mkdir -p "$NONGIT/pkg/protected"; : > "$NONGIT/pkg/protected/001.sql"
printf 'append_only = "nonrepo/pkg/protected"\n' > "$T/checkride.toml"
python3 - "$T/outside-config.json" "$NONGIT/pkg" <<'PY'
import json, sys
json.dump({"session_id":"outside-config","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
           "tool_name":"mcp__filesystem__write_file",
           "tool_input":{"path":"protected/001.sql","content":"changed"}}, open(sys.argv[1],"w"))
PY
run_event "$T/outside-config.json" "$T/outside-config-state" pre-other >/dev/null 2>"$T/outside-config.err"; r=$?
if [ "$r" -ne 0 ]; then cat "$T/outside-config.err"; fi
check 0 "$r" "Codex 독립 프로젝트가 상위 폴더의 Checkride 설정을 물려받지 않는다"

# Stop 계열 훅은 성공 시 Codex가 요구하는 JSON 을 내고, 차단 뒤 다시 쓴 답도 검사한다.
python3 - "$T/stop.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"stop","cwd":sys.argv[2],"hook_event_name":"Stop",
           "turn_id":"turn-stop","stop_hook_active":False,
           "last_assistant_message":"작업을 마쳤습니다."},
          open(sys.argv[1],"w"))
PY
run_event "$T/stop.json" "$T/stop-state" stop >"$T/stop.out" 2>"$T/stop.err"; r=$?
check 0 "$r" "Stop 게이트 통과 → exit 0"
python3 - "$T/stop.out" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8")); assert d.get("continue") is True
PY
check 0 $? "Stop 게이트 통과 시 Codex JSON 을 출력한다"

RSTATE="$T/active-stop-state"; mkdir -p "$RSTATE/state/reentry-session"
printf '%s' 'Does this repository have package.json?' > "$RSTATE/state/reentry-session/prompt"
python3 - "$T/active-stop.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"reentry-session","turn_id":"turn-reentry","cwd":sys.argv[2],
           "hook_event_name":"Stop","stop_hook_active":False,
           "last_assistant_message":"This repository has package.json."}, open(sys.argv[1],"w"))
PY
NGG_JUDGE=0 run_event "$T/active-stop.json" "$RSTATE" stop >"$T/active-stop.out" 2>"$T/active-stop.err"; r=$?
check 2 "$r" "첫 번째 근거 게이트 차단은 Codex continuation 을 요청한다"
python3 - "$T/active-stop.json" "$T/stop-continuation-prompt.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
json.dump({"session_id":d["session_id"],"turn_id":d["turn_id"],"cwd":d["cwd"],
           "hook_event_name":"UserPromptSubmit",
           "prompt":"Checkride: answer the request with evidence."}, open(sys.argv[2],"w"))
PY
run_event "$T/stop-continuation-prompt.json" "$RSTATE" prompt >"$T/stop-continuation-prompt.out" 2>"$T/stop-continuation-prompt.err"; r=$?
check 0 "$r" "Codex Stop continuation 프롬프트는 정상 처리한다"
grep -qFx 'Does this repository have package.json?' "$RSTATE/state/reentry-session/prompt"
check 0 "$?" "자동 continuation 이 원래 사용자 프롬프트를 덮어쓰지 않는다"
python3 - "$T/active-stop.json" "$T/active-stop-retry.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8")); d["stop_hook_active"]=True
json.dump(d, open(sys.argv[2],"w"))
PY
NGG_JUDGE=0 run_event "$T/active-stop-retry.json" "$RSTATE" stop >"$T/active-stop-retry.out" 2>"$T/active-stop-retry.err"; r=$?
check 2 "$r" "Codex Stop 재진입에서도 근거 게이트가 다시 차단한다"

# 모델이 답을 고치면 재진입 검사는 통과하고 해당 turn 의 반복 상태를 지운다.
printf 'Bash\n' > "$RSTATE/state/reentry-session/tools"
python3 - "$T/active-stop-retry.json" "$T/active-stop-pass.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8")); d["last_assistant_message"]="I checked package.json with cat and confirmed it exists."
json.dump(d, open(sys.argv[2],"w"))
PY
NGG_JUDGE=0 run_event "$T/active-stop-pass.json" "$RSTATE" stop >"$T/active-stop-pass.out" 2>"$T/active-stop-pass.err"; r=$?
check 0 "$r" "수정된 Codex 재진입 답은 두 Stop 게이트를 통과한다"
python3 - "$T/active-stop-pass.out" "$RSTATE/state/reentry-session" <<'PY'
import json, pathlib, sys
assert json.load(open(sys.argv[1], encoding="utf-8")) == {"continue": True}
assert not (pathlib.Path(sys.argv[2]) / "stop").exists()
PY
check 0 "$?" "통과한 재진입은 JSON 을 출력하고 반복 상태를 비운다"

# SubagentStop도 stop_hook_active 재진입 때 원래 agent의 답을 다시 검사한다.
SSTATE="$T/subagent-stop-state"; mkdir -p "$SSTATE/state/subagent-session/agent-agent-test"
printf '%s' 'Does this repository have package.json?' > "$SSTATE/state/subagent-session/agent-agent-test/prompt"
python3 - "$T/subagent-stop.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"subagent-session","turn_id":"turn-subagent","agent_id":"agent-test",
           "cwd":sys.argv[2],"hook_event_name":"SubagentStop","stop_hook_active":False,
           "last_assistant_message":"This repository has package.json."}, open(sys.argv[1],"w"))
PY
NGG_JUDGE=0 run_event "$T/subagent-stop.json" "$SSTATE" subagent-stop 2>"$T/subagent-stop.err"; r=$?
check 2 "$r" "Codex SubagentStop 첫 차단은 continuation 을 요청한다"
python3 - "$T/subagent-stop.json" "$T/subagent-stop-retry.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8")); d["stop_hook_active"]=True
json.dump(d, open(sys.argv[2],"w"))
PY
NGG_JUDGE=0 run_event "$T/subagent-stop-retry.json" "$SSTATE" subagent-stop 2>"$T/subagent-stop-retry.err"; r=$?
check 2 "$r" "Codex SubagentStop 재진입에서도 근거 게이트가 다시 차단한다"

# Codex 의 stop_hook_active 는 재진입 상한이 아니므로 Checkride 가 여덟 번까지만 다시 요청한다.
BST="$T/bounded-stop-state"; mkdir -p "$BST/state/bounded-session"
printf '%s' 'Does this repository have package.json?' > "$BST/state/bounded-session/prompt"
for attempt in 0 1 2 3 4 5 6 7 8; do
  active=false; [ "$attempt" -eq 0 ] || active=true
  python3 - "$T/bounded-$attempt.json" "$P" "$active" <<'PY'
import json, sys
json.dump({"session_id":"bounded-session","turn_id":"turn-bounded","cwd":sys.argv[2],
           "hook_event_name":"Stop","stop_hook_active":sys.argv[3] == "true",
           "last_assistant_message":"This repository has package.json."}, open(sys.argv[1],"w"))
PY
  NGG_JUDGE=0 run_event "$T/bounded-$attempt.json" "$BST" stop \
    >"$T/bounded-$attempt.out" 2>"$T/bounded-$attempt.err"
  r=$?
  if [ "$attempt" -lt 8 ]; then
    check 2 "$r" "Codex 재진입 $((attempt+1))회까지 실패 답을 다시 검사한다"
  else
    check 0 "$r" "8회 재진입이 실패하면 Codex turn 을 안전하게 종료한다"
    python3 - "$T/bounded-$attempt.out" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
assert d["continue"] is False and d["stopReason"] and d["systemMessage"]
PY
    check 0 "$?" "상한 응답은 Codex 종료 형식과 사용자 경고를 포함한다"
  fi
done

# 반복 횟수를 사용자 상태 경로에 기록하지 못하면 무한 continuation을 만들지 않고 경고와 함께 끝낸다.
FSTATE="$T/unwritable-retry-state"; mkdir -p "$FSTATE/state/retry-failure"; printf x > "$FSTATE/stop-retries"
printf '%s' 'Does this repository have package.json?' > "$FSTATE/state/retry-failure/prompt"
python3 - "$T/retry-state-error.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"retry-failure","turn_id":"turn-retry-failure","cwd":sys.argv[2],
           "hook_event_name":"Stop","stop_hook_active":False,
           "last_assistant_message":"This repository has package.json."}, open(sys.argv[1],"w"))
PY
NGG_JUDGE=0 run_event "$T/retry-state-error.json" "$FSTATE" stop \
  >"$T/retry-state-error.out" 2>"$T/retry-state-error.err"; r=$?
check 0 "$r" "Codex retry 상태를 저장할 수 없으면 안전하게 turn 을 끝낸다"
python3 - "$T/retry-state-error.out" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
assert d["continue"] is False and d["systemMessage"]
PY
check 0 "$?" "retry 상태 저장 오류를 사용자 경고로 반환한다"

# 검사를 통과해도 반복 상태 정리에 실패하면 Codex 응답을 빠뜨리지 않고 종료를 알린다.
CLEANSTATE="$T/unclearable-retry-state"; mkdir -p "$CLEANSTATE/state/cleanup-failure"
printf 'Bash\n' > "$CLEANSTATE/state/cleanup-failure/tools"
python3 - "$CLEANSTATE" <<'PY'
import hashlib, json, pathlib, sys
identity=json.dumps(["stop", "cleanup-failure", "turn-cleanup", None], ensure_ascii=False, separators=(",", ":"))
path=pathlib.Path(sys.argv[1]) / "stop-retries" / (hashlib.sha256(identity.encode("utf-8")).hexdigest() + ".count")
path.mkdir(parents=True)
PY
python3 - "$T/retry-cleanup-error.json" "$P" <<'PY'
import json, sys
json.dump({"session_id":"cleanup-failure","turn_id":"turn-cleanup","cwd":sys.argv[2],
           "hook_event_name":"Stop","stop_hook_active":False,
           "last_assistant_message":"I checked package.json with cat and confirmed it exists."}, open(sys.argv[1],"w"))
PY
NGG_JUDGE=0 run_event "$T/retry-cleanup-error.json" "$CLEANSTATE" stop \
  >"$T/retry-cleanup-error.out" 2>"$T/retry-cleanup-error.err"; r=$?
check 0 "$r" "Codex retry 상태 정리 오류도 Stop 응답을 반환한다"
python3 - "$T/retry-cleanup-error.out" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
assert d["continue"] is False and "clear" in d["systemMessage"].lower()
PY
check 0 "$?" "retry 상태 정리 오류에서 turn 을 경고와 함께 끝낸다"

# Codex Bash의 PostToolUse.tool_response 는 명령 출력 문자열이라 종료 코드를 주지 않는다.
Q="$T/bash-repo"; mkrepo "$Q"
printf 'before\n' > "$Q/app.py"
git -C "$Q" add app.py
git -C "$Q" -c user.name=Checkride -c user.email=checkride@example.invalid commit -qm init
python3 - "$T/bash-pre.json" "$Q" "$T/bash-success.jsonl" <<'PY'
import json, sys
open(sys.argv[3], "w", encoding="utf-8").close()
json.dump({"session_id":"bash-success","turn_id":"turn-success","cwd":sys.argv[2],
           "tool_use_id":"bash-ok","transcript_path":sys.argv[3],
           "hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"true"}},
          open(sys.argv[1],"w"))
PY
run_event "$T/bash-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-pre.err"; r=$?
check 0 "$r" "Codex Bash 호출 전 검사가 스냅샷을 저장한다"
printf 'after\n' > "$Q/app.py"
printf '%s\n' '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","true"],"exit_code":0,"status":"completed"}}' >> "$T/bash-success.jsonl"
python3 - "$T/bash-post.json" "$Q" "$T/bash-success.jsonl" <<'PY'
import json, sys
json.dump({"session_id":"bash-success","turn_id":"turn-success","cwd":sys.argv[2],
           "tool_use_id":"bash-ok","transcript_path":sys.argv[3],
           "hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"},
           "tool_response":"saved app.py"}, open(sys.argv[1],"w"))
PY
run_event "$T/bash-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-post.err"; r=$?
check 0 "$r" "Codex Bash transcript 성공 결과를 처리한다"
check S "$(cat "$T/bash-state/state/bash-success/bashseq")" "새 transcript 레코드의 0 종료 코드를 성공으로 기록한다"
python3 - "$Q/app.py" "$T/bash-state/state/bash-success/changed" <<'PY'
import pathlib, sys
expected = pathlib.Path(sys.argv[1]).resolve()
paths = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
assert any(pathlib.Path(path).resolve() == expected for path in paths), paths
PY
check 0 "$?" "Bash 전후 스냅샷에서 수정 파일을 기록한다"

python3 - "$T/bash-fail.json" "$Q" <<'PY'
import json, sys
json.dump({"session_id":"bash-failure","cwd":sys.argv[2],"tool_use_id":"bash-fail",
           "hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"false"},
           "tool_response":"Process exited with code 17\\nOutput:\\n"}, open(sys.argv[1],"w"))
PY
run_event "$T/bash-fail.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-fail.err"; r=$?
check 0 "$r" "출력에 종료 코드처럼 보이는 문장이 있어도 응답을 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-failure/bashseq")" "임의의 출력 문장을 실패 종료 코드로 오인하지 않는다"

python3 - "$T/bash-unknown.json" "$Q" <<'PY'
import json, sys
json.dump({"session_id":"bash-unknown","cwd":sys.argv[2],"tool_use_id":"bash-unknown",
           "hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"},
           "tool_response":"Output without process status"}, open(sys.argv[1],"w"))
PY
run_event "$T/bash-unknown.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-unknown.err"; r=$?
check 0 "$r" "상태를 알 수 없는 Codex Bash 응답도 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-unknown/bashseq")" "알 수 없는 결과를 중립 기호로 기록한다"

# Codex transcript 는 PreToolUse 이후 새로 기록된 단일 실행만 정확한 명령과 맞춰 쓴다.
python3 - "$T/bash-failed.jsonl" "$T/bash-failed-pre.json" "$T/bash-failed-post.json" "$Q" <<'PY'
import json, sys
transcript, pre, post, cwd = sys.argv[1:]
open(transcript, "w", encoding="utf-8").close()
common = {"session_id":"bash-transcript-failed", "turn_id":"turn-failed",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"false"},
          "transcript_path":transcript}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-failed", "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-failed", "hook_event_name":"PostToolUse",
               "tool_response":""}, f)
PY
run_event "$T/bash-failed-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-failed-pre.err"; r=$?
check 0 "$r" "Codex Bash 사전 훅이 transcript 기준점을 저장한다"
printf '%s\n' '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","false"],"exit_code":17,"status":"failed"}}' >> "$T/bash-failed.jsonl"
run_event "$T/bash-failed-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-failed-post.err"; r=$?
check 0 "$r" "Codex transcript 의 실패 실행 결과를 처리한다"
check F "$(cat "$T/bash-state/state/bash-transcript-failed/bashseq")" "새 transcript 레코드의 비영 종료 코드를 실패로 기록한다"
python3 - "$T/bash-failed-stop.json" "$Q" <<'PY'
import json, sys
json.dump({"session_id":"bash-transcript-failed","turn_id":"turn-failed","cwd":sys.argv[2],
           "hook_event_name":"Stop","stop_hook_active":False,
           "last_assistant_message":"테스트를 실행했고 전부 통과했습니다."}, open(sys.argv[1],"w"))
PY
NGG_JUDGE=0 run_event "$T/bash-failed-stop.json" "$T/bash-state" stop >"$T/bash-failed-stop.out" 2>"$T/bash-failed-stop.err"; r=$?
check 2 "$r" "Codex transcript Bash 실패 뒤 성공 주장을 R5 가 차단한다"
grep -q 'R5' "$T/bash-failed-stop.err"; check 0 "$?" "Codex Stop 응답에서 R5 사유를 알린다"
python3 - "$T/bash-failed-pre2.json" "$T/bash-failed-post2.json" "$T/bash-failed.jsonl" "$Q" <<'PY'
import json, sys
pre, post, transcript, cwd = sys.argv[1:]
common = {"session_id":"bash-transcript-failed", "turn_id":"turn-failed",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"true"},
          "transcript_path":transcript, "tool_use_id":"bash-recovered"}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PostToolUse"}, f)
PY
run_event "$T/bash-failed-pre2.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-failed-pre2.err"; r=$?
check 0 "$r" "Codex 재시도 Bash 호출의 transcript 기준점을 저장한다"
printf '%s\n' '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","true"],"exit_code":0,"status":"completed"}}' >> "$T/bash-failed.jsonl"
run_event "$T/bash-failed-post2.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-failed-post2.err"; r=$?
check 0 "$r" "Codex 재시도 성공 transcript 를 처리한다"
check FS "$(cat "$T/bash-state/state/bash-transcript-failed/bashseq")" "실패 뒤 새 Bash 성공을 순서대로 기록한다"

python3 - "$T/bash-ambiguous.jsonl" "$T/bash-ambiguous-pre.json" "$T/bash-ambiguous-post.json" "$Q" <<'PY'
import json, sys
transcript, pre, post, cwd = sys.argv[1:]
open(transcript, "w", encoding="utf-8").close()
common = {"session_id":"bash-transcript-ambiguous", "turn_id":"turn-ambiguous",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"false"},
          "transcript_path":transcript}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-ambiguous", "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-ambiguous", "hook_event_name":"PostToolUse"}, f)
PY
run_event "$T/bash-ambiguous-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-ambiguous-pre.err"; r=$?
check 0 "$r" "모호성 검사 전 Codex Bash 훅을 준비한다"
printf '%s\n' \
  '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","false"],"exit_code":1,"status":"failed"}}' \
  '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","false"],"exit_code":0,"status":"completed"}}' >> "$T/bash-ambiguous.jsonl"
run_event "$T/bash-ambiguous-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-ambiguous-post.err"; r=$?
check 0 "$r" "Codex transcript 의 복수 실행 레코드를 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-transcript-ambiguous/bashseq")" "복수 실행 레코드의 결과를 추측하지 않는다"

python3 - "$T/bash-stale.jsonl" "$T/bash-stale-pre.json" "$T/bash-stale-post.json" "$Q" <<'PY'
import json, sys
transcript, pre, post, cwd = sys.argv[1:]
with open(transcript, "w", encoding="utf-8") as f:
    f.write('{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","false"],"exit_code":17,"status":"failed"}}\\n')
common = {"session_id":"bash-transcript-stale", "turn_id":"turn-stale",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"false"},
          "transcript_path":transcript}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-stale", "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "tool_use_id":"bash-stale", "hook_event_name":"PostToolUse"}, f)
PY
run_event "$T/bash-stale-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-stale-pre.err"; r=$?
check 0 "$r" "오래된 transcript 레코드 검사 전 Codex Bash 훅을 준비한다"
run_event "$T/bash-stale-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-stale-post.err"; r=$?
check 0 "$r" "새 결과가 없는 Codex Bash 응답을 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-transcript-stale/bashseq")" "PreToolUse 이전의 실패 결과를 새 실행으로 오인하지 않는다"

python3 - "$T/bash-mismatch.jsonl" "$T/bash-mismatch-pre.json" "$T/bash-mismatch-post.json" "$Q" <<'PY'
import json, sys
transcript, pre, post, cwd = sys.argv[1:]
open(transcript, "w", encoding="utf-8").close()
common = {"session_id":"bash-transcript-mismatch", "turn_id":"turn-mismatch",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"false"},
          "transcript_path":transcript, "tool_use_id":"bash-mismatch"}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PostToolUse"}, f)
PY
run_event "$T/bash-mismatch-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-mismatch-pre.err"; r=$?
check 0 "$r" "명령 일치 검사 전 Codex Bash 훅을 준비한다"
printf '%s\n' '{"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","true"],"exit_code":0,"status":"completed"}}' >> "$T/bash-mismatch.jsonl"
run_event "$T/bash-mismatch-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-mismatch-post.err"; r=$?
check 0 "$r" "Codex transcript 의 다른 명령 레코드를 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-transcript-mismatch/bashseq")" "요청한 명령과 다른 transcript 결과를 분류하지 않는다"

python3 - "$T/bash-large.jsonl" "$T/bash-large-pre.json" "$T/bash-large-post.json" "$Q" <<'PY'
import json, sys
transcript, pre, post, cwd = sys.argv[1:]
open(transcript, "w", encoding="utf-8").close()
common = {"session_id":"bash-transcript-large", "turn_id":"turn-large",
          "cwd":cwd, "tool_name":"Bash", "tool_input":{"command":"false"},
          "transcript_path":transcript, "tool_use_id":"bash-large"}
with open(pre, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PreToolUse"}, f)
with open(post, "w", encoding="utf-8") as f:
    json.dump({**common, "hook_event_name":"PostToolUse"}, f)
PY
run_event "$T/bash-large-pre.json" "$T/bash-state" pre-bash >/dev/null 2>"$T/bash-large-pre.err"; r=$?
check 0 "$r" "대량 transcript 검사 전 Codex Bash 훅을 준비한다"
python3 - "$T/bash-large.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "a", encoding="utf-8") as f:
    json.dump({"type":"response_item","payload":{"type":"AgentMessage","message":"x"*(1024*1024)}}, f)
    f.write("\n")
    json.dump({"type":"response_item","payload":{"type":"CommandExecution","command":["/bin/bash","-c","false"],"exit_code":17}}, f)
    f.write("\n")
PY
run_event "$T/bash-large-post.json" "$T/bash-state" post-bash >/dev/null 2>"$T/bash-large-post.err"; r=$?
check 0 "$r" "Codex의 대량 transcript 응답을 처리한다"
check '?' "$(cat "$T/bash-state/state/bash-transcript-large/bashseq")" "1 MiB 를 넘는 transcript 는 분류하지 않는다"

mkdir -p "$T/bin"; cat > "$T/bin/bash" <<'SH'
#!/bin/sh
echo simulated-hook-error >&2
exit 1
SH
chmod +x "$T/bin/bash"
PATH="$T/bin:$PATH" run_event "$T/read.json" "$T/reentry-state" pre-other 2>"$T/reentry.err"; r=$?
check 2 "$r" "하위 훅 exit 1 도 Codex에서 실패 폐쇄한다"
grep -q 'simulated-hook-error' "$T/reentry.err"; check 0 $? "하위 훅 오류를 stderr 에 전달한다"

# 실행할 셸을 찾을 수 없으면 Python traceback/exit 1 대신 Codex의 차단 코드로 실패 폐쇄한다.
mkdir -p "$T/no-shell"
PYTHON=$(command -v python3)
PATH="$T/no-shell" NGG_STATE="$T/no-shell-state" "$PYTHON" "$W/codex.py" pre-other \
  < "$T/read.json" > "$T/no-shell.out" 2> "$T/no-shell.err"; r=$?
check 2 "$r" "하위 훅 실행 파일이 없으면 Codex 차단 코드 exit 2 를 쓴다"
grep -q 'could not start' "$T/no-shell.err"; check 0 $? "하위 훅 실행 실패를 traceback 없이 알린다"

# NGG_INNER 는 Codex 내부 판정 세션에서 모든 훅 모드를 빠져나오게 한다.
PATH="$T/bin:$PATH" NGG_INNER=1 run_event "$T/read.json" "$T/inner-state" pre-other >/dev/null 2>&1; r=$?
check 0 "$r" "NGG_INNER=1 이면 Codex 훅을 건너뛴다"
if [ -e "$T/inner-state" ]; then no_inner_state=1; else no_inner_state=0; fi
check 0 "$no_inner_state" "내부 세션은 훅 상태를 기록하지 않는다"

# 저장소 공유 훅이 설치된 상태에서 사용자 플러그인 사본은 건너뛰고, 저장소 복사본은 계속 실행한다.
mkdir -p "$P/.checkride" "$T/user-plugin"; touch "$P/.checkride/.managed-by-checkride"
cp -R "$W" "$T/user-plugin/hooks"
cp -R "$W" "$P/.checkride/hooks"
printf '{"session_id":"duplicate","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hello"}' "$P" > "$T/duplicate.json"
env NGG_STATE="$T/plugin-copy-state" python3 "$T/user-plugin/hooks/codex.py" prompt < "$T/duplicate.json" >/dev/null
if [ -e "$T/plugin-copy-state/state/duplicate/prompt" ]; then plugin_copy_ran=1; else plugin_copy_ran=0; fi
check 0 "$plugin_copy_ran" "저장소 공유 훅이 있으면 Codex 플러그인 복사본은 건너뛴다"
env NGG_STATE="$T/shared-copy-state" python3 "$P/.checkride/hooks/codex.py" prompt < "$T/duplicate.json" >/dev/null
if [ -e "$T/shared-copy-state/state/duplicate/prompt" ]; then shared_copy_ran=1; else shared_copy_ran=0; fi
check 1 "$shared_copy_ran" "저장소의 관리 훅 복사본은 계속 실행된다"

# 사용자별 기본 상태 경로는 저장소 하위 폴더가 아니라 Git 루트로 정한다.
PSTATE="$T/state-repo"; mkrepo "$PSTATE"; mkdir -p "$PSTATE/packages/app"
for dir in "$PSTATE" "$PSTATE/packages/app"; do
  python3 - "$T/session.json" "$dir" <<'PY'
import json, sys
json.dump({"session_id":"state-root","cwd":sys.argv[2],"hook_event_name":"SessionStart"}, open(sys.argv[1],"w"))
PY
  env -u NGG_STATE -u PLUGIN_DATA -u CLAUDE_PLUGIN_DATA XDG_STATE_HOME="$T/xdg-state" \
    python3 "$W/codex.py" session < "$T/session.json" >/dev/null
done
check 1 "$(find "$T/xdg-state/checkride" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" \
  "Codex 상태 기본 경로는 하위 폴더에서도 저장소 루트를 쓴다"

# Codex 판정기는 Codex CLI를 쓰고, 빈 작업 폴더·읽기 전용 샌드박스·닫힌 stdin 으로 실행한다.
mkdir -p "$T/fakebin"
cat > "$T/fakebin/codex" <<'SH'
#!/bin/sh
printf '%s\0' "$@" > "$JUDGE_ARGS"
cat > "$JUDGE_STDIN"
pwd -P > "$JUDGE_CWD"
printf '%s' "${NGG_INNER:-}" > "$JUDGE_INNER"
out=""; previous=""
for arg in "$@"; do
  if [ "$previous" = "--output-last-message" ]; then out="$arg"; break; fi
  previous="$arg"
done
printf '%s\n' '{"release":true,"why":"opinion"}' > "$out"
SH
chmod +x "$T/fakebin/codex"
printf '%s' '{"rules":"R2b","prompt":"concept question","last":"perhaps"}' |
  PATH="$T/fakebin:$PATH" NGG_JUDGE_PROVIDER=codex NGG_JUDGE_TIMEOUT=5 \
  JUDGE_ARGS="$T/judge-args" JUDGE_STDIN="$T/judge-stdin" JUDGE_CWD="$T/judge-cwd" JUDGE_INNER="$T/judge-inner" \
  python3 "$W/no-guess-gate/judge.py" > "$T/judge.out" 2>"$T/judge.err"
r=$?; check 0 "$r" "Codex 판정기 → 분류 결과로 exit 0"
grep -q 'opinion' "$T/judge.out"; check 0 $? "Codex 판정기 이유를 읽는다"
python3 - "$T/judge-args" "$T/judge-stdin" "$T/judge-cwd" "$ROOT" "$T/judge-inner" <<'PY'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_bytes().decode().split("\0")
stdin = pathlib.Path(sys.argv[2]).read_bytes()
cwd = pathlib.Path(sys.argv[3]).resolve()
repo = pathlib.Path(sys.argv[4]).resolve()
inner = pathlib.Path(sys.argv[5]).read_text()
assert args[0:2] == ["exec", "--ignore-user-config"]
for item in ("--ephemeral", "--sandbox", "read-only", "--skip-git-repo-check", "--disable", "shell_tool"):
    assert item in args, item
assert "--model" not in args and args[-2].startswith("You are a strict classifier")
assert stdin == b"" and inner == "1", (stdin, inner)
assert cwd != repo and repo not in cwd.parents, (str(cwd), str(repo))
PY
check 0 $? "Codex 판정 세션은 사용자 설정·저장소 밖 임시 폴더·read-only·shell 비활성·빈 stdin 을 쓴다"

echo; if [ "$fail" -eq 0 ]; then echo "전부 통과"; else echo "실패 ${fail}건"; fi
exit "$fail"
