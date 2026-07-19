#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bin/lib/vendor.sh
source "$SRC/bin/lib/vendor.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-vendor-test.XXXXXX")"
fixture="$tmp/source"
mkdir -p "$fixture/vendor/alpha" "$fixture/vendor/beta"
printf '%s\n' '# Alpha' >"$fixture/vendor/alpha/SKILL.md"
printf '%s\n' '# Beta' >"$fixture/vendor/beta/SKILL.md"

fail() {
  echo "vendor lock test failed: $*" >&2
  exit 1
}

content_hash="$(llmctx_vendor_hash "$fixture/vendor")"
jq -n --arg content_hash "$content_hash" '
  {
    schemaVersion:1,
    sources:[{
      name:"example",
      repository:"https://example.com/skills",
      commit:"0123456789abcdef0123456789abcdef01234567",
      contentSha256:$content_hash,
      recordedAt:"2026-07-18",
      skills:["alpha","beta"]
    }]
  }
' >"$fixture/vendor.lock.json"

"$SRC/bin/check-vendor-lock.sh" "$fixture" >/dev/null || fail "valid lock was rejected"

printf '%s\n' 'drift' >>"$fixture/vendor/alpha/SKILL.md"
if "$SRC/bin/check-vendor-lock.sh" "$fixture" >/dev/null 2>&1; then
  fail "content drift was accepted"
fi

printf '%s\n' '# Alpha' >"$fixture/vendor/alpha/SKILL.md"
jq '.sources[0].commit = "0123456"' "$fixture/vendor.lock.json" >"$tmp/invalid.json"
mv "$tmp/invalid.json" "$fixture/vendor.lock.json"
if "$SRC/bin/check-vendor-lock.sh" "$fixture" >/dev/null 2>&1; then
  fail "short commit was accepted"
fi

"$SRC/bin/check-vendor-lock.sh" "$SRC" >/dev/null || fail "repository vendor lock is invalid"
if "$SRC/bin/update-vendor.sh" >/dev/null 2>&1; then
  fail "vendor update accepted a missing ref"
fi
if "$SRC/bin/update-vendor.sh" main >/dev/null 2>&1; then
  fail "vendor update accepted floating main"
fi
echo "vendor lock tests: passed"
