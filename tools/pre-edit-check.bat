@echo off
REM 修改 .h 头文件前的强制预检工具（impact-analyze + 自动备份）
REM 用法:
REM   pre-edit-check audio_self_test.h
REM   pre-edit-check app_config.h APP_AUDIO_
REM   pre-edit-check es8311_driver.h -SkipConfirm
setlocal
set "SCRIPT=%~dp0pre-edit-check.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if %EXIT_CODE%==1 (
	echo.
	echo [提示] 存在高影响文件（调用 >=5 次），请务必同步修改 ^!
) else if %EXIT_CODE%==2 (
	echo [已取消]
)
exit /b %EXIT_CODE%
