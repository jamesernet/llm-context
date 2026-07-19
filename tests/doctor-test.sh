#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-doctor-test.XXXXXX")"
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

# Private machine settings may be installed before llm-context. Installation
# must preserve keys this public repository does not own.
mkdir -p "$test_home/.claude"
printf '%s\n' '{"permissions":{"allow":["Private(example)"]},"theme":"dark"}' \
  >"$test_home/.claude/settings.json"

fail() {
  echo "doctor test failed: $*" >&2
  exit 1
}

if HOME="$test_home" "$copy/bin/llmctx" doctor --json >"$tmp/missing.json"; then
  fail "unconfigured machine was reported healthy"
fi
jq -e '.healthy == false and any(.checks[]; .id == "adapters" and .status == "FAIL")' "$tmp/missing.json" >/dev/null ||
  fail "missing adapters were not reported"

HOME="$test_home" "$copy/install.sh" >/dev/null
jq -e '.permissions.allow == ["Private(example)"] and .theme == "dark" and (.hooks.PreToolUse | length) == 1' \
  "$test_home/.claude/settings.json" >/dev/null || fail "private Claude settings were not preserved"
HOME="$test_home" "$copy/bin/llmctx" doctor --json >"$tmp/healthy.json" ||
  fail "installed machine was reported unhealthy"
jq -e '.healthy == true and all(.checks[]; .status == "PASS")' "$tmp/healthy.json" >/dev/null ||
  fail "healthy JSON contained a failure"
HOME="$test_home" "$copy/bin/llmctx" doctor --quiet || fail "quiet check failed"
[[ -z "$(HOME="$test_home" "$copy/bin/llmctx" doctor --quiet)" ]] || fail "quiet check produced output"

HOME="$test_home" "$copy/bin/llmctx" skills install --dev >/dev/null
HOME="$test_home" "$copy/bin/llmctx" doctor --json >"$tmp/development.json" ||
  fail "development skill install was reported unhealthy"
jq -e 'all(.checks[] | select(.id == "claude-skills" or .id == "codex-skills"); .detail | contains("development links"))' \
  "$tmp/development.json" >/dev/null || fail "development mode was not identified"
HOME="$test_home" "$copy/bin/llmctx" skills install >/dev/null

rm -rf "$test_home/.claude/skills/codebase-design"
ln -s "$copy/skills/codebase-design" "$test_home/.claude/skills/codebase-design"
if HOME="$test_home" "$copy/bin/llmctx" doctor --json >"$tmp/mixed.json"; then
  fail "mixed skill modes were reported healthy"
fi
jq -e 'any(.checks[]; .id == "claude-skills" and (.detail | contains("mix copy and development")))' \
  "$tmp/mixed.json" >/dev/null || fail "mixed skill modes were not identified"
HOME="$test_home" "$copy/bin/llmctx" skills install >/dev/null

printf '\nlocal skill drift\n' >>"$test_home/.claude/skills/codebase-design/SKILL.md"
if HOME="$test_home" "$copy/bin/llmctx" doctor --json >"$tmp/skill-drift.json"; then
  fail "skill drift was reported healthy"
fi
jq -e 'any(.checks[]; .id == "claude-skills" and .status == "FAIL")' "$tmp/skill-drift.json" >/dev/null ||
  fail "skill drift was not identified"
HOME="$test_home" "$copy/bin/llmctx" skills install >/dev/null

printf '\nlocal drift\n' >>"$test_home/.codex/AGENTS.md"
if HOME="$test_home" "$copy/bin/llmctx" doctor --quiet; then
  fail "adapter drift was reported healthy"
fi

if HOME="$test_home" "$copy/bin/llmctx" doctor --json --quiet >/dev/null 2>&1; then
  fail "conflicting output modes were accepted"
fi

echo "doctor tests: passed"
