#!/bin/sh
set -eu
REPOSITORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:?Supply an absolute output executable path}
case "$OUTPUT" in /*) ;; *) exit 2 ;; esac
TARGET_ARCH=${ARCH:-$(uname -m)}
mkdir -p "$(dirname -- "$OUTPUT")" "$REPOSITORY/native/build"
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -O -parse-as-library -sdk "$SDK" -target "$TARGET_ARCH-apple-macosx13.0" \
  -module-cache-path "$REPOSITORY/native/build/observer-module-cache" \
  "$REPOSITORY/native-appkit/Sources/BlobfishNative/CodexObservation.swift" \
  "$REPOSITORY/native/CodexObserver.swift" -o "$OUTPUT"
codesign --force --sign - "$OUTPUT"
