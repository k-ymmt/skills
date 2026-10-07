# Codex plugin and skill spec (snapshot 2026-10-07)

Field lists and examples below were copied from the official `openai/plugins` repository, the `openai/codex` source tree, and the Codex docs. Use [research.md](research.md) to refresh them.

## Contents

1. Plugin directory layout
2. `.codex-plugin/plugin.json`
3. `.agents/plugins/marketplace.json`
4. `SKILL.md` frontmatter as Codex parses it
5. `agents/openai.yaml`
6. Injection format at runtime
7. CLI commands (codex-cli 0.159.2)
8. Claude Code counterpart mapping

## 1. Plugin directory layout

From `github.com/openai/plugins` (`plugins/<name>/`):

```text
my-plugin/
├── .codex-plugin/
│   ├── plugin.json          required manifest
│   └── assets/              optional logos / composer icon referenced by plugin.json
├── skills/                  optional; one subdirectory per skill
│   └── <skill>/SKILL.md
├── .app.json                optional app integration
├── .mcp.json                optional MCP server config
├── agents/, commands/, hooks.json, assets/   optional, plugin-level
└── README.md                optional, human-facing
```

## 2. `.codex-plugin/plugin.json`

Required: `name` (stable kebab-case), `version`, `description`. All paths are relative to the plugin root and start with `./`.

Real example (`plugins/remotion/.codex-plugin/plugin.json` in openai/plugins, trimmed):

```json
{
  "name": "remotion",
  "version": "1.0.7",
  "description": "Remotion video creation skills ...",
  "author": { "name": "Remotion", "email": "hi@remotion.dev", "url": "https://remotion.dev" },
  "homepage": "https://remotion.dev",
  "repository": "https://github.com/remotion-dev/remotion",
  "license": "MIT",
  "keywords": ["remotion", "video"],
  "skills": "./skills/",
  "interface": {
    "displayName": "Remotion",
    "shortDescription": "Make videos agentically",
    "longDescription": "Build videos programmatically ...",
    "category": "Creativity",
    "developerName": "Remotion",
    "capabilities": ["Read", "Write"],
    "defaultPrompt": ["Create an animated chart with 5 bars"],
    "brandColor": "#0B84F3",
    "brandColorDark": "#0C85F4",
    "logo": "./.codex-plugin/assets/logo.png",
    "logoDark": "./.codex-plugin/assets/logo-dark.png",
    "composerIcon": "./.codex-plugin/assets/composer-icon.svg",
    "websiteURL": "https://remotion.dev",
    "privacyPolicyURL": "https://www.remotion.dev/privacy",
    "termsOfServiceURL": "https://www.remotion.dev/terms",
    "supportURL": "https://remotion.dev/support"
  }
}
```

Other documented top-level keys: `mcpServers` (`"./.mcp.json"`), `apps` (`"./.app.json"`). Everything under `interface` is optional and only affects the plugin browser UI.

## 3. `.agents/plugins/marketplace.json`

Lives at the repository root (`$REPO_ROOT/.agents/plugins/marketplace.json`) or per user (`~/.agents/plugins/marketplace.json`). Example copied from openai/plugins:

```json
{
  "name": "openai-curated",
  "interface": { "displayName": "Codex official" },
  "plugins": [
    {
      "name": "linear",
      "source": { "source": "local", "path": "./plugins/linear" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Productivity"
    }
  ]
}
```

- `policy.installation`: `INSTALLED_BY_DEFAULT`, `AVAILABLE`, or `NOT_AVAILABLE`.
- `policy.authentication`: `ON_INSTALL` or `ON_FIRST_USE` (only matters for plugins with apps/MCP auth).
- The marketplace `name` is what users type after `@` in `codex plugin add <plugin>@<name>`.

## 4. `SKILL.md` frontmatter as Codex parses it

Source: `codex-rs/skills/src/parser.rs`.

```rust
struct SkillFrontmatter {
    name: Option<String>,          // defaults to directory name; max 64 chars
    description: Option<String>,
    metadata: SkillFrontmatterMetadata,
}
struct SkillFrontmatterMetadata {
    #[serde(rename = "short-description")]
    short_description: Option<String>,
}
```

No `deny_unknown_fields`, so additional keys (Claude Code's `disable-model-invocation`, `argument-hint`, `allowed-tools`, ...) are ignored. The parser also tolerates an unquoted `description` containing a colon.

Minimal portable frontmatter for a user-only skill shared with Claude Code:

```yaml
---
name: my-skill
description: What it does and when to use it.
disable-model-invocation: true      # Claude Code only; ignored by Codex
metadata:
  short-description: Short UI blurb  # Codex only; ignored by Claude Code
---
```

## 5. `agents/openai.yaml`

Source: `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`. Read by the harness, not the model.

```yaml
interface:
  display_name: "Optional user-facing name"
  short_description: "Optional user-facing description"   # 25–64 chars
  icon_small: "./assets/small-400px.png"
  icon_large: "./assets/large-logo.svg"
  brand_color: "#3B82F6"
  default_prompt: "Use $skill-name to ..."                  # must mention $skill-name

dependencies:
  tools:
    - type: "mcp"            # only "mcp" supported
      value: "github"
      description: "GitHub MCP server"
      transport: "streamable_http"
      url: "https://api.githubcopilot.com/mcp/"

policy:
  allow_implicit_invocation: true   # false = explicit $skill-name only; default true
```

Rules: quote all string values, keep keys unquoted, paths relative to the skill directory. Loading is fail-open (`codex-rs/ext/skills/src/loader/metadata.rs`): an invalid file is logged and ignored.

## 6. Injection format at runtime

Source: `codex-rs/ext/skills/src/fragments.rs`. When a skill is selected (implicitly or via `$name`), Codex appends a user-role fragment:

```text
<skill>
<name>{name}</name>
<path>{path}</path>
{SKILL.md contents, verbatim}
</skill>
```

Nothing in the body is substituted. The user's own message, including the `$name` mention and any text after it, is delivered unchanged.

## 7. CLI commands (codex-cli 0.159.2)

```text
codex plugin marketplace add <SOURCE> [--ref REF] [--sparse PATH]   SOURCE: local path | owner/repo[@ref] | HTTPS/SSH git URL
codex plugin marketplace list | upgrade | remove <name>
codex plugin add <PLUGIN>@<MARKETPLACE>   (or <PLUGIN> --marketplace <MARKETPLACE>)
codex plugin list
codex plugin remove <PLUGIN>
```

Inside a session: `/plugin marketplace add owner/repo`, `/plugins` (browser), `/skills` or `$` to pick a skill, `/reload-plugins`. There is no validate subcommand; use an isolated `CODEX_HOME` (see SKILL.md) to exercise the real loader. Installed plugins are cached under `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/`.

## 8. Claude Code counterpart mapping

| Concern | Codex | Claude Code |
| --- | --- | --- |
| Marketplace file | `.agents/plugins/marketplace.json` | `.claude-plugin/marketplace.json` |
| Plugin manifest | `.codex-plugin/plugin.json` (`name`, `version`, `description` required) | `.claude-plugin/plugin.json` (`name` required) |
| Skills directory | `skills/<name>/SKILL.md` | same path; both default to `./skills/` |
| User-only invocation | `agents/openai.yaml` → `policy.allow_implicit_invocation: false` | SKILL.md → `disable-model-invocation: true` |
| Arguments | none; body injected verbatim | `$ARGUMENTS`, `$0`..`$n`, named args; appended as `ARGUMENTS:` if no placeholder |
| Project-scoped skills | `.agents/skills/<name>/` | `.claude/skills/<name>/` |
| Local test | isolated `CODEX_HOME` + `codex plugin add` | `claude --plugin-dir <dir>`, `claude plugin validate --strict` |
| Install from GitHub | `codex plugin marketplace add owner/repo` then `codex plugin add p@m` | `claude plugin marketplace add owner/repo` then `claude plugin install p@m` |
