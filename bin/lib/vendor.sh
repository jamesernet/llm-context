# shellcheck shell=bash
# shellcheck source=bin/lib/skills.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills.sh"

llmctx_vendor_hash() {
  local vendor_root="$1" skill_dir
  (
    find "$vendor_root" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort |
      while IFS= read -r skill_dir; do
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        basename "$skill_dir"
        llmctx_skill_hash "$skill_dir"
      done
  ) | llmctx_skill_hash_stream
}
