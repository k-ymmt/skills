# How to refresh Codex plugin/skill knowledge

Codex ships weekly and its docs move. Before trusting a detail in this skill for something that matters (a field name, a CLI flag, whether substitution exists), re-check it in this order. Source code beats docs beats blog posts.

## 1. The installed CLI is the ground truth for commands

```bash
codex --version
codex plugin --help
codex plugin marketplace add --help
codex plugin add --help
```

Compare against the version recorded in SKILL.md. If the version is newer, re-derive the command section from `--help` output rather than memory.

## 2. Source of truth for behavior: `openai/codex`

Fetch raw files without cloning:

```bash
B=https://raw.githubusercontent.com/openai/codex/main
curl -sfL $B/codex-rs/skills/src/parser.rs                        # which SKILL.md frontmatter keys are read
curl -sfL $B/codex-rs/ext/skills/src/fragments.rs                 # how a skill is injected into context
curl -sfL $B/codex-rs/ext/skills/src/loader/metadata.rs           # agents/openai.yaml parsing (fail-open)
curl -sfL $B/codex-rs/ext/skills/src/loader/discovery.rs          # discovery paths
curl -sfL $B/codex-rs/skills/src/assets/samples/skill-creator/SKILL.md
curl -sfL $B/codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md
curl -sfL $B/codex-rs/skills/src/assets/samples/review-agent/agents/openai.yaml   # explicit-only example
```

When a file has moved, locate it with GitHub code search (`gh` must be logged in):

```bash
gh search code "allow_implicit_invocation" --repo openai/codex --json path
gh search code "<skill>" --repo openai/codex --json path
gh api "repos/openai/codex/contents/codex-rs/ext/skills/src/loader" --jq '.[].name'
```

Questions this answers and where: argument substitution (grep `ARGUMENTS` under `codex-rs/skills` and `codex-rs/ext/skills`; a zero result means none), unknown-key tolerance (`deny_unknown_fields` in `parser.rs`), policy semantics (`Policy` struct in `metadata.rs`).

## 3. Source of truth for manifests: `openai/plugins`

The official curated marketplace is a living example of every manifest field:

```bash
curl -sL https://raw.githubusercontent.com/openai/plugins/main/.agents/plugins/marketplace.json
gh api repos/openai/plugins/contents/plugins --jq '.[].name'
curl -sL https://raw.githubusercontent.com/openai/plugins/main/plugins/<name>/.codex-plugin/plugin.json
```

Pick a skills-only plugin (for example `remotion`) when you want the `skills` key, and an app-backed one (for example `linear`) when you need `.app.json`, `.mcp.json`, or `policy.authentication`.

## 4. Official docs

- Skills: https://developers.openai.com/codex/skills (currently 308-redirects to https://learn.chatgpt.com/docs/build-skills). Append `.md` to either URL to get Markdown instead of HTML.
- Plugins (user-facing): https://developers.openai.com/codex/plugins → https://learn.chatgpt.com/docs/plugins. This page explains concepts and the `/plugins` browser but not manifest schemas; use `openai/plugins` for those.
- Open standard that both tools follow for SKILL.md: https://agentskills.io/specification

The docs omit several things the source answers (argument handling, parser tolerance), so do not stop at the docs for behavioral questions.

## 5. Claude Code side, for dual-support work

- https://code.claude.com/docs/en/skills.md (frontmatter, `$ARGUMENTS`, `disable-model-invocation`)
- https://code.claude.com/docs/en/plugins/manifest-reference.md
- https://code.claude.com/docs/en/plugins/marketplace-reference.md
- https://code.claude.com/docs/en/plugins/cli-reference.md (`claude plugin validate`, `--plugin-dir`)

In a Claude Code session the `claude-code-guide` subagent can read these for you and returns exact facts with URLs.

## 6. Record what you learned

When a re-check changes a fact, update [codex-spec.md](codex-spec.md) and the version/date line at the top of SKILL.md in the same change, so the next session knows how fresh the snapshot is.
