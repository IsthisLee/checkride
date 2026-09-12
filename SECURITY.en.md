# Security policy

**[한국어](SECURITY.md)** · English

## What this plugin can reach

Hooks **run shell commands as you.** Installing this plugin means trusting that code, so here is what it does.

| What | Where | Risk |
|---|---|---|
| Runs a shell script on every prompt, tool call, and turn end | `hooks/hooks.json` → `hooks/no-guess-gate/*.sh` | If a script changes, arbitrary code runs |
| Reads Claude's full final answer | `stop.sh` receives `last_assistant_message` from the hook input | Whatever is in that answer passes through the decision logic |
| Writes prompts, tool names, and verdicts to files | `${CLAUDE_PLUGIN_DATA}/state/` | The start of the prompt and 80 characters of the answer land in `events.log` |
| Calls a model (optional) | `judge.py` runs `claude -p --model haiku` | The flagged sentences are sent to the model |

**The judge is the only thing that leaves this machine, and it goes through your own Claude Code.** Nothing is sent to any external service. Turn the judge off with `NGG_JUDGE=0`.

What `events.log` keeps is part of the prompt and the first 80 characters of the answer. In a repo handling sensitive material, clear `${CLAUDE_PLUGIN_DATA}/state/` periodically or switch the gate off for that repo (`claude plugin disable checked-practices@checked-practices --scope project`).

## Checking for yourself what you are installing

This plugin runs a shell as you, so you should be able to verify what you are getting.

**Release tags are signed.** Fetch and verify.

```bash
git clone https://github.com/IsthisLee/checked-practices
cd checked-practices
git tag -v v1.4.1        # should print Good "git" signature
```

**Only `plugin/` ships.** 25 files, of which ten hooks and eight skills actually run. Tests, docs, and CI never reach the installed copy.

```bash
git ls-files plugin | wc -l          # 25
cat plugin/hooks/hooks.json          # every event and what it runs
```

**The `main` branch blocks force-push and deletion.** Code you read yesterday does not quietly change today.

**The attack surface is checked against the code.** `tests/attack-surface.sh` re-verifies this document's promises on every run: no network commands, exactly one model call in `judge.py`, three isolation flags on the judge, the profile never reading `.env` values, no writes to system paths, and a timeout on every hook.

## What has already been fixed

**Prompt injection into the judge.** The judge hands Claude's answer to a model. An answer with a verdict JSON planted inside it could be read as the verdict and release the gate. The answer text is now wrapped in a data block, braces and verdict keywords are neutralized, and only the last JSON in the response is read. The regression test is group 12 of `unit.sh`; the record is `docs/VERIFICATION.md` V4f.

**Silent disabling.** If `python3` was missing or a hook exceeded its time, the gate could pass the turn without saying anything. It now reports on stderr and exits 1, and the wiring pins a timeout. V4b, V4g.

## Reporting

If you find a vulnerability, **do not open a public issue.** Tell the repository owner through GitHub's private vulnerability reporting (Security → Report a vulnerability). Reproduction steps and blast radius help.

These count as vulnerabilities.

- Input that neuters the gate, especially anything that flips the verdict through Claude's answer or the user's prompt
- Any path where a hook or the judge executes an unintended command
- `events.log` or state files retaining more than intended

These do not.

- False positives and false negatives. Open an issue — the matching `events.log` line makes it fast
- Someone who installed the hooks editing the scripts themselves. Hooks run as that person by design
