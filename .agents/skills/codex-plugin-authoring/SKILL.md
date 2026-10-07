---
name: codex-plugin-authoring
description: How to author, package, and verify OpenAI Codex plugins and skills (.codex-plugin/plugin.json, .agents/plugins/marketplace.json, SKILL.md, agents/openai.yaml), including how Codex actually loads them and how to look up the latest spec. Use this whenever creating or editing a Codex plugin or skill, adding a plugin to this repository, making a skill work in both Codex and Claude Code, or answering questions about Codex skill behavior such as argument handling, invocation policy, or discovery paths.
metadata:
  short-description: Author and verify Codex plugins and skills
---

# Codex Plugin Authoring

Knowledge gathered on 2026-10-07 against codex-cli 0.159.2 and the openai/codex `main` branch. Codex evolves quickly, so when a detail matters, re-verify it with [references/research.md](references/research.md) before relying on it.

## Shapes you need

A plugin is a directory with a manifest; skills live under it. Exact field lists and JSON examples copied from the official sources are in [references/codex-spec.md](references/codex-spec.md). Read it when writing a manifest or `agents/openai.yaml`.

```text
<repo>/.agents/plugins/marketplace.json   catalog of plugins (Codex marketplace)
<repo>/plugins/<name>/
  .codex-plugin/plugin.json               required manifest; paths start with "./"
  skills/<skill>/SKILL.md                 frontmatter: name, description, metadata
  skills/<skill>/agents/openai.yaml       optional UI metadata + invocation policy
```

In this repository every plugin also carries `.claude-plugin/plugin.json` and is listed in `.claude-plugin/marketplace.json`, so one directory installs in both tools. `scripts/validate.sh` checks that the two catalogs stay in sync.

## How Codex actually treats a skill (verified in source)

These facts change what you write, so they are worth knowing before drafting:

- **No argument substitution.** Codex does not replace `$ARGUMENTS` or any placeholder. When a user types `$skill-name some task`, the whole message stays the user prompt and the SKILL.md body is injected verbatim as a user-role `<skill>` block containing `<name>`, `<path>`, and the file contents. If a body must also work in Claude Code (which does substitute `$ARGUMENTS`), add a fallback sentence such as "if the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention".
- **Frontmatter is read loosely.** The parser only looks at `name`, `description`, and `metadata.short-description`; every other key is ignored, not rejected. Claude-only keys like `disable-model-invocation` or `argument-hint` are therefore safe in a shared SKILL.md. `name` is limited to 64 characters and should match the directory name.
- **Explicit-only invocation** is `policy.allow_implicit_invocation: false` in `agents/openai.yaml`. The skill then stays out of the model context until the user mentions `$skill-name`. This is the Codex counterpart of Claude Code's `disable-model-invocation: true`; set both for a user-only skill.
- **`agents/openai.yaml` fails open.** A malformed file is logged and ignored rather than blocking the skill, so a typo there silently loses the policy. Check it after editing.
- **Discovery paths**, nearest first: `$CWD/.agents/skills`, `.agents/skills` in parent directories up to the repo root, `~/.agents/skills`, `/etc/codex/skills`, then bundled skills. Installed plugins contribute their `skills/` directory. A project-scoped skill for Codex therefore lives in `.agents/skills/<name>/`; for Claude Code it lives in `.claude/skills/<name>/`, and a symlink from one to the other lets a single copy serve both.

## Writing guidance Codex's own skill-creator gives

The official sample (`codex-rs/skills/src/assets/samples/skill-creator/SKILL.md`) is the best statement of style. Its principles, condensed:

- Assume the model is already capable; include only what changes its decisions. Cut generic advice and speculative edge cases.
- Preserve the user's intent and scope; never let an example or a past failure become a universal rule.
- Match specificity to risk: describe outcomes for open-ended work, reserve fixed step lists for genuinely fragile operations.
- Keep name and description discriminating; add exclusions only to prevent likely misrouting.
- Disclose progressively: short SKILL.md, details in `references/`, scripts only when determinism matters. Do not add README, changelog, or placeholder directories inside a skill.
- `interface.default_prompt` must mention the skill as `$skill-name`; `short_description` is 25–64 characters; quote all YAML string values.

## Verify before committing

There is no `codex plugin validate` command (as of 0.159.2). Instead, exercise the real loader in an isolated home so the user's `~/.codex` is untouched:

```bash
T=$(mktemp -d)
CODEX_HOME="$T" codex plugin marketplace add "$PWD"            # local path, owner/repo[@ref], or git URL
CODEX_HOME="$T" codex plugin add <plugin>@<marketplace-name>
CODEX_HOME="$T" codex plugin list                               # expect "installed, enabled"
rm -rf "$T"
```

`scripts/validate.sh` in this repository already runs the marketplace-add and list steps alongside `claude plugin validate --strict`. For a behavioral check in Claude Code, `claude --plugin-dir ./plugins/<name> -p "/<skill> <task>" --max-turns 2` shows what the skill actually makes the model do.
