#!/usr/bin/env bash
# Release build (COU-112): Dart code obfuscated and debug symbols kept apart,
# so stack traces can be de-obfuscated with `flutter symbolize` but the shipped
# binary does not expose class or method names.
#
#   scripts/build_release.sh <staging|prod> [appbundle|apk|ipa]
#
# The env file (env/<flavor>.json) is not versioned; symbols land in
# build/symbols/<flavor>/<version> and must be archived with each release
# (never inside the app or the repository).
set -euo pipefail

flavor="${1:?usage: scripts/build_release.sh <staging|prod> [appbundle|apk|ipa]}"
target="${2:-appbundle}"
cd "$(dirname "$0")/.."

env_file="env/${flavor}.json"
[[ -f "$env_file" ]] || { echo "Missing $env_file (copy env/${flavor}.example.json)" >&2; exit 1; }

version="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
symbols="build/symbols/${flavor}/${version}"

flutter build "$target" --release \
  --flavor "$flavor" \
  --dart-define-from-file="$env_file" \
  --obfuscate \
  --split-debug-info="$symbols"

echo "Symbols: $symbols (archive them privately with this release)"
