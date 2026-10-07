# skills

Personal agent skills, packaged so that each one installs as a plugin in either **Claude Code** or **OpenAI Codex**. This repository is a plugin marketplace for both tools.

## Plugins

| Plugin | Invoke | What it does |
| --- | --- | --- |
| `ask-until-clear` | `/ask-until-clear <task>` (Claude Code) / `$ask-until-clear <task>` (Codex) | Carries out the task, but asks you about every unclear or ambiguous point first and keeps asking until nothing is left to guess. Only you can start it; the model never selects it on its own. |
| `codex-adversarial-review` | `/codex-adversarial-review [ref\|range\|commit\|focus]` (Claude Code) / `$codex-adversarial-review ...` (Codex) | Runs an adversarial review of your changes in a fresh read-only `codex exec` session, then verifies every finding against the code before reporting. Requires the Codex CLI, logged in. Only you can start it. |

## Install

### Claude Code

```bash
claude plugin marketplace add k-ymmt/skills
claude plugin install ask-until-clear@k-ymmt-skills
claude plugin install codex-adversarial-review@k-ymmt-skills
```

Or from inside a session: `/plugin marketplace add k-ymmt/skills`, then `/plugin install ask-until-clear@k-ymmt-skills`.

### Codex

```bash
codex plugin marketplace add k-ymmt/skills
codex plugin add ask-until-clear@k-ymmt-skills
codex plugin add codex-adversarial-review@k-ymmt-skills
```

Or from inside a session: `/plugin marketplace add k-ymmt/skills`, then install it from `/plugins`.

## Try without installing (Claude Code)

```bash
claude --plugin-dir ./plugins/ask-until-clear
```

## Repository layout

```
.claude-plugin/marketplace.json   Claude Code marketplace
.agents/plugins/marketplace.json  Codex marketplace
plugins/<name>/
  .claude-plugin/plugin.json      Claude Code plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  skills/<name>/
    SKILL.md                      Skill body shared by both tools
    agents/openai.yaml            Codex UI metadata and invocation policy
scripts/validate.sh               Validates manifests with both CLIs
```

## Development

```bash
scripts/validate.sh
```

See [CLAUDE.md](CLAUDE.md) for the conventions a new plugin must follow.
