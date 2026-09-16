@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0preflight.ps1" %*
