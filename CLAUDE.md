# skills

Personal agent skills packaged as plugins for both Claude Code and OpenAI Codex. One git repository is a plugin marketplace for both tools, and each skill ships as its own plugin.

## Layout

```
.claude-plugin/marketplace.json   Claude Code marketplace (lists every plugin)
.agents/plugins/marketplace.json  Codex marketplace (lists every plugin)
plugins/<name>/
  .claude-plugin/plugin.json      Claude Code plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  skills/<name>/
    SKILL.md                      Shared skill body (read by both tools)
    agents/openai.yaml            Codex-only UI metadata and invocation policy
scripts/validate.sh               Validation for the whole repository
```

## Rules

- One plugin per skill. The plugin name, the skill directory name, and the `name` frontmatter field must all match.
- Every new plugin must be registered in **both** marketplace files and must carry **both** plugin manifests.
- Keep the SKILL.md body portable: Claude Code substitutes `$ARGUMENTS`; Codex injects the file verbatim, so any placeholder needs a fallback sentence.
- A skill that only the user may trigger sets `disable-model-invocation: true` in SKILL.md (Claude Code) and `policy.allow_implicit_invocation: false` in `agents/openai.yaml` (Codex). Codex ignores unknown frontmatter keys, so Claude-only fields are safe.
- Follow the skill-writing guidance of both tools: explain why, prefer imperative steps, keep SKILL.md well under 500 lines, move long material into `references/`.

## Workflow

- Run `scripts/validate.sh` before committing. It checks manifest consistency, runs `claude plugin validate --strict`, and loads the marketplace into an isolated Codex home.
- Test a plugin in Claude Code without installing: `claude --plugin-dir ./plugins/<name>`.
- Commit at the end of every work session with the original task context in the message.
