@echo off
setlocal EnableExtensions
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_platforms.ps1" %*
exit /b %ERRORLEVEL%
