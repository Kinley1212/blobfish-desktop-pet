#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPOSITORY=$(CDPATH= cd -- "$ROOT/.." && pwd)
TARGET_ARCH=${ARCH:-$(uname -m)}
case "$TARGET_ARCH" in
  arm64|x86_64) ;;
  *) printf 'Unsupported architecture: %s\n' "$TARGET_ARCH" >&2; exit 1 ;;
esac
APP=${BLOBFISH_PACKAGE_OUTPUT:-"$ROOT/.build/水滴鱼.app"}
if [ -n "${BLOBFISH_PACKAGE_OUTPUT:-}" ]; then
  case "$APP" in "$ROOT"/.build/*) ;; *) printf '%s\n' 'Custom package output must stay inside native-appkit/.build' >&2; exit 1 ;; esac
  if [ -e "$APP" ]; then printf '%s\n' 'Custom package output already exists; refusing to overwrite it.' >&2; exit 1; fi
fi
CONTENTS="$APP/Contents"
EXECUTABLE="$ROOT/.build/$TARGET_ARCH-apple-macosx/release/BlobfishNative"

if [ -z "${BLOBFISH_PACKAGE_OUTPUT:-}" ]; then rm -rf "$APP"; fi
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$EXECUTABLE" "$CONTENTS/MacOS/BlobfishNative"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
ditto "$REPOSITORY/src/packs" "$CONTENTS/Resources/packs"
ditto "$REPOSITORY/integrations" "$CONTENTS/Resources/integrations"
mkdir -p "$CONTENTS/Resources/native"
swiftc -parse-as-library -target "$TARGET_ARCH-apple-macosx13.0" \
  "$REPOSITORY/native/AgentEventSender.swift" \
  -o "$CONTENTS/Resources/native/blobfish-agent-event-sender"
chmod 700 "$CONTENTS/Resources/native/blobfish-agent-event-sender"
swiftc -O -parse-as-library -target "$TARGET_ARCH-apple-macosx13.0" \
  "$ROOT/Sources/BlobfishNative/CodexObservation.swift" \
  "$REPOSITORY/native/CodexObserver.swift" \
  -o "$CONTENTS/Resources/native/blobfish-codex-observer"
cp "$REPOSITORY/native/LaunchCodexWithBlobfish.command" "$CONTENTS/Resources/native/LaunchCodexWithBlobfish.command"
chmod 700 "$CONTENTS/Resources/native/blobfish-codex-observer" "$CONTENTS/Resources/native/LaunchCodexWithBlobfish.command"
chmod 755 "$CONTENTS/MacOS/BlobfishNative"
SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--}
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$CONTENTS/Resources/native/blobfish-agent-event-sender"
  codesign --force --sign - "$CONTENTS/Resources/native/blobfish-codex-observer"
  codesign --force --sign - "$APP"
  printf '%s\n' 'Packaged with an ad-hoc signature; no Developer ID or notarization.' >&2
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$CONTENTS/Resources/native/blobfish-agent-event-sender"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$CONTENTS/Resources/native/blobfish-codex-observer"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
printf '%s\n' "$APP"
