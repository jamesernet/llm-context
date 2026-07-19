#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$SRC/bin/claude-hooks/branch-policy.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-branch-test.XXXXXX")"
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" symbolic-ref HEAD refs/heads/main
export GIT_CONFIG_GLOBAL="$tmp/global.gitconfig"

fail() {
  echo "branch policy test failed: $*" >&2
  exit 1
}

run_hook() {
  (cd "$repo" && printf '%s' '{"tool_name":"Edit","session_id":"test"}' | "$HOOK")
}

printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"
output="$(run_hook)"
[[ "$output" == *'"permissionDecision": "deny"'* ]] || fail "client policy did not deny"

git -C "$repo" config --local llmctx.branchPolicy off
[[ -z "$(run_hook)" ]] || fail "local off override did not allow"
git -C "$repo" config --local --unset llmctx.branchPolicy

printf '%s\n' '{"schemaVersion":99,"profile":"client"}' >"$repo/.llmctx.json"
[[ -z "$(run_hook)" ]] || fail "invalid policy did not fail open"

printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"
git -C "$repo" symbolic-ref HEAD refs/heads/feature/test
[[ -z "$(run_hook)" ]] || fail "feature branch was blocked"

echo "branch policy tests: passed"
