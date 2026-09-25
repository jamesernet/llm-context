#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SRC/bin/env-check.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/llmctx-env-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "env-check test failed: $*" >&2
  exit 1
}

# A repo whose declaration is written for us, with no ambient CI or AWS state
# leaking in from the caller.
repo() {
  local dir="$tmp/$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" >"$dir/.llmctx.json"
  printf '%s' "$dir"
}

run() { # dir [mode] -> output on stdout, exit status in $status
  local dir="$1" mode="${2:-check}"
  set +e
  output="$(CI= HOME="$tmp/home" "$CHECK" "$mode" "$dir" 2>&1)"
  status=$?
  set -e
}

mkdir -p "$tmp/home"

# --- no declaration is not a failure ---------------------------------------
d="$(repo none '{"schemaVersion":1}')"
run "$d"
[[ "$status" -eq 0 ]] || fail "a repo with no environment should pass, got $status"
[[ "$output" == *"declares no environment"* ]] || fail "expected the no-environment message: $output"

# --- no policy file at all --------------------------------------------------
mkdir -p "$tmp/bare"
run "$tmp/bare"
[[ "$status" -eq 0 ]] || fail "a repo with no .llmctx.json should pass, got $status"

# --- an unknown target names the ones that exist ----------------------------
d="$(repo unknown '{"schemaVersion":1,"environment":{"target":"nope"}}')"
run "$d"
[[ "$status" -eq 1 ]] || fail "an unknown target must fail, got $status"
[[ "$output" == *"cloudflare-pages"* ]] || fail "expected the available targets listed: $output"

# --- a Pages site that deploys on push needs no token -----------------------
# The regression this guards: the target lists CLOUDFLARE_API_TOKEN as one it
# MAY need, and checking the target's list instead of the project's reported a
# missing secret for every Pages site that holds no token, which is most.
d="$(repo pages '{"schemaVersion":1,"environment":{"target":"cloudflare-pages"}}')"
touch "$d/_headers" "$d/_redirects"
run "$d"
[[ "$status" -eq 0 ]] || fail "a Pages site with no declared secret should pass: $output"
[[ "$output" != *"CLOUDFLARE_API_TOKEN"* ]] || fail "target secrets must not be checked: $output"

# --- a secret the project DOES declare is checked ---------------------------
d="$(repo pages-token '{"schemaVersion":1,"environment":{"target":"cloudflare-pages","secrets":["CLOUDFLARE_API_TOKEN"]}}')"
touch "$d/_headers" "$d/_redirects"
run "$d"
[[ "$status" -eq 1 ]] || fail "a declared but unbound secret must fail"
[[ "$output" == *"CLOUDFLARE_API_TOKEN"* ]] || fail "expected the secret named: $output"
printf 'export CLOUDFLARE_API_TOKEN=whatever\n' >"$d/.envrc.local"
run "$d"
[[ "$status" -eq 0 ]] || fail "a bound secret should pass: $output"
[[ "$output" != *whatever* ]] || fail "a secret VALUE must never be printed: $output"

# --- required env names must appear in the declaration ----------------------
d="$(repo amplify-bare '{"schemaVersion":1,"environment":{"target":"aws-amplify"}}')"
run "$d"
[[ "$output" == *"env:AWS_PROFILE"*MISSING* || "$output" == *MISSING*"env:AWS_PROFILE"* ]] ||
  [[ "$output" == *"AWS_PROFILE"* ]] || fail "expected AWS_PROFILE reported: $output"
[[ "$status" -eq 1 ]] || fail "a target requiring env names must fail when they are absent"

# --- AWS profile resolution, and the measured CI exemption ------------------
d="$(repo amplify '{"schemaVersion":1,"environment":{"target":"aws-amplify","cloud":{"awsProfile":"acme","awsRegion":"us-west-2"}}}')"
touch "$d/customHttp.yml"
run "$d"
[[ "$output" == *"~/.aws/config does not exist"* ]] || fail "expected the missing-config finding: $output"
set +e
ci_output="$(CI=1 HOME="$tmp/home" "$CHECK" check "$d" 2>&1)"
set -e
[[ "$ci_output" == *"CI"* ]] || fail "CI must be exempt when ~/.aws/config is absent: $ci_output"
# Where a config DOES exist, the profile is still checked — only the missing
# file is exempt.
mkdir -p "$tmp/home/.aws"
printf '[profile other]\n' >"$tmp/home/.aws/config"
set +e
ci_output="$(CI=1 HOME="$tmp/home" "$CHECK" check "$d" 2>&1)"
ci_status=$?
set -e
[[ "$ci_status" -eq 1 ]] || fail "a present config must still be checked under CI"
printf '[profile acme]\n' >>"$tmp/home/.aws/config"
run "$d"
[[ "$output" == *"configured in ~/.aws/config"* ]] || fail "expected the profile to resolve: $output"

# --- two sources of truth for one Cloudflare account ------------------------
d="$(repo workers '{"schemaVersion":1,"environment":{"target":"other","cloud":{"cloudflareAccount":"deadbeef"}}}')"
run "$d"
[[ "$output" == *"no wrangler config"* ]] || fail "expected the no-wrangler note: $output"
printf '{"account_id":"cafe"}\n' >"$d/wrangler.jsonc"
run "$d"
[[ "$status" -eq 1 ]] || fail "a disagreeing wrangler account must fail"
[[ "$output" == *CONFLICT* ]] || fail "expected CONFLICT: $output"
printf '{"account_id":"deadbeef"}\n' >"$d/wrangler.jsonc"
run "$d"
[[ "$output" == *"agrees with wrangler.jsonc"* ]] || fail "expected agreement: $output"

# --- explain is read-only and prints the manual steps -----------------------
d="$(repo explain '{"schemaVersion":1,"environment":{"target":"cloudflare-pages"}}')"
run "$d" explain
[[ "$status" -eq 0 ]] || fail "explain must succeed: $output"
[[ "$output" == *"Still manual"* ]] || fail "explain must print the manual steps: $output"
[[ "$output" == *"onboard"* ]] || fail "explain must print the onboard hint: $output"

# --- an invalid declaration is rejected by the policy validator -------------
d="$(repo badsecret '{"schemaVersion":1,"environment":{"target":"other","secrets":["op://Vault/Item/field"]}}')"
run "$d"
[[ "$status" -eq 2 ]] || fail "a vault reference in secrets must be rejected, got $status"
[[ "$output" == *"NAMES"* ]] || fail "expected the names-not-values error: $output"

# --- every shipped target file parses and declares a description ------------
for conf in "$SRC"/targets/*.conf; do
  grep -qE '^description=.+' "$conf" || fail "$(basename "$conf") has no description"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[a-z_]+= ]] || fail "$(basename "$conf"): not key=value: $line"
  done <"$conf"
done

echo "env-check tests: passed"
