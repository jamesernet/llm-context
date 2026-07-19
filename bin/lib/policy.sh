# shellcheck shell=bash
# shellcheck disable=SC2034 # resolved values are consumed by scripts that source this library

# Shared llm-context repository policy resolution. Source this file; it does not
# execute anything on its own. Compatible with the Bash 3.2 shipped by macOS.

LLMCTX_POLICY_SCHEMA_VERSION=1
LLMCTX_POLICY_ERROR=""

llmctx_policy_error() {
  LLMCTX_POLICY_ERROR="$1"
  return 1
}

llmctx_policy_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

llmctx_policy_file() {
  printf '%s/.llmctx.json\n' "$1"
}

llmctx_policy_validate() {
  local root="$1" file schema profile branch_policy invalid_branch
  file="$(llmctx_policy_file "$root")"
  LLMCTX_POLICY_ERROR=""
  [[ -f "$file" ]] || return 0

  command -v jq >/dev/null 2>&1 || {
    llmctx_policy_error "cannot read $file: jq is not installed"
    return 1
  }
  jq empty "$file" >/dev/null 2>&1 || {
    llmctx_policy_error "invalid JSON: $file"
    return 1
  }

  schema="$(jq -r '.schemaVersion // empty' "$file")"
  [[ "$schema" == "$LLMCTX_POLICY_SCHEMA_VERSION" ]] || {
    llmctx_policy_error "unsupported schemaVersion in $file: ${schema:-missing}"
    return 1
  }

  profile="$(jq -r '.profile // empty' "$file")"
  case "$profile" in
    "" | personal | client) ;;
    *)
      llmctx_policy_error "invalid profile in $file: $profile"
      return 1
      ;;
  esac

  branch_policy="$(jq -r '.branchPolicy // empty' "$file")"
  case "$branch_policy" in
    "" | off | remind | ask | deny) ;;
    *)
      llmctx_policy_error "invalid branchPolicy in $file: $branch_policy"
      return 1
      ;;
  esac

  invalid_branch="$(jq -r '
    if has("protectedBranches") and
       ((.protectedBranches | type) != "array" or
        (.protectedBranches | length) == 0 or
        any(.protectedBranches[]; type != "string" or length == 0))
    then "invalid" else "" end
  ' "$file")"
  [[ -z "$invalid_branch" ]] || {
    llmctx_policy_error "protectedBranches must be a non-empty string array in $file"
    return 1
  }
}

llmctx_policy_resolve() {
  local root="$1" file value profile_default
  llmctx_policy_validate "$root" || return 1
  file="$(llmctx_policy_file "$root")"

  if value="$(git -C "$root" config --local --get llmctx.profile 2>/dev/null)"; then
    LLMCTX_PROFILE="$value"
    LLMCTX_PROFILE_SOURCE="git-local"
  elif [[ -f "$file" ]] && value="$(jq -r '.profile // empty' "$file")" && [[ -n "$value" ]]; then
    LLMCTX_PROFILE="$value"
    LLMCTX_PROFILE_SOURCE="repo-policy"
  else
    LLMCTX_PROFILE="personal"
    LLMCTX_PROFILE_SOURCE="built-in"
  fi
  case "$LLMCTX_PROFILE" in
    personal | client) ;;
    *) llmctx_policy_error "invalid resolved profile: $LLMCTX_PROFILE" || return 1 ;;
  esac

  [[ "$LLMCTX_PROFILE" == "client" ]] && profile_default="deny" || profile_default="remind"
  if value="$(git -C "$root" config --local --get llmctx.branchPolicy 2>/dev/null)"; then
    LLMCTX_BRANCH_POLICY="$value"
    LLMCTX_BRANCH_POLICY_SOURCE="git-local"
  elif [[ -f "$file" ]] && value="$(jq -r '.branchPolicy // empty' "$file")" && [[ -n "$value" ]]; then
    LLMCTX_BRANCH_POLICY="$value"
    LLMCTX_BRANCH_POLICY_SOURCE="repo-policy"
  elif value="$(git config --global --get llmctx.branchPolicy 2>/dev/null)"; then
    LLMCTX_BRANCH_POLICY="$value"
    LLMCTX_BRANCH_POLICY_SOURCE="git-global"
  else
    LLMCTX_BRANCH_POLICY="$profile_default"
    LLMCTX_BRANCH_POLICY_SOURCE="built-in:$LLMCTX_PROFILE"
  fi
  case "$LLMCTX_BRANCH_POLICY" in
    off | remind | ask | deny) ;;
    *) llmctx_policy_error "invalid resolved branchPolicy: $LLMCTX_BRANCH_POLICY" || return 1 ;;
  esac

  if value="$(git -C "$root" config --local --get llmctx.protectedBranches 2>/dev/null)"; then
    LLMCTX_PROTECTED_BRANCHES="$value"
    LLMCTX_PROTECTED_BRANCHES_SOURCE="git-local"
  elif [[ -f "$file" ]] && value="$(jq -r '.protectedBranches // [] | join(" ")' "$file")" && [[ -n "$value" ]]; then
    LLMCTX_PROTECTED_BRANCHES="$value"
    LLMCTX_PROTECTED_BRANCHES_SOURCE="repo-policy"
  elif value="$(git config --global --get llmctx.protectedBranches 2>/dev/null)"; then
    LLMCTX_PROTECTED_BRANCHES="$value"
    LLMCTX_PROTECTED_BRANCHES_SOURCE="git-global"
  else
    LLMCTX_PROTECTED_BRANCHES="main master"
    LLMCTX_PROTECTED_BRANCHES_SOURCE="built-in"
  fi
  [[ -n "$LLMCTX_PROTECTED_BRANCHES" ]] ||
    llmctx_policy_error "resolved protectedBranches is empty"
}
