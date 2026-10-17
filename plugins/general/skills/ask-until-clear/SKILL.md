---
name: ask-until-clear
description: Carry out the task given as the argument, but ask the user about every unclear, doubtful, or ambiguous point first, and keep asking in rounds until nothing is left to guess. Only the user can start this skill; it is never selected automatically.
disable-model-invocation: true
argument-hint: <task>
metadata:
  short-description: Do the task, asking until nothing is unclear
---

# Ask Until Clear

## Task

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention.

## Why this skill exists

The user chose this skill because they would rather answer many questions than receive work built on guesses. The mistakes that hurt here are silent assumptions: picking a plausible interpretation, filling a gap with a default, deciding a detail the user never mentioned. Every one of those is a question that should have been asked. Thoroughness in asking is the whole point, so do not economize on questions to look efficient.

## How to work

1. Do the research you can do alone first. Read the relevant code, docs, and history so you never ask something you could have found out yourself. Questions earn trust only when the user is the one person who can answer them.
2. List every point that is unclear, doubtful, or open to more than one reading: the goal, scope, inputs and outputs, constraints, priorities, edge cases, and what "done" means. Ask about all of them. Do not quietly resolve any of them on your own.
3. Keep asking in rounds. Answers usually reveal further questions. After each reply, re-check the whole picture and ask again. Stop only when you can state the plan without a single assumption.
4. Only then start the work. If a new ambiguity appears mid-task, stop and ask again instead of guessing.
5. If the user explicitly tells you to proceed on your own judgement, state the assumptions you are making and continue.

## How to ask

- Ask in the language the user is writing in.
- Number the questions and make each one concrete and answerable. One topic per question.
- Where you have a leaning, show your current interpretation so the user can simply confirm or correct it, but never present it as decided.
- Put the recommended answer first. When a question offers choices and you favour one, list that choice at the top and mark it as recommended (for example a `(Recommended)` suffix on its label), so the user can accept the default in one move and spend their attention on the questions where they disagree. If you have no preference, say so rather than inventing one.
- Use an interactive question tool when one is available (for example AskUserQuestion in Claude Code). Otherwise ask in chat and wait for the reply before doing anything else.
