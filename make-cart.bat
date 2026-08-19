@echo off
setlocal
cd /d "%~dp0"

if not exist "wolf64.d64" (
  echo wolf64.d64 not found — run build.bat first.
  exit /b 1
)

python --version >nul 2>&1
if errorlevel 1 (
  echo Python is not installed or not in PATH.
  exit /b 1
)

if not exist "tools\disk2easyflash.py" (
  echo tools\disk2easyflash.py not found.
  echo Download v1.1 from https://github.com/milasoft64/Disk2Easyflash-v1
  echo   ^(v1.1/disk2easyflash_v1.1.py^) and save it as tools\disk2easyflash.py
  exit /b 1
)

python tools\disk2easyflash.py --crt wolf64.d64 wolf64.crt
if errorlevel 1 exit /b 1

echo Built wolf64.crt
dir wolf64.crt
