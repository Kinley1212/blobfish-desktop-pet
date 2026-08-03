#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/App/AppIcon.svg"
DESTINATION="$ROOT/App/AppIcon.icns"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/blobfish-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

/usr/bin/qlmanage -t -s 1024 -o "$WORK" "$SOURCE" >/dev/null 2>&1
MASTER="$WORK/AppIcon.svg.png"
test -f "$MASTER"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in \
  "16:icon_16x16.png" \
  "32:icon_16x16@2x.png" \
  "32:icon_32x32.png" \
  "64:icon_32x32@2x.png" \
  "128:icon_128x128.png" \
  "256:icon_128x128@2x.png" \
  "256:icon_256x256.png" \
  "512:icon_256x256@2x.png" \
  "512:icon_512x512.png" \
  "1024:icon_512x512@2x.png"
do
  size=${spec%%:*}
  name=${spec#*:}
  /usr/bin/sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

/usr/bin/iconutil -c icns "$ICONSET" -o "$DESTINATION"
printf '%s\n' "$DESTINATION"
