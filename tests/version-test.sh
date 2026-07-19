#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-version-test.XXXXXX")"
fixture="$tmp/source"
mkdir -p "$fixture/bin"
cp "$SRC/bin/llmctx" "$SRC/bin/version.sh" "$SRC/bin/check-release-tag.sh" "$fixture/bin/"
git -C "$fixture" init -q
git -C "$fixture" config user.name Test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config commit.gpgsign false
mkdir -p "$tmp/empty-hooks"
git -C "$fixture" config core.hooksPath "$tmp/empty-hooks"
printf '%s\n' 'fixture' >"$fixture/tracked.txt"
git -C "$fixture" add tracked.txt bin
git -C "$fixture" commit -q -m fixture
revision="$(git -C "$fixture" rev-parse HEAD)"

fail() {
  echo "version test failed: $*" >&2
  exit 1
}

[[ "$("$fixture/bin/llmctx" version)" == "${revision:0:12}" ]] || fail "untagged version is wrong"
git -C "$fixture" tag v1.2.3
[[ "$("$fixture/bin/llmctx" version)" == v1.2.3 ]] || fail "tagged version is wrong"
"$fixture/bin/check-release-tag.sh" v1.2.3 >/dev/null || fail "valid release tag was rejected"
jq -e --arg revision "$revision" '.version == "v1.2.3" and .revision == $revision and .tag == "v1.2.3" and .dirty == false' \
  <<<"$("$fixture/bin/llmctx" version --json)" >/dev/null || fail "version JSON is wrong"

printf '%s\n' 'dirty' >>"$fixture/tracked.txt"
[[ "$("$fixture/bin/llmctx" version)" == v1.2.3-dirty ]] || fail "dirty version is wrong"
if "$fixture/bin/check-release-tag.sh" release-1 >/dev/null 2>&1; then
  fail "invalid release tag was accepted"
fi

echo "version tests: passed"
