# FlashTap 环境自检脚本
# 纯离线运行，无网络请求

$ErrorActionPreference = 'Stop'

# 刷新 PATH（兼容刚安装完的程序）
try {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $merged = @()
    if ($m) { $merged += $m }
    if ($u) { $merged += $u }
    $env:Path = $merged -join ';'
} catch { }

function Write-Status {
    param([string]$Item, [string]$Status, [string]$Color = 'White')
    $pad = [Math]::Max(1, 40 - $Item.Length)
    Write-Host "  $Item" -NoNewline
    Write-Host "$(' ' * $pad)$Status" -ForegroundColor $Color
}

function Check-Ollama {
    Write-Host ""
    Write-Host "检查 Ollama 服务..." -ForegroundColor Cyan

    $isRunning = $false

    # 方式1：检查进程
    try {
        $proc = Get-Process -Name 'ollama' -ErrorAction SilentlyContinue
        if ($proc) { $isRunning = $true }
    } catch {}

    # 方式2：检查Windows服务
    try {
        $service = Get-Service -Name 'ollama' -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') { $isRunning = $true }
    } catch {}

    if ($isRunning) {
        Write-Status "Ollama 服务状态" "[OK] 运行中" "Green"
    } else {
        Write-Status "Ollama 服务状态" "[WARN] 未检测到进程" "Yellow"
        Write-Host "    建议：ollama serve 可能未启动" -ForegroundColor Yellow
    }

    # netstat 不需要管理员权限即可检查端口（PID=0 特殊处理）
    try {
        $netstat = & cmd.exe /c 'netstat -ano 2>&1' 2>&1
        # 取最后2列：本地地址:端口 和 PID；跳过 PID=0 的行（非活跃监听）
        $found11434 = $false
        foreach ($line in ($netstat -split '\r?\n')) {
            if ($line -match ':11434\s+\S+\s+\S+\s+(\d+)$') {
                $pid = [int]$matches[1]
                if ($pid -gt 0) { $found11434 = $true; break }
            }
        }
        if ($found11434) {
            Write-Status "端口 11434" "[OK] 监听中" "Green"
        } else {
            Write-Status "端口 11434" "[WARN] 未监听" "Yellow"
        }
    } catch {
        Write-Status "端口 11434" "[WARN] 检查失败" "Yellow"
    }
}

function Check-Models {
    Write-Host ""
    Write-Host "检查 Ollama 模型..." -ForegroundColor Cyan

    try {
        $job = Start-Job -ScriptBlock { ollama list 2>&1 }
        if (Wait-Job -Job $job -Timeout 10) {
            $output = Receive-Job -Job $job | Out-String
            if ($output -match "qwen2.5-coder:7b") {
                Write-Status "Qwen2.5-Coder-7B" "[OK] 已导入" "Green"
            } else {
                Write-Status "Qwen2.5-Coder-7B" "[WARN] 未导入" "Yellow"
                Write-Host "    建议：重新运行模型下载脚本" -ForegroundColor Yellow
            }
        } else {
            Write-Status "模型检查" "[WARN] 响应超时" "Yellow"
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Status "模型检查" "[WARN] 命令不可用" "Yellow"
    }
}

# 验证是否为真实可用的 VS Code（排除 0KB 残留文件）
function Test-RealVSCode {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item -is [System.IO.DirectoryInfo]) {
            return $false
        }
        if ($item -is [System.IO.FileInfo] -and $item.Length -lt 5242880) {
            return $false
        }
    } catch { return $false }
    return $true
}

function Find-VSCodePath {
    # 方法0: 直接检查用户安装器的标准路径（最快，匹配 install-vscode.ps1 的安装逻辑）
    $userVSCodeExe = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe')
    if ((Test-Path -LiteralPath $userVSCodeExe) -and (Test-RealVSCode $userVSCodeExe)) {
        return $userVSCodeExe
    }

    # 方法1: 注册表 Uninstall 条目（最可靠）
    $regRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($regRoot in $regRoots) {
        try {
            $subkeys = Get-ChildItem -Path $regRoot -ErrorAction SilentlyContinue
            foreach ($key in $subkeys) {
                try {
                    $displayName = (Get-ItemProperty -Path $key.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                    if ($displayName -and $displayName -match 'Microsoft Visual Studio Code') {
                        $installLocation = (Get-ItemProperty -Path $key.PSPath -Name 'InstallLocation' -ErrorAction SilentlyContinue).InstallLocation
                        if ($installLocation) {
                            $exe = [System.IO.Path]::Combine($installLocation, 'Code.exe')
                            if (Test-Path -LiteralPath $exe) { return $exe }
                            $cmd = [System.IO.Path]::Combine($installLocation, 'bin\code.cmd')
                            if (Test-Path -LiteralPath $cmd) { return $cmd }
                        }
                        # InstallLocation 为空时，尝试 DisplayIcon / UninstallString
                        if (-not $installLocation) {
                            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                            $icon = $props.DisplayIcon
                            if ($icon) {
                                $iconExe = $icon -replace '^"([^"]+)".*', '$1'
                                if ($iconExe -and (Test-Path -LiteralPath $iconExe)) { return $iconExe }
                            }
                            $uninst = $props.UninstallString
                            if ($uninst) {
                                $uninstExe = $uninst -replace '^"([^"]+)".*', '$1'
                                if ($uninstExe) {
                                    $dir = Split-Path -Parent $uninstExe
                                    $exe = [System.IO.Path]::Combine($dir, 'Code.exe')
                                    if (Test-Path -LiteralPath $exe) { return $exe }
                                }
                            }
                        }
                    }
                } catch {}
            }
        } catch {}
    }

    # 方法2: where.exe（可能返回非 VS Code 的 code 命令，需验证）
    try {
        $whereResult = & where.exe code 2>&1
        if ($LASTEXITCODE -eq 0) {
            $firstMatch = ($whereResult -split '\r?\n')[0].Trim()
            if (Test-RealVSCode $firstMatch) { return $firstMatch }
        }
    } catch {}

    # 方法3: Get-Command（同样可能返回非 VS Code 的 code 命令）
    try {
        $cmd = Get-Command code -ErrorAction Stop
        if ($cmd -and (Test-RealVSCode $cmd.Source)) { return $cmd.Source }
    } catch {}

    # 方法4: 固定路径
    $candidates = @(
        [System.IO.Path]::Combine($env:ProgramFiles, 'Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine([Environment]::GetEnvironmentVariable("ProgramFiles(x86)"), 'Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\bin\code.cmd'),
        [System.IO.Path]::Combine($env:USERPROFILE, 'AppData\Local\Programs\Microsoft VS Code\Code.exe')
    )
    # $env:ProgramW6432 始终指向 64 位原生路径（32位进程中也有效）
    if ($env:ProgramW6432) {
        $candidates += [System.IO.Path]::Combine($env:ProgramW6432, 'Microsoft VS Code\Code.exe')
    }
    foreach ($c in $candidates) {
        if (Test-RealVSCode $c) { return $c }
    }

    # 方法5: 枚举目录
    $enumDirs = @(
        "$env:ProgramFiles\Microsoft VS Code",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code"
    )
    if ($env:ProgramW6432) {
        $enumDirs += "$env:ProgramW6432\Microsoft VS Code"
    }
    foreach ($ed in $enumDirs) {
        try {
            $find = Get-ChildItem -Path $ed -Filter 'Code*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($find) { return $find.FullName }
        } catch {}
    }

    return $null
}

function Check-VSCode {
    Write-Host ""
    Write-Host "检查 VS Code..." -ForegroundColor Cyan

    $codePath = Find-VSCodePath

    if ($codePath) {
        Write-Status "VS Code 安装" "[OK] 已安装 ($codePath)" "Green"
    } else {
        Write-Status "VS Code 安装" "[WARN] 未检测到" "Yellow"
        Write-Host "    建议：从 https://code.visualstudio.com 安装 VS Code" -ForegroundColor Yellow
    }

    try {
        $extensionPath = [System.IO.Path]::Combine($env:USERPROFILE, '.vscode\extensions')
        $continueExt = Get-ChildItem -LiteralPath $extensionPath -Directory -Filter '*continue.continue*' -ErrorAction SilentlyContinue
        if ($continueExt) {
            Write-Status "Continue 扩展" "[OK] 已安装" "Green"
        } else {
            Write-Status "Continue 扩展" "❌ 未安装" "Red"
            Write-Host "    建议：在 VS Code 扩展商店安装 Continue" -ForegroundColor Yellow
        }
    } catch {
        Write-Status "Continue 扩展" "❌ 未检查" "Yellow"
    }
}

function Check-ContinueConfig {
    Write-Host ""
    Write-Host "检查 Continue 配置..." -ForegroundColor Cyan

    try {
        $configPath = [System.IO.Path]::Combine($env:USERPROFILE, '.continue\config.yaml')
        if (Test-Path -LiteralPath $configPath) {
            $content = Get-Content -LiteralPath $configPath -Raw
            if ($content -match 'qwen2.5-coder') {
                Write-Status "config.yaml" "[OK] 已配置" "Green"
            } else {
                Write-Status "config.yaml" "[!!] 配置不完整" "Yellow"
            }
        } else {
            Write-Status "config.yaml" "❌ 未找到" "Red"
            Write-Host "    建议：重新运行 Continue 配置脚本" -ForegroundColor Yellow
        }
    } catch {
        Write-Status "config.yaml" "❌ 检查失败" "Red"
    }
}

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  FlashTap 环境自检"
Write-Host "====================================" -ForegroundColor Cyan

Check-Ollama
Check-Models
Check-VSCode
Check-ContinueConfig

Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  检查完成"
Write-Host "====================================" -ForegroundColor Cyan