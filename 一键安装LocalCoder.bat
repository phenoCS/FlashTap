﻿@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
title LocalCoder - One-Click Install

echo =============================================
echo   LocalCoder - AI Programming Assistant
echo   One-Click Install
echo =============================================
echo.
echo [INFO] This installation takes 10-20 minutes
echo [INFO] Fully automatic, please do not close this window
echo.

rem Check administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Requesting administrator privileges...
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo [INFO] Administrator check passed
echo [INFO] Launching main installer...
echo.

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-LocalCoder.ps1"

echo.
echo Installation finished. Press any key to exit...
pause >nul
exit /b