#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${1:-$DEFAULT_SRC}"
[[ "$#" -le 1 ]] || {
  echo "usage: llmctx vendor check" >&2
  exit 2
}
# shellcheck source=bin/lib/vendor.sh
source "$SCRIPT_DIR/lib/vendor.sh"

lock="$SRC/vendor.lock.json"
[[ -f "$lock" ]] || {
  echo "vendor lock missing: $lock" >&2
  exit 1
}

jq -e '
  .schemaVersion == 1 and
  (.sources | length) == 1 and
  (.sources[0].name | type) == "string" and
  (.sources[0].repository | type) == "string" and
  (.sources[0].commit | test("^[0-9a-f]{40}$")) and
  (.sources[0].contentSha256 | test("^[0-9a-f]{64}$")) and
  (.sources[0].skills | length) > 0 and
  all(.sources[0].skills[]; type == "string" and length > 0)
' "$lock" >/dev/null || {
  echo "vendor lock is invalid: $lock" >&2
  exit 1
}

expected_skills="$(jq -c '.sources[0].skills | sort' "$lock")"
actual_skills="$(
  find "$SRC/vendor" -mindepth 1 -maxdepth 1 -type d -print |
    while IFS= read -r skill_dir; do
      [[ -f "$skill_dir/SKILL.md" ]] && basename "$skill_dir"
    done | LC_ALL=C sort | jq -R . | jq -sc .
)"
[[ "$actual_skills" == "$expected_skills" ]] || {
  echo "vendor skill set does not match vendor.lock.json" >&2
  exit 1
}

expected_hash="$(jq -r '.sources[0].contentSha256' "$lock")"
actual_hash="$(llmctx_vendor_hash "$SRC/vendor")"
[[ "$actual_hash" == "$expected_hash" ]] || {
  echo "vendor content does not match vendor.lock.json" >&2
  echo "expected: $expected_hash" >&2
  echo "actual:   $actual_hash" >&2
  exit 1
}

echo "vendor lock verified: $(jq -r '.sources[0].commit' "$lock")"
