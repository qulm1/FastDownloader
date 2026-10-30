@echo off
cd /d "%~dp0"
if not exist "%~dp0bin\FastDownloader.exe" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildWindow.ps1"
  if errorlevel 1 (
    pause
    exit /b 1
  )
)
start "" "%~dp0bin\FastDownloader.exe"
