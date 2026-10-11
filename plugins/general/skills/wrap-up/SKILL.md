---
name: wrap-up
description: Close a work session in three steps - run the codex-adversarial-review skill on the session's code changes and verify its findings, remove from TODO.md the tasks this session finished, and record in TODO.md anything left undone or deferred. Use it when the work the user asked for is complete and before the session's final commit, and whenever the user asks to wrap up, finish up, or close out the session.
argument-hint: "[notes for the wrap-up]"
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *)
metadata:
  short-description: Review the changes, then settle TODO.md
---

# Wrap Up

End every session the same way: a second opinion on the code, then a TODO.md that matches reality.

## Notes from the user

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the notes are whatever the user wrote alongside the skill mention, possibly nothing. Notes are extra input to the steps below: a review scope goes to step 1, anything the user wants remembered goes to step 3.

## Why these three steps, in this order

A session ends with two kinds of loose ends. Mistakes nobody caught, because the author reviewed their own work; and tasks that were finished, half-finished or deliberately deferred but exist only in the conversation. An independent reviewer catches the first kind. The second kind survives only if TODO.md is edited now, while the session is still in context. Review first, so that findings you decide not to fix can be written down as leftovers.

## Step 1: adversarial review

Run the `codex-adversarial-review` skill, which ships in the same plugin as this one. In Claude Code invoke it through the Skill tool. In Codex, or wherever there is no skill tool, read `../codex-adversarial-review/SKILL.md` next to this file and follow it. Use its auto scope unless the user's notes name one. Follow that skill to the end: run Codex, verify every finding against the code, report the verdicts. If the session produced no code changes (documentation or configuration only), skip the review and say so.

Confirmed findings are the user's to decide on. Fix one only when the user asks; otherwise it becomes a leftover for step 3.

## Step 2: remove finished tasks from TODO.md

Look for `TODO.md` at the repository root, or in the current directory when there is no repository. If there is none, go to step 3.

Read the whole file. Then go through the session's work: what the user asked for, what changed (`git status`, `git diff`, and `git log` for commits made during the session), and what was discussed. Delete every task that this session finished: the task's lines, not just its checkbox. If a section becomes empty, delete its heading too.

- Delete only what the session really finished. A task that was partly done is rewritten to describe the remaining part.
- Leave every other line untouched, including items checked off before the session started and items that look stale. Those are the user's.
- Keep the file's own conventions: section order, checkbox style, line width.

## Step 3: record what is left

Collect everything from this session that is not done:

- work the user asked for that was skipped, scaled down or deferred, and why
- problems found but not fixed, including step 1 findings that were not fixed
- follow-ups you promised or proposed during the session
- anything the user's notes say to remember

Write each as a self-contained item: what to do, where (file or component), and why it was left, so that a future session with no memory of this one can act on it. Add it to the matching section of TODO.md, following the file's conventions, or add a section. If TODO.md does not exist and there is something to record, create it with a single heading. Do not record vague improvements, things already done, or an item the file already has.

If nothing is left, say so and leave the file alone.

## Report

Tell the user briefly: the review's verdicts, or that it was skipped and why; the tasks removed from TODO.md; the items added. This skill does not run tests or commit. Whatever the project's end-of-session rules say about those happens after it.
