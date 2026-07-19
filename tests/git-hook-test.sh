#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-git-hook-test.XXXXXX")"
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" symbolic-ref HEAD refs/heads/main
export GIT_CONFIG_GLOBAL="$tmp/global.gitconfig"

fail() {
  echo "git hook test failed: $*" >&2
  exit 1
}

"$SRC/bin/install-git-hooks.sh" "$repo" >/dev/null
hooks_dir="$(git -C "$repo" rev-parse --git-path hooks)"
case "$hooks_dir" in /*) ;; *) hooks_dir="$repo/$hooks_dir" ;; esac
hook="$hooks_dir/pre-commit"
policy_lib="$hooks_dir/llmctx-policy.sh"
[[ -x "$hook" ]] || fail "pre-commit hook was not installed"
cmp "$SRC/bin/lib/policy.sh" "$policy_lib" >/dev/null || fail "policy library was not installed"

printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"
if (cd "$repo" && "$hook" >/dev/null 2>&1); then
  fail "client policy did not block main"
fi

git -C "$repo" config --local llmctx.branchPolicy off
(cd "$repo" && "$hook" >/dev/null 2>&1) || fail "local off override did not allow"
git -C "$repo" config --local --unset llmctx.branchPolicy

printf '%s\n' '{"schemaVersion":99,"profile":"client"}' >"$repo/.llmctx.json"
(cd "$repo" && "$hook" >/dev/null 2>&1) || fail "invalid policy did not fail open"

printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"
git -C "$repo" symbolic-ref HEAD refs/heads/feature/test
(cd "$repo" && "$hook" >/dev/null 2>&1) || fail "feature branch was blocked"

echo "git hook tests: passed"
