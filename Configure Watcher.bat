@echo off
setlocal
cd /d "%~dp0"

echo Opening the Codex Limit Watcher configuration menu...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\configure.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo The configuration menu stopped with an error. Read the message above, then try again.
) else (
  echo The configuration menu is finished.
)
echo.
pause
exit /b %EXIT_CODE%
