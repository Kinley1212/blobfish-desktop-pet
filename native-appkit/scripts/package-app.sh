#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPOSITORY=$(CDPATH= cd -- "$ROOT/.." && pwd)
APP="$ROOT/.build/水滴鱼原生版.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/BlobfishNative" "$CONTENTS/MacOS/BlobfishNative"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
ditto "$REPOSITORY/src/packs" "$CONTENTS/Resources/packs"
ditto "$REPOSITORY/integrations" "$CONTENTS/Resources/integrations"
mkdir -p "$CONTENTS/Resources/native"
swiftc -parse-as-library "$REPOSITORY/native/AgentEventSender.swift" -o "$CONTENTS/Resources/native/blobfish-agent-event-sender"
chmod 700 "$CONTENTS/Resources/native/blobfish-agent-event-sender"
chmod 755 "$CONTENTS/MacOS/BlobfishNative"
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
