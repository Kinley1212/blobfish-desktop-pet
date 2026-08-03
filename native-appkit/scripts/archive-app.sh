#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")
TARGET_ARCH=${ARCH:-$(uname -m)}
case "$TARGET_ARCH" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *) printf 'Unsupported architecture: %s\n' "$TARGET_ARCH" >&2; exit 1 ;;
esac
OUTPUT="$ROOT/.build/BlobfishNative-$VERSION-macOS-$ARCH.zip"
rm -f "$OUTPUT"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$ROOT/.build/水滴鱼.app" "$OUTPUT"
shasum -a 256 "$OUTPUT"
