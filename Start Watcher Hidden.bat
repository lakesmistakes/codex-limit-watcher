@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-background.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Background start reported an issue. Read the message above.
  echo.
  pause
  exit /b %EXIT_CODE%
)

timeout /t 4 >nul
exit /b 0
