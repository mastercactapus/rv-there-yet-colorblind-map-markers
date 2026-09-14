#!/usr/bin/env bash
# Build the Nexus-ready archive.
#
# Produces dist/ColorblindMapMarkers-<version>.zip laid out so that it can be
# extracted straight into Ride/Binaries/Win64/ (and so Vortex/the RV There Yet
# extension sees a normal UE4SS Lua mod).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$REPO/VERSION")"
OUT="$REPO/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$OUT" "$STAGE/ue4ss/Mods"
cp -r "$REPO/mod/ColorblindMapMarkers" "$STAGE/ue4ss/Mods/"
cp "$REPO/README.md" "$STAGE/ue4ss/Mods/ColorblindMapMarkers/README.md"
cp "$REPO/LICENSE" "$STAGE/ue4ss/Mods/ColorblindMapMarkers/LICENSE"

ZIP="$OUT/ColorblindMapMarkers-$VERSION.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -r -q "$ZIP" ue4ss )

echo "built $ZIP"
unzip -l "$ZIP"
