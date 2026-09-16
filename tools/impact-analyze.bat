@echo off
REM ============================================
REM  impact-analyze.bat
REM  变更影响分析工具启动器
REM  调用同目录下的 impact-analyze.ps1
REM ============================================

setlocal

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%impact-analyze.ps1"

REM 检查 PowerShell 脚本是否存在
if not exist "%PS1_PATH%" (
    echo [错误] 未找到 PowerShell 脚本: %PS1_PATH%
    pause
    exit /b 1
)

REM 透传所有参数给 PowerShell 脚本
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" %*

REM 退出码继承自 PowerShell
exit /b %ERRORLEVEL%
