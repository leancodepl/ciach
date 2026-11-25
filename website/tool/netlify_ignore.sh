#!/usr/bin/env bash
# AI-Provenance:
#   model: claude-opus-5-5
#   harness: Claude Code
#
# Netlify's ignore command (see netlify.toml): exit 0 skips the build, exit 1
# runs it. Builds only when the site or the package version that it shows
# changed, and builds whenever that can't be told, such as on the first build
# after the project was linked to this repository, or on a retry without
# cache.

if [ -z "${CACHED_COMMIT_REF:-}" ] ||
  [ "$CACHED_COMMIT_REF" = "$COMMIT_REF" ] ||
  ! git cat-file -e "$CACHED_COMMIT_REF^{commit}" 2>/dev/null; then
  exit 1
fi

if git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- . ../pubspec.yaml; then
  exit 0
fi
exit 1
