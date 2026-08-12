@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

if defined ACME if exist "%ACME%" goto run
where acme >nul 2>&1 && set ACME=acme && goto run
echo ACME not found. Set ACME in setup-env.bat ^(see c:\dev\Squaredoom\SETUP.md^)
exit /b 1

:run
python tools\gensounds.py
if errorlevel 1 exit /b 1
python tools\gentables.py
if errorlevel 1 exit /b 1
python tools\gen_sqtab.py
if errorlevel 1 exit /b 1
python tools\gen_bss.py
if errorlevel 1 exit /b 1
python tools\gen_painters.py
if errorlevel 1 exit /b 1
python tools\pack_enemies.py
if errorlevel 1 exit /b 1
python tools\gen_weapon_sprites.py
if errorlevel 1 exit /b 1
python tools\gen_enemy_painters.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -v3 --vicelabels ..\painters.lbl painters_bin.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

python tools\make_painter_tables.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -v3 --vicelabels ..\wolf64.lbl wolf64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" -v3 boot.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\game_image.prg move /y src\game_image.prg game_image.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul
if exist src\painters.bin move /y src\painters.bin painters.bin >nul

python tools\mkdisk.py --all-maps
if errorlevel 1 exit /b 1

echo Built wolf64.d64
dir wolf64.d64
dir boot.prg game_image.prg 2>nul
