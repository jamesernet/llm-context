#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bin/lib/skills.sh
source "$SCRIPT_DIR/lib/skills.sh"

output_json=0
quiet=0
for arg in "$@"; do
  case "$arg" in
    --json) output_json=1 ;;
    --quiet) quiet=1 ;;
    *)
      echo "usage: llmctx doctor [--json|--quiet]" >&2
      exit 2
      ;;
  esac
done

if [[ "$output_json" -eq 1 && "$quiet" -eq 1 ]]; then
  echo "usage: llmctx doctor [--json|--quiet]" >&2
  exit 2
fi

# jq is required by the installer and by the normal diagnostic renderer. Keep
# its own failure path independent so doctor can still explain a missing jq.
if ! command -v jq >/dev/null 2>&1; then
  if [[ "$quiet" -eq 0 ]]; then
    if [[ "$output_json" -eq 1 ]]; then
      printf '%s\n' '{"healthy":false,"checks":[{"id":"dependency-jq","status":"FAIL","detail":"jq is not installed","remediation":"install jq, then rerun llmctx doctor"}]}'
    else
      echo "FAIL  dependency-jq           jq is not installed"
      echo "      fix: install jq, then rerun llmctx doctor"
      echo "Result: 1 check(s) failed"
    fi
  fi
  exit 1
fi

findings="$(mktemp "${TMPDIR:-/tmp}/llmctx-doctor.XXXXXX")"
skill_catalog="$(mktemp "${TMPDIR:-/tmp}/llmctx-skill-catalog.XXXXXX")"
trap 'rm -f "$findings" "$skill_catalog"' EXIT
failures=0

add_check() {
  local id="$1" status="$2" detail="$3" remediation="$4"
  jq -cn \
    --arg id "$id" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg remediation "$remediation" \
    '{id:$id,status:$status,detail:$detail,remediation:$remediation}' \
    >>"$findings"
  [[ "$status" != "FAIL" ]] || failures=$((failures + 1))
}

if command -v git >/dev/null 2>&1; then
  add_check dependency-git PASS "git is installed" ""
else
  add_check dependency-git FAIL "git is not installed" "install git, then rerun llmctx doctor"
fi
add_check dependency-jq PASS "jq is installed" ""
hash_available=1
if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
  add_check dependency-sha256 PASS "SHA-256 hashing is available" ""
else
  hash_available=0
  add_check dependency-sha256 FAIL "shasum and sha256sum are missing" "install a SHA-256 command, then rerun llmctx doctor"
fi

if "$SCRIPT_DIR/build-adapters.sh" --check >/dev/null 2>&1; then
  add_check adapters PASS "managed adapters and settings are current" ""
else
  add_check adapters FAIL "managed adapters or settings are missing or stale" "$SRC/install.sh"
fi

if command -v git >/dev/null 2>&1 && git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  hooks_path="$(git -C "$SRC" config --get core.hooksPath || true)"
  if [[ -n "$hooks_path" ]]; then
    add_check self-git-hook FAIL "core.hooksPath is managed externally: $hooks_path" "integrate the llm-context checks into that hook framework"
    add_check self-policy-library FAIL "policy resolver could not be verified through core.hooksPath" "integrate the policy resolver into that hook framework"
    add_check self-local-checks FAIL "local checks could not be verified through core.hooksPath" "integrate the llm-context checks into that hook framework"
  else
    hooks_dir="$(git -C "$SRC" rev-parse --git-path hooks)"
    case "$hooks_dir" in /*) ;; *) hooks_dir="$SRC/$hooks_dir" ;; esac

    if [[ -x "$hooks_dir/pre-commit" ]] && cmp "$SCRIPT_DIR/git-hooks/pre-commit" "$hooks_dir/pre-commit" >/dev/null 2>&1; then
      add_check self-git-hook PASS "branch backstop is current" ""
    else
      add_check self-git-hook FAIL "branch backstop is missing or stale" "$SRC/install.sh"
    fi

    if [[ -f "$hooks_dir/llmctx-policy.sh" ]] && cmp "$SCRIPT_DIR/lib/policy.sh" "$hooks_dir/llmctx-policy.sh" >/dev/null 2>&1; then
      add_check self-policy-library PASS "Git hook policy resolver is current" ""
    else
      add_check self-policy-library FAIL "Git hook policy resolver is missing or stale" "$SRC/install.sh"
    fi

    if [[ -x "$hooks_dir/pre-commit.local" ]] && cmp "$SCRIPT_DIR/git-hooks/pre-commit-local.llm-context" "$hooks_dir/pre-commit.local" >/dev/null 2>&1; then
      add_check self-local-checks PASS "repository-local checks are current" ""
    else
      add_check self-local-checks FAIL "repository-local checks are missing or stale" "$SRC/install.sh"
    fi
  fi
else
  add_check self-git-hook FAIL "llm-context source is not a Git repository" "clone llm-context with Git"
  add_check self-policy-library FAIL "llm-context source is not a Git repository" "clone llm-context with Git"
  add_check self-local-checks FAIL "llm-context source is not a Git repository" "clone llm-context with Git"
fi

build_skill_catalog() {
  local source_dir name source_path content_hash duplicate_names
  for source_dir in "$SRC"/skills/*/ "$SRC"/vendor/*/; do
    [[ -f "$source_dir/SKILL.md" ]] || continue
    source_dir="${source_dir%/}"
    name="$(basename "$source_dir")"
    source_path="${source_dir#"$SRC/"}"
    content_hash="$(llmctx_skill_hash "$source_dir")" || return 1
    printf '%s\t%s\t%s\t%s\n' "$name" "$source_dir" "$source_path" "$content_hash" >>"$skill_catalog"
  done
  duplicate_names="$(cut -f1 "$skill_catalog" | LC_ALL=C sort | uniq -d)"
  [[ -z "$duplicate_names" ]] || return 1
}

skill_link_is_managed() {
  local destination="$1" link_target
  [[ -L "$destination" ]] || return 1
  link_target="$(readlink "$destination")"
  case "$link_target" in
    "$SRC"/skills/* | "$SRC"/vendor/*) return 0 ;;
    *) return 1 ;;
  esac
}

check_skill_target() {
  local target="$1" id="$2" name source_dir source_path expected_hash destination
  local metadata_source metadata_hash metadata_mode actual_hash installed copies=0 links=0
  local issues="" expected_count=0

  while IFS=$'\t' read -r name source_dir source_path expected_hash; do
    [[ -n "$name" ]] || continue
    expected_count=$((expected_count + 1))
    destination="$target/$name"
    if [[ -L "$destination" && "$(readlink "$destination")" == "$source_dir" ]]; then
      links=$((links + 1))
    elif llmctx_skill_is_managed_copy "$destination"; then
      metadata_source="$(jq -r '.sourcePath // ""' "$destination/$LLMCTX_SKILL_MARKER_NAME")"
      metadata_hash="$(jq -r '.contentHash // ""' "$destination/$LLMCTX_SKILL_MARKER_NAME")"
      metadata_mode="$(jq -r '.mode // ""' "$destination/$LLMCTX_SKILL_MARKER_NAME")"
      actual_hash="$(llmctx_skill_hash "$destination" 2>/dev/null || true)"
      if [[ "$metadata_source" == "$source_path" && "$metadata_hash" == "$expected_hash" &&
        "$metadata_mode" == copy && "$actual_hash" == "$expected_hash" ]]; then
        copies=$((copies + 1))
      else
        issues="${issues}${issues:+, }$name"
      fi
    else
      issues="${issues}${issues:+, }$name"
    fi
  done <"$skill_catalog"

  if [[ -d "$target" ]]; then
    for installed in "$target"/*; do
      [[ -e "$installed" || -L "$installed" ]] || continue
      name="$(basename "$installed")"
      cut -f1 "$skill_catalog" | grep -Fxq "$name" && continue
      if llmctx_skill_is_managed_copy "$installed" || skill_link_is_managed "$installed"; then
        issues="${issues}${issues:+, }$name"
      fi
    done
  fi

  if [[ -n "$issues" ]]; then
    add_check "$id" FAIL "skills needing attention: $issues" "$SRC/bin/llmctx skills install"
  elif [[ "$copies" -gt 0 && "$links" -gt 0 ]]; then
    add_check "$id" FAIL "managed skills mix copy and development modes" "$SRC/bin/llmctx skills install"
  elif [[ "$links" -eq "$expected_count" ]]; then
    add_check "$id" PASS "$links development links are current" ""
  elif [[ "$copies" -eq "$expected_count" ]]; then
    add_check "$id" PASS "$copies managed copies are current" ""
  else
    add_check "$id" FAIL "managed skill set is incomplete" "$SRC/bin/llmctx skills install"
  fi
}

if [[ "$hash_available" -eq 1 ]] && build_skill_catalog; then
  check_skill_target "$HOME/.claude/skills" claude-skills
  check_skill_target "$HOME/.codex/skills" codex-skills
else
  add_check claude-skills FAIL "managed skills could not be inventoried" "$SRC/bin/llmctx skills install"
  add_check codex-skills FAIL "managed skills could not be inventoried" "$SRC/bin/llmctx skills install"
fi

if [[ "$quiet" -eq 0 ]]; then
  if [[ "$output_json" -eq 1 ]]; then
    jq -s --argjson healthy "$([[ "$failures" -eq 0 ]] && echo true || echo false)" \
      '{healthy:$healthy,checks:.}' "$findings"
  else
    while IFS= read -r finding; do
      status="$(jq -r '.status' <<<"$finding")"
      id="$(jq -r '.id' <<<"$finding")"
      detail="$(jq -r '.detail' <<<"$finding")"
      printf '%-5s %-24s %s\n' "$status" "$id" "$detail"
      remediation="$(jq -r '.remediation' <<<"$finding")"
      [[ -z "$remediation" ]] || printf '      fix: %s\n' "$remediation"
    done <"$findings"
    if [[ "$failures" -eq 0 ]]; then
      echo "Result: healthy"
    else
      echo "Result: $failures check(s) failed"
    fi
  fi
fi

[[ "$failures" -eq 0 ]]
