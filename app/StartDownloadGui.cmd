@echo off
setlocal
title 极速下载助手
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0FastDownloadGui.ps1"
endlocal
