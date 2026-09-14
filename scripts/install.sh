#!/usr/bin/env bash
# Install UE4SS + ColorblindMapMarkers into a local "RV There Yet?" install.
#
# Usage: scripts/install.sh [--ue4ss-zip PATH] [--no-ue4ss]
#
# RV_GAME_DIR overrides the game location (the dir containing Ride.exe).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="${RV_GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/Ride}"
WIN64="$GAME_DIR/Ride/Binaries/Win64"
UE4SS_ZIP=""
INSTALL_UE4SS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ue4ss-zip) UE4SS_ZIP="$2"; shift 2 ;;
    --no-ue4ss)  INSTALL_UE4SS=0; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$WIN64" ]] || { echo "not a game install: $WIN64 missing" >&2; exit 1; }

if [[ "$INSTALL_UE4SS" == 1 ]]; then
  if [[ -z "$UE4SS_ZIP" ]]; then
    UE4SS_ZIP="$(ls -1 "$REPO"/work/ue4ss/UE4SS_v*.zip "$REPO"/work/ue4ss/UE4SS.zip 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$UE4SS_ZIP" && -f "$UE4SS_ZIP" ]] || {
    echo "no UE4SS zip found; pass --ue4ss-zip PATH" >&2; exit 1; }
  echo "installing UE4SS from $(basename "$UE4SS_ZIP")"
  unzip -o -q "$UE4SS_ZIP" -d "$WIN64"
fi

MODS="$WIN64/ue4ss/Mods"
[[ -d "$MODS" ]] || { echo "UE4SS Mods dir missing: $MODS" >&2; exit 1; }

echo "installing ColorblindMapMarkers -> $MODS"
rm -rf "$MODS/ColorblindMapMarkers"
cp -r "$REPO/mod/ColorblindMapMarkers" "$MODS/"

echo
echo "done. Steam launch options for Proton:"
echo '    WINEDLLOVERRIDES="dwmapi=n,b" %command%'
