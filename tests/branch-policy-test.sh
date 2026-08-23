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

# --- scope: judge the TARGET, not where the session stands -------------------
#
# This hook used to resolve the repository from the process cwd and judge that
# repository's branch whatever the tool was touching. Two false denials
# followed, both hard blocks under `deny`, and neither action broke the rule.

git -C "$repo" symbolic-ref HEAD refs/heads/main
printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$repo/.llmctx.json"

hook_with() { printf '%s' "$1" | "$HOOK"; }
decision() { printf '%s' "$1" | "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow; }

# Misfire 1: a file outside any git repository is none of this hook's business.
outside="$(mktemp -d)"
payload="$(jq -nc --arg c "$repo" --arg f "$outside/scratch.txt" \
  '{tool_name:"Edit",session_id:"t",tool_input:{file_path:$f},cwd:$c}')"
[[ -z "$(hook_with "$payload")" ]] ||
  fail "denied an edit to a file outside any repository"
rm -rf "$outside"

# Misfire 2: pushing a feature branch is how work is published. Naming an
# unprotected ref must not be blocked just because the checkout sits on main.
payload="$(jq -nc --arg c "$repo" \
  '{tool_name:"Bash",session_id:"t",tool_input:{command:"git push origin feature/x"},cwd:$c}')"
[[ -z "$(hook_with "$payload")" ]] ||
  fail "denied pushing an unprotected branch"

# The rule itself must survive all of the above.
payload="$(jq -nc --arg c "$repo" --arg f "$repo/README.md" \
  '{tool_name:"Edit",session_id:"t",tool_input:{file_path:$f},cwd:$c}')"
[[ "$(decision "$payload")" == deny ]] ||
  fail "an edit inside the protected checkout was allowed"

# Relative paths resolve against the payload cwd, or every relative edit escapes.
payload="$(jq -nc --arg c "$repo" \
  '{tool_name:"Edit",session_id:"t",tool_input:{file_path:"README.md"},cwd:$c}')"
[[ "$(decision "$payload")" == deny ]] ||
  fail "a relative-path edit inside the protected checkout was allowed"

for c in "git commit -m x" "git push" "git push origin main"; do
  payload="$(jq -nc --arg c "$repo" --arg cmd "$c" \
    '{tool_name:"Bash",session_id:"t",tool_input:{command:$cmd},cwd:$c}')"
  [[ "$(decision "$payload")" == deny ]] || fail "allowed '$c' on a protected branch"
done

# A push naming a DIFFERENT repository is judged by that repository's branch.
other="$(mktemp -d)"
git -C "$other" init -q -b main
git -C "$other" symbolic-ref HEAD refs/heads/feature/elsewhere
payload="$(jq -nc --arg c "$repo" --arg cmd "git -C $other push -u origin feature/elsewhere" \
  '{tool_name:"Bash",session_id:"t",tool_input:{command:$cmd},cwd:$c}')"
[[ -z "$(hook_with "$payload")" ]] ||
  fail "denied a push to another repository that is on a feature branch"
rm -rf "$other"

echo "branch policy tests: passed"
