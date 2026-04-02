@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "LAUNCH_SCRIPT=%SCRIPT_DIR%tools\start_qwen3_tts_fa2_background.ps1"

if not exist "%LAUNCH_SCRIPT%" (
    echo Background launch script not found:
    echo %LAUNCH_SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Start script exited with code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
