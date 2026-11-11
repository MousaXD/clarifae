#!/usr/bin/env bash
# Package the module payload only. The companion APK has its own build.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(sed -n 's/^version=//p' module.prop)"
out="$PWD/dist/clarifae-$version.zip"

shopt -s nullglob
libs=(lib/*/libclarifae.so)
if (( ${#libs[@]} == 0 )); then
  echo "No per-ABI native effect found. Run ./build.sh first." >&2
  exit 1
fi

files=(module.prop META-INF customize.sh post-fs-data.sh service.sh uninstall.sh
       system.prop sepolicy.rule common webroot scripts/diagnose-hyperos.sh "${libs[@]}")
[[ ! -d models ]] || files+=(models)
mkdir -p dist
tmp="$(mktemp -d "$PWD/dist/package.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
zip -qr9 "$tmp/module.zip" "${files[@]}"
unzip -tq "$tmp/module.zip"
mv -f "$tmp/module.zip" "$out"
echo "Created: $out"
