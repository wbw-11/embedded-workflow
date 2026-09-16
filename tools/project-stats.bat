@echo off
REM ==========================================
REM 嵌入式项目统计工具启动器
REM ==========================================
REM 用法:
REM   project-stats.bat [路径] [-Detail] [-Top N]
REM
REM 示例:
REM   project-stats.bat
REM   project-stats.bat D:\MyProject
REM   project-stats.bat -Detail
REM   project-stats.bat D:\MyProject -Detail -Top 10
REM ==========================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0project-stats.ps1" %*