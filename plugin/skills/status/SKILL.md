---
name: status
description: Show which gates are live, what this repo has configured, and what has been blocked lately. Everything measured, nothing assumed.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# Status

Report what did-you-check is actually doing in this repo. **Measure all of it.** A command that answers this one by guessing contradicts itself.

**Reply in whatever language I am writing to you in.**

## What to check

1. **Installed and wired.** `claude plugin list` for the install, `hooks/hooks.json` for which event runs what.
2. **Repo configuration.** If `.check.toml` exists, read and show `test_command`, `fast_test_command`, `append_only`, and `disabled_rules`. If it does not exist, say so and name which gates are therefore idle.
3. **Off switches.** Check whether any of `NGG_JUDGE`, `NGG_DONE`, `NGG_TESTGUARD`, `NGG_GUARD`, `NGG_PROFILE` is turned off in the environment.
4. **Recent verdicts.** Read the last 20 lines of `events.log` in the state folder and summarize. It lives at `${CLAUDE_PLUGIN_DATA}/state/events.log`. If it is not there, say so.

## How to report

One table. Per gate: **on / idle for lack of config / off**, and the evidence for that.

If there are blocks on record, count them by rule and show that too. Call out any rule that looks like it is producing false positives, and mention two things they can do about it: disable that one rule or check with `disabled_rules` in `.check.toml` (rules `R0`–`R5`, or gate items such as `done.pr` and `ti.exclude`), or open an issue so the rule itself gets fixed.

If `events.log` shows `off=[...]`, say which rules or checks this repo has disabled and since when, based on the log — not on the config file alone.

Lines with `allowed=[...]` are one-off passes a human granted by writing `check allow <item>` in a prompt. List them separately from blocks and from disabled checks.
