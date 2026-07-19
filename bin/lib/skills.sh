# shellcheck shell=bash
LLMCTX_SKILL_MARKER_NAME=".llmctx-managed.json"
LLMCTX_SKILL_MANAGED_BY="jamesernet/llm-context"

llmctx_skill_hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

llmctx_skill_hash_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

llmctx_skill_hash() {
  local source_dir="$1"
  (
    cd "$source_dir" || exit 1
    find . -type f ! -name "$LLMCTX_SKILL_MARKER_NAME" -print | LC_ALL=C sort |
      while IFS= read -r file; do
        printf '%s\n' "$file"
        llmctx_skill_hash_file "$file"
      done
  ) | llmctx_skill_hash_stream
}

llmctx_skill_is_managed_copy() {
  local destination="$1"
  [[ -f "$destination/$LLMCTX_SKILL_MARKER_NAME" ]] &&
    jq -e --arg managed_by "$LLMCTX_SKILL_MANAGED_BY" '.managedBy == $managed_by' \
      "$destination/$LLMCTX_SKILL_MARKER_NAME" >/dev/null 2>&1
}
