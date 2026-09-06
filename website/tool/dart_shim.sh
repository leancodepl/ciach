# Sourced by tool/build.sh and tool/jaspr.sh.
#
# jaspr_builder 0.23 parses Dart with analyzer 12, where Dart 3.13 primary
# constructors are still an off-by-default experiment, and `jaspr` gives no
# way to pass `--enable-experiment` to the build_runner it launches. It does,
# however, locate `dart` through PATH and only insists on an SDK-like layout
# (`<sdk>/bin/dart` next to `<sdk>/version`). So this puts a tiny wrapper
# first on PATH that appends the experiment flag to `dart run build_runner …`
# and hands everything else to the real SDK untouched.
#
# Drop this file, and its two callers, once jaspr builds with analyzer 13+.
use_dart_shim() {
  local real_dart sdk shim
  real_dart="$(command -v dart)" || { echo "dart not found on PATH" >&2; return 1; }
  sdk="$(cd "$(dirname "$real_dart")/.." && pwd)"
  shim="$(mktemp -d "${TMPDIR:-/tmp}/dart-shim.XXXXXX")"
  mkdir -p "$shim/bin"
  cp "$sdk/version" "$shim/version"
  cat > "$shim/bin/dart" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = run ] && [ "\${2:-}" = build_runner ]; then
  exec "$real_dart" "\$@" --enable-experiment=primary-constructors
fi
exec "$real_dart" "\$@"
SHIM
  chmod +x "$shim/bin/dart"
  export PATH="$shim/bin:$PATH"
  export DART_SHIM_DIR="$shim"
}
