@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_SCRIPT=%SCRIPT_DIR%tools\install_and_build_fa2.ps1"

if not exist "%INSTALL_SCRIPT%" (
    echo Install script not found:
    echo %INSTALL_SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Install/build script exited with code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
