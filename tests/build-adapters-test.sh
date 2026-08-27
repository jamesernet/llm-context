#!/usr/bin/env bash
set -euo pipefail

# Regression cover for the settings merge. jq's `*` replaces arrays rather than
# merging them, so the previous merge deleted every locally-added hook entry and
# kept only the one this repository declares — silently, and in a way `--check`
# then reported as drift, sending you to the very command that caused it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-adapters-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
test_home="$tmp/home"
mkdir -p "$test_home/.claude"

fail() {
  echo "build-adapters test failed: $*" >&2
  exit 1
}

settings="$test_home/.claude/settings.json"
foreign='$HOME/.claude/hooks/local-guard.sh'

# A machine that already carries its own PreToolUse guard alongside a stale copy
# of the managed one, plus a local key this repository has no opinion about.
jq -n --arg foreign "$foreign" '{
  theme: "dark",
  hooks: {
    PreToolUse: [
      {matcher: "Edit|Write|NotebookEdit|Bash",
       hooks: [{type: "command", command: "$HOME/.claude/hooks/branch-policy.sh"}]},
      {matcher: "Edit|Write|NotebookEdit|Bash",
       hooks: [{type: "command", command: $foreign, statusMessage: "local"}]}
    ]
  }
}' >"$settings"

HOME="$test_home" "$SRC/bin/build-adapters.sh" >/dev/null

jq -e --arg foreign "$foreign" \
  '[.hooks.PreToolUse[].hooks[].command] | index($foreign) != null' "$settings" >/dev/null ||
  fail "a locally-added hook entry was deleted by the merge"
jq -e '[.hooks.PreToolUse[].hooks[].command] | index("$HOME/.claude/hooks/branch-policy.sh") != null' \
  "$settings" >/dev/null || fail "the managed hook entry is missing"
jq -e '.theme == "dark"' "$settings" >/dev/null || fail "an undeclared local key was lost"

# The managed entry must not accumulate a duplicate on every rebuild.
before="$(jq '.hooks.PreToolUse | length' "$settings")"
HOME="$test_home" "$SRC/bin/build-adapters.sh" >/dev/null
[[ "$(jq '.hooks.PreToolUse | length' "$settings")" == "$before" ]] ||
  fail "rebuild duplicated hook entries"

# A foreign entry is not this repository's business, so it is not drift.
HOME="$test_home" "$SRC/bin/build-adapters.sh" --check >/dev/null ||
  fail "a foreign hook entry was reported as drift"

# An edited MANAGED entry still is.
jq '(.hooks.PreToolUse[] | select(.hooks[0].command | test("branch-policy")) | .matcher) = "Bash"' \
  "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
if HOME="$test_home" "$SRC/bin/build-adapters.sh" --check >/dev/null 2>&1; then
  fail "an edited managed hook entry was not reported as drift"
fi

rm -rf "$tmp"
echo "build-adapters tests passed."
