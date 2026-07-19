@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
title FlashTap - Uninstall

echo =============================================
echo   FlashTap - Uninstall / Cleanup
echo =============================================
echo.
echo [WARNING] This will remove ALL FlashTap components:
echo           - Ollama + Models
echo           - VS Code (user-level only, system-level preserved)
echo           - Continue extension + config
echo           - Environment variables
echo           - Download cache
echo.
echo [INFO] System-level VS Code and Ollama will NOT be removed.
echo [INFO] User's other VS Code extensions will NOT be removed.
echo.
echo Press any key to continue, or close this window to cancel...
pause >nul

echo.
echo =============================================
echo   Step 1: Stop Ollama processes
echo =============================================
taskkill /f /im ollama.exe 2>nul
taskkill /f /im "ollama app.exe" 2>nul
sc stop ollama 2>nul
echo   Done.
echo.

echo =============================================
echo   Step 2: Remove Ollama
echo =============================================
rem Check user-level Ollama
set "OLLAMA_USER=%LOCALAPPDATA%\Programs\Ollama"
if exist "%OLLAMA_USER%" (
    echo   Removing user-level Ollama: %OLLAMA_USER%
    rmdir /s /q "%OLLAMA_USER%" 2>nul
) else (
    echo   No user-level Ollama found.
)

rem Check system-level Ollama (ask before removing)
set "OLLAMA_SYS=%ProgramFiles%\Ollama"
if exist "%OLLAMA_SYS%" (
    echo.
    echo   [WARNING] System-level Ollama found: %OLLAMA_SYS%
    set /p "REMOVE_SYS=  Remove system-level Ollama? (y/N): "
    if /i "!REMOVE_SYS!"=="y" (
        rmdir /s /q "%OLLAMA_SYS%" 2>nul
        echo   System-level Ollama removed.
    ) else (
        echo   Skipped system-level Ollama.
    )
)
echo.

echo =============================================
echo   Step 3: Remove Ollama models + data
echo =============================================
rem Remove user .ollama directory
if exist "%USERPROFILE%\.ollama" (
    echo   Removing: %USERPROFILE%\.ollama
    rmdir /s /q "%USERPROFILE%\.ollama" 2>nul
)

rem Remove D:\ollama_models (if exists)
if exist "D:\ollama_models" (
    echo   Removing: D:\ollama_models
    rmdir /s /q "D:\ollama_models" 2>nul
)

rem Remove D:\ollama_data (if exists)
if exist "D:\ollama_data" (
    echo   Removing: D:\ollama_data
    rmdir /s /q "D:\ollama_data" 2>nul
)
echo   Done.
echo.

echo =============================================
echo   Step 4: Remove VS Code (user-level only)
echo =============================================
set "VSCODE_USER=%LOCALAPPDATA%\Programs\Microsoft VS Code"
if exist "%VSCODE_USER%" (
    echo   Removing user-level VS Code: %VSCODE_USER%
    rmdir /s /q "%VSCODE_USER%" 2>nul
) else (
    echo   No user-level VS Code found.
)

rem Do NOT remove system-level VS Code (D:\Microsoft VS Code etc.)
echo   System-level VS Code preserved (if any).
echo.

echo =============================================
echo   Step 5: Remove VS Code user data + extensions
echo =============================================
rem Ask before removing user config (may contain user's other settings)
if exist "%APPDATA%\Code" (
    echo   Found VS Code user data: %APPDATA%\Code
    set /p "REMOVE_VSC_DATA=  Remove VS Code user data (settings, extensions)? (y/N): "
    if /i "!REMOVE_VSC_DATA!"=="y" (
        rmdir /s /q "%APPDATA%\Code" 2>nul
        rmdir /s /q "%USERPROFILE%\.vscode" 2>nul
        rmdir /s /q "%USERPROFILE%\.vscode-shared" 2>nul
        echo   VS Code user data removed.
    ) else (
        echo   Skipped VS Code user data.
    )
) else (
    echo   No VS Code user data found.
}
echo.

echo =============================================
echo   Step 6: Remove Continue config
echo =============================================
if exist "%USERPROFILE%\.continue" (
    echo   Removing: %USERPROFILE%\.continue
    rmdir /s /q "%USERPROFILE%\.continue" 2>nul
) else (
    echo   No Continue config found.
}
echo   Done.
echo.

echo =============================================
echo   Step 7: Remove environment variables
echo =============================================
setx OLLAMA_HOST "" 2>nul
setx OLLAMA_ORIGINS "" 2>nul
setx OLLAMA_MAX_VRAM "" 2>nul
setx OLLAMA_NUM_PARALLEL "" 2>nul
setx OLLAMA_MODELS "" 2>nul
setx OLLAMA_HOME "" 2>nul

rem Also remove from registry (user level)
reg delete "HKCU\Environment" /v OLLAMA_HOST /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_ORIGINS /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_MAX_VRAM /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_NUM_PARALLEL /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_MODELS /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_HOME /f 2>nul
echo   Done.
echo.

echo =============================================
echo   Step 8: Remove FlashTap temp files
echo =============================================
if exist "%~dp0.flashtap-env.txt" del /q "%~dp0.flashtap-env.txt" 2>nul
if exist "%~dp0flashtap-user.txt" del /q "%~dp0flashtap-user.txt" 2>nul
if exist "%~dp0.ollama_latest_version" del /q "%~dp0.ollama_latest_version" 2>nul
if exist "%~dp0install.log" del /q "%~dp0install.log" 2>nul
if exist "%~dp0vscode-install.log" del /q "%~dp0vscode-install.log" 2>nul
if exist "%~dp0download.log" del /q "%~dp0download.log" 2>nul
if exist "%~dp0configure.log" del /q "%~dp0configure.log" 2>nul
if exist "%~dp0cpp-env.log" del /q "%~dp0cpp-env.log" 2>nul
if exist "%~dp0OldLogs" rmdir /s /q "%~dp0OldLogs" 2>nul
echo   Done.
echo.

echo =============================================
echo   Step 9: Remove Ollama Windows service (if exists)
echo =============================================
sc query ollama 2>nul | findstr /i "SERVICE_NAME" >nul
if %errorlevel% equ 0 (
    echo   Removing Ollama Windows service...
    sc stop ollama 2>nul
    sc delete ollama 2>nul
    echo   Done.
) else (
    echo   No Ollama Windows service found.
)
echo.

echo =============================================
echo   Cleanup Complete!
echo =============================================
echo.
echo   FlashTap has been fully removed from this account.
echo   System-level software (if any) was preserved.
echo.
echo   To reinstall, run: 一键安装FlashTap.bat
echo.
pause
exit /b
