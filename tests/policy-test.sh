#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../bin/lib/policy.sh
source "$SRC/bin/lib/policy.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-policy-test.XXXXXX")"
repo="$tmp/repo"
global_config="$tmp/global.gitconfig"
mkdir -p "$repo"
git -C "$repo" init -q
export GIT_CONFIG_GLOBAL="$global_config"

fail() {
  echo "policy test failed: $*" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

llmctx_policy_resolve "$repo"
assert_eq "$LLMCTX_PROFILE" personal
assert_eq "$LLMCTX_BRANCH_POLICY" remind
assert_eq "$LLMCTX_PROTECTED_BRANCHES" "main master"

printf '%s\n' '{"schemaVersion":1,"profile":"client","protectedBranches":["main","stage"]}' >"$repo/.llmctx.json"
llmctx_policy_resolve "$repo"
assert_eq "$LLMCTX_PROFILE" client
assert_eq "$LLMCTX_PROFILE_SOURCE" repo-policy
assert_eq "$LLMCTX_BRANCH_POLICY" deny
assert_eq "$LLMCTX_BRANCH_POLICY_SOURCE" built-in:client
assert_eq "$LLMCTX_PROTECTED_BRANCHES" "main stage"

git config --global llmctx.branchPolicy ask
llmctx_policy_resolve "$repo"
assert_eq "$LLMCTX_BRANCH_POLICY" ask
assert_eq "$LLMCTX_BRANCH_POLICY_SOURCE" git-global

git -C "$repo" config --local llmctx.profile personal
git -C "$repo" config --local llmctx.branchPolicy off
git -C "$repo" config --local llmctx.protectedBranches "trunk release"
llmctx_policy_resolve "$repo"
assert_eq "$LLMCTX_PROFILE" personal
assert_eq "$LLMCTX_PROFILE_SOURCE" git-local
assert_eq "$LLMCTX_BRANCH_POLICY" off
assert_eq "$LLMCTX_BRANCH_POLICY_SOURCE" git-local
assert_eq "$LLMCTX_PROTECTED_BRANCHES" "trunk release"

printf '%s\n' '{"schemaVersion":99,"profile":"client"}' >"$repo/.llmctx.json"
if llmctx_policy_resolve "$repo"; then
  fail "unsupported schemaVersion was accepted"
fi
[[ "$LLMCTX_POLICY_ERROR" == *"unsupported schemaVersion"* ]] ||
  fail "unexpected validation error: $LLMCTX_POLICY_ERROR"

echo "policy tests: passed"
