@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
title FlashTap - One-Click Install

REM Unblock files from Mark-of-the-Web (GitHub ZIP / browser download)
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem '%~dp0' -Recurse -File | Unblock-File 2>$null" >nul 2>&1

echo =============================================
echo   FlashTap - AI Programming Assistant
echo   One-Click Install
echo =============================================
echo.
echo [INFO] This installation takes 15-20 minutes.
echo [INFO] Do NOT close this window.
echo.

REM Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] No administrator privileges!
    echo.
    echo [HOW TO FIX]
    echo   1. Close this window.
    echo   2. Right-click the BAT file.
    echo   3. Select "Run as Administrator".
    echo   4. Click "Yes" in the UAC dialog.
    echo.
    echo   (Right-click + Run as Admin = your user + admin rights.
    echo    This ensures VS Code extensions install to YOUR account.)
    echo.
    echo This window will close in 10 seconds...
    timeout /t 10 >nul
    exit /b 1
)

echo [SUCCESS] Administrator rights confirmed.
echo [INFO] Current user: %USERNAME%
echo [INFO] User profile: %USERPROFILE%
echo.

echo [INFO] Launching main installer...
echo.

cd /d "%~dp0"
echo [INFO] Script directory: %CD%
echo.

echo [INFO] Running network pre-flight check...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0preflight-check.ps1"
echo.

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-FlashTap.ps1"
set INSTALL_RC=%errorlevel%

echo.
if %INSTALL_RC% neq 0 (
    echo =============================================
    echo   Installation completed with errors (code: %INSTALL_RC%).
    echo   Check install.log in script directory for details.
    echo =============================================
) else (
    echo =============================================
    echo   Installation finished successfully.
    echo   Check install.log in script directory for details.
    echo =============================================
)
echo.
echo Press any key to close...
pause >nul
exit /b %INSTALL_RC%
