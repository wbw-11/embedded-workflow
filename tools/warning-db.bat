@echo off
chcp 65001 >nul 2>&1
setlocal

set "PS1=%~dp0warning-db.ps1"

if not exist "%PS1%" (
    echo 错误：找不到 warning-db.ps1
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

set EXITCODE=%ERRORLEVEL%

endlocal & exit /b %EXITCODE%