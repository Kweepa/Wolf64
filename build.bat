@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

if defined ACME if exist "%ACME%" goto run
where acme >nul 2>&1 && set ACME=acme && goto run
echo ACME not found. Set ACME in setup-env.bat ^(see c:\dev\Squaredoom\SETUP.md^)
exit /b 1

:run
python tools\gentables.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -v3 --vicelabels ..\wolf64.lbl wolf64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\wolf64.prg move /y src\wolf64.prg wolf64.prg >nul
echo Built wolf64.prg
dir wolf64.prg
