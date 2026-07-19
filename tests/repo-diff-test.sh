#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$SRC/bin/llmctx"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-repo-diff-test.XXXXXX")"
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
export GIT_CONFIG_GLOBAL="$tmp/global.gitconfig"

fail() {
  echo "repo diff test failed: $*" >&2
  exit 1
}

if "$CLI" repo diff "$repo" --json >"$tmp/missing.json"; then
  fail "empty repository was reported compliant"
fi
jq -e '.compliant == false and any(.findings[]; .status == "MISSING")' "$tmp/missing.json" >/dev/null ||
  fail "missing findings were not reported"

printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"
printf '%s\n' '# Project instructions' >"$repo/AGENTS.md"
printf '%s\n' '# Claude' '' '@AGENTS.md' >"$repo/CLAUDE.md"
mkdir -p "$repo/docs/briefs"
printf '%s\n' '# Briefs' >"$repo/docs/briefs/README.md"
"$SRC/bin/install-git-hooks.sh" "$repo" >/dev/null

"$CLI" repo diff "$repo" --json >"$tmp/compliant.json" || fail "configured repository was not compliant"
jq -e '.compliant == true' "$tmp/compliant.json" >/dev/null || fail "compliant JSON was false"

git -C "$repo" config --local llmctx.branchPolicy off
"$CLI" repo diff "$repo" --json >"$tmp/override.json" || fail "intentional override failed"
jq -e 'any(.findings[]; .id == "branch-policy" and .status == "OVERRIDE")' "$tmp/override.json" >/dev/null ||
  fail "local override was not identified"

hooks_dir="$(git -C "$repo" rev-parse --git-path hooks)"
case "$hooks_dir" in /*) ;; *) hooks_dir="$repo/$hooks_dir" ;; esac
printf '%s\n' '# stale' >>"$hooks_dir/pre-commit"
if "$CLI" repo diff "$repo" --json >"$tmp/stale.json"; then
  fail "stale hook was reported compliant"
fi
jq -e 'any(.findings[]; .id == "git-hook" and .status == "STALE")' "$tmp/stale.json" >/dev/null ||
  fail "stale hook was not identified"

echo "repo diff tests: passed"
