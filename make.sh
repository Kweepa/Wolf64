#!/bin/bash
set -e
cd "$(dirname "$0")"

# Unix counterpart to make.bat - keep the two in step.
# Builds both disks, then launches the KERNAL disk in VICE if x64sc is found.

./build.sh

if [ -z "$VICE" ] && [ -n "$VICE_BIN" ] && [ -x "$VICE_BIN/x64sc" ]; then
  VICE="$VICE_BIN/x64sc"
fi
if [ -z "$VICE" ]; then
  VICE=$(command -v x64sc || true)
fi
if [ -z "$VICE" ] || [ ! -x "$VICE" ]; then
  echo "VICE not found - wolf64.d64 is built; run it manually. run-game.sh krill for the Krill disk."
  exit 0
fi

if [ ! -f wolf64.d64 ]; then
  echo "wolf64.d64 missing after build"
  exit 1
fi
"$VICE" -silent -autostartprgmode 0 -trapdevice8 +drive8truedrive -8 wolf64.d64 -autostart wolf64.d64 &
