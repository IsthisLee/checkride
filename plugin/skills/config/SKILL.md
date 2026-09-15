---
name: config
description: Pick which checks this repo enforces and set the gate's language. Shows every gate item and its source, then writes disabled_rules and lang to .check.toml, or the language to global settings.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, AskUserQuestion
---

# Choose what to enforce

Let me pick, check by check, what did-you-check enforces in this repo. **Everything starts on.** Turning something off is a decision written into `.check.toml`, so it shows up in the pull request and the team can see it.

**Reply in whatever language I am writing to you in,** and write config comments in that language.

## 1. Read the current state

Read `.check.toml` at the repo root. Take the `disabled_rules` line and the `lang` line if they are there. **Those two lines, plus `env.NGG_LANG` in `~/.claude/settings.json` when I choose a global language, are the only things this command changes.** Leave every other key and comment exactly as it is.

Check the environment too. If `NGG_DONE`, `NGG_TESTGUARD`, `NGG_GUARD` or `NGG_JUDGE` is `0`, that switch turns a whole gate off regardless of the file. Say so. If `NGG_LANG` is `ko` or `en`, it forces the gate's language regardless of the file; say so, because `lang` in the file has no effect while it is set.

`NGG_LANG` can also sit in the `env` block of `~/.claude/settings.json`. Look only at that one key there. That file can hold tokens, so never print it whole.

## 2. Show every item

One table with five columns: **Gate, Name, Blocks, Source, On/Off.** Use these rows and copy the Source text as written.

**Never drop the Source column.** It is the reason this command exists: I should see where a rule comes from before I switch it off. A table without it is not the table this command promises.

| Gate | Name | Blocks | Source |
|---|---|---|---|
| Evidence | `R0` | Answering about this repo's state without running a tool | Prompting best practices, "investigate and read relevant files BEFORE answering questions about the codebase" |
| Evidence | `R1` | Asserting a file's state without looking | Prompting best practices, "Never make any claims about code before investigating unless you are certain of the correct answer" |
| Evidence | `R2a` | In a question about the codebase, ending on "this needs to be verified" without running a tool | Prompting best practices, "investigate and read relevant files BEFORE answering questions about the codebase". Saying why it cannot be checked is exempt: Reduce hallucinations, "Allow Claude to say I don't know" |
| Evidence | `R2b` | With zero tool calls, guessing at local state ("probably") | Prompting best practices, "Never speculate about code you have not opened" |
| Evidence | `R3` | Claiming tests passed with zero Bash calls | Best practices, "Have Claude show evidence rather than asserting success" |
| Evidence | `R5` | Claiming success when the last command failed | Best practices, "Have Claude show evidence rather than asserting success" |
| Completion | `done.turn` | Ending a turn that changed code before the check passes | Best practices, "As a deterministic gate: a Stop hook runs your check as a script and blocks the turn from ending until it passes." |
| Completion | `done.commit` | Committing before the full check passes | Kent Beck, "Only commit when ALL tests are passing." |
| Completion | `done.pr` | Opening a PR whose body claims tests passed or something was verified, with no command output | Best practices, "Have Claude show evidence rather than asserting success" |
| Test integrity | `ti.skip` | Adding `.skip`-style markers to tests | Kent Beck, "disabling or deleting tests" |
| Test integrity | `ti.assert` | Removing assertions | EvilGenie (arXiv 2511.21654), "Modified Testing Procedure": "The agent modifies the test cases or the code that runs the testing procedure." |
| Test integrity | `ti.rm` | Deleting test files | Kent Beck, same sentence |
| Test integrity | `ti.exclude` | Adding exclusions to test-runner config | EvilGenie (arXiv 2511.21654), same section |

Append-only paths have no name here. They are on only when `append_only` is set, and `/check:init` handles that.

## 3. Ask what to turn off

Use `AskUserQuestion` with multi-select, one question per gate, listing that gate's items. The question is **which to turn off**, not which to keep. It allows at most four options per question, so split the evidence gate's six items across two questions. If I only want to change one gate, ask about that one.

Before asking, say this once: for a single false positive, writing `check allow <item>` on its own line in the next prompt lets one action through without turning anything off. That does not cover `R0`–`R5`.

## 4. Write it

Show the `disabled_rules` line before and after, and get a yes before writing. Then:

- If the file exists, replace that one line, or add it if it was missing.
- If the file does not exist, create it with that line and a one-line comment saying why.
- If nothing is off anymore, remove the line.

Names are comma-separated and case does not matter. Do not write a name that is not in the table above; the gates report unknown names but turn nothing off.

## 5. Language

The gate speaks the repo's language. Resolve the current one in this order and tell me which applies:

1. `NGG_LANG` (`ko`/`en`) if set — an environment override the file cannot change. Say whether it comes from the shell or from `~/.claude/settings.json`.
2. `lang` in `.check.toml` (`ko`/`en`) if set.
3. Otherwise the locale (`LC_ALL` > `LC_MESSAGES` > `LANG`): a `ko*` locale gives Korean, anything else English.

Offer to pin it with `AskUserQuestion` in two questions: first the language (Korean, English, or follow the locale), then where to write it.

- **This repo.** Change only the `lang` line in `.check.toml`: add or replace `lang = "ko"` / `lang = "en"`, or remove the line to follow the locale. It shows up in the pull request and applies to everyone who opens the repo. If `NGG_LANG` is set, note that the file change takes effect only once it is unset.
- **Global.** Change only `env.NGG_LANG` in `~/.claude/settings.json`: set it to `ko` / `en`, or remove the key to follow the locale. Put the trade-off in the option's description: it applies to every repo on this machine, it beats every repo's `lang`, and it is in no pull request. Keep every other key and the file's formatting, and do not print the file. If the gate still speaks the old language afterwards, tell me to start a new session.

Get a yes before writing, and show the line or key before and after.

## 6. Report

The same table as step 2, with the new state, and the gate's effective language. Then say where the change will be visible: in the diff of `.check.toml`, in the repo profile at the start of every session, and as `off=[...]` in `events.log` whenever a disabled check would have blocked. A global language is not in any diff; it lives only in `~/.claude/settings.json`.
