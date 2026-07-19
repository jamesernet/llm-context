#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-skills-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
fixture="$tmp/source"
mkdir -p "$fixture/bin/lib" "$fixture/skills/owned" "$fixture/vendor/vendored"
cp "$SRC/bin/llmctx" "$SRC/bin/install-skills.sh" "$fixture/bin/"
cp "$SRC/bin/lib/skills.sh" "$fixture/bin/lib/"
printf '%s\n' '# Owned skill' >"$fixture/skills/owned/SKILL.md"
printf '%s\n' '# Vendored skill' >"$fixture/vendor/vendored/SKILL.md"
git -C "$fixture" init -q
export GIT_CONFIG_GLOBAL="$tmp/global.gitconfig"

fail() {
  echo "skill install test failed: $*" >&2
  exit 1
}

copy_home="$tmp/copy-home"
HOME="$copy_home" "$fixture/bin/llmctx" skills install >/dev/null
for target in "$copy_home/.claude/skills" "$copy_home/.codex/skills"; do
  [[ -d "$target/owned" && ! -L "$target/owned" ]] || fail "owned skill was not copied"
  [[ -d "$target/vendored" && ! -L "$target/vendored" ]] || fail "vendored skill was not copied"
  jq -e '.schemaVersion == 1 and .managedBy == "jamesernet/llm-context" and .mode == "copy" and (.contentHash | length) == 64' \
    "$target/owned/.llmctx-managed.json" >/dev/null || fail "copy metadata is invalid"
done

printf '%s\n' '# Updated owned skill' >"$fixture/skills/owned/SKILL.md"
HOME="$copy_home" "$fixture/bin/llmctx" skills install >/dev/null
cmp "$fixture/skills/owned/SKILL.md" "$copy_home/.claude/skills/owned/SKILL.md" >/dev/null ||
  fail "managed copy was not updated"

HOME="$copy_home" "$fixture/bin/llmctx" skills install --dev >/dev/null
[[ -L "$copy_home/.claude/skills/owned" ]] || fail "managed copy did not switch to development mode"
HOME="$copy_home" "$fixture/bin/llmctx" skills install >/dev/null
[[ -d "$copy_home/.claude/skills/owned" && ! -L "$copy_home/.claude/skills/owned" ]] ||
  fail "development link did not switch back to copy mode"

rm -rf "$fixture/vendor/vendored"
HOME="$copy_home" "$fixture/bin/llmctx" skills install >/dev/null
[[ ! -e "$copy_home/.claude/skills/vendored" ]] || fail "retired managed skill was not pruned"

mkdir -p "$fixture/skills/local" "$copy_home/.claude/skills/local"
printf '%s\n' '# Local source' >"$fixture/skills/local/SKILL.md"
printf '%s\n' 'keep me' >"$copy_home/.claude/skills/local/local.txt"
if HOME="$copy_home" "$fixture/bin/llmctx" skills install >/dev/null 2>&1; then
  fail "unmanaged directory conflict was accepted"
fi
[[ "$(cat "$copy_home/.claude/skills/local/local.txt")" == "keep me" ]] || fail "unmanaged directory was changed"

dev_home="$tmp/dev-home"
HOME="$dev_home" "$fixture/bin/llmctx" skills install --dev >/dev/null
for target in "$dev_home/.claude/skills" "$dev_home/.codex/skills"; do
  [[ -L "$target/owned" ]] || fail "development skill was not linked"
  [[ "$(readlink "$target/owned")" == "$fixture/skills/owned" ]] || fail "development link points to the wrong source"
done

if HOME="$dev_home" "$fixture/bin/llmctx" skills install --unknown >/dev/null 2>&1; then
  fail "unknown option was accepted"
fi

echo "skill install tests: passed"
