@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"
title FlashTap - One-Click Install

REM ============================================================
REM 解锁从网络下载的文件的 Mark-of-the-Web 标记
REM GitHub Download ZIP 会给所有文件打上"来自Internet"标签，
REM 导致 .ps1/.bat 被 PowerShell/Windows 阻止执行
REM ============================================================
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem '%~dp0' -Recurse -File | Unblock-File 2>$null" >nul 2>&1

echo =============================================
echo   FlashTap - AI Programming Assistant
echo   One-Click Install
echo =============================================
echo.
echo [INFO] This installation takes 10-20 minutes
echo [INFO] Fully automatic, please do not close this window
echo [TIP] To copy log: select text, press Enter to copy
echo      After copying, press Enter again to resume
echo.

rem ============================================================
rem 统一入口：必须右键"以管理员方式运行"
rem 不再自动 UAC 提权（避免 VM 共享文件夹路径硬编码、跨用户上下文丢失）
rem ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 没有管理员权限！
    echo.
    echo [操作指引]
    echo   - 关闭此窗口
    echo   - 找到 一键安装FlashTap.bat
    echo   - 右键点击 → "以管理员方式运行"
    echo   - 在弹出的 UAC 窗口中点"是"
    echo.
    echo   （右键以管理员运行 = 当前用户 + 管理员权限，
    echo    不会丢失用户上下文，VS Code 扩展/配置会装到正确目录）
    echo.
    echo 此窗口将在 10 秒后自动关闭...
    timeout /t 10 >nul
    exit /b 1
)

echo [SUCCESS] 管理员权限已确认
echo [INFO] 当前用户: %USERNAME% (可直接安装软件/写注册表/配环境变量)
echo [INFO] 用户目录: %USERPROFILE%
echo.

echo [INFO] Launching main installer...
echo [INFO] 这是【主安装终端】，所有日志都会在这里滚动，请勿关闭。
echo.

rem 切换到脚本目录（管理员运行后工作目录可能是 System32，必须切回来）
cd /d "%~dp0"
echo [INFO] 脚本目录: %CD%
echo.

echo [INFO] Running network pre-flight check (a few seconds)...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0preflight-check.ps1"
echo.

rem 主安装脚本以当前用户身份+管理员权限运行，无需传递 OriginalUser 参数
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-FlashTap.ps1"
set INSTALL_RC=%errorlevel%

echo.
if %INSTALL_RC% neq 0 (
    echo =============================================
    echo   安装未完全成功（安装器退出码: %INSTALL_RC%）
    echo   请查看上方红色报错，或脚本目录下的 install.log
    echo   日志路径: %~dp0install.log
    echo =============================================
) else (
    echo =============================================
    echo   安装流程已结束（详见上方日志与脚本目录下的 install.log）
    echo   日志路径: %~dp0install.log
    echo =============================================
)
echo.
echo 按任意键关闭此窗口...
pause
exit /b %INSTALL_RC%
