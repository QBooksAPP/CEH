@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found on PATH.
  echo Close this window, open a new Windows session, and try again.
  pause
  exit /b 1
)

echo Starting CEH Company Operations for Windows...
flutter run -d windows
if errorlevel 1 (
  echo.
  echo CEH Windows launch failed. Review the Flutter output above.
  pause
  exit /b 1
)
