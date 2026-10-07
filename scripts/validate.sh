#!/usr/bin/env bash
# Validate the plugin repository for both Claude Code and Codex.
#
# Checks:
#   1. Both marketplace manifests parse and list the same plugin set.
#   2. Every plugin directory has both .claude-plugin/plugin.json and .codex-plugin/plugin.json.
#   3. Every skill directory has SKILL.md whose frontmatter name matches the directory name,
#      and skill names are unique across all plugins (they become /<skill> and $<skill>).
#   4. `claude plugin validate --strict` passes for the marketplace and each plugin (when claude is installed).
#   5. Codex can load the marketplace and list its plugins in an isolated CODEX_HOME (when codex is installed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }
info() { echo "==> $*"; }

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 2; }

info "Checking marketplace manifests"
claude_plugins=$(python3 -c 'import json,sys; m=json.load(open(".claude-plugin/marketplace.json")); print("\n".join(sorted(p["name"] for p in m["plugins"])))')
codex_plugins=$(python3 -c 'import json,sys; m=json.load(open(".agents/plugins/marketplace.json")); print("\n".join(sorted(p["name"] for p in m["plugins"])))')
if [ "$claude_plugins" != "$codex_plugins" ]; then
  err "Marketplace plugin lists differ.\n  claude: $(echo "$claude_plugins" | tr '\n' ' ')\n  codex:  $(echo "$codex_plugins" | tr '\n' ' ')"
fi

info "Checking plugin directories"
for dir in plugins/*/; do
  name=$(basename "$dir")
  echo "$claude_plugins" | grep -qx "$name" || err "plugins/$name is not listed in .claude-plugin/marketplace.json"
  echo "$codex_plugins" | grep -qx "$name" || err "plugins/$name is not listed in .agents/plugins/marketplace.json"
  for manifest in .claude-plugin/plugin.json .codex-plugin/plugin.json; do
    [ -f "$dir$manifest" ] || { err "$dir$manifest is missing"; continue; }
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['name']==sys.argv[2], f\"name {d['name']!r} != {sys.argv[2]!r}\"" "$dir$manifest" "$name" \
      || err "$dir$manifest has a bad or mismatched name"
  done
  [ -d "${dir}skills" ] || err "${dir}skills/ is missing"
  for skill in "$dir"skills/*/; do
    sname=$(basename "$skill")
    [ -f "${skill}SKILL.md" ] || { err "${skill}SKILL.md is missing"; continue; }
    fm_name=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} /^name:/{sub(/^name:[ \t]*/,""); print}' "${skill}SKILL.md")
    [ "$fm_name" = "$sname" ] || err "${skill}SKILL.md frontmatter name '$fm_name' != directory '$sname'"
  done
done

info "Checking that skill names are unique across plugins"
dupes=$(for skill in plugins/*/skills/*/; do basename "$skill"; done | sort | uniq -d)
[ -z "$dupes" ] || err "Duplicate skill names across plugins: $(echo "$dupes" | tr '\n' ' ')"

if command -v claude >/dev/null; then
  info "Running claude plugin validate"
  claude plugin validate . --strict || err "claude plugin validate failed for marketplace"
  for dir in plugins/*/; do
    claude plugin validate "$dir" --strict || err "claude plugin validate failed for $dir"
  done
else
  echo "claude not installed; skipping claude plugin validate"
fi

if command -v codex >/dev/null; then
  info "Checking that Codex can load the marketplace (isolated CODEX_HOME)"
  tmp_home=$(mktemp -d)
  trap 'rm -rf "$tmp_home"' EXIT
  if CODEX_HOME="$tmp_home" codex plugin marketplace add "$ROOT" >/dev/null 2>&1; then
    listing=$(CODEX_HOME="$tmp_home" codex plugin list 2>&1 || true)
    echo "$listing"
    while read -r name; do
      echo "$listing" | grep -q "$name" || err "codex plugin list does not show $name"
    done <<< "$codex_plugins"
  else
    err "codex plugin marketplace add failed"
  fi
else
  echo "codex not installed; skipping codex checks"
fi

if [ "$fail" -ne 0 ]; then
  echo "Validation FAILED" >&2
  exit 1
fi
echo "Validation passed"
