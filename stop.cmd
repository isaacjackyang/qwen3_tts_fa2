@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "STOP_SCRIPT=%SCRIPT_DIR%tools\stop_qwen3_tts_fa2.ps1"

if not exist "%STOP_SCRIPT%" (
    echo Stop script not found:
    echo %STOP_SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%STOP_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Stop script exited with code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
