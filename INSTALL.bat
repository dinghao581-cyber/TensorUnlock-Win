@echo off
setlocal
title GPU-UNLOCK v3.1.1 - installer
echo.
echo  GPU-UNLOCK v3.1.1  ---  install (all-in-one) (Windows 10/11 x64, GA102)
echo  Read "how-to-install.txt" first. This window runs the checker
echo  and, if every check passes, registers the 3 scheduled tasks.
echo.
if not exist "%~dp0installer\install.ps1" (
  echo [ERROR] installer\install.ps1 not found next to this file.
  echo         Keep the folder structure intact and run it from the package folder.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\install.ps1"
set RC=%ERRORLEVEL%
echo.
echo  exit code: %RC%
echo.
pause
endlocal
