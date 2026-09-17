# Contributing

**[한국어](CONTRIBUTING.md)** · English

One rule covers this repo: **back your claims with evidence.** Contributors are held to the same standard the plugin holds Claude to.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

You need `bash`, `python3`, and Claude Code. It runs on macOS, Linux, and Windows — Windows through Git Bash.

```bash
git clone https://github.com/IsthisLee/did-you-check
cd did-you-check
./setup.sh                            # turn on the hook that blocks personal data in commits
claude --plugin-dir .                 # load this folder in that session instead of the installed copy
```

## Checks

Run them before and after your change.

```bash
for g in lib no-guess-gate done-gate test-integrity project-guard repo-profile; do tests/$g/unit.sh; done
tests/skills-unit.sh && tests/attack-surface.sh && tests/invariants.sh
tests/fuzz.sh                                  # malformed input against every hook
shellcheck -x -s bash plugin/hooks/*/*.sh tests/*.sh tests/*/*.sh
python3 -m py_compile plugin/hooks/no-guess-gate/judge.py
claude plugin validate . --strict
```

Two suites call a model and take minutes, so they are not in CI:

```bash
tests/no-guess-gate/selftest.sh         # 12 real-prompt regressions
tests/no-guess-gate/judge-accuracy.sh   # judge accuracy and latency
```

CI runs syntax checks, `shellcheck -x`, actionlint, and the unit suites on ubuntu, macos, and windows. **If you touched the gate's decision logic, run the model-calling suites yourself and paste the results into the PR.**

## Changing a gate rule

1. **Write the test first.** Add the case to the relevant `unit.sh` and watch it go RED. A test that never fails protects nothing.
2. Implement, then confirm the whole suite passes.
3. If you touched the judge, run `selftest.sh` as well.
4. Record **the command you ran and its raw output** in `docs/VERIFICATION.md`. "I checked it" is not a record.

A new rule or exemption **must be grounded in official or verified documentation.** Quote the sentence in the PR body. If there is no such source, say so and explain why the rule is needed anyway — an ungrounded rule is the very thing this plugin exists to block.

When fixing a false positive, bring the case that triggered it. The matching line from `events.log` is enough.

## Commits and PRs

Commit messages are `type(scope): summary`, with the body saying what changed and why. If a measurement drove the change, give the number.

Attach the output of the checks you ran. Do not open a pull request with code you have not reviewed yourself.

## What must not be committed

`.githooks/pre-commit` blocks commits containing home paths, email addresses, or private paths. Turn it on with `./setup.sh` and it catches the slip for you.

The hook file is committed, but that alone does nothing. Git looks for hooks in `.git/hooks`, and `core.hooksPath`, which points somewhere else, lives in `.git/config` and never travels with a clone. So each person who clones runs `./setup.sh` once. The session profile's first lines tell you whether it is on.

The strings it blocks come from two places. Home paths (`/Users/<name>`, `/home/<name>`) are baked into the hook; everything else comes from a pattern file. The shared one is `~/.config/git-guard/patterns`, the per-repo one is `.private/guard-patterns`. Both sit outside the repo or inside an ignored folder, so neither is committed. **Never commit a pattern file: it holds, in plain text, exactly the values the guard exists to keep out.**

If you already use husky or lefthook, `./setup.sh` refuses to overwrite and stops. `core.hooksPath` holds one value, so overwriting kills that manager's hooks silently. Add the line it prints to that manager's own `pre-commit` and both run. Why husky is not used here is in [the design decisions](docs/decisions.md#7-커밋-가드에-husky-를-쓰지-않습니다).

Know what the hook cannot do: it cannot undo what is already pushed, it only blocks patterns you listed, and `--no-verify` bypasses it. If it blocks something you believe is a false positive, open an issue rather than reaching for `--no-verify`.
