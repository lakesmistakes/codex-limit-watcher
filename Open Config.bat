@echo off
setlocal
cd /d "%~dp0"

set "CONFIG_FILE=%~dp0config.json"
set "EXAMPLE_FILE=%~dp0config.example.json"

if exist "%CONFIG_FILE%" (
  echo Opening config.json...
  start "" notepad.exe "%CONFIG_FILE%"
  exit /b 0
)

if exist "%EXAMPLE_FILE%" (
  echo config.json does not exist yet.
  echo Opening config.example.json so you can see the default settings.
  echo Double-click Setup.bat to create config.json automatically.
  start "" notepad.exe "%EXAMPLE_FILE%"
  exit /b 0
)

echo Could not find config.json or config.example.json in this folder.
echo Make sure this file is still inside the Codex Limit Watcher folder.
echo.
pause
exit /b 1
