@echo off
setlocal
cd /d "%~dp0"
call build.bat
if errorlevel 1 exit /b 1

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"
if defined VICE if exist "%VICE%" goto launch
if defined VICE_BIN if exist "%VICE_BIN%\x64sc.exe" (
  set VICE=%VICE_BIN%\x64sc.exe
  goto launch
)
echo VICE not found — wolf64.d64 is built; run it manually. run-game.bat krill for the Krill disk.
exit /b 0

:launch
if not exist "%~dp0wolf64.d64" (
  echo wolf64.d64 missing after build
  exit /b 1
)
start "" "%VICE%" -silent -autostartprgmode 0 -trapdevice8 +drive8truedrive -8 "%~dp0wolf64.d64" -autostart "%~dp0wolf64.d64"
