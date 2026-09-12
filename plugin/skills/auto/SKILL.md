---
name: auto
description: Explore to ship in one run. Calls the built-ins in order and lets the gates hold each step honest.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Task, AskUserQuestion
---

# End to end

Take $ARGUMENTS from start to finish.

**Reply in whatever language I am writing to you in.**

Follow the four stages from the official best practices: Explore → Plan → Implement → Commit. **Do not reinvent a stage — call what already exists.**

## 0. Size it first

If you can describe the diff in one sentence, skip planning. The official docs: "If you could describe the diff in one sentence, skip the plan." Wrap ceremony around small work and people stop using the command.

For anything bigger, walk the steps below.

## 1. Explore

Hand it to the **built-in Explore subagent**. It runs in its own context and returns only the conclusion, so this conversation does not fill up with file contents. The official docs: "Use subagents to keep research out of it."

## 2. Plan

Enter **plan mode** (`Shift+Tab`) and write the plan. No code changes before approval. If the plan turns out to be a large feature, suggest settling a spec first with `/checked-practices:spec`.

## 3. Implement

Follow the `/checked-practices:tdd` loop: failing test first, confirm RED, minimum implementation, confirm GREEN.

All four gates are live through this stage. Assert without evidence and the evidence gate stops you; try to finish without running the checks and the completion gate does; try to neuter a test and the integrity gate does; try to rewrite history and the project guard does. **If a gate blocks you, assume the gate is right and go measure.**

## 4. Review

Call the **built-in `/code-review`**. A fresh subagent judges the diff, so the author is not grading their own work.

Keep the official caution in mind too. "Tell the reviewer to flag only gaps that affect correctness or the stated requirements, and treat the rest as optional." Chase every remark and you end up over-engineering.

If the screen changed, tell me to run the **built-in `/verify`** and look at it. This command cannot click through it for you.

## 5. Finish

Use `/checked-practices:ship` for checks, commit, and PR. If the session ends here, run `/checked-practices:handoff` as well.

## Throughout

After each stage, report in one line **what you did and what is left**. Where a judgment call could go either way, do not decide alone — ask with `AskUserQuestion`.
