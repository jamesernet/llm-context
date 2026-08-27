#!/usr/bin/env bash
set -euo pipefail

# One-command setup on a new machine (after cloning this repo):
#   bin/bootstrap.sh
#   bin/bootstrap.sh --account <name>    just one Claude account
#
# 1. builds the tool adapters (<account>/CLAUDE.md, ~/.codex/AGENTS.md)
#    and installs the versioned <account>/settings.json
# 2. installs versioned copies of all skills (skills/ + vendor/) into
#    <account>/skills and ~/.codex/skills
#
# <account> is every registered Claude config directory, always including
# ~/.claude. See bin/lib/accounts.sh and `llmctx account list`.
#
# 3. installs the branch backstop + this repo's own pre-commit checks
#    (lint-skills + build-adapters --check) into THIS repo's .git/hooks
#
# Not covered here (per-repo, run where needed):
#   bin/install-git-hooks.sh   pre-commit branch protection for other repos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-adapters.sh" "$@"
"$SCRIPT_DIR/install-skills.sh" "$@"

"$SCRIPT_DIR/install-git-hooks.sh" "$SRC"
hooks_dir="$(git -C "$SRC" rev-parse --git-path hooks)"
case "$hooks_dir" in /*) ;; *) hooks_dir="$SRC/$hooks_dir" ;; esac
cp "$SCRIPT_DIR/git-hooks/pre-commit-local.llm-context" "$hooks_dir/pre-commit.local"
chmod +x "$hooks_dir/pre-commit.local"
echo "installed pre-commit.local (skill lint + adapter drift check) -> $SRC"

echo
echo "bootstrap complete. per-repo git hooks: bin/install-git-hooks.sh in each repo."
