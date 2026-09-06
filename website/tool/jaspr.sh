#!/usr/bin/env bash
# Runs any `jaspr` command with the build_runner experiment flag the site
# needs (see tool/dart_shim.sh), e.g. `tool/jaspr.sh serve`.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tool/dart_shim.sh
source tool/dart_shim.sh
use_dart_shim
trap 'rm -rf "$DART_SHIM_DIR"' EXIT
if command -v jaspr >/dev/null 2>&1; then
  exec jaspr "$@"
fi
exec dart pub global run jaspr_cli:jaspr "$@"
