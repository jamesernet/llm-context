#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bin/lib/skills.sh
source "$SCRIPT_DIR/lib/skills.sh"

mode=copy
case "${1:-}" in
  "") ;;
  --dev) mode=dev ;;
  *)
    echo "usage: llmctx skills install [--dev]" >&2
    exit 2
    ;;
esac
[[ "$#" -le 1 ]] || {
  echo "usage: llmctx skills install [--dev]" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required to install managed skills" >&2
  exit 1
}
if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
  echo "error: shasum or sha256sum is required to install managed skills" >&2
  exit 1
fi

source_revision="unknown"
source_version="unknown"
if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_revision="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
  source_version="$(git -C "$SRC" describe --tags --exact-match HEAD 2>/dev/null || true)"
  [[ -n "$source_version" ]] || source_version="${source_revision:0:12}"
  if [[ -n "$(git -C "$SRC" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    source_version="$source_version-dirty"
  fi
fi

is_managed_link() {
  local destination="$1" link_target
  [[ -L "$destination" ]] || return 1
  link_target="$(readlink "$destination")"
  case "$link_target" in
    "$SRC"/skills/* | "$SRC"/vendor/*) return 0 ;;
    *) return 1 ;;
  esac
}

replace_managed_destination() {
  local staged="$1" destination="$2" backup_root
  backup_root="$(mktemp -d "$(dirname "$destination")/.llmctx-backup.XXXXXX")" || return 1
  if ! mv "$destination" "$backup_root/skill"; then
    rmdir "$backup_root"
    return 1
  fi
  if mv "$staged" "$destination"; then
    rm -rf "$backup_root"
  else
    mv "$backup_root/skill" "$destination" || return 1
    rmdir "$backup_root" || return 1
    return 1
  fi
}

install_copy() {
  local source_dir="$1" destination="$2" source_path="$3" content_hash staged
  if [[ -L "$destination" ]]; then
    if ! is_managed_link "$destination"; then
      echo "conflict: $destination is an unmanaged symlink" >&2
      return 1
    fi
  elif [[ -e "$destination" ]] && ! llmctx_skill_is_managed_copy "$destination"; then
    echo "conflict: $destination is not managed by llm-context" >&2
    return 1
  fi

  content_hash="$(llmctx_skill_hash "$source_dir")" || return 1
  staged="$(mktemp -d "$(dirname "$destination")/.llmctx-skill.XXXXXX")" || return 1
  cp -R "$source_dir/." "$staged/" || {
    rm -rf "$staged"
    return 1
  }
  if ! jq -n \
    --arg managed_by "$LLMCTX_SKILL_MANAGED_BY" \
    --arg source_path "$source_path" \
    --arg source_revision "$source_revision" \
    --arg source_version "$source_version" \
    --arg content_hash "$content_hash" \
    '{schemaVersion:1,managedBy:$managed_by,mode:"copy",sourcePath:$source_path,sourceRevision:$source_revision,sourceVersion:$source_version,contentHash:$content_hash}' \
    >"$staged/$LLMCTX_SKILL_MARKER_NAME"; then
    rm -rf "$staged"
    return 1
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    replace_managed_destination "$staged" "$destination" || return 1
    echo "updated: $destination ($source_version)"
  else
    mv "$staged" "$destination" || return 1
    echo "installed: $destination ($source_version)"
  fi
}

install_dev_link() {
  local source_dir="$1" destination="$2"
  if [[ -L "$destination" ]]; then
    if is_managed_link "$destination"; then
      ln -sfn "$source_dir" "$destination" || return 1
      echo "linked: $destination"
      return
    fi
    echo "conflict: $destination is an unmanaged symlink" >&2
    return 1
  elif [[ -e "$destination" ]]; then
    if llmctx_skill_is_managed_copy "$destination"; then
      rm -rf "$destination" || return 1
    else
      echo "conflict: $destination is not managed by llm-context" >&2
      return 1
    fi
  fi
  ln -s "$source_dir" "$destination" || return 1
  echo "linked: $destination"
}

skill_names="$(mktemp "${TMPDIR:-/tmp}/llmctx-skill-names.XXXXXX")"
trap 'rm -f "$skill_names"' EXIT
for source_dir in "$SRC"/skills/*/ "$SRC"/vendor/*/; do
  [[ -f "$source_dir/SKILL.md" ]] || continue
  basename "$source_dir" >>"$skill_names"
done
duplicate_names="$(LC_ALL=C sort "$skill_names" | uniq -d)"
[[ -z "$duplicate_names" ]] || {
  echo "error: duplicate skill names:" >&2
  echo "$duplicate_names" >&2
  exit 1
}
LC_ALL=C sort -o "$skill_names" "$skill_names"

failures=0
targets=("$HOME/.claude/skills" "$HOME/.codex/skills")
for target in "${targets[@]}"; do
  mkdir -p "$target"

  for installed in "$target"/*; do
    [[ -e "$installed" || -L "$installed" ]] || continue
    name="$(basename "$installed")"
    grep -Fxq "$name" "$skill_names" && continue
    if is_managed_link "$installed"; then
      rm "$installed"
      echo "pruned: $installed"
    elif llmctx_skill_is_managed_copy "$installed"; then
      rm -rf "$installed"
      echo "pruned: $installed"
    fi
  done

  for source_dir in "$SRC"/skills/*/ "$SRC"/vendor/*/; do
    [[ -f "$source_dir/SKILL.md" ]] || continue
    source_dir="${source_dir%/}"
    name="$(basename "$source_dir")"
    source_path="${source_dir#"$SRC/"}"
    destination="$target/$name"
    if [[ "$mode" == dev ]]; then
      install_dev_link "$source_dir" "$destination" || failures=$((failures + 1))
    else
      install_copy "$source_dir" "$destination" "$source_path" || failures=$((failures + 1))
    fi
  done
done

[[ "$failures" -eq 0 ]] || {
  echo "skill installation completed with $failures conflict(s)" >&2
  exit 1
}
echo "skills installed in $mode mode."
