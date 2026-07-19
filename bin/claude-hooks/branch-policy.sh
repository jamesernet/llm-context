#!/usr/bin/env bash
set -euo pipefail

# Claude Code PreToolUse hook: "branch before you build".
#
# Installed to ~/.claude/hooks/branch-policy.sh by bin/build-adapters.sh and
# referenced from claude/settings.json. Lives here as a real script rather than
# an escaped one-liner inside settings.json so it can be read, shellcheck'd and
# tested — the previous inline version was four levels of JSON escaping deep,
# which made the most security-relevant code in the repo the only code the
# linter could not see.
#
# POLICY, not enforcement. The rule is documented in
# global/behavioral-guidelines.md §5; this hook is one of several backstops, and
# how hard it pushes is a per-repo decision:
#
#   git config llmctx.branchPolicy off      silent; no check at all
#   git config llmctx.branchPolicy remind   remind once per session, then allow   [default]
#   git config llmctx.branchPolicy ask      confirm on every edit/commit
#   git config llmctx.branchPolicy deny     block outright
#
# Repo-local config beats global automatically (git config precedence), so:
#   git config --global llmctx.branchPolicy remind   # your default everywhere
#   git config llmctx.branchPolicy deny              # strict, in this repo only
#
# Why `remind` is the default rather than `deny`: a hard block on main is right
# for a client repo with a real review process, and wrong for a personal repo
# that legitimately has one branch. A guard that is wrong half the time gets
# disabled entirely, and then it protects nothing. Defaulting to a reminder
# keeps the norm visible everywhere while leaving `deny` available where it
# genuinely applies. A committed client profile defaults to `deny`.
#
# Which branches count as protected is configurable too:
#   git config llmctx.protectedBranches "main master release"

# Any unexpected failure must ALLOW, never block. A broken guard that wedges
# every edit is worse than no guard: it trains you to remove it.
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_LIB="$SCRIPT_DIR/llmctx-policy.sh"
[[ -f "$POLICY_LIB" ]] || POLICY_LIB="$SCRIPT_DIR/../lib/policy.sh"
[[ -f "$POLICY_LIB" ]] || exit 0
# shellcheck source=../lib/policy.sh
source "$POLICY_LIB"

repo="$(llmctx_policy_root 2>/dev/null || true)"
[[ -n "$repo" ]] || exit 0
# Invalid policy must not wedge every edit. doctor/repo diff reports the error.
llmctx_policy_resolve "$repo" || exit 0
policy="$LLMCTX_BRANCH_POLICY"
[[ "$policy" == "off" ]] && exit 0

# symbolic-ref, NOT `rev-parse --abbrev-ref HEAD`. On an unborn branch — a repo
# freshly `git init`ed, before its first commit — rev-parse reports the literal
# string "HEAD", so a brand new `main` reads as unprotected and the very first
# commit of a repo sails past the guard. symbolic-ref resolves it correctly.
# It exits non-zero on a detached HEAD, which is not a protected branch anyway.
branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
[[ -n "$branch" ]] || exit 0 # not a git repo, or detached HEAD

protected="$LLMCTX_PROTECTED_BRANCHES"
is_protected=0
for b in $protected; do
  [[ "$branch" == "$b" ]] && is_protected=1 && break
done
[[ "$is_protected" -eq 1 ]] || exit 0

# A merge, rebase, cherry-pick or bisect in progress legitimately edits files on
# the protected branch — that is what resolving a conflict IS. Worse, the advice
# this hook gives is actively wrong mid-operation: branching now would strand the
# in-flight merge. Stay out of the way until it finishes.
git_dir="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
for state in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
  [[ -e "$git_dir/$state" ]] && exit 0
done

# Only mutating tools are in scope. This deliberately re-checks the tool name
# rather than trusting the `matcher` in settings.json to be correct: matchers
# get widened over time, and a guard that blocks Read the moment someone adds a
# tool to that regex is a guard that gets deleted.
#
# For Bash, only git commit/push matter. Everything else on a protected branch
# is fine — reading, building, running tests, and `git checkout -b` itself,
# which must not be blocked or the suggested fix would be unreachable.
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
case "$tool" in
  Edit | Write | NotebookEdit | Bash) ;;
  *) exit 0 ;;
esac

if [[ "$tool" == "Bash" ]]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
  # Match `git commit`/`git push` only where a command can actually START:
  # beginning of string, or after ; && || | & or a newline. Plain substring
  # matching also fired on `echo "run git commit first"`, a heredoc mentioning
  # it, or `grep -r "git push" .` — and under `deny` every one of those false
  # positives is a hard block on an innocent command, which is how a guard
  # earns its removal. Optional leading `sudo`/`env`; allows `cd x && git commit`.
  if ! printf '%s' "$cmd" |
    grep -qE '(^|[;&|]|&&|\|\||[[:space:]]&|^[[:space:]]*)[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[^[:space:]]+=[^[:space:]]*[[:space:]]+)*git[[:space:]]+(commit|push)\b'; then
    exit 0
  fi
fi

# `remind`: fire once per (session, repo), then get out of the way. Keyed on the
# session_id Claude Code passes in, so a new session reminds again but a long
# one does not nag on every edit.
if [[ "$policy" == "remind" ]]; then
  session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"')"
  marker_dir="${TMPDIR:-/tmp}/claude-branch-policy"
  marker="$marker_dir/$(printf '%s|%s' "$session" "$repo" | shasum | cut -d' ' -f1)"
  mkdir -p "$marker_dir"
  # One marker per (session, repo), and sessions are never revisited — so
  # without this they accumulate indefinitely. Cheap, and keeps the hook from
  # slowly littering a directory nobody thinks to look at.
  find "$marker_dir" -type f -mtime +7 -delete 2>/dev/null || true
  [[ -e "$marker" ]] && exit 0
  : >"$marker"
fi

decision="ask"
[[ "$policy" == "deny" ]] && decision="deny"

reason="On protected branch \"$branch\". The convention (behavioral-guidelines §5) is to branch first:

  git checkout -b feature/<short-description>

If this repo legitimately works on $branch, relax it here:
  git config llmctx.branchPolicy off"

jq -n --arg d "$decision" --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
