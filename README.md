# skills

Personal agent skills, packaged so that each one installs as a plugin in either **Claude Code** or **OpenAI Codex**. This repository is a plugin marketplace for both tools.

## Plugins

### `general`

General-purpose skills bundled as one plugin. Install it once and every skill below becomes available.

| Skill | Invoke | What it does |
| --- | --- | --- |
| `ask-until-clear` | `/ask-until-clear <task>` (Claude Code) / `$ask-until-clear <task>` (Codex) | Carries out the task, but asks you about every unclear or ambiguous point first and keeps asking until nothing is left to guess. Only you can start it; the model never selects it on its own. |
| `codex-adversarial-review` | `/codex-adversarial-review [ref\|range\|commit\|focus]` (Claude Code) / `$codex-adversarial-review ...` (Codex) | Runs an adversarial review of your changes in a fresh read-only `codex exec` session, then verifies every finding against the code before reporting. Requires the Codex CLI, logged in. You can start it at any time, and the model also runs it on its own at the end of a work session, before committing. |
| `wrap-up` | `/wrap-up [notes]` (Claude Code) / `$wrap-up [notes]` (Codex) | Closes a work session: runs `codex-adversarial-review` on the session's changes, removes the tasks the session finished from `TODO.md`, and records anything left undone or deferred there. The model runs it on its own when the requested work is complete, before the final commit; you can also start it yourself. |

### `apple-platform-build`

Builds, tests, and inspects Apple platform projects through Xcode's MCP server (`xcrun mcpbridge`), with an `xcodebuild` fallback.

| Skill | What it does |
| --- | --- |
| `apple-platform-build` | Builds, runs tests, renders previews and reads build errors through Xcode. |
| `simulator-verify` | Verifies an app in the iOS Simulator: drives its flows with Xcode's device interaction tools, catches crashes and console errors, and checks each screen's layout with apvt. |
| `apvt` | Finds layout mistakes (truncation, overlap, off-screen, unsafe area, tap targets) in a running simulator app with [apvt](https://github.com/k-ymmt/apvt). |

## Install

### Claude Code

```bash
claude plugin marketplace add k-ymmt/skills
claude plugin install general@k-ymmt-skills
claude plugin install apple-platform-build@k-ymmt-skills
```

Or from inside a session: `/plugin marketplace add k-ymmt/skills`, then `/plugin install general@k-ymmt-skills`.

### Codex

```bash
codex plugin marketplace add k-ymmt/skills
codex plugin add general@k-ymmt-skills
codex plugin add apple-platform-build@k-ymmt-skills
```

Or from inside a session: `/plugin marketplace add k-ymmt/skills`, then install it from `/plugins`.

## Try without installing (Claude Code)

```bash
claude --plugin-dir ./plugins/general
```

## Repository layout

```
.claude-plugin/marketplace.json   Claude Code marketplace
.agents/plugins/marketplace.json  Codex marketplace
plugins/<plugin>/
  .claude-plugin/plugin.json      Claude Code plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  skills/<skill>/                 One or more skills per plugin
    SKILL.md                      Skill body shared by both tools
    agents/openai.yaml            Codex UI metadata and invocation policy
scripts/validate.sh               Validates manifests with both CLIs
```

## Development

```bash
scripts/validate.sh
```

See [CLAUDE.md](CLAUDE.md) for the conventions a new plugin must follow.
