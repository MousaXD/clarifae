#!/usr/bin/env bash
# Package one root module. The companion APK has its own build.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
version="$(sed -n 's/^version=//p' module.prop)"
mkdir -p dist
tmp="$(mktemp -d "$root/dist/package.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

case "${1:-native}" in
  native)
    out="$root/dist/clarifae-$version.zip"
    shopt -s nullglob
    libs=(lib/*/libclarifae.so)
    if (( ${#libs[@]} == 0 )); then
      echo "No per-ABI native effect found. Run ./build.sh first." >&2
      exit 1
    fi
    files=(module.prop META-INF customize.sh post-fs-data.sh service.sh uninstall.sh
           system.prop sepolicy.rule common webroot scripts/diagnose-hyperos.sh "${libs[@]}")
    [[ ! -d models ]] || files+=(models)
    zip -qr9 "$tmp/module.zip" "${files[@]}"
    ;;
  stock)
    out="$root/dist/clarifae-stock-$version.zip"
    stage="$tmp/stock"
    mkdir -p "$stage/common" "$stage/scripts"
    cp -r META-INF "$stage/"
    cp common/{functions.sh,patch-effects.awk} "$stage/common/"
    cp scripts/diagnose-hyperos.sh "$stage/scripts/"
    cp scripts/install-stock.sh "$stage/customize.sh"
    cp uninstall.sh "$stage/"
    sed -e 's/^name=.*/name=Clarifae Stock Mic/' \
        -e 's/^version=.*/&-stock/' \
        -e 's/^description=.*/description=Enable the built-in noise suppressor on microphone, camcorder and VoIP capture routes./' \
        module.prop > "$stage/module.prop"
    (cd "$stage" && zip -qr9 "$tmp/module.zip" .)
    ;;
  *)
    echo "Usage: $0 [native|stock]" >&2
    exit 2
    ;;
esac

unzip -tq "$tmp/module.zip"
mv -f "$tmp/module.zip" "$out"
echo "Created: $out"
