#!/usr/bin/env bash
# Run an adversarial code review of a git change set with `codex exec` and
# write the findings as JSON (schema: ../references/findings.schema.json).
#
# Usage:
#   run_review.sh [scope] [options]
#
# Scope (default: auto):
#   --uncommitted        staged + unstaged + untracked changes
#   --base <ref>         commits on HEAD that are not on <ref> (three-dot diff)
#   --range <a>..<b>     an explicit commit range
#   --commit <sha>       a single commit
#   auto = --uncommitted when the working tree is dirty, otherwise --base <detected main branch>
#
# Options:
#   --focus <text>       extra instructions for the reviewer (what to look at hardest)
#   --model <name>       Codex model override
#   --effort <level>     model_reasoning_effort for Codex (default: high)
#   --out <file>         where to write the JSON findings (default: a temp file)
#   --dry-run            print the prompt and command, do not call Codex
#
# Exit codes: 0 review written; 2 usage error or nothing to review; 3 codex unavailable; 4 codex exec failed.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="$SKILL_DIR/references/review-prompt.md"
SCHEMA_FILE="$SKILL_DIR/references/findings.schema.json"

scope=auto
ref=""
focus=""
model=""
effort="high"
out=""
dry_run=0

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "run_review.sh: $*" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --uncommitted) scope=uncommitted; shift ;;
    --base) scope=base; ref="${2:-}"; shift 2 ;;
    --range) scope=range; ref="${2:-}"; shift 2 ;;
    --commit) scope=commit; ref="${2:-}"; shift 2 ;;
    --focus) focus="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --effort) effort="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v git >/dev/null || die "git is required" 3
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ "$dry_run" -eq 0 ]; then
  command -v codex >/dev/null || die "codex CLI is not installed (npm i -g @openai/codex)" 3
  codex login status >/dev/null 2>&1 || die "codex is not logged in; run 'codex login' first" 3
fi

detect_base() {
  local b
  b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$b" ]; then echo "${b#origin/}"; return; fi
  for c in main master develop; do
    if git rev-parse --verify --quiet "$c" >/dev/null; then echo "$c"; return; fi
  done
  return 1
}

dirty=0
if [ -n "$(git status --porcelain)" ]; then dirty=1; fi

if [ "$scope" = auto ]; then
  if [ "$dirty" -eq 1 ]; then
    scope=uncommitted
  else
    ref="$(detect_base || true)"
    [ -n "$ref" ] || die "working tree is clean and no base branch (origin/HEAD, main, master, develop) was found; pass --base/--range/--commit"
    scope=base
  fi
fi

# Build the scope description and a diffstat for orientation.
scope_text=""
stat=""
case "$scope" in
  uncommitted)
    [ "$dirty" -eq 1 ] || die "nothing to review: working tree is clean"
    untracked="$(git ls-files --others --exclude-standard)"
    stat="$(git diff HEAD --stat 2>/dev/null || git diff --stat)"
    scope_text="Uncommitted changes in the working tree. Run \`git diff HEAD\` to see staged and unstaged changes, and \`git status --porcelain\` for the file list."
    if [ -n "$untracked" ]; then
      scope_text+=$'\n'"Untracked files are NOT in that diff; read each of these in full:"$'\n'"$(echo "$untracked" | sed 's/^/  - /')"
    fi
    ;;
  base)
    [ -n "$ref" ] || die "--base needs a ref"
    git rev-parse --verify --quiet "$ref" >/dev/null || die "unknown ref: $ref"
    if [ -z "$(git rev-list "$ref..HEAD")" ]; then
      die "nothing to review: HEAD has no commits that are not on $ref"
    fi
    stat="$(git diff --stat "$ref...HEAD")"
    scope_text="Commits on HEAD that are not on \`$ref\`. Run \`git diff $ref...HEAD\` for the full diff and \`git log --oneline $ref..HEAD\` for the commit list."
    ;;
  range)
    [ -n "$ref" ] || die "--range needs <a>..<b>"
    git rev-list "$ref" >/dev/null 2>&1 || die "invalid range: $ref"
    stat="$(git diff --stat "$ref")"
    scope_text="The commit range \`$ref\`. Run \`git diff $ref\` for the full diff and \`git log --oneline $ref\` for the commit list."
    ;;
  commit)
    [ -n "$ref" ] || die "--commit needs a sha"
    git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "unknown commit: $ref"
    stat="$(git show --stat --format='%h %s' "$ref")"
    scope_text="The single commit \`$ref\`. Run \`git show $ref\` for the full diff."
    ;;
esac

[ -n "$stat" ] || die "nothing to review: the diff is empty"

if [ -z "$out" ]; then
  out="$(mktemp "${TMPDIR:-/tmp}/codex-adversarial-review.XXXXXX")"
  mv "$out" "$out.json"; out="$out.json"
fi

prompt="$(cat "$PROMPT_FILE")"
prompt+=$'\n\n## Scope of this review\n\n'"$scope_text"$'\n\nDiffstat for orientation:\n\n```\n'"$stat"$'\n```\n'
prompt+=$'\nRepository root: '"$repo_root"$'\n'
if [ -n "$focus" ]; then
  prompt+=$'\n## Focus requested by the caller\n\n'"$focus"$'\n\nTreat this as the highest-priority area, but do not limit the review to it.\n'
fi

cmd=(codex exec --sandbox read-only --ephemeral --skip-git-repo-check --color never
     -c "model_reasoning_effort=\"$effort\""
     --output-schema "$SCHEMA_FILE"
     -o "$out"
     -C "$repo_root")
[ -n "$model" ] && cmd+=(-m "$model")
cmd+=(-)

if [ "$dry_run" -eq 1 ]; then
  echo "--- command ---"; printf '%q ' "${cmd[@]}"; echo
  echo "--- prompt ---"; echo "$prompt"
  exit 0
fi

echo "Scope: $scope${ref:+ ($ref)}" >&2
echo "Running codex exec (this can take several minutes)..." >&2
# Codex streams its progress to stdout; keep it on stderr so stdout stays clean for the result.
if ! printf '%s' "$prompt" | "${cmd[@]}" 1>&2; then
  die "codex exec failed (see output above)" 4
fi
[ -s "$out" ] || die "codex exec produced no final message" 4

# Validate that the output is JSON before handing it back.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$out" 2>/dev/null \
  || die "final message in $out is not valid JSON; inspect it manually" 4

echo "FINDINGS_FILE=$out"
cat "$out"
echo
