#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
output_json=0
case "${1:-}" in
  "") ;;
  --json) output_json=1 ;;
  *)
    echo "usage: llmctx version [--json]" >&2
    exit 2
    ;;
esac
[[ "$#" -le 1 ]] || {
  echo "usage: llmctx version [--json]" >&2
  exit 2
}

revision="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
tag="$(git -C "$SRC" describe --tags --exact-match HEAD 2>/dev/null || true)"
version="$tag"
[[ -n "$version" ]] || version="${revision:0:12}"
dirty=false
if [[ -n "$(git -C "$SRC" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
  dirty=true
  version="$version-dirty"
fi

if [[ "$output_json" -eq 1 ]]; then
  jq -n --arg version "$version" --arg revision "$revision" --arg tag "$tag" --argjson dirty "$dirty" \
    '{version:$version,revision:$revision,tag:($tag | select(length > 0) // null),dirty:$dirty}'
else
  echo "$version"
fi
