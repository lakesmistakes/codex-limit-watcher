@echo off
setlocal
cd /d "%~dp0"

set "LOG_FILE=%~dp0logs\codex-limit-watcher.log"

if exist "%LOG_FILE%" (
  echo Opening Codex Limit Watcher log...
  start "" notepad.exe "%LOG_FILE%"
  exit /b 0
)

echo No log file exists yet.
echo A log will appear after you run Setup.bat, Test Notification.bat, or Start Watcher.bat.
echo.
pause
exit /b 0
