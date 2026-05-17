@echo off
setlocal
cd /d "%~dp0"

echo Testing Codex Limit Watcher notifications...
echo This may play a sound, show a toast, and show the billboard.
echo.

where npm >nul 2>nul
if errorlevel 1 (
  echo npm was not found. Install Node.js, then double-click Setup.bat.
  echo.
  pause
  exit /b 1
)

call npm run diagnose:notifications
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo Notification test reported an issue. Read the message above.
) else (
  echo Notification test finished.
)
echo.
pause
exit /b %EXIT_CODE%
