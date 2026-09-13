# did-you-check — gates and commands in detail

The README stays short; the detail lives here — what each gate blocks, how to turn it off, and which document grounds it.

## Judge settings

When only R2a/R2b fire, the evidence gate asks a small model whether the flagged wording is an opinion or a claim about state. The judge can only release, never block. The rules and exemptions are in the [README](../README.en.md#what-gets-blocked).

| Variable | Default | Meaning |
|---|---|---|
| `NGG_JUDGE` | `1` | `0` disables judging entirely |
| `NGG_JUDGE_MODEL` | `haiku` | Judge model. One classification call, so a large model is not needed, but you can change it |
| `NGG_JUDGE_CMD` | (unset) | Replace the whole judge command. Overrides the model setting |
| `NGG_JUDGE_TIMEOUT` | `40` | Seconds |

### Message language

Every message the gates emit exists in Korean and English. The rule verdict is the same either way.

| Variable | Default | Meaning |
|---|---|---|
| `NGG_LANG` | (locale) | `ko` or `en`. Set it and the locale is ignored |

Without `NGG_LANG` the gate reads `LC_ALL`, then `LC_MESSAGES`, then `LANG`: Korean locales get Korean, everything else gets English. All strings live in `plugin/hooks/lib/msg.sh`.

### Why not the built-in `type: "prompt"` hook

Claude Code ships [prompt hooks](https://code.claude.com/docs/en/hooks) for judgment calls: instead of a shell command, it asks a model and reads back `{"ok": bool, "reason": …}`. That is what `judge.py` does. The difference is **how often it runs**.

| Approach | Runs on | Cost per turn |
|---|---|---|
| `type: "prompt"` Stop hook | **every turn** | measured +1.6s (4.8s baseline → 6.4s) |
| Ours (regex + `judge.py`) | about 4% of blocks | median 8s when it fires, zero otherwise |

The regex floor is free and the model is consulted rarely. Moving to a prompt hook would slow down every uneventful turn. The `ok:false` path does work: the model kept going for 6 turns after being blocked.

If it fails or times out, the block stands. Each verdict is logged to `${CLAUDE_PLUGIN_DATA}/state/events.log` as `judge=released|kept|failed` with the elapsed seconds.

## Disabling one item

Regex doesn't read intent, and in some repos one rule fires far more often than it should. Turning the whole gate off to escape it takes every other check in that gate down with it.

Name it in `.check.toml` and only that one drops out.

```toml
# R2b fires on every design discussion here, and PRs get a separate human review
disabled_rules = "R2b, done.pr"
```

Comma-separate several; case doesn't matter. These are the names:

| Gate | Name | What stops |
|---|---|---|
| Evidence | `R0`, `R1`, `R2a`, `R2b`, `R3`, `R4`, `R5` | That one rule |
| Completion | `done.turn` | The check at the end of a turn that changed code |
| | `done.commit` | The full check right before a commit |
| | `done.pr` | The evidence check on a PR body |
| Test integrity | `ti.skip` | Blocking added disable markers |
| | `ti.assert` | Blocking fewer assertions |
| | `ti.rm` | Blocking test file deletion |
| | `ti.exclude` | Blocking new exclusions in runner config |
| Project guard | `pg.noverify` | Blocking `--no-verify` commits |

Append-only has no name: without `append_only` it is already off.

**Putting it in a file rather than an env var is the whole point.** An env var like `NGG_DONE=0` switches off every check in that gate at once, and in someone's shell it is invisible to the rest of the team. `.check.toml` is committed, so it shows up in the pull request and the reason lives in the same commit. This does not make switching something off easier; it makes switching it off **visible**. The env vars stay as an emergency switch.

The fact is recorded in three places.

- `off=[R2b]` or `off=[done.pr]` in `events.log`
- The repo profile loads `Disabled rules: R2b, done.pr` into context every session
- Naming something that doesn't exist is reported on stderr whenever any gate blocks. Believing a check is off when it isn't is the worst state to be in

The file is read only right before a gate blocks or runs a check, so tool calls that pass straight through pay nothing.

## Letting one through

Disabling a check in the file keeps it off. To get past a single false positive, write this on its own line in your next prompt:

```
check allow ti.skip
```

That check passes **once** within the turn, and the allowance is gone. An unused allowance is cleared by the next prompt too. When a gate blocks, it tells you what to write, item name included.

- **Only a human can grant it.** The `UserPromptSubmit` hook reads it from your prompt alone. The model writing the same text in its answer does nothing, and background task notifications do not count as your prompt.
- **It must start the line.** Mentioning it mid-sentence is a quote. Case does not matter; comma-separate several.
- **Only the gate items in the table above.** The evidence gate's `R0`–`R5` are not covered; that gate has its own exemption for saying why something cannot be checked.
- Each pass is logged to `events.log` as `allowed=[ti.skip]`.

The idea comes from Probity's `enforceTdd`: "reply in the session asking for the change to be let through, and it's allowed on the next attempt."

## Completion gate: the check must pass

A turn that changed code files does not end until your project's check actually runs. This is the mechanism the official docs prescribe:

> "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes."

The check command is resolved in this order:

| Order | Source |
|---|---|
| 1 | `test_command` in `.check.toml` at the repo root |
| 2 | `scripts.test` in `package.json` → `npm test` |
| 3 | a `test` target in `Makefile` → `make test` |
| 4 | `pyproject.toml` → `python3 -m pytest -q` |

```toml
# .check.toml
fast_test_command = "npm test -- --changed"   # per turn
test_command      = "npm test"                # before a commit
```

**It does not run your whole suite every turn.** The official CLAUDE.md example says as much: "Prefer running single tests, and not the whole test suite, for performance." With `fast_test_command` set, turns run only that and the full suite runs once before `git commit`. Without the split, `test_command` does both. If a check takes over 30 seconds, the gate suggests splitting it.

Three principles. **Never block on what it doesn't know** — if no check command is found, it says so and lets the turn end. **Never fail silently** — a timeout is reported, not swallowed. **Non-code changes are out of scope** — a docs-only turn runs nothing, and files outside the repo don't count.

Disable with `NGG_DONE=0`; the timeout is `DONE_TIMEOUT` (default 180s).

This repo eats its own dog food: its `.check.toml` points at its own test suites, so changing a hook makes the hook check itself.

### No evidence, no PR

Right before `gh pr create`, the gate reads the body. Without the command you ran and its output, the PR does not open. That is exactly what the official docs name as evidence:

> "Have Claude show evidence rather than asserting success: the test output, the command it ran and what it returned, or a screenshot of the result."

What counts is a **closed code block** (both the opening and the closing fence) or an **image**. The body is read from `--body`, `--body-file`, or a heredoc passed with `-F -`, including the `--body "$(cat <<'EOF' … EOF)"` shape agents usually write.

| Case | Verdict |
|---|---|
| The body has a code block or an image | Passes |
| The body only says "all tests pass" | Blocked |
| No code files changed against the base branch (docs only) | Passes |
| The body is not in the command (`--fill`, `--web`) | Passes. It never blocks on what it cannot see |
| `gh pr create` appears inside a commit message or a doc | Passes. Quoting is not using |
| No base branch found | It cannot tell whether code changed, so it judges the body alone |

The base is `--base` if given, otherwise the first that exists of `origin/HEAD` → `origin/main` → `origin/master` → `main` → `master`. Local git only; nothing goes over the network.

**It checks the form only.** It cannot tell whether the pasted output came from a real run; it stops at telling a blocked model not to make output up. It does not look at `gh pr edit --body` either.

A one-line code fix is in scope too. That clashes with the habit of opening small fixes with a title alone; the choice here is that a code change carries one block of check output. Docs-only PRs are not affected.

To switch off this check alone, add `done.pr` to `disabled_rules`. `NGG_DONE=0` turns off the whole completion gate.

## Test-integrity gate: fix the code, not the test

This blocks exactly what Kent Beck called cheating.

> "Any indication that the genie was cheating, for example by disabling or deleting tests."

Only three things are blocked: a test file gaining **disabling markers** (`.skip(`, `.only(`, `xit(`, `@pytest.mark.skip`, `#[ignore]`, `t.Skip(`, …), **assertions being removed**, and **commands that delete test files**.

**Runner configs count too.** In `jest.config.*`, `vitest.config.*`, `pytest.ini`, `pyproject.toml`, `.mocharc.*` and friends, an edit that **increases** exclusion directives (`testPathIgnorePatterns`, `--ignore=`, `exclude`, `norecursedirs`, …) is blocked. Deleting tests through config was an open route. EvilGenie (arXiv [2511.21654](https://arxiv.org/abs/2511.21654)) files this under "Modified Testing Procedures". Reducing exclusions, or any unrelated edit, passes.

**Editing tests is not blocked in general.** Changing an expected value or adding assertions passes. TDD is a methodology of writing and revising tests, so blocking that would contradict the very docs this kit follows. Disable with `NGG_TESTGUARD=0`.

## Project guard: history is append-only

This is the spot the official hook example points at.

> "Write a hook that blocks writes to the migrations folder."

This guard is more precise: **new files are allowed; only edits and deletions of existing files are blocked.** You still need to write migrations.

```toml
# .check.toml
append_only = "supabase/migrations, db/migrate"
```

With no configuration it blocks nothing. `git commit --no-verify` is blocked **only when there are commit hooks to bypass** (`.check.toml`, `.husky/pre-commit`, `.git/hooks/pre-commit`, or `core.hooksPath`). Installing a plugin should not change git's behaviour in repos you never configured. Disable with `NGG_GUARD=0`.

## Repo profile: facts, loaded every session

The gates need to know what to enforce, and Claude needs to know what to run here. At session start a `SessionStart` hook puts about twenty lines of fact into the context.

```
[check 프로필] did-you-check  (branch main)
패키지 매니저: pnpm
스택: next, react, typescript, vitest
검사 명령: pnpm test   (source: package.json scripts.test → vitest run)
게이트: 근거(always) · 완료(on) · 테스트 무결성(always) · 프로젝트 가드(on)
```

The docs are explicit that this event's stdout becomes context: "The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`, where Claude Code adds plain-text stdout as context that Claude can see and act on."

**It carries facts, never instructions** — enforcement is the gates' job. It calls no model, only reads files, and never reads values out of secret files like `.env`. The last line shows which gate is idle, so a missing setting is visible immediately. Disable with `NGG_PROFILE=0`.

## What it costs

Installing this adds time to every turn. Here are the numbers: the median of 20 runs per hook on the same input, on macOS (arm64) with bash 3.2 and python 3.13. The script is in [V38](VERIFICATION.md).

| Hook | Runs | Measured |
|---|---|---|
| `no-guess-gate/prompt.sh` | once per turn | 51ms |
| `no-guess-gate/stop.sh` | end of turn | 161ms |
| `done-gate/stop.sh` | end of turn | 44ms |
| `no-guess-gate/pre.sh` | per tool call | 17ms |
| `test-integrity/pre.sh` | per Edit, Write or Bash call | 46ms; 12ms for a Bash call with no delete in it |
| `project-guard/pre.sh` | per Edit, Write or Bash call | 41ms; 13ms for a Bash call with no delete, move or commit in it |
| `done-gate/pre.sh` | per Bash call | 12ms unless it is a commit or a PR |
| `no-guess-gate/bashres.sh` | per Bash call | 17ms |
| `done-gate/post.sh` | per Edit or Write call | 44ms |
| `repo-profile/session.sh` | once per session | 65ms |

**The per-turn floor is about 256ms** (`prompt` plus both `stop` hooks). What a tool call adds depends on the tool: about 70ms per Bash call, or about 170ms when the command deletes, moves, commits or opens a PR and the hooks check it all the way; about 155ms per Edit or Write; 17ms for any other tool. The three Bash-side hooks look at the tool name and the relevant words first, and skip Python for commands that do not concern them (V40). Opening a session costs 65ms once.

The first measurement (V28) put the floor at 326ms. Running v1.5.0 through the same script today gives 258ms, so the drop comes from the measuring conditions, not the code. 1.6.0 added four features and no hook moved by more than 5ms.

Timing a whole session on one short prompt: 1,416ms without hooks, 2,367ms with them (V28, median of 3 each). That has not been re-measured.

Most of the cost is Python startup. `stop.sh` invokes Python three times and startup alone is 26.9ms each (V28). Folding them into one call would save roughly 50ms, but that code builds the input the rules judge, so it is untouched for now.

If it feels slow, turn the profile off with `NGG_PROFILE=0`, or disable gates individually with `NGG_DONE=0`, `NGG_TESTGUARD=0`, `NGG_GUARD=0`.
## Eight commands

The gates run on their own. What needs your judgment about *when* and *what it costs* stays a command. All eight are **user-invoked only** (`disable-model-invocation: true`), as the docs advise: "Use `disable-model-invocation: true` for workflows with side effects that you want to trigger manually."

| Command | What it does |
|---|---|
| `/check:spec` | Interviews you with `AskUserQuestion` before a large feature and writes `SPEC.md` |
| `/check:init` | Actually runs the candidate check command, then pins it in `.check.toml`; proposes a baseline, append-only paths, and secret-file denies |
| `/check:tdd` | Failing test first, confirm RED, minimum implementation |
| `/check:ship` | Runs the checks and puts their output into the PR body as evidence |
| `/check:handoff` | Writes a handoff for the next session |
| `/check:status` | Measures and reports what every gate is actually doing |
| `/check:auto` | Explore → plan → implement → review → ship, in order |
| `/check:config` | Shows every gate item with what it blocks and where it comes from, then writes your picks to `disabled_rules` |

**The commands answer in whatever language you write in.** `SKILL.md` cannot branch on locale, so it is written in English with an instruction in the body to reply in the user's language — the same principle `msg.sh` applies to the gate's own sentences.

**More commands are absent than present.** Planning is built-in plan mode, exploration is the built-in Explore agent, review is `/code-review`, run-and-see is `/verify`, looping is `/goal`. An audit cut 23 candidates down to 7, and `config` for picking checks came later. Nothing here duplicates something that already exists.

## Sources

Every rule cites where it came from. No rule ships without one.

| Document | What it grounds |
|---|---|
| [Reduce hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) | R0, R1, R2a, R2b, R4 and the exemptions. *"If it can't find a quote, it must retract the claim."* R2a was narrowed to zero-tool turns to match *"Allow Claude to say I don't know."* |
| [Best practices](https://code.claude.com/docs/en/best-practices) | R3, the completion gate's Stop-hook approach, and the PR body check (`done.pr`). *"Have Claude show evidence rather than asserting success."* |
| [Hooks](https://code.claude.com/docs/en/hooks) · [Hooks guide](https://code.claude.com/docs/en/hooks-guide) | exit 2 blocking, the 8-block cap, timeouts, and using a model where judgment is needed. The `PostToolUseFailure` event R5 uses to learn a command failed |

The reason for using hooks at all is in the docs too:

> "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens."

## Development

```bash
claude --plugin-dir .                         # load this folder instead of the installed copy
claude plugin validate .                      # manifest and hook wiring
for g in lib no-guess-gate done-gate test-integrity project-guard repo-profile; do
  hooks/$g/unit.sh || break; done && tests/skills-unit.sh    # 252 assertions, no model calls
tests/fuzz.sh                                 # 24 malformed inputs x ten hooks = 240 runs
tests/no-guess-gate/selftest.sh               # 12-case regression against real prompts, minutes
tests/no-guess-gate/judge-accuracy.sh         # judge accuracy and latency, minutes
shellcheck -x -s bash hooks/*/*.sh skills/unit.sh
```

Every string the gates emit lives in `plugin/hooks/lib/msg.sh`, not in the hooks. A new string goes in with both its Korean and English form; leave one out and `tests/lib/unit.sh` fails.

Every verification records the exact command and its raw output in [`docs/VERIFICATION.md`](VERIFICATION.md). See [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md).
