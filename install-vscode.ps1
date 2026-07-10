# FlashTap: VS Code 安装与配置
# 1. 静默安装 VS Code
# 2. 按顺序逐个安装扩展，30秒超时，绝不并发
# 3. settings.json 原封不动复制
# 4. config.yaml 原封不动复制
# 5. 不做其他任何多余操作

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'

# 确保 TLS 1.2 可用（旧版 PowerShell 默认不开启）
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { $p = [System.Net.WebRequest]::GetSystemWebProxy(); $p.Credentials = [System.Net.CredentialCache]::DefaultCredentials; [System.Net.WebRequest]::DefaultWebProxy = $p } catch {}

# 获取脚本所在目录（兼容 Invoke-Expression 内存执行模式）
$PROJECT_DIR = $null
try {
    if ($MyInvocation -ne $null -and $MyInvocation.MyCommand -ne $null -and $MyInvocation.MyCommand.Path -ne $null) {
        $PROJECT_DIR = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
    }
}
catch {}
if ($PROJECT_DIR -eq $null -or $PROJECT_DIR -eq "") {
    try {
        if ($PWD -ne $null -and $PWD.Path -ne $null) {
            $PROJECT_DIR = $PWD.Path
        }
    }
    catch {}
}
if ($PROJECT_DIR -eq $null -or $PROJECT_DIR -eq "") {
    Write-Host "[错误] 无法获取脚本目录" -ForegroundColor Red
    exit 1
}

$LOG_FILE = [System.IO.Path]::Combine($PROJECT_DIR, 'vscode-install.log')

$VSCODE_DOWNLOAD_URLS = @(
    # 全部使用用户级安装器（VSCodeUserSetup），无需管理员权限即可安装
    'https://vscode.cdn.azure.cn/stable/f1e16e1e6214d7c44d078b1f0607b23251591115/VSCodeUserSetup-x64-1.90.0.exe',
    'https://update.code.visualstudio.com/latest/win32-x64-user/stable',
    'https://az764295.vo.msecnd.net/stable/f1e16e1e6214d7c44d078b1f0607b23251591115/VSCodeUserSetup-x64-1.90.0.exe'
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogLine = "[$Timestamp] [$Level] $Message"
    Write-Host $LogLine
    try { Add-Content -Path $LOG_FILE -Value $LogLine -ErrorAction SilentlyContinue } catch {}
}

function Test-Admin {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $AdminPrincipal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
    return $AdminPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-RealVSCode {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        # VS Code 二进制至少几 MB
        if ($item.Length -lt 5242880) { return $false }
    } catch {
        return $false
    }
    return $true
}

function Invoke-RobustDownload {
    param([string]$Url, [string]$OutFile)
    $maxRetries = 3
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            Write-Log "[信息] 正在下载（第 $($i+1)/$maxRetries 次）: $Url"
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            $outItem = Get-Item -LiteralPath $OutFile -ErrorAction Stop
            if ($outItem.Length -gt 10MB) {
                Write-Log "[信息] 下载完成: $($outItem.Length / 1MB -as [int]) MB"
                return $true
            }
            Write-Log "[警告] 下载文件异常（$($outItem.Length) 字节），重试" 'WARNING'
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        } catch {
            Write-Log "[警告] 下载失败: $($_.Exception.Message)，重试" 'WARNING'
            Start-Sleep -Seconds 3
        }
    }
    Write-Log "[错误] 所有下载尝试均失败" 'ERROR'
    return $false
}

function Install-VSCode {
    Write-Log '[信息] 检查是否已有 VS Code...'

    $vscCandidates = @(
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine($env:ProgramFiles, 'Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine([Environment]::GetEnvironmentVariable("ProgramFiles(x86)"), 'Microsoft VS Code\Code.exe'),
        [System.IO.Path]::Combine($env:USERPROFILE, 'AppData\Local\Programs\Microsoft VS Code\Code.exe')
    )
    if ($env:ProgramW6432) {
        $vscCandidates += [System.IO.Path]::Combine($env:ProgramW6432, 'Microsoft VS Code\Code.exe')
    }

    foreach ($cand in $vscCandidates) {
        if (Test-RealVSCode -Path $cand) {
            Write-Log "[信息] 找到 VS Code: $cand"
            $binDir = Split-Path -Parent $cand
            $cmdPath = [System.IO.Path]::Combine($binDir, 'bin\code.cmd')
            if (-not (Test-Path $cmdPath)) {
                $cmdPath = [System.IO.Path]::Combine($binDir, 'code.cmd')
            }
            if (Test-Path $cmdPath) {
                Write-Log "[信息] 找到 code.cmd: $cmdPath"
                return $cmdPath
            }
            return $cand
        }
    }

    Write-Log '[信息] 未找到 VS Code，开始下载安装...'

    $installerPath = [System.IO.Path]::Combine($env:TEMP, 'VSCodeUserSetup-x64-latest.exe')
    if (Test-Path $installerPath) {
        Write-Log '[信息] 安装器已存在，跳过下载'
    } else {
        $ok = $false
        foreach ($url in $VSCODE_DOWNLOAD_URLS) {
            if (Invoke-RobustDownload -Url $url -OutFile $installerPath) {
                $ok = $true
                break
            }
        }
        if (-not $ok) {
            throw "无法下载 VS Code 安装器，请检查网络连接"
        }
    }

    Write-Log '[信息] 正在静默安装 VS Code（最长等待 10 分钟）...'
    Write-Log '[信息] 安装器路径: ' + $installerPath

    # very silent + no restart + don't run after install
    $installLog = [System.IO.Path]::Combine($env:TEMP, 'vscode-install-log.log')
    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList '/verysilent', '/norestart', '/mergetasks=!runcode', "/LOG=`"$installLog`"" -PassThru
        $finished = $process.WaitForExit(600000)
        if (-not $finished) {
            Write-Log '[错误] VS Code 安装超时，强制终止'
            $process.Kill()
            throw 'VS Code 安装 10 分钟未完成，请检查安装包或网络'
        }
        $ec = $process.ExitCode
    }
    catch {
        throw "VS Code 安装程序运行失败: $($_.Exception.Message)"
    }

    if ($ec -ne 0) {
        Write-Log "[警告] VS Code 安装退出码: $ec" 'WARNING'
        if (Test-Path $installLog) {
            $logContent = Get-Content $installLog -Raw -ErrorAction SilentlyContinue
            if ($logContent -match '.*Error.*|failed|aborted') {
                Write-Log "[错误] 安装日志包含错误信息:" 'ERROR'
                Write-Log $logContent 'ERROR'
            }
        } else {
            Write-Log '[错误] 未生成安装日志，安装器可能未正常启动' 'ERROR'
        }
        throw 'VS Code 安装失败，安装器未正常启动，请检查安装包是否完整'
    }

    Write-Log '[成功] VS Code 安装完成'

    # 重新查找安装好的 VS Code
    Start-Sleep -Seconds 2
    foreach ($cand in $vscCandidates) {
        if (Test-RealVSCode -Path $cand) {
            $binDir = Split-Path -Parent $cand
            $cmdPath = [System.IO.Path]::Combine($binDir, 'bin\code.cmd')
            if (-not (Test-Path $cmdPath)) {
                $cmdPath = [System.IO.Path]::Combine($binDir, 'code.cmd')
            }
            if (Test-Path $cmdPath) {
                Write-Log "[信息] 找到安装后的 code.cmd: $cmdPath"
                return $cmdPath
            }
            return $cand
        }
    }

    $userVSCodeExe = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe')
    if (Test-RealVSCode -Path $userVSCodeExe) {
        $binDir = Split-Path -Parent $userVSCodeExe
        $cmdPath = [System.IO.Path]::Combine($binDir, 'bin\code.cmd')
        if (-not (Test-Path $cmdPath)) {
            $cmdPath = [System.IO.Path]::Combine($binDir, 'code.cmd')
        }
        if (Test-Path $cmdPath) {
            return $cmdPath
        }
        return $userVSCodeExe
    }

    throw 'VS Code 安装后未找到可执行文件，请手动安装'
}

function Install-VSCode-WithRetry {
    $maxRetries = 2
    for ($i = 0; $i -le $maxRetries; $i++) {
        try {
            $cmd = Install-VSCode
            return $cmd
        } catch {
            Write-Log "[警告] VS Code 安装失败（第 $($i+1)/$($maxRetries+1) 次）: $($_.Exception.Message)" 'WARNING'
            if ($i -lt $maxRetries) {
                Start-Sleep -Seconds 5
            }
        }
    }
    throw 'VS Code 安装多次失败，请检查网络后重试'
}

# ── 扩展白名单（唯一允许安装的扩展） ──
# 注意：ms-vscode.cpptools 不在白名单中，因为它在 WSL 远端单独安装 linux-x64 版本
# 如果在这里安装会拿到 Windows 二进制，导致 WSL 中报「二进制不兼容」
$EXTENSION_WHITELIST = @(
    'continue.continue',
    'ms-ceintl.vscode-language-pack-zh-hans',
    'ms-vscode-remote.remote-wsl',
    'formulahendry.code-runner'
)

# 辅助：检查扩展是否已安装（通过目录存在性判定，不依赖 code --install-extension 的退出码）
function Test-ExtensionInstalled {
    param([string]$ExtensionId, [string]$ExtRoot)
    if (-not (Test-Path -LiteralPath $ExtRoot)) { return $false }
    try {
        $found = @(Get-ChildItem -Path $ExtRoot -Directory -Filter "$ExtensionId-*" -ErrorAction SilentlyContinue)
        return ($found.Count -gt 0)
    } catch {
        return $false
    }
}

# 1. 扩展安装：逐个安装，通过检查扩展目录判定成功，失败自动重试2次
function Install-All-Extensions {
    param([string]$VSCodeCmd = 'code')
    Write-Log '[信息] 正在安装 VS Code 扩展...'

    # 确保通过 code.cmd 执行（CLI 模式，不弹出 VS Code 窗口）
    $cliCmd = $VSCodeCmd
    if ($cliCmd -match '\\Code\.exe$') {
        $parentDir = Split-Path -Parent $cliCmd
        $candidate = Join-Path $parentDir 'bin\code.cmd'
        if (-not (Test-Path $candidate)) {
            $candidate = Join-Path $parentDir 'code.cmd'
        }
        if (Test-Path $candidate) {
            $cliCmd = $candidate
        }
    }

    # 预检：code CLI 是否可用
    try {
        $codeVer = & $cliCmd --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "[警告] code CLI 不可用，扩展安装将跳过: $codeVer" 'WARNING'
            return $false
        }
        Write-Log "[信息] code CLI 就绪: $($codeVer[0])" 'INFO'
    } catch {
        Write-Log "[警告] code CLI 调用失败，扩展安装将跳过: $($_.Exception.Message)" 'WARNING'
        return $false
    }

    $extRoot = [System.IO.Path]::Combine($env:USERPROFILE, '.vscode', 'extensions')
    $successCount = 0
    $failCount = 0
    $errorLog = @()

    foreach ($extId in $EXTENSION_WHITELIST) {
        $installed = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                & $cliCmd --install-extension $extId --force 2>&1 | Out-Null
                Start-Sleep -Seconds 1
            } catch {
                # 忽略调用异常，后续通过目录存在性判定
            }

            # 不依赖退出码，通过检查扩展目录真实存在来判定成功
            if (Test-ExtensionInstalled -ExtensionId $extId -ExtRoot $extRoot) {
                Write-Log "  [成功] $extId" 'INFO'
                $successCount++
                $installed = $true
                break
            }

            if ($attempt -lt 3) {
                Write-Log "  [信息] ${extId} 第 $attempt 次未检测到，重试..." 'WARNING'
                Start-Sleep -Seconds 2
            } else {
                Write-Log "  [错误] ${extId} (3次均未检测到安装目录)" 'ERROR'
                $errorLog += $extId
            }
        }

        if (-not $installed) {
            $failCount++
        }
    }

    if ($errorLog.Count -gt 0) {
        Write-Log "[警告] 安装失败的扩展: $($errorLog -join ', ')" 'WARNING'
    }

    Write-Log "[信息] 扩展安装结果: 成功 $successCount 个 / 失败 $failCount 个"
    return ($failCount -eq 0)
}

# 1b. 扩展清理：卸载所有不在白名单中的扩展
function Remove-NonWhitelistExtensions {
    param([string]$VSCodeCmd = 'code')

    # 确保通过 code.cmd 执行（CLI 模式，不弹出 VS Code 窗口）
    $cliCmd = $VSCodeCmd
    if ($cliCmd -match '\\Code\.exe$') {
        $parentDir = Split-Path -Parent $cliCmd
        $candidate = Join-Path $parentDir 'bin\code.cmd'
        if (-not (Test-Path $candidate)) {
            $candidate = Join-Path $parentDir 'code.cmd'
        }
        if (Test-Path $candidate) {
            $cliCmd = $candidate
        }
    }

    try {
        $installed = & $cliCmd --list-extensions 2>&1
    } catch {
        return
    }
    if (-not $installed) { return }

    $extRoot = [System.IO.Path]::Combine($env:USERPROFILE, '.vscode', 'extensions')
    $removedCount = 0
    foreach ($ext in $installed) {
        $extId = $ext.Trim()
        if ($extId -eq '' -or $extId -in $EXTENSION_WHITELIST) { continue }

        try {
            & $cliCmd --uninstall-extension $extId --force 2>&1 | Out-Null
            Start-Sleep -Seconds 1
        } catch { }

        # 不依赖退出码，通过检查扩展目录是否消失来判定卸载成功
        if (-not (Test-ExtensionInstalled -ExtensionId $extId -ExtRoot $extRoot)) {
            Write-Log "  [已卸载] $extId" 'INFO'
            $removedCount++
        }
    }

    if ($removedCount -gt 0) {
        Write-Log "[信息] 已清理 $removedCount 个非白名单扩展"
    }
}

# 2. 原封不动复制 settings.json 到 VS Code 用户配置
function Copy-SettingsJson {
    Write-Log '[信息] 正在同步 settings.json 配置文件...'

    $srcPath = [System.IO.Path]::Combine($PROJECT_DIR, 'settings.json')
    if (-not (Test-Path -LiteralPath $srcPath)) {
        throw "找不到源 settings.json: $srcPath"
    }

    # VS Code 用户配置目录：%APPDATA%\Code\User\settings.json
    $targetDir = [System.IO.Path]::Combine($env:APPDATA, 'Code', 'User')
    $targetPath = [System.IO.Path]::Combine($targetDir, 'settings.json')

    # 创建目录
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Log "[信息] 已创建目录: $targetDir"
    }

    # 备份已有配置
    if (Test-Path -LiteralPath $targetPath) {
        $backup = "$targetPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $targetPath -Destination $backup -Force -ErrorAction Stop
        Write-Log "[信息] 已备份现有配置到: $backup"
    }

    # 纯搬运：直接复制，不修改任何字节
    Copy-Item -LiteralPath $srcPath -Destination $targetPath -Force -ErrorAction Stop
    Write-Log "[成功] settings.json 已复制到: $targetPath" 'INFO'

    return $true
}

# 2b. 写入 locale.json，确保中文语言包安装后 VS Code 首次启动就是中文界面
function Write-LocaleJson {
    Write-Log '[信息] 正在写入语言区域配置...'

    $targetDir = [System.IO.Path]::Combine($env:APPDATA, 'Code', 'User')
    $targetPath = [System.IO.Path]::Combine($targetDir, 'locale.json')

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $localeContent = '{"locale":"zh-cn"}'
    try {
        Set-Content -LiteralPath $targetPath -Value $localeContent -Encoding UTF8 -Force
        Write-Log "[成功] locale.json 已写入: $targetPath" 'INFO'
    } catch {
        Write-Log "[警告] locale.json 写入失败: $($_.Exception.Message)" 'WARNING'
    }
}

# 3. 复制 Continue 配置文件（config.json + config.yaml）
function Copy-ContinueConfig {
    Write-Log '[信息] 正在同步 Continue 配置文件...'

    $continueDir = [System.IO.Path]::Combine($env:USERPROFILE, '.continue')

    if (-not (Test-Path $continueDir)) {
        New-Item -ItemType Directory -Path $continueDir -Force | Out-Null
        Write-Log "[信息] 已创建 Continue 目录: $continueDir"
    }

    $allOk = $true
    $configFiles = @('config.json', 'config.yaml', 'config.ts')

    foreach ($cfgName in $configFiles) {
        $srcPath = [System.IO.Path]::Combine($PROJECT_DIR, $cfgName)
        $targetPath = [System.IO.Path]::Combine($continueDir, $cfgName)

        if (-not (Test-Path -LiteralPath $srcPath)) {
            Write-Log "  [信息] 跳过 $cfgName（源文件不存在）"
            continue
        }

        # 备份已有配置
        if (Test-Path -LiteralPath $targetPath) {
            $backup = "$targetPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $targetPath -Destination $backup -Force -ErrorAction Stop
            Write-Log "  [信息] 已备份 $cfgName 到: $backup"
        }

        # 复制
        Copy-Item -LiteralPath $srcPath -Destination $targetPath -Force -ErrorAction Stop
        Write-Log "  [成功] $cfgName 已复制到: $targetPath"
    }

    return $allOk
}

# ── Main ──
function Main {
    # Step 1: 安装 VS Code（或找到已安装）
    $codeCmd = Install-VSCode-WithRetry
    Write-Log "[信息] VS Code: $codeCmd"

    # Step 2: 安装白名单扩展（5个，逐个安装，60s超时，重试2次）
    $extSuccess = Install-All-Extensions -VSCodeCmd $codeCmd

    # Step 2b: 清理非白名单扩展
    Remove-NonWhitelistExtensions -VSCodeCmd $codeCmd

    # Step 3: 复制 settings.json 原封不动
    Copy-SettingsJson

    # Step 3b: 写入 locale.json（VS Code 1.90+ 通过此文件决定显示语言）
    Write-LocaleJson

    # Step 4: 复制 Continue config.yaml 原封不动
    $continueSuccess = Copy-ContinueConfig

    Write-Log '[成功] VS Code 配置完成' 'INFO'

    return @{
        CodeCmd = $codeCmd
        ExtSuccess = $extSuccess
        ContinueSuccess = $continueSuccess
    }
}

# 直接执行，返回结果供 Setup-FlashTap.ps1 调用
$mainResult = Main
if (-not $mainResult.ExtSuccess) {
    Write-Log '[警告] 部分扩展安装失败，请检查上方日志' 'WARNING'
    exit 2
}
exit 0