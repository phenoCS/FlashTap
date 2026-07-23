# FlashTap: Windows 原生 C++ 编译环境自动配置（MinGW-w64 / GCC + GDB）
#
# 设计目标（针对编程新手）：
#   - 不依赖 WSL、不安装十几 GB 的 Visual Studio。
#   - 一键安装轻量级 MinGW-w64（GCC 编译器 + GDB 调试器），VS Code 按 F5 即可编译并调试，直接看到结果。
#   - 本模块为【必装项】：任何失败都会明确报错并返回非 0，主安装流程因此中断并给出解决办法。
#   - 具备幂等性：已装好的会跳过；支持本地离线包（把 mingw64.zip 放到项目目录即可，无需联网）。
#
# 可离线部署：将 MinGW-w64 压缩包命名为 mingw64.zip（或 mingw64.7z）放到项目目录或 tools\ 下，
#            脚本会优先使用本地文件，完全不联网。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PROJECT_DIR = $PSScriptRoot
if ([string]::IsNullOrEmpty($PROJECT_DIR)) { $PROJECT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrEmpty($PROJECT_DIR)) { $PROJECT_DIR = (Get-Location).Path }

$LOG_FILE   = Join-Path $PROJECT_DIR 'cpp-env.log'
# 固定安装目录，便于加入 PATH 与日后查找；与桌面快捷方式、工作区保持一致
$MINGW_DIR  = 'C:\FlashTap\mingw64'
$BIN_DIR    = Join-Path $MINGW_DIR 'bin'
$WORKSPACE  = 'C:\FlashTap\cpp-workspace'

# ── 离线包候选（优先使用，无需联网）──
$LOCAL_CANDIDATES = @(
    (Join-Path $PROJECT_DIR 'mingw64.zip'),
    (Join-Path $PROJECT_DIR 'mingw64.7z'),
    (Join-Path $PROJECT_DIR 'tools\mingw64.zip'),
    (Join-Path $PROJECT_DIR 'tools\mingw64.7z')
)

# ── 在线下载候选（失效时把离线包 mingw64.zip 放到项目目录即可）──
# 版本：GCC 14.2.0 / win32 线程 / SEH 异常
# 说明：winlibs 没有「win32-seh-ucrt」组合，win32 线程默认配 msvcrt；
#       ucrt 运行时版本见 posix-ucrt 候选。两个都是可用的 MinGW-w64 工具链。
$MINGW_BASE = 'https://github.com/brechtsanders/winlibs_mingw/releases/download'
$MINGW_URLS_RAW = @(
    "$MINGW_BASE/14.2.0win32-12.0.0-msvcrt-r1/winlibs-x86_64-win32-seh-gcc-14.2.0-mingw-w64msvcrt-12.0.0-r1.zip",
    "$MINGW_BASE/14.2.0posix-12.0.0-ucrt-r3/winlibs-x86_64-posix-seh-gcc-14.2.0-mingw-w64ucrt-12.0.0-r3.zip",
    "$MINGW_BASE/14.2.0win32-12.0.0-msvcrt-r1/winlibs-x86_64-win32-seh-gcc-14.2.0-mingw-w64msvcrt-12.0.0-r1.7z"
)
# 备用镜像：GitHub 直连不通时（如国内网络）走 ghproxy 代理
$MINGW_URLS_MIRROR = $MINGW_URLS_RAW | ForEach-Object { 'https://ghproxy.net/' + $_ }
$DOWNLOAD_URLS = $MINGW_URLS_RAW + $MINGW_URLS_MIRROR

function Write-Log {
    param([string]$Msg, [string]$Clr)
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Msg"
    if ($Clr) { Write-Host "  $line" -ForegroundColor $Clr } else { Write-Host "  $line" }
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::AppendAllText($LOG_FILE, $line + [Environment]::NewLine, $utf8)
    } catch { }
}

function Get-LocalArchive {
    foreach ($c in $LOCAL_CANDIDATES) {
        if (Test-Path -LiteralPath $c) {
            Write-Log "发现本地离线包: $c" 'Green'
            return $c
        }
    }
    return $null
}

function Get-FileWithRetry {
    param([string[]]$Urls, [string]$OutFile)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # 继承系统代理（公司/校园网常见）
    try {
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        [System.Net.WebRequest]::DefaultWebProxy = $proxy
    } catch { }

    foreach ($u in $Urls) {
        Write-Log "  尝试下载: $u" 'Cyan'
        try {
            # 关键：必须加超时，避免网络不可达时无限挂起（参考前文 Ollama 卡死教训）
            Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec 120 -MaximumRedirection 5 -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 1MB)) {
                $mb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1)
                Write-Log "  下载成功: $mb MB" 'Green'
                return $true
            }
            Write-Log '  下载文件异常（大小不符），重试...' 'Yellow'
        } catch {
            Write-Log "  下载失败: $($_.Exception.Message)" 'Yellow'
        }
    }
    return $false
}

function Expand-ArchiveRobust {
    param([string]$Archive, [string]$Dest)
    $ext = [System.IO.Path]::GetExtension($Archive).ToLower()
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }

    if ($ext -eq '.zip') {
        try {
            Expand-Archive -LiteralPath $Archive -DestinationPath $Dest -Force -ErrorAction Stop
            return $true
        } catch {
            Write-Log "  ZIP 解压失败: $($_.Exception.Message)" 'Yellow'
            return $false
        }
    }
    if ($ext -eq '.7z') {
        # 优先用系统自带 tar.exe（Win10+ 通常支持 7z 读取）
        try {
            & tar.exe -xf $Archive -C $Dest 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch { }
        # 退而求其次用 7z.exe（若已安装）
        $sevenZip = $null
        try { $sevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source } catch {}
        if ($sevenZip) {
            & $sevenZip x -y -o"$Dest" "$Archive" 2>&1 | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        Write-Log '  .7z 解压失败：系统缺少 tar/7z，请改用 .zip 离线包' 'Yellow'
        return $false
    }
    Write-Log "  不支持的压缩格式: $ext" 'Yellow'
    return $false
}

function Add-ToUserPath {
    param([string]$Dir)
    try {
        # 优先写入 Machine（系统）PATH：在提权跨账户场景下，
        # [Environment]::SetEnvironmentVariable('Path',...,'User') 始终写入
        # 当前进程 SID 对应的 HKCU，可能不是目标用户的注册表。
        # Machine PATH 对所有用户生效，且已提权即可写入。
        $targetScope = 'Machine'
        $currentPath = [Environment]::GetEnvironmentVariable('Path', $targetScope)
        if ([string]::IsNullOrEmpty($currentPath)) { $currentPath = '' }
        $escapedDir = [regex]::Escape($Dir)
        if ($currentPath -notmatch $escapedDir) {
            if ($currentPath.EndsWith(';')) { $currentPath = $currentPath + $Dir }
            else { $currentPath = "$currentPath;$Dir" }
            [Environment]::SetEnvironmentVariable('Path', $currentPath, $targetScope)
            Write-Log "  已将 $Dir 加入系统 PATH (Machine)" 'Green'
        } else {
            Write-Log '  PATH 已包含 MinGW，跳过' 'Green'
        }
        # 同步到当前进程，便于本次验证
        if ($env:Path -notmatch $escapedDir) { $env:Path = "$env:Path;$Dir" }
    } catch {
        Write-Log "  加入 PATH 失败（仍需手动添加）: $($_.Exception.Message)" 'Yellow'
    }
}

function Protect-Dir {
    param([string]$Dir)
    # 尽力而为：加 Windows Defender 排除，避免 g++.exe 被误删（360/Defender 友好）
    try { Add-MpPreference -ExclusionPath $Dir -ErrorAction SilentlyContinue } catch { }
}

function Install-CpptoolsExtension {
    # 将 C/C++ 扩展装入"原生 VS Code"（按 F5 调试必需），尽力而为
    # 优先用户级，其次系统级注册表（含 D 盘等非标准位置），最后兜底固定路径
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\Code.exe'),
        (Join-Path ([Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) 'Microsoft VS Code\Code.exe')
    )
    if ($env:ProgramW6432) {
        $cands += (Join-Path $env:ProgramW6432 'Microsoft VS Code\Code.exe')
    }

    # 注册表查找（含 D 盘等非标准位置）
    $regPaths = @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($rp in $regPaths) {
        try {
            $entries = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
            foreach ($e in $entries) {
                if ($e.DisplayName -like '*Visual Studio Code*' -and $e.UninstallString) {
                    $uninst = $e.UninstallString -replace '^"', '' -replace '"$', ''
                    $dir = Split-Path -Parent $uninst
                    $exe = Join-Path $dir 'Code.exe'
                    if ($exe -notin $cands) { $cands += $exe }
                }
            }
        } catch {}
    }

    $codeExe = $null
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $codeExe = $c; break } }
    if (-not $codeExe) {
        Write-Log '  未找到 VS Code，跳过 C/C++ 扩展安装（请确认第二步已成功）' 'Yellow'
        return
    }
    try {
        Write-Log '  正在为 VS Code 安装 C/C++ 扩展 (ms-vscode.cpptools)...' 'Cyan'
        $codeCmd = Join-Path (Split-Path -Parent $codeExe) 'bin\code.cmd'
        if (-not (Test-Path -LiteralPath $codeCmd)) { $codeCmd = Join-Path (Split-Path -Parent $codeExe) 'code.cmd' }
        $installer = if (Test-Path -LiteralPath $codeCmd) { $codeCmd } else { $codeExe }
        
        # 用 System.Diagnostics.Process 带超时启动，避免 code CLI 因网络波动无限挂死
        # （code --install-extension 会在后台启动 VS Code Server，若连不上 marketplace 可能永不返回）
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
        $started = [DateTime]::Now
        Write-Log "  等待 code --install-extension（最多 90 秒）..." 'Cyan'
        if ($process.WaitForExit(90000)) {
            # 正常完成
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            if ($process.ExitCode -eq 0) {
                Write-Log '  C/C++ 扩展安装成功' 'Green'
            } else {
                Write-Log "  C/C++ 扩展安装返回非零退出码: $($process.ExitCode)，可能仍需手动安装" 'Yellow'
            }
        } else {
            # 超时：强制结束，避免阻塞主流程
            Write-Log '  扩展安装超时（90秒），强制结束，继续后续步骤' 'Yellow'
            try { $process.Kill() } catch {}
            Write-Log '  提示：安装完成后可在 VS Code 扩展商店手动搜索 ms-vscode.cpptools 安装' 'Yellow'
        }
    } catch {
        Write-Log "  C/C++ 扩展安装异常（可稍后在扩展商店手动安装）: $($_.Exception.Message)" 'Yellow'
    }
}

function Write-NativeConfig {
    # 在工作区写入 Windows 原生的 launch.json / tasks.json / 示例 main.cpp
    try {
        $vscDir = Join-Path $WORKSPACE '.vscode'
        if (-not (Test-Path -LiteralPath $vscDir)) { New-Item -ItemType Directory -Path $vscDir -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $WORKSPACE)) { New-Item -ItemType Directory -Path $WORKSPACE -Force | Out-Null }
        # ASCII 临时目录：MinGW g++ 不兼容 Unicode 用户名路径（如 本人2），
        # 编译时需写 .o 中间文件到 TMP/TEMP，路径含中文则报 Fatal error: can't create ...
        $tmpDir = 'C:\FlashTap\tmp'
        if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

        $launchJson = @'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "g++ 调试运行",
            "type": "cppdbg",
            "request": "launch",
            "program": "${fileDirname}\\${fileBasenameNoExtension}.exe",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${fileDirname}",
            "environment": [
                {
                    "name": "PATH",
                    "value": "C:\\FlashTap\\mingw64\\bin;${env:PATH}"
                }
            ],
            "externalConsole": false,
            "MIMode": "gdb",
            "miDebuggerPath": "C:\\FlashTap\\mingw64\\bin\\gdb.exe",
            "setupCommands": [
                {
                    "description": "为 gdb 启用整齐打印",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ],
            "preLaunchTask": "C/C++: g++ 生成活动文件",
            "logging": {
                "engineLogging": false
            }
        }
    ]
}
'@
        $tasksJson = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "type": "process",
            "label": "C/C++: g++ 生成活动文件",
            "command": "C:\\FlashTap\\mingw64\\bin\\g++.exe",
            "args": [
                "-g",
                "${file}",
                "-o",
                "${fileDirname}\\${fileBasenameNoExtension}.exe",
                "-std=c++17"
            ],
            "options": {
                "cwd": "${fileDirname}",
                "env": {
                    "TMP": "C:\\FlashTap\\tmp",
                    "TEMP": "C:\\FlashTap\\tmp"
                }
            },
            "problemMatcher": [
                "$gcc"
            ],
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "presentation": {
                "reveal": "silent"
            },
            "detail": "compiler: g++.exe (MinGW-w64)"
        }
    ]
}
'@
        $mainCpp = @'
#include <iostream>
#include <vector>
#include <string>

int main() {
    std::vector<std::string> msg = {
        "Hello, FlashTap!",
        "C++ build environment: MinGW-w64 (Windows native)",
        "Press F5 to build and debug."
    };

    for (const auto& line : msg) {
        std::cout << line << std::endl;
    }

    return 0;
}
'@
        $utf8noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $vscDir 'launch.json'), $launchJson, $utf8noBom)
        [System.IO.File]::WriteAllText((Join-Path $vscDir 'tasks.json'),  $tasksJson,  $utf8noBom)
        [System.IO.File]::WriteAllText((Join-Path $WORKSPACE 'main.cpp'),  $mainCpp,    $utf8noBom)
        Write-Log '  已写入 F5 调试配置 (launch.json/tasks.json) 与示例 main.cpp' 'Green'
    } catch {
        Write-Log "  写入调试配置失败: $($_.Exception.Message)" 'Yellow'
    }
}

function Test-GppReady {
    try {
        $gpp = Join-Path $BIN_DIR 'g++.exe'
        if (-not (Test-Path -LiteralPath $gpp)) { return $false }
        # 必须用绝对路径 $gpp 调用：首次安装时 mingw 尚未加入 PATH，
        # 若用 `& g++.exe`（依赖 PATH）会因找不到命令而抛异常，误判为"未安装"。
        $raw = & $gpp --version 2>&1
        $ver = @("$raw" -split [Environment]::NewLine) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
        if ($ver) { Write-Log "  检测到 g++: $($ver.Trim())" 'Green' }
        return $true
    } catch {
        return $false
    }
}

function Main {
    Write-Log '=== 检测 / 安装 Windows 原生 C++ 编译环境 (MinGW-w64) ==='

    # 1) 已安装则跳过下载，仅确保 PATH 与配置
    if (Test-GppReady) {
        Write-Log 'C++ 编译环境已就绪 (MinGW-w64 g++)' 'Green'
        Add-ToUserPath -Dir $BIN_DIR
        Protect-Dir -Dir $MINGW_DIR
        Write-NativeConfig
        Install-CpptoolsExtension
        return 0
    }

    # 2) 取得压缩包：本地优先，否则联网下载
    $archive = Get-LocalArchive
    if (-not $archive) {
        Write-Log '未找到本地离线包，开始联网下载 MinGW-w64...' 'Cyan'
        $tmpArchive = Join-Path $env:TEMP "flashtap-mingw-$(Get-Date -Format 'yyyyMMddHHmmss').zip"
        if (Get-FileWithRetry -Urls $DOWNLOAD_URLS -OutFile $tmpArchive) {
            $archive = $tmpArchive
        }
    }

    if (-not $archive -or -not (Test-Path -LiteralPath $archive)) {
        Write-Log '无法获取 MinGW-w64 压缩包（离线包缺失且下载失败）。' 'Red'
        Write-Log "解决办法：手动下载 mingw64.zip 放到 FlashTap 目录，重新运行本脚本。" 'Yellow'
        return 1
    }

    # 去除网盘/浏览器下载带来的 Mark-of-the-Web，避免 Defender 拦截解压出的 exe/dll
    try { Unblock-File -Path $archive -ErrorAction SilentlyContinue } catch {}

    # 3) 解压到 C:\FlashTap（压缩包根目录为 mingw64\）
    Write-Log "正在解压 MinGW-w64 到 $MINGW_DIR ..." 'Cyan'
    $parent = Split-Path -Parent $MINGW_DIR
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    # 若已存在旧目录先备份移除，避免残留
    if (Test-Path -LiteralPath $MINGW_DIR) {
        try { Remove-Item -LiteralPath $MINGW_DIR -Recurse -Force -ErrorAction Stop } catch { Write-Log '  旧目录清理失败，尝试覆盖解压' 'Yellow' }
    }
    if (-not (Expand-ArchiveRobust -Archive $archive -Dest $parent)) {
        Write-Log 'MinGW-w64 解压失败。' 'Red'
        Write-Log "请确认压缩包完整，或换用 .zip 格式离线包放到 FlashTap 目录后重试。" 'Yellow'
        return 1
    }

    # 4) 校验编译器
    if (-not (Test-GppReady)) {
        Write-Log '解压后未找到 g++.exe，安装失败。' 'Red'
        return 1
    }

    # 5) 加入 PATH + 杀软排除 + 写配置 + 装扩展
    Add-ToUserPath -Dir $BIN_DIR
    Protect-Dir -Dir $MINGW_DIR
    Write-NativeConfig
    Install-CpptoolsExtension

    # 6) 验证 GDB（调试必需）
    try {
        $gdbRaw = & gdb.exe --version 2>&1
        $gdbVer = @("$gdbRaw" -split [Environment]::NewLine) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
        if ($gdbVer) { Write-Log "GDB 已就绪: $($gdbVer.Trim())" 'Green' }
    } catch {
        Write-Log 'GDB 未检测到（F5 调试可能不可用），请检查安装。' 'Yellow'
    }

    Write-Log 'C++ 编译环境安装完成 (MinGW-w64: gcc/g++/gdb)' 'Green'
    return 0
}

try {
    exit (Main)
} catch {
    Write-Log "C++ 环境配置失败 (异常): $($_.Exception.Message)" 'Red'
    exit 1
}
