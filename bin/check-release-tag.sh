#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
tag="${1:-}"
[[ "$#" -eq 1 ]] || {
  echo "usage: bin/check-release-tag.sh <vMAJOR.MINOR.PATCH>" >&2
  exit 2
}
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "invalid release tag: $tag" >&2
  exit 1
}

tag_revision="$(git -C "$SRC" rev-parse "refs/tags/$tag^{}" 2>/dev/null)" || {
  echo "release tag does not exist: $tag" >&2
  exit 1
}
head_revision="$(git -C "$SRC" rev-parse HEAD)"
[[ "$tag_revision" == "$head_revision" ]] || {
  echo "release tag $tag does not point to HEAD" >&2
  exit 1
}
echo "release tag verified: $tag ($head_revision)"
