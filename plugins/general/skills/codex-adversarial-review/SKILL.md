---
name: codex-adversarial-review
description: Run an adversarial second-opinion review of the current code changes with OpenAI Codex (codex exec in a fresh read-only session), then verify every finding against the code before reporting it. Only the user can start this skill; it never runs on its own.
disable-model-invocation: true
argument-hint: "[base-ref | a..b | commit | focus text]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/run_review.sh *) Bash(git diff *) Bash(git status *) Bash(git log *) Bash(git show *)
metadata:
  short-description: Attack the diff with a fresh Codex session
---

# Codex Adversarial Review

Have an independent model attack the change, then judge its claims yourself.

## Scope

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the scope is whatever the user wrote alongside the skill mention. Map it to script flags like this:

| User wrote | Run with |
| --- | --- |
| nothing | no scope flag (auto: uncommitted changes if the tree is dirty, otherwise commits not on the main branch) |
| a branch or ref such as `main`, `origin/develop` | `--base <ref>` |
| a range such as `abc123..HEAD` | `--range <a>..<b>` |
| a single commit sha | `--commit <sha>` |
| anything else (for example "the retry logic", "auth changes") | `--focus "<text>"`, scope stays auto |

Combinations are fine: `main the migration` becomes `--base main --focus "the migration"`.

## Why a second model, and why adversarial

A reviewer who wrote or watched the code being written shares its blind spots. The Codex session started by this skill has no conversation history, is told to assume the change is broken, and must back every claim with a file, a line, and a failure scenario. That setup deliberately produces false positives alongside real bugs. The value of the exercise comes from step 3, where you check each claim against the code instead of forwarding it.

## Steps

1. **Run the review.** Call `${CLAUDE_SKILL_DIR}/scripts/run_review.sh` with the flags from the table (in Codex, the script lives next to this file under `scripts/`). It prints progress on stderr and, on success, `FINDINGS_FILE=<path>` followed by the JSON on stdout. Codex typically needs two to eight minutes, so give the command the longest timeout you can (in Claude Code, pass a 600000 ms timeout or run it in the background) and do not kill it early. Exit code 2 means nothing to review or bad flags, 3 means the Codex CLI is missing or logged out, 4 means Codex ran but failed. Report those plainly instead of retrying blindly.
   When this skill runs inside Codex itself, the nested `codex exec` needs network access; if the sandbox blocks it, rerun the command with approval rather than giving up.
2. **Read the findings.** Each has `severity`, `claim`, `failure_scenario`, `evidence`, and `confidence`. Also read `reviewed`, which says what Codex did and did not look at.
3. **Verify every finding yourself.** Open the cited file and line, trace the scenario through the actual code, and reach one of three verdicts:
   - CONFIRMED: you followed the scenario and the wrong behavior really happens.
   - PLAUSIBLE: you could neither reproduce nor rule it out (for example it depends on runtime data or a system you cannot inspect).
   - REJECTED: the claim is wrong, and you can say why in one sentence.
   Low confidence is not a reason to skip verification, and a convincing write-up is not a reason to skip it either.
4. **Report to the user.** Lead with confirmed findings ordered by severity, then plausible ones, each with file and line, the scenario, and your verdict. List rejected claims briefly with the reason, so the user can see what was considered. If there were no findings, say what Codex covered according to `reviewed` so the user can judge the depth. Keep the raw JSON path in the report for reference.
5. **Do not fix anything** unless the user asks. The deliverable of this skill is the verified assessment.

## Script reference

```text
run_review.sh [--uncommitted | --base <ref> | --range <a>..<b> | --commit <sha>]
              [--focus <text>] [--model <name>] [--effort low|medium|high|xhigh]
              [--out <file>] [--dry-run]
```

`--dry-run` prints the exact prompt and command without calling Codex; use it when debugging scope detection. The reviewer instructions live in `references/review-prompt.md` and the output shape in `references/findings.schema.json`; edit those, not the script, to change what Codex looks for.
