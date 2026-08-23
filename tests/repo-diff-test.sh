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

# --- declarable conventions ------------------------------------------------
#
# Both defaults are unchanged above; these assert the opt-outs, and that a
# `false` value is distinguishable from an absent one. jq's `//` yields its
# right-hand side for false as well as null, which made `"claudeImport": false`
# read back as unset and do nothing at all.

decl="$tmp/decl"
rm -rf "$decl" && mkdir -p "$decl"
git -C "$decl" init -q -b main
git -C "$decl" checkout -q -b feature/t
printf '%s\n' '# Project instructions' >"$decl/AGENTS.md"
"$SRC/bin/install-git-hooks.sh" "$decl" >/dev/null

printf '%s\n' '{"schemaVersion":1,"profile":"personal"}' >"$decl/.llmctx.json"
"$CLI" repo diff "$decl" --json >"$tmp/undeclared.json" 2>/dev/null || true
jq -e 'any(.findings[]; .id == "briefs" and .status == "MISSING")' "$tmp/undeclared.json" >/dev/null ||
  fail "briefs default is no longer enforced"
jq -e 'any(.findings[]; .id == "claude-import" and .status == "MISSING")' "$tmp/undeclared.json" >/dev/null ||
  fail "claude-import default is no longer enforced"

printf '%s\n' '{"schemaVersion":1,"profile":"personal","briefs":"tracker","claudeImport":false}' >"$decl/.llmctx.json"
"$CLI" repo diff "$decl" --json >"$tmp/declared.json" || fail "declared opt-outs did not make the repository compliant"
jq -e 'any(.findings[]; .id == "briefs" and .status == "OVERRIDE")' "$tmp/declared.json" >/dev/null ||
  fail "briefs=tracker was not recorded as an override"
jq -e 'any(.findings[]; .id == "claude-import" and .status == "OVERRIDE")' "$tmp/declared.json" >/dev/null ||
  fail "claudeImport=false was not recorded as an override (jq // treats false as absent)"

# --- core.hooksPath must not read as compliant ------------------------------
#
# The regression this guards: git-hook returned UNKNOWN, the policy-library
# check was skipped entirely, and a repository with no branch enforcement at all
# printed "Result: compliant".

hp="$tmp/hookspath"
rm -rf "$hp" && mkdir -p "$hp/.githooks"
git -C "$hp" init -q -b main
git -C "$hp" checkout -q -b feature/t
git -C "$hp" config core.hooksPath .githooks
printf '%s\n' '# Project instructions' >"$hp/AGENTS.md"
printf '%s\n' '# Claude' '' '@AGENTS.md' >"$hp/CLAUDE.md"
mkdir -p "$hp/docs/briefs" && printf '%s\n' '# Briefs' >"$hp/docs/briefs/README.md"
printf '%s\n' '{"schemaVersion":1,"profile":"personal"}' >"$hp/.llmctx.json"

"$CLI" repo diff "$hp" --json >"$tmp/hp-empty.json" 2>/dev/null || true
jq -e 'any(.findings[]; .id == "policy-enforcement" and .status == "MISSING")' "$tmp/hp-empty.json" >/dev/null ||
  fail "core.hooksPath with no branch check was not reported"

printf '%s\n' '#!/bin/sh' 'git symbolic-ref --short HEAD' >"$hp/.githooks/pre-commit"
"$CLI" repo diff "$hp" --json >"$tmp/hp-own.json" 2>/dev/null || true
jq -e 'any(.findings[]; .id == "policy-enforcement" and .status == "UNKNOWN")' "$tmp/hp-own.json" >/dev/null ||
  fail "a foreign branch check was not distinguished from none at all"

echo "repo diff tests: passed"
