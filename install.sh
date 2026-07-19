#!/usr/bin/env bash
set -euo pipefail

# Stable installation entry point for people and workstation automation.
# Keep orchestration in bin/ so this root-level contract can remain unchanged.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/bin/llmctx" install "$@"
