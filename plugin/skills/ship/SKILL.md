---
name: ship
description: Run the checks, commit, push, open the PR. The PR body carries the commands you ran and their output as evidence.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit
---

# Ship it

Get the checks passing, commit, and open a pull request. If $ARGUMENTS is given, use it as the PR title.

**Reply in whatever language I am writing to you in,** and write the commit message and PR body in that language.

Willison's anti-pattern warning is the reason this command exists.

> "Don't file pull requests with code you haven't reviewed yourself."
> "Agents write convincing looking pull request descriptions. You need to review these too!"

## The order

1. **Read `git status` and `git diff` first.** Do not open a PR without knowing what you changed.
2. **Run the checks.** `test_command` from `.check.toml`, or whatever this repo uses. Keep the output. If it fails, stop here and fix it — the completion gate will block you anyway.
3. Run lint and type-checking too if they are separate.
4. Write the commit message. Put **what changed and why** in the body. Follow the repo's format.
5. Push and open the PR with `gh pr create`.

## What the PR body must carry

- **What changed and why.** One paragraph.
- **The checks you ran and their output.** Paste the command and the result. "Tests pass" on its own is not evidence.
- **What you verified by hand.** If the screen changed, how you looked at it and what you clicked.
- **A note for the reviewer.** Where to look hardest, and what you are still unsure about.

The completion gate enforces the second item. `gh pr create` is refused when the body has no closed code block and no image, unless the branch changes only non-code files. Paste real output. The gate checks the form, not whether the output is genuine — that part is on you.

## Last thing

After opening it, ask me whether **I have read that body.** Making someone else read a description you never read yourself is rude.
