---
name: config
description: Pick which checks this repo enforces and set the gate's language. Shows every gate item and where it comes from, then writes your choice to disabled_rules (and lang) in .check.toml.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, AskUserQuestion
---

# Choose what to enforce

Let me pick, check by check, what did-you-check enforces in this repo. **Everything starts on.** Turning something off is a decision written into `.check.toml`, so it shows up in the pull request and the team can see it.

**Reply in whatever language I am writing to you in,** and write config comments in that language.

## 1. Read the current state

Read `.check.toml` at the repo root. Take the `disabled_rules` line and the `lang` line if they are there. **Those two lines are the only things this command changes.** Leave every other key and comment exactly as it is.

Check the environment too. If `NGG_DONE`, `NGG_TESTGUARD`, `NGG_GUARD` or `NGG_JUDGE` is `0`, that switch turns a whole gate off regardless of the file. Say so. If `NGG_LANG` is `ko` or `en`, it forces the gate's language regardless of the file; say so, because `lang` in the file has no effect while it is set.

## 2. Show every item

One table with five columns: **Gate, Name, Blocks, Source, On/Off.** Use these rows and copy the Source text as written.

**Never drop the Source column.** It is the reason this command exists: I should see where a rule comes from before I switch it off. A table without it is not the table this command promises.

| Gate | Name | Blocks | Source |
|---|---|---|---|
| Evidence | `R0` | Answering about this repo's state without running a tool | Reduce hallucinations |
| Evidence | `R1` | Asserting a file's state without looking | Reduce hallucinations |
| Evidence | `R2a` | Ending on "this needs to be verified" without running a tool | Reduce hallucinations, "Allow Claude to say I don't know" (deferring what could be checked is not the same) |
| Evidence | `R2b` | Guessing at local state ("probably") | Reduce hallucinations |
| Evidence | `R3` | Claiming tests passed with zero Bash calls | Best practices |
| Evidence | `R4` | Ending again with no tool call after a block | Reduce hallucinations |
| Evidence | `R5` | Claiming success when the last command failed | Hooks docs, built on the `PostToolUseFailure` event |
| Completion | `done.turn` | Ending a turn that changed code before the check passes | Best practices, "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes." |
| Completion | `done.commit` | Committing before the full check passes | Kent Beck, "Only commit when ALL tests are passing." |
| Completion | `done.pr` | Opening a PR whose body has no command output | Best practices, "Have Claude show evidence rather than asserting success" |
| Test integrity | `ti.skip` | Adding `.skip`-style markers to tests | Kent Beck, "disabling or deleting tests" |
| Test integrity | `ti.assert` | Removing assertions | Kent Beck, same sentence |
| Test integrity | `ti.rm` | Deleting test files | Kent Beck, same sentence |
| Test integrity | `ti.exclude` | Adding exclusions to test-runner config | EvilGenie (arXiv 2511.21654), "Modified Testing Procedures" |
| Project guard | `pg.noverify` | `git commit --no-verify` when commit hooks exist | No external source. Skipping the repo's own checks is a human's call |

Append-only paths have no name here. They are on only when `append_only` is set, and `/check:init` handles that.

## 3. Ask what to turn off

Use `AskUserQuestion` with multi-select, one question per gate, listing that gate's items. The question is **which to turn off**, not which to keep. It allows at most four options per question, so split the evidence gate's seven rules across two questions. If I only want to change one gate, ask about that one.

Before asking, say this once: for a single false positive, writing `check allow <item>` on its own line in the next prompt lets one action through without turning anything off. That does not cover `R0`–`R5`.

## 4. Write it

Show the `disabled_rules` line before and after, and get a yes before writing. Then:

- If the file exists, replace that one line, or add it if it was missing.
- If the file does not exist, create it with that line and a one-line comment saying why.
- If nothing is off anymore, remove the line.

Names are comma-separated and case does not matter. Do not write a name that is not in the table above; the gates report unknown names but turn nothing off.

## 5. Language

The gate speaks the repo's language. Resolve the current one in this order and tell me which applies:

1. `NGG_LANG` (`ko`/`en`) if set — an environment override the file cannot change.
2. `lang` in `.check.toml` (`ko`/`en`) if set.
3. Otherwise the locale (`LC_ALL` > `LC_MESSAGES` > `LANG`): a `ko*` locale gives Korean, anything else English.

Offer to pin it with `AskUserQuestion`: Korean, English, or follow the locale. On a choice, change only the `lang` line in `.check.toml` — add or replace `lang = "ko"` / `lang = "en"`, or remove the line to follow the locale. Get a yes before writing, and show the line before and after. If `NGG_LANG` is set, note that the file change takes effect only once it is unset.

## 6. Report

The same table as step 2, with the new state, and the gate's effective language. Then say where the change will be visible: in the diff of `.check.toml`, in the repo profile at the start of every session, and as `off=[...]` in `events.log` whenever a disabled check would have blocked.
