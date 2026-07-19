#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Git exports repository-local variables to hooks. Clear them before tests
# create temporary repositories, or their Git commands can mutate the caller.
while IFS= read -r variable; do
  unset "$variable"
done < <(git rev-parse --local-env-vars)

for test_file in "$SCRIPT_DIR"/*-test.sh; do
  bash "$test_file"
done
