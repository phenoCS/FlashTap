# FlashTap install pre-flight network check (seconds, non-blocking)
# Runs before the 20-min download to quickly verify all critical download
# sources are reachable, turning a silent mid-install hang into an early,
# visible report. This script only REPORTS; it never blocks the install.
# The install scripts themselves also have per-source timeouts/retries.

$ErrorActionPreference = 'Stop'
trap {
    Write-Output "  [preflight internal error] $($_.Exception.Message)"
}

function Test-OneUrl {
    param([string]$Url)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = 'HEAD'; $req.Timeout = 7000; $req.ReadWriteTimeout = 7000
        $req.AllowAutoRedirect = $true; $req.UserAgent = 'FlashTap-Preflight'
        $resp = $req.GetResponse(); $code = [int]$resp.StatusCode; $resp.Close()
        if ($code -ge 200 -and $code -lt 400) { return @{ ok = $true; ms = $sw.ElapsedMilliseconds; note = "HTTP $code" } }
        if ($code -eq 405 -or $code -eq 403 -or $code -eq 501) {
            $r2 = [System.Net.HttpWebRequest]::Create($Url)
            $r2.Method='GET'; $r2.Timeout=7000; $r2.ReadWriteTimeout=7000
            $r2.AllowAutoRedirect=$true; $r2.UserAgent='FlashTap-Preflight'
            $x=$r2.GetResponse(); $c2=[int]$x.StatusCode; $x.Close()
            if ($c2 -ge 200 -and $c2 -lt 400) { return @{ ok = $true; ms = $sw.ElapsedMilliseconds; note = "HTTP $c2(GET)" } }
            return @{ ok = $false; ms = $sw.ElapsedMilliseconds; note = "HTTP $c2" }
        }
        return @{ ok = $false; ms = $sw.ElapsedMilliseconds; note = "HTTP $code" }
    } catch { return @{ ok = $false; ms = $sw.ElapsedMilliseconds; note = 'Timeout/Unreachable' } }
}

$Sources = @(
    @{ Name = 'Python(Huawei)';     Url = 'https://mirrors.huaweicloud.com/python/3.12.7/python-3.12.7-amd64.exe'; Critical = $true },
    @{ Name = 'Python(npmmirror)';  Url = 'https://registry.npmmirror.com/-/binary/python/3.12.7/python-3.12.7-amd64.exe'; Critical = $true },
    @{ Name = 'Python(TUNA)';       Url = 'https://mirrors.tuna.tsinghua.edu.cn/python/3.12.7/python-3.12.7-amd64.exe'; Critical = $false },
    @{ Name = 'Ollama(official)';   Url = 'https://ollama.com/download/OllamaSetup.exe'; Critical = $true },
    @{ Name = 'Ollama(ghproxy)';    Url = 'https://ghproxy.net/https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe'; Critical = $false },
    @{ Name = 'VSCode(official)';   Url = 'https://update.code.visualstudio.com/latest/win32-x64-user/stable'; Critical = $true },
    @{ Name = 'ModelScope(API)';    Url = 'https://modelscope.cn/api/v1/models/qwen/Qwen2.5-Coder-7B-Instruct-GGUF/repo/files?Recursive=true&Revision=master'; Critical = $true },
    @{ Name = 'VSCode Marketplace'; Url = 'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-ceintl/vsextensions/vscode-language-pack-zh-hans/latest/vspackage'; Critical = $false },
    @{ Name = 'VSCode(open-vsx CN)';Url = 'https://open-vsx.org/'; Critical = $false }
)

Write-Output '============================================='
Write-Output '  FlashTap Install Pre-flight Network Check'
Write-Output '============================================='
Write-Output ''

$Jobs = @()
foreach ($s in $Sources) {
    $Jobs += Start-Job -ScriptBlock {
        param($Name, $Url)
        function T { param([string]$u)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $doGet = $false
            try {
                $req=[System.Net.HttpWebRequest]::Create($u)
                $req.Method='HEAD'; $req.Timeout=7000; $req.ReadWriteTimeout=7000
                $req.AllowAutoRedirect=$true; $req.UserAgent='FlashTap-Preflight'
                $r=$req.GetResponse(); $c=[int]$r.StatusCode; $r.Close()
                if ($c -ge 200 -and $c -lt 400) { return @{ok=$true;ms=$sw.ElapsedMilliseconds;note="HTTP $c"} }
                $doGet = $true
            } catch { $doGet = $true }
            if ($doGet) {
                try {
                    $r2=[System.Net.HttpWebRequest]::Create($u); $r2.Method='GET'; $r2.Timeout=7000
                    $r2.ReadWriteTimeout=7000; $r2.AllowAutoRedirect=$true; $r2.UserAgent='FlashTap-Preflight'
                    $x=$r2.GetResponse(); $c2=[int]$x.StatusCode; $x.Close()
                    if ($c2 -ge 200 -and $c2 -lt 400) { return @{ok=$true;ms=$sw.ElapsedMilliseconds;note="HTTP $c2(GET)"} }
                    return @{ok=$false;ms=$sw.ElapsedMilliseconds;note="HTTP $c2"}
                } catch { return @{ok=$false;ms=$sw.ElapsedMilliseconds;note='Timeout/Unreachable'} }
            }
        }
        $res = T $Url
        [PSCustomObject]@{ Name = $Name; ok = $res.ok; ms = $res.ms; note = $res.note }
    } -ArgumentList $s.Name, $s.Url
}

$null = Wait-Job -Job $Jobs -Timeout 15
$Results = @()
foreach ($j in $Jobs) {
    try {
        if ($j.State -eq 'Completed') {
            $out = Receive-Job $j -ErrorAction SilentlyContinue
            if ($out -and $out.Name) { $Results += $out } else { $Results += [PSCustomObject]@{ Name = 'Unknown'; ok = $false; ms = 0; note = 'NoResult' } }
        } else { $Results += [PSCustomObject]@{ Name = 'ProbeTimeout'; ok = $false; ms = 15000; note = 'Timeout' } }
    } catch { $Results += [PSCustomObject]@{ Name = 'ProbeError'; ok = $false; ms = 0; note = 'Exception' } }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
}

$criticalFail = 0
foreach ($s in $Sources) {
    $r = $Results | Where-Object { $_.Name -eq $s.Name } | Select-Object -First 1
    if (-not $r) { $r = [PSCustomObject]@{ Name = $s.Name; ok = $false; ms = 0; note = 'NotProbed' } }
    $mark = if ($r.ok) { '[OK]' } else { '[XX]' }
    Write-Output ("  {0} {1,-20} {2,8}ms  {3}" -f $mark, $s.Name, $r.ms, $r.note)
    if (-not $r.ok -and $s.Critical) { $criticalFail++ }
}

Write-Output ''
# 专项检查：VS Code 扩展两个来源（marketplace + open-vsx 国内镜像）是否都不可达
$market = $Results | Where-Object { $_.Name -eq 'VSCode Marketplace' } | Select-Object -First 1
$ovsx = $Results | Where-Object { $_.Name -eq 'VSCode(open-vsx CN)' } | Select-Object -First 1
if (($market -and -not $market.ok) -and ($ovsx -and -not $ovsx.ok)) {
    Write-Output '  [WARNING] BOTH VS Code extension sources unreachable (marketplace + open-vsx).'
    Write-Output '            Extensions (Continue / language pack / Code Runner) may NOT install.'
    Write-Output '            Installer will retry with timeouts; if all fail, AI assistant not wired into VS Code.'
    Write-Output ''
}

if ($criticalFail -eq 0) {
    Write-Output '  [RESULT] All critical sources reachable. Safe to start install.'
} else {
    Write-Output "  [WARNING] $criticalFail critical source(s) unreachable! Install may be slow or fail."
    Write-Output '            Suggestion: check network/proxy, or retry on a better connection.'
    Write-Output '            (Install scripts have per-source retries/timeouts; non-critical failures do not block.)'
}
Write-Output ''
[Environment]::Exit(0)
