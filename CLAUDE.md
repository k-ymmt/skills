# skills

Personal agent skills packaged as plugins for both Claude Code and OpenAI Codex. One git repository is a plugin marketplace for both tools. General-purpose skills ship together in the `general` plugin; a skill that needs its own MCP server or tooling ships as its own plugin (see `apple-platform-build`).

## Layout

```
.claude-plugin/marketplace.json   Claude Code marketplace (lists every plugin)
.agents/plugins/marketplace.json  Codex marketplace (lists every plugin)
plugins/<plugin>/
  .claude-plugin/plugin.json      Claude Code plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  .mcp.json                       Optional MCP servers (same file for both tools; see apple-platform-build)
  skills/<skill>/                 One or more skills per plugin
    SKILL.md                      Shared skill body (read by both tools)
    agents/openai.yaml            Codex-only UI metadata and invocation policy
scripts/validate.sh               Validation for the whole repository
.agents/skills/<name>/            Project-scoped skills for this repo (Codex reads this path)
.claude/skills/<name>             Symlink to the same directory so Claude Code sees it too
```

## Project skills

- `codex-plugin-authoring`: verified facts about how Codex loads plugins and skills, manifest examples, and how to re-check the latest spec. Load it before adding or changing a Codex plugin here. Keep it current: when a re-check changes a fact, update its `references/codex-spec.md` and the version line in its SKILL.md.

## Rules

- A new general-purpose skill goes into `plugins/general/skills/<skill>/`; bump the `version` in both of that plugin's manifests and in `.claude-plugin/marketplace.json`. Create a separate plugin only when the skill needs its own MCP server or other plugin-level configuration.
- The skill directory name and the `name` frontmatter field must match. Skill names must be unique across the whole marketplace, since Claude Code and Codex expose them as `/<skill>` and `$<skill>`.
- Every new plugin must be registered in **both** marketplace files and must carry **both** plugin manifests, with a `name` that matches its directory.
- Keep the SKILL.md body portable: Claude Code substitutes `$ARGUMENTS`; Codex injects the file verbatim, so any placeholder needs a fallback sentence.
- A skill that only the user may trigger sets `disable-model-invocation: true` in SKILL.md (Claude Code) and `policy.allow_implicit_invocation: false` in `agents/openai.yaml` (Codex). Codex ignores unknown frontmatter keys, so Claude-only fields are safe.
- Follow the skill-writing guidance of both tools: explain why, prefer imperative steps, keep SKILL.md well under 500 lines, move long material into `references/`.

## Workflow

- Run `scripts/validate.sh` before committing. It checks manifest consistency, runs `claude plugin validate --strict`, and loads the marketplace into an isolated Codex home.
- Test a plugin in Claude Code without installing: `claude --plugin-dir ./plugins/<name>`.
- Commit at the end of every work session with the original task context in the message.
