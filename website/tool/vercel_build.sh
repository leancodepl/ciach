#!/usr/bin/env bash
# Vercel "build" step: pre-render the site into build/jaspr. Run from the
# website/ root, after tool/vercel_install.sh.
set -euo pipefail

export PATH="$PWD/.dart-sdk/bin:$HOME/.pub-cache/bin:$PATH"

# Production always advertises the real domain; previews get their own URL so
# links and the <base href> work, but stay out of search results.
if [ "${VERCEL_ENV:-production}" = "production" ]; then
  SITE_URL="${SITE_URL:-https://ciach.leancode.co}"
else
  SITE_URL="https://${VERCEL_URL:-localhost:8080}"
fi
echo "Building for $SITE_URL"

jaspr build --sitemap-domain "$SITE_URL" --dart-define=SITE_URL="$SITE_URL"

# Ship only the rendered page and its assets, not build_runner's intermediate
# package sources.
rm -rf build/jaspr/packages build/jaspr/.dart_tool build/jaspr/.build.manifest

if [ "${VERCEL_ENV:-production}" != "production" ]; then
  printf 'User-agent: *\nDisallow: /\n' > build/jaspr/robots.txt
fi

ls -la build/jaspr
