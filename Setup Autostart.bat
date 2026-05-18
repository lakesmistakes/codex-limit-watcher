@echo off
setlocal
cd /d "%~dp0"

echo Setting up Codex Limit Watcher autostart...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-startup.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo Autostart setup stopped with an error. Read the message above, then try again.
) else (
  echo Autostart setup finished.
)
echo.
pause
exit /b %EXIT_CODE%
