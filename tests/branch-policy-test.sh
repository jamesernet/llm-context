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

# --- leading `cd <dir> &&` --------------------------------------------------
#
# The most common way an agent operates on another repository, and it was being
# judged against wherever the session stood. Leading only, one level: chasing
# `cd` through a pipeline or a subshell needs a shell parser, and a guard that
# half-parses shell is wrong in both directions.
#
# GC is built rather than written literally so this file can be edited and run
# by an agent without the string tripping the guard under test.
GC="git"" commit -m x"

feature_repo="$(mktemp -d)"
git -C "$feature_repo" init -q -b main
git -C "$feature_repo" symbolic-ref HEAD refs/heads/feature/elsewhere
printf '%s\n' '{"schemaVersion":1,"profile":"client"}' >"$feature_repo/.llmctx.json"

bash_payload() { jq -nc --arg c "$1" --arg cmd "$2" \
  '{tool_name:"Bash",session_id:"t",tool_input:{command:$cmd},cwd:$c}'; }

# cd into a repo on a feature branch: allowed, whatever this repo is on.
[[ -z "$(hook_with "$(bash_payload "$repo" "cd $feature_repo && $GC")")" ]] ||
  fail "denied a commit in a repo on a feature branch reached by a leading cd"

# Quoted path, and `;` as the separator, are the same case.
[[ -z "$(hook_with "$(bash_payload "$repo" "cd \"$feature_repo\" && $GC")")" ]] ||
  fail "denied a leading cd with a quoted path"
[[ -z "$(hook_with "$(bash_payload "$repo" "cd $feature_repo ; $GC")")" ]] ||
  fail "denied a leading cd separated by ;"

# cd into a repo on a PROTECTED branch: still denied. The rule follows the
# target, which is the whole point — it does not simply stop applying.
[[ "$(decision "$(bash_payload "$feature_repo" "cd $repo && $GC")")" == deny ]] ||
  fail "allowed a commit in a protected checkout reached by a leading cd"

# A cd that is not leading is not followed. Anything else needs a shell parser.
[[ "$(decision "$(bash_payload "$repo" "ls && cd $feature_repo && $GC")")" == deny ]] ||
  fail "followed a non-leading cd"

# A cd to somewhere that does not exist falls back to the session, not to allow.
[[ "$(decision "$(bash_payload "$repo" "cd /no/such/dir && $GC")")" == deny ]] ||
  fail "a cd to a nonexistent directory did not fall back to the session repo"

# `cd "$VAR"` where VAR was assigned earlier in the same command. The dominant
# way an agent addresses a worktree, and until this was handled the capture
# returned the literal string "$WT", failed the directory test, and fell back to
# the session — denying every commit made from every worktree of a repo whose
# primary checkout sat on the trunk.
[[ -z "$(hook_with "$(bash_payload "$repo" "$(printf 'WT=%s\ncd "$WT" && %s' "$feature_repo" "$GC")")")" ]] ||
  fail "denied a cd to a variable assigned in the same command"

# Braced form.
[[ -z "$(hook_with "$(bash_payload "$repo" "$(printf 'WT=%s\ncd "${WT}" && %s' "$feature_repo" "$GC")")")" ]] ||
  fail "denied a cd to a braced variable"

# Same idiom, but the target is on a protected branch: still denied. Resolving
# the variable must not become a way past the rule.
[[ "$(decision "$(bash_payload "$feature_repo" "$(printf 'WT=%s\ncd "$WT" && %s' "$repo" "$GC")")")" == deny ]] ||
  fail "allowed a commit in a protected checkout reached by a variable cd"

# A variable that was never assigned in this command is not guessable, so it
# falls back to the session rather than inventing a target.
[[ "$(decision "$(bash_payload "$repo" "$(printf 'cd "$NOPE" && %s' "$GC")")")" == deny ]] ||
  fail "an unassigned variable did not fall back to the session repo"

# `cd <dir>` terminated by a newline rather than `&&`. The most ordinary shape a
# multi-line script has, and requiring `&&` sent it to the session repo.
[[ -z "$(hook_with "$(bash_payload "$repo" "$(printf 'cd %s\n%s' "$feature_repo" "$GC")")")" ]] ||
  fail "denied a cd terminated by a newline"

# The variable form of the same thing, which is what an agent actually writes.
[[ -z "$(hook_with "$(bash_payload "$repo" "$(printf 'WT=%s\ncd "$WT"\n%s' "$feature_repo" "$GC")")")" ]] ||
  fail "denied a variable cd terminated by a newline"

# Still follows the target: newline-terminated cd into a protected checkout is denied.
[[ "$(decision "$(bash_payload "$feature_repo" "$(printf 'cd %s\n%s' "$repo" "$GC")")")" == deny ]] ||
  fail "allowed a commit in a protected checkout reached by a newline cd"

rm -rf "$feature_repo"

echo "branch policy tests: passed"
