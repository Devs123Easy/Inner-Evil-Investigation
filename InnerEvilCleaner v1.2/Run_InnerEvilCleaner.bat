@echo off
setlocal
title InnerEvil / Exastealer Cleaner

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo Choose remediation mode:
echo   1. Quarantine ^(recommended^)
echo   2. Permanently delete
echo   3. Cancel
choice /C 123 /N /M "Selection: "

if errorlevel 3 exit /b 0
if errorlevel 2 set "MODE=Delete"
if errorlevel 1 set "MODE=Quarantine"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0InnerEvilCleaner.ps1" -Mode "%MODE%"

echo.
pause
