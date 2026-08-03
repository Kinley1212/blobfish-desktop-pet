#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPOSITORY=$(CDPATH= cd -- "$ROOT/.." && pwd)
APP="$ROOT/.build/水滴鱼原生版.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/debug/BlobfishNative" "$CONTENTS/MacOS/BlobfishNative"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
ditto "$REPOSITORY/src/packs" "$CONTENTS/Resources/packs"
chmod 755 "$CONTENTS/MacOS/BlobfishNative"
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
