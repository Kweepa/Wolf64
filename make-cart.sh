#!/bin/bash
set -e
cd "$(dirname "$0")"

# Unix counterpart to make-cart.bat - keep the two in step.

if [ ! -f wolf64.d64 ]; then
  echo "wolf64.d64 not found - run build.sh first."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python is not installed or not in PATH."
  exit 1
fi

if [ ! -f 3rdparty/disk2easyflash.py ]; then
  echo "3rdparty/disk2easyflash.py not found."
  echo "Download v1.1 from https://github.com/milasoft64/Disk2Easyflash-v1"
  echo "  (v1.1/disk2easyflash_v1.1.py) and save it as 3rdparty/disk2easyflash.py"
  exit 1
fi

python3 3rdparty/disk2easyflash.py --crt wolf64.d64 wolf64.crt

echo "Built wolf64.crt"
ls -l wolf64.crt
