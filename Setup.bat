@echo off
setlocal
cd /d "%~dp0"

echo Starting Codex Limit Watcher setup...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo Setup stopped with an error. Read the message above, then try again.
) else (
  echo Setup finished.
)
echo.
pause
exit /b %EXIT_CODE%
