#!/bin/bash
set -e
cd "$(dirname "$0")"

# Unix counterpart to run-game.bat - keep the two in step.
# Set VICE to the x64sc binary, or VICE_BIN to its directory, if not on PATH.

if [ -z "$VICE" ] && [ -n "$VICE_BIN" ] && [ -x "$VICE_BIN/x64sc" ]; then
  VICE="$VICE_BIN/x64sc"
fi
if [ -z "$VICE" ]; then
  VICE=$(command -v x64sc || true)
fi
if [ -z "$VICE" ] || [ ! -x "$VICE" ]; then
  echo "VICE x64sc not found. Install VICE or set VICE / VICE_BIN"
  exit 1
fi

DISK=wolf64.d64
DRIVEOPTS="-trapdevice8 +drive8truedrive"
case "${1,,}" in
  krill|--krill)
    DISK=wolf64-krill.d64
    DRIVEOPTS="+trapdevice8 -drive8truedrive"
    ;;
esac
if [ ! -f "$DISK" ]; then
  echo "$DISK missing - run build.sh first"
  exit 1
fi

"$VICE" -silent -autostartprgmode 0 $DRIVEOPTS -8 "$DISK" -autostart "$DISK" &
