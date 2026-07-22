# FlashTap: C++ 编译环境自动配置 (MinGW-w64)
# Bug #20/#21/#23 修复版：90秒超时 + 绝对路径 + type:process
# 非强制模块：任何失败仅输出提示，绝不中断主安装流程

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$PROJECT_DIR = $PSScriptRoot
if ((-not $PROJECT_DIR) -or ($PROJECT_DIR -eq '')) {
    $PROJECT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ((-not $PROJECT_DIR) -or ($PROJECT_DIR -eq '')) {
    $PROJECT_DIR = (Get-Location).Path
}
$LOG_FILE = [System.IO.Path]::Combine($PROJECT_DIR, 'cpp-env.log')

function Write-Log {
    param([string]$Msg, [string]$Clr)
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Msg"
    if ($Clr) { Write-Host $line -ForegroundColor $Clr } else { Write-Host $line }
    try { Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
}

function Main {
    Write-Log '=== MinGW-w64 C++ 编译环境配置 ===' 'Cyan'

    $mingwDir = 'C:\FlashTap\mingw64'
    $mingwBin = Join-Path $mingwDir 'bin'
    $gppExe = Join-Path $mingwBin 'g++.exe'
    $gdbExe = Join-Path $mingwBin 'gdb.exe'
    $workspaceDir = 'C:\FlashTap\cpp-workspace'
    $vscodeDir = Join-Path $workspaceDir '.vscode'

    # 1. 部署 MinGW-w64
    Write-Log '[1/5] 检查 MinGW-w64 编译环境...' 'Cyan'
    if (-not (Test-Path -LiteralPath $gppExe)) {
        $mingwZip = Join-Path $PROJECT_DIR 'mingw64.zip'
        if (Test-Path -LiteralPath $mingwZip) {
            Write-Log '  发现 mingw64.zip，解压中...（约 1-2 分钟）' 'Cyan'
            try {
                New-Item -ItemType Directory -Path $mingwDir -Force | Out-Null
                Expand-Archive -Path $mingwZip -DestinationPath 'C:\FlashTap\' -Force
                Write-Log '  MinGW-w64 解压完成' 'Green'
            } catch {
                Write-Log "  解压失败: $($_.Exception.Message)，将尝试联网下载" 'Yellow'
            }
        }
        if (-not (Test-Path -LiteralPath $gppExe)) {
            Write-Log '  未找到 mingw64.zip，将尝试联网下载 MinGW-w64...' 'Yellow'
            $mingwUrl = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/14.2.0posix-18.1.8-12.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-14.2.0-mingw-w64ucrt-12.0.0-r1.zip'
            $mingwZip = Join-Path $env:TEMP 'mingw64.zip'
            try {
                Write-Log "  下载: $mingwUrl" 'Cyan'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                (New-Object System.Net.WebClient).DownloadFile($mingwUrl, $mingwZip)
                Write-Log '  下载完成，解压中...' 'Cyan'
                New-Item -ItemType Directory -Path $mingwDir -Force | Out-Null
                Expand-Archive -Path $mingwZip -DestinationPath 'C:\FlashTap\' -Force
                Remove-Item $mingwZip -Force -ErrorAction SilentlyContinue
                Write-Log '  MinGW-w64 安装完成' 'Green'
            } catch {
                Write-Log "  联网下载失败: $($_.Exception.Message)" 'Yellow'
            }
        }
    }

    if (Test-Path -LiteralPath $gppExe) {
        $ver = & $gppExe --version 2>&1 | Select-Object -First 1
        Write-Log "  g++ 版本: $ver" 'Green'
    } else {
        Write-Log '  MinGW-w64 未安装成功，C++ 编译环境不可用' 'Yellow'
        Write-Log '  提示：可手动放置 mingw64.zip 到脚本目录后重试' 'Yellow'
    }

    # 2. 创建 C++ 工作区
    Write-Log '[2/5] 创建 C++ 工作区...' 'Cyan'
    try {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
        $mainCpp = Join-Path $workspaceDir 'main.cpp'
        if (-not (Test-Path -LiteralPath $mainCpp)) {
            Set-Content -Path $mainCpp -Value @'
#include <iostream>
int main() {
    std::cout << "Hello, FlashTap!" << std::endl;
    return 0;
}
'@ -Encoding UTF8
        }
        Write-Log "  工作区: $workspaceDir" 'Green'
    } catch {
        Write-Log "  工作区创建失败: $($_.Exception.Message)" 'Yellow'
    }

    # 3. 写入 VS Code 配置文件（tasks.json + launch.json）
    Write-Log '[3/5] 配置 VS Code tasks.json / launch.json...' 'Cyan'
    try {
        $tasksJson = @"
{
    "version": "2.0.0",
    "tasks": [
        {
            "type": "process",
            "label": "C/C++: g++ 生成活动文件",
            "command": "C:\\FlashTap\\mingw64\\bin\\g++.exe",
            "args": [
                "-g",
                "`${file}",
                "-o",
                "`${fileDirname}\\`${fileBasenameNoExtension}.exe",
                "-std=c++17"
            ],
            "options": {
                "cwd": "`${fileDirname}"
            },
            "problemMatcher": [
                "`$gcc"
            ],
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "detail": "compiler: C:\\FlashTap\\mingw64\\bin\\g++.exe"
        }
    ]
}
"@
        Set-Content -Path (Join-Path $vscodeDir 'tasks.json') -Value $tasksJson -Encoding UTF8

        $launchJson = @"
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "(gdb) 启动",
            "type": "cppdbg",
            "request": "launch",
            "program": "`${fileDirname}\\`${fileBasenameNoExtension}.exe",
            "args": [],
            "stopAtEntry": false,
            "cwd": "`${fileDirname}",
            "environment": [],
            "externalConsole": true,
            "MIMode": "gdb",
            "miDebuggerPath": "C:\\FlashTap\\mingw64\\bin\\gdb.exe",
            "setupCommands": [
                {
                    "description": "为 gdb 启用整齐打印",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ],
            "preLaunchTask": "C/C++: g++ 生成活动文件"
        }
    ]
}
"@
        Set-Content -Path (Join-Path $vscodeDir 'launch.json') -Value $launchJson -Encoding UTF8
        Write-Log '  tasks.json / launch.json 已配置（MinGW-w64 绝对路径 + type:process）' 'Green'
    } catch {
        Write-Log "  VS Code 配置文件写入失败: $($_.Exception.Message)" 'Yellow'
    }

    # 4. 安装 C/C++ 扩展（90 秒超时，Bug #20）
    Write-Log '[4/5] 安装 VS Code C/C++ 扩展 (ms-vscode.cpptools)...' 'Cyan'
    $codeExe = $null
    $codeCandidates = @(
        Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
        Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'
        Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe'
    )
    foreach ($c in $codeCandidates) {
        if (Test-Path -LiteralPath $c) { $codeExe = $c; break }
    }

    if ($codeExe) {
        try {
            $codeCmd = Join-Path (Split-Path -Parent $codeExe) 'bin\code.cmd'
            if (-not (Test-Path -LiteralPath $codeCmd)) { $codeCmd = Join-Path (Split-Path -Parent $codeExe) 'code.cmd' }
            $installer = if (Test-Path -LiteralPath $codeCmd) { $codeCmd } else { $codeExe }

            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $installer
            $pinfo.Arguments = '--install-extension ms-vscode.cpptools --force'
            $pinfo.UseShellExecute = $false
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.CreateNoWindow = $true
            $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $pinfo.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

            $process = [System.Diagnostics.Process]::Start($pinfo)
            Write-Log '  等待 code --install-extension（最多 90 秒）...' 'Cyan'
            if ($process.WaitForExit(90000)) {
                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()
                if ($process.ExitCode -eq 0) {
                    Write-Log '  C/C++ 扩展安装成功' 'Green'
                } else {
                    Write-Log "  C/C++ 扩展安装返回非零退出码: $($process.ExitCode)" 'Yellow'
                }
            } else {
                Write-Log '  扩展安装超时（90秒），跳过（可稍后手动安装）' 'Yellow'
                try { $process.Kill() } catch { }
            }
        } catch {
            Write-Log "  C/C++ 扩展安装异常（可稍后手动安装）: $($_.Exception.Message)" 'Yellow'
        }
    } else {
        Write-Log '  未找到 VS Code，跳过 C/C++ 扩展安装' 'Yellow'
    }

    # 5. 配置 PATH 环境变量
    Write-Log '[5/5] 配置系统 PATH（MinGW-w64 bin）...' 'Cyan'
    try {
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if ($currentPath -notlike "*$mingwBin*") {
            [Environment]::SetEnvironmentVariable('Path', "$currentPath;$mingwBin", 'Machine')
            $env:Path = "$env:Path;$mingwBin"
            Write-Log "  MinGW-w64 bin 已添加到系统 PATH: $mingwBin" 'Green'
        } else {
            Write-Log '  MinGW-w64 bin 已在系统 PATH 中' 'Green'
        }
    } catch {
        Write-Log "  PATH 配置失败: $($_.Exception.Message)" 'Yellow'
    }

    Write-Log '=== C++ 编译环境配置完成 ===' 'Cyan'
    return 0
}

try {
    $ErrorActionPreference = 'SilentlyContinue'
    exit (Main)
} catch {
    Write-Log "C++ 环境配置异常: $($_.Exception.Message)" 'Yellow'
    exit 0
}
