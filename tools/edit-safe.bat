@echo off
REM 安全文件编辑包装器 - 修改文件前自动创建时间戳备份
REM 用法:
REM   edit-safe main.c                  : 为单个文件创建备份
REM   edit-safe main.c app_config.h     : 批量备份多文件
REM   edit-safe -Restore main.c         : 从最新时间戳备份恢复
REM   edit-safe -List main.c            : 列出文件所有备份
setlocal
set "SCRIPT=%~dp0edit-safe.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
endlocal
