# FlashTap 快速诊断脚本
# 用法：右键 → 使用 PowerShell 运行
# 5 秒内检测所有关键环境，粘贴结果给开发者

Write-Host '══════════════ FlashTap 快速诊断 ══════════════' -ForegroundColor Cyan

# 1. 管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
Write-Host "管理员: $(if ($isAdmin) { 'YES' } else { 'NO (需要管理员运行)' })" -ForegroundColor $(if ($isAdmin) { 'Green' } else { 'Red' })

# 2. 网络
@('github.com','ghproxy.net','ollama.com') | ForEach-Object {
    try {
        $r = Invoke-WebRequest -Uri "https://$_" -Method Head -TimeoutSec 3 -UseBasicParsing
        Write-Host "$_ : OK ($($r.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "$_ : FAIL" -ForegroundColor Red
    }
}

# 3. 代理
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$proxyUri = $proxy.GetProxy('https://github.com')
Write-Host "代理: $(if ($proxyUri -ne 'https://github.com') { $proxyUri } else { '无' })"

# 4. 磁盘
$free = [math]::Round((Get-PSDrive (Get-Location).Drive.Name).Free / 1GB, 1)
Write-Host "磁盘剩余: ${free}GB" -ForegroundColor $(if ($free -gt 5) { 'Green' } else { 'Red' })

# 5. Ollama
$ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue
if ($ollama) {
    Write-Host "Ollama: 已安装 ($($ollama.Source))" -ForegroundColor Green
} else {
    Write-Host "Ollama: 未安装" -ForegroundColor Yellow
}

# 6. OllamaSetup.exe
$installer = Join-Path $PSScriptRoot 'OllamaSetup.exe'
if (Test-Path $installer) {
    $size = [math]::Round((Get-Item $installer).Length / 1MB, 1)
    $valid = if ($size -gt 100) { 'OK' } else { '可能损坏' }
    Write-Host "OllamaSetup.exe: ${size}MB ($valid)" -ForegroundColor $(if ($size -gt 100) { 'Green' } else { 'Red' })
} else {
    Write-Host "OllamaSetup.exe: 未找到" -ForegroundColor Yellow
}

# 7. VS Code
$vscode = Get-Command code.cmd -ErrorAction SilentlyContinue
if ($vscode) {
    Write-Host "VS Code: 已安装 ($($vscode.Source))" -ForegroundColor Green
} else {
    Write-Host "VS Code: 未安装" -ForegroundColor Yellow
}

Write-Host '══════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host '复制以上全部内容发给开发者即可' -ForegroundColor Gray
Write-Host '按任意键退出...' -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')