#!/usr/bin/env bash
set -euo pipefail

# Cover for the failure that made accounts necessary: a second Claude config
# directory existed, `llmctx install` reported success, and that directory had
# no skills, no hooks and a frozen copy of CLAUDE.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-accounts-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
copy="$tmp/source"
test_home="$tmp/home"
mkdir -p "$copy" "$test_home"
tar -C "$SRC" --exclude=.git -cf - . | tar -C "$copy" -xf -
rm -rf "$copy/skills" "$copy/vendor"
mkdir -p "$copy/skills/codebase-design" "$copy/vendor/example-vendor"
printf '%s\n' '# Codebase design' >"$copy/skills/codebase-design/SKILL.md"
printf '%s\n' '# Example vendor' >"$copy/vendor/example-vendor/SKILL.md"
git -C "$copy" init -q
export GIT_CONFIG_GLOBAL="$tmp/global.gitconfig"

CLI="$copy/bin/llmctx"
acme_dir="$test_home/.claude-acme"

fail() {
  echo "accounts test failed: $*" >&2
  exit 1
}

run() { HOME="$test_home" "$@"; }

# An unconfigured machine still has exactly one account.
output="$(run "$CLI" account list)"
[[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" == 1 ]] || fail "empty registry listed more than the default"
printf '%s\n' "$output" | grep -q "^default .*$test_home/.claude" || fail "default account missing: $output"

run "$CLI" account add acme "$acme_dir" >/dev/null || fail "could not register an account"
run "$CLI" account list | grep -q "^acme " || fail "registered account was not listed"

# Refusals that must change nothing.
! run "$CLI" account add default "$tmp/elsewhere" 2>/dev/null || fail "reserved name was accepted"
! run "$CLI" account add acme "$tmp/elsewhere" 2>/dev/null || fail "duplicate name was accepted"
! run "$CLI" account add other "$acme_dir" 2>/dev/null || fail "duplicate directory was accepted"
! run "$CLI" account add Acme "$tmp/elsewhere" 2>/dev/null || fail "invalid name was accepted"
! run "$CLI" account add rel ./relative 2>/dev/null || fail "relative directory was accepted"
[[ "$(run "$CLI" account list | wc -l | tr -d ' ')" == 2 ]] || fail "a refused add changed the registry"

# A registry that cannot be parsed must stop the run, not silently shrink it.
git config --global --add llmctx.claudeAccount "no-equals-sign"
! run "$CLI" account list >/dev/null 2>&1 || fail "malformed registry entry was tolerated"
! run "$CLI" doctor --quiet 2>/dev/null || fail "doctor passed with a malformed registry"
git config --global --unset llmctx.claudeAccount "^no-equals-sign$"

run "$copy/install.sh" >/dev/null || fail "install failed"

for dir in "$test_home/.claude" "$acme_dir"; do
  [[ -f "$dir/CLAUDE.md" ]] || fail "$dir has no CLAUDE.md"
  [[ -f "$dir/settings.json" ]] || fail "$dir has no settings.json"
  [[ -x "$dir/hooks/branch-policy.sh" ]] || fail "$dir has no branch-policy hook"
  [[ -d "$dir/skills/codebase-design" ]] || fail "$dir has no skills"
done

# Each account's settings must point at ITS OWN hooks. Borrowing the default
# account's directory works until that one is reset, and then the guard is
# unwired with nothing to show for it.
jq -e '[.hooks.PreToolUse[].hooks[].command] | index("$HOME/.claude-acme/hooks/branch-policy.sh") != null' \
  "$acme_dir/settings.json" >/dev/null || fail "acme settings point at another account's hooks"
jq -e '[.hooks.PreToolUse[].hooks[].command] | index("$HOME/.claude/hooks/branch-policy.sh") != null' \
  "$test_home/.claude/settings.json" >/dev/null || fail "default settings hook path changed"
grep -q '`~/.claude-acme/hooks/branch-policy.sh`' "$acme_dir/CLAUDE.md" ||
  fail "acme CLAUDE.md names another account's hook path"

run "$CLI" doctor --json >"$tmp/health.json" || fail "doctor reported an unhealthy machine"
jq -e 'any(.checks[]; .id == "claude-skills[acme]" and .status == "PASS")' "$tmp/health.json" >/dev/null ||
  fail "doctor did not check the second account"
jq -e 'any(.checks[]; .id == "accounts" and (.detail | test("acme")))' "$tmp/health.json" >/dev/null ||
  fail "doctor did not report the account list"

# A missing skill in ONE account is a failure, even when the other is complete.
rm -rf "$acme_dir/skills/codebase-design"
! run "$CLI" doctor --quiet 2>/dev/null || fail "a stripped second account was reported healthy"
run "$CLI" skills install --account acme >/dev/null || fail "narrowed install failed"
[[ -d "$acme_dir/skills/codebase-design" ]] || fail "narrowed install did not repair the account"
run "$CLI" doctor --quiet || fail "machine unhealthy after repair"

! run "$CLI" skills install --account nope 2>/dev/null || fail "unknown account was accepted"

# Unregistering is a config change, not a deletion.
run "$CLI" account remove acme >/dev/null || fail "could not unregister"
if run "$CLI" account list | grep -q "^acme "; then fail "unregistered account still listed"; fi
[[ -d "$acme_dir/skills" ]] || fail "unregistering deleted the config directory"
! run "$CLI" account remove default 2>/dev/null || fail "the default account was unregistered"

rm -rf "$tmp"
echo "accounts tests: passed"
