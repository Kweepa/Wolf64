@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"
python editor\bundle_editor.py
if errorlevel 1 (
  echo Failed to bundle editor — opening existing index.html anyway.
)
start "" "%~dp0editor\index.html"
