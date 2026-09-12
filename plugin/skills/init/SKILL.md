---
name: init
description: Fit checked-practices to this repo. Finds the check command, writes .checked-practices.toml, and proposes append-only paths and secret-file denies.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion
---

# Fit it to this repo

Set things up so the gates actually do work here. **Show a diff and get approval before overwriting any file.**

**Reply in whatever language I am writing to you in,** and write config comments in that language.

## 1. Measure where we are

If the `SessionStart` profile already loaded facts, start from those. Otherwise check for yourself: package manager (lockfile), stack, any existing `.checked-practices.toml`, and the permissions in `.claude/settings.json`.

## 2. Settle the check command

The completion gate looks in this order: `.checked-practices.toml` → `scripts.test` in `package.json` → a `test` target in `Makefile` → `pyproject.toml`.

**Actually run whatever you auto-detect**, show the output, and ask whether it is right. Do not write it down without running it. If it is slow (minutes), propose a fast subset alongside it — the CLAUDE.md example in the official best practices recommends exactly that. "Prefer running single tests, and not the whole test suite, for performance."

```toml
# .checked-practices.toml
test_command = "pnpm test"
fast_test_command = "pnpm test -- --changed"
```

## 3. Record the baseline

If tests are failing right now, list them. When every turn gets blocked by something that was already broken, people switch the gate off. Ask whether to fix them first or start from here.

This is Willison's advice too. "Any time I start a new session with an agent against an existing project I'll start by prompting a variant of the following: First run the tests."

## 4. Propose append-only paths

Find folders whose history must not be rewritten — migrations and the like. Point at `supabase/migrations`, `prisma/migrations`, `db/migrate` if they exist. If there are none, move on. Do not invent one.

```toml
append_only = "supabase/migrations, db/migrate"
```

## 5. Propose blocking secret files

Suggest a `Read` deny rule in `.claude/settings.json`. From the official permissions docs: "A `Read` deny rule also blocks the Edit and Write tools on the same path, including creating a new file there. NotebookEdit isn't covered." If this repo uses NotebookEdit, tell them an `Edit` deny is needed as well.

## 6. Wrap up

Report as a table: what you changed, which gates are now live, and which are still idle and why. The next session's profile will show the same thing.
