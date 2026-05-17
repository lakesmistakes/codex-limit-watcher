@echo off
setlocal
cd /d "%~dp0"

echo Starting Codex Limit Watcher...
echo Leave this window open while you want the watcher running.
echo Press Ctrl+C in this window to stop it.
echo.

where npm >nul 2>nul
if errorlevel 1 (
  echo npm was not found. Install Node.js, then double-click Setup.bat.
  echo.
  pause
  exit /b 1
)

call npm start
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Codex Limit Watcher stopped.
if not "%EXIT_CODE%"=="0" (
  echo It ended with an error code: %EXIT_CODE%
)
echo.
pause
exit /b %EXIT_CODE%
