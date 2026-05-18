@echo off
setlocal
cd /d "%~dp0"

echo Removing Codex Limit Watcher autostart...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\remove-startup.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo Autostart removal stopped with an error. Read the message above, then try again.
) else (
  echo Autostart removal finished.
)
echo.
pause
exit /b %EXIT_CODE%
