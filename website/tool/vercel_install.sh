#!/usr/bin/env bash
# Vercel "install" step: the build image has no Dart, so fetch a pinned SDK
# into the project directory. Run from the website/ root.
set -euo pipefail

DART_VERSION="${DART_VERSION:-3.13.3}"
SDK_DIR=".dart-sdk"

if [ -x "$SDK_DIR/bin/dart" ] && "$SDK_DIR/bin/dart" --version 2>&1 | grep -q "$DART_VERSION"; then
  echo "Dart $DART_VERSION already present."
else
  rm -rf "$SDK_DIR"
  echo "Downloading Dart $DART_VERSION…"
  curl -fsSL -o dart-sdk.zip \
    "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/dartsdk-linux-x64-release.zip"
  unzip -q dart-sdk.zip
  mv dart-sdk "$SDK_DIR"
  rm dart-sdk.zip
fi

export PATH="$PWD/$SDK_DIR/bin:$PATH"
dart --version
dart pub global activate jaspr_cli 0.23.4
dart pub get
