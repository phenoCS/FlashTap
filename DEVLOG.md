# FlashTap 开发日志 / Bug 记录

> 记录开发过程中遇到的每一个坑，方便后来人避开。

---

## 2026-07-10 · Ollama 下载攻坚日

### Bug #1: PowerShell 管理员模式不继承系统代理

**现象**：用户开了国际网络，`curl` 能通 GitHub，但脚本里 `Invoke-WebRequest` 报"无法连接到远程服务器"。

**原因**：脚本以管理员身份运行，PowerShell 管理员进程不会自动继承用户会话的代理设置。`curl.exe` 能通是因为它走的是系统级代理，跟 PowerShell 的 .NET 网络栈不是同一套。

**解决**：在所有 .ps1 脚本开头加上：
```powershell
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
[System.Net.WebRequest]::DefaultWebProxy = $proxy
```

**影响文件**：`install-flashtap.ps1`、`Setup-FlashTap.ps1`、`install-vscode.ps1`

---

### Bug #2: 控制台快速编辑模式导致下载卡死

**现象**：下载过程中鼠标不小心点到终端空白区域，下载进程立即卡住不动。

**原因**：Windows 控制台默认开启"快速编辑模式"，点击终端会进入文本选择状态，暂停所有控制台输出。而脚本用 `\r` 实时刷新进度条，输出被阻塞后整个下载流程卡死。

**尝试方案**：用 kernel32.dll 的 `SetConsoleMode` 禁用快速编辑模式。
**放弃原因**：禁用后用户无法复制粘贴日志，反而影响调试。

**最终方案**：接受这个行为，不显示实时进度条，改用简单日志输出。用户需要复制日志时正常操作，下载期间不要点击终端即可。

---

### Bug #3: BITS 多线程下载卡在 85MB

**现象**：用 `Start-BitsTransfer` 下载 1.4GB 文件，到 85MB 左右不动了。

**原因**：BITS 依赖服务器支持 Range 请求，且对网络中断处理较差。免费镜像服务器（ghproxy）可能不支持或不稳定。

**解决**：放弃 BITS，改用 `Invoke-WebRequest -OutFile`，最稳定。

---

### Bug #4: Winget 安装 Ollama 失败

**现象**：`winget install Ollama.Ollama` 卡在协议确认页面。

**尝试方案**：加 `--accept-package-agreements --accept-source-agreements --force`。
**结果**：依然失败，winget 底层也是从 GitHub 下载，没有加速效果。

**最终方案**：移除 winget 尝试，直接网络下载。

---

### Bug #5: 免费 GitHub 镜像大面积失效

**测试结果**（2026-07-10）：

| 镜像 | 状态 |
|------|------|
| ghproxy.com | ❌ 超时（已挂） |
| gh.con.sh | ❌ 返回 suspended.txt（已停用） |
| gh.llkk.cc | 未测试 |
| gitdl.cn | 未测试 |
| gh.api.99988866.xyz | 未测试 |
| ghproxy.net | ✅ 唯一可用，速度约 186KB/s |

**教训**：免费镜像不稳定，随时可能挂。不要依赖太多镜像，保留 1-2 个有效 + GitHub 直连即可。

---

### Bug #6: `ForEach-Object -Parallel` 在 PowerShell 5.1 不兼容

**现象**：尝试用 `$chunks | ForEach-Object -Parallel { ... }` 实现多线程分块下载，脚本直接报错。

**原因**：`-Parallel` 参数是 PowerShell 7.0+ 才引入的，Windows 10/11 默认的 PowerShell 5.1 不支持。

**解决**：放弃多线程分块下载，回退到单线程 `Invoke-WebRequest`。

---

### Bug #7: `Register-ObjectEvent` 回调中变量作用域问题

**现象**：用 `$wc.DownloadFileAsync()` + `Register-ObjectEvent` 显示下载进度，事件回调中无法访问外部变量 `$sw`（秒表）。

**原因**：`Register-ObjectEvent -Action` 脚本块在独立 Runspace 中运行，无法访问调用方的局部变量。

**解决**：放弃异步下载 + 事件回调，改用同步 `Invoke-WebRequest`。

---

### Bug #8: `Invoke-WebRequest` 无超时导致永久卡死

**现象**：`Invoke-WebRequest` 连接镜像源时无限等待，没有任何错误提示。

**原因**：默认不设超时，连接不上会一直等。

**解决**：加 `-TimeoutSec 600`（10 分钟），超时后自动跳到下一个镜像。
```powershell
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 600
```

---

### Bug #9: HEAD 请求测速反而卡住下载

**现象**：用 `HttpWebRequest.Method = 'HEAD'` 逐个测 7 个镜像的响应时间，结果测速阶段就卡住，下载永远不开始。

**原因**：`HttpWebRequest.Timeout` 在某些网络环境下对 HEAD 请求不生效，导致 `GetResponse()` 阻塞。

**解决**：去掉测速环节，直接按顺序尝试镜像下载。

---

### Bug #10: GitHub 国内访问不稳定（非代码问题）

**现象**：同一份代码，有时候 10 秒 push 成功，有时候 30 分钟 push 不上去。OllamaSetup.exe 下载速度波动极大（50KB/s ~ 500KB/s）。

**原因**：中国到 GitHub 的国际出口带宽有限，受运营商、时段、国际线路拥堵等因素影响，属于基础设施问题，代码无法解决。

**缓解措施**：
- 允许用户提前下载 `OllamaSetup.exe` 放同目录跳过下载
- README 中说明预计 1-2 小时，让用户有心理预期
- 建议用户开启国际网络加速

---

## 经验总结

1. **.NET 网络栈 ≠ 系统网络栈**：PowerShell 用 .NET 发请求，和 `curl.exe` 走不同路径，代理设置需要单独配置。
2. **Windows 控制台有很多历史遗留问题**：快速编辑模式、CRLF 换行符、UTF-8 BOM 等都是坑。
3. **PowerShell 5.1 是 Windows 默认版本**：不要用 PowerShell 7+ 才有的特性（`-Parallel`、三元运算符等）。
4. **免费的东西不可靠**：GitHub 镜像随时可能挂，不要依赖。
5. **大文件下载在国内是硬伤**：1.4GB 从 GitHub 下载，MVP 阶段只能接受慢，后续有钱了上 CDN。

---

## 2026-07-21 · 纯净态测试：扩展安装致命 bug（Bug #11）

> 背景：之前所有测试都在"本机已装好一切"的环境里跑，扩展"全装成功"是**假阳性**。
> 今天按用户要求做"空白态"验证，用一个临时克隆 VM 失败（缺 Guest Additions 无法无界面跑），
> 改为**本机隔离用户数据层**验证：把 `~/.continue`、4 个 FlashTap 扩展、settings/locale 改名移到备份区，
> 二进制层（VS Code 本体 / Ollama / 4.7GB 模型）因 headless 无法安全卸载、且重下代价大，**未真删**，
> 仅通过代码审查 + 组件实测覆盖，测完一键还原。

### Bug #11: 扩展一个都装不上（之前被"已预装"完全掩盖）

**现象**：真正干净态（扩展目录 + 清单 `extensions.json` 都清空）下运行 `install-vscode.ps1`，
4 个扩展**全部安装失败**（marketplace 主路径"未检测到" + open-vsx 兜底也失败）。
而此前汇报的"4 扩展全装成功"是假的——因为那时扩展本就预装，`code --install-extension` 对已存在扩展直接返回成功，
把 `Invoke-CodeInstall` 的 bug 完全盖住了。

**定位过程**：
1. 先排除网络：直接 `code --install-extension continue.continue --force` → **"successfully installed"**，目录生成；
   `Test-NetConnection` 测 `marketplace.visualstudio.com` / `open-vsx.org` / `update.code.visualstudio.com` 的 443 全通。
   → 结论：**不是网络问题，是安装器逻辑 bug**。
2. 看检测函数 `Test-ExtensionInstalled`：靠**扩展目录存在性**判定（`Get-ChildItem -Filter "$ExtensionId-*"`）。
3. 看安装函数 `Invoke-CodeInstall`：问题出在传参方式。

**根因**：`Invoke-CodeInstall` 把整条命令当**单个字符串**传给 `code.cmd`：
```powershell
# ❌ 原代码
param([string]$CliCmd, [string]$Argument)
$job = Start-Job -ScriptBlock { param($c, $a) & $c $a 2>&1 } -ArgumentList $CliCmd, $Argument
# 调用处：-Argument "--install-extension continue.continue --force"
```
PowerShell 里 `& $c $a`（`$a` 是字符串变量）会把整串 `"--install-extension continue.continue --force"`
当作**一个参数**传给 `code.cmd` → `code` 收到一个无法识别的长参数 → **静默什么都不装** → 目录不生成 →
`Test-ExtensionInstalled` 判定"未检测到"。marketplace 失败后，open-vsx 兜底**走的是同一个函数**，于是连兜底也一起失效。
我手动 `& $code --install-extension continue.continue --force`（分离的多个 token）能成功，完美印证。

**修复**：把参数改成**数组**并用 `@a` 展开，且用一元逗号 `(,$Arguments)` 防止 `Start-Job -ArgumentList` 把数组展平：
```powershell
# ✅ 修复后
function Invoke-CodeInstall {
    param([string]$CliCmd, [string[]]$Arguments)
    $job = Start-Job -ScriptBlock { param($c, $a) & $c @a 2>&1 } -ArgumentList $CliCmd, (, $Arguments)
    if ($job | Wait-Job -Timeout 120) {
        $null = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue   # 顺手修掉原 success 分支漏删 job 的泄漏
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        throw 'code install timed out (120s)'
    }
}
```
两处调用同步改为传数组：
```powershell
Invoke-CodeInstall -CliCmd $cliCmd -Arguments @('--install-extension', $extId, '--force')
Invoke-CodeInstall -CliCmd $cliCmd -Arguments @('--install-extension', $tmpVsix, '--force')  # open-vsx 兜底
```

**验证（干净态，网络已确认正常）**：
| 阶段 | 结果 |
|---|---|
| 修复前干净态跑 `install-vscode.ps1` | 4 扩展全失败（marketplace + open-vsx 双源） |
| 直接 `code --install-extension` | 成功 → 证明是安装器逻辑 bug，非市场问题 |
| **修复后**干净态跑 `install-vscode.ps1` | **成功 4 / 失败 0**，4 个目录真实生成 |
| `configure-continue.py` | config.json/yaml/ts 三个 [OK] |
| `check-environment.ps1` | 全 [OK]（Ollama / 模型 / VS Code / Continue / config） |

**环境还原**：测试用隔离 + 还原脚本，100% 原位恢复——`.continue`、settings/locale 回位；
4 个扩展恢复到**原始版本**（测试装的 `language-pack 1.129` 已清除、回到 `1.126`）；
模型双标签 `qwen2.5-coder:7b` + `qwen2.5-coder-7b:latest` 完好；用户自有扩展（claude-code / cpptools / doki-theme 等）全程未动；
临时备份区已删除，还原后自检全绿。

**影响文件**：`install-vscode.ps1`（仅该函数 + 两处调用）

---

### 本次纯净测试暴露的"未验证清单"（诚实记录，非已修复 bug）

> 上面修的是"轻量用户数据层"。真正空白电脑最危险的是下面这些**仍未在空白环境实测**的重型阶段：

1. **VS Code 本体安装**：`install-vscode.ps1` 含下载 + `/verysilent` 静默安装逻辑，但本次干净测试复用了本机已装 VS Code，
   **这条下载/静默安装路径从未在空白环境跑过**。风险：SmartScreen/Defender 拦截、10 分钟超时、PATH 刷新（装完立刻装扩展可能找不到 `code`）。
2. **Ollama 本体安装**（`install-flashtap.ps1`）：下载 1.4GB + `/verysilent` + 启动服务 + 环境变量，**从未在空白环境实测**。
3. **模型下载**（`download-models.py`）：经 modelscope 拉 5GB GGUF + `setx /M`（需管理员）+ 停/启 Ollama 服务 + 导入，
   **仅代码审查、从未实跑**（headless 跑它有系统级风险）。这是项目目标（本地可跑的模型）的核心，风险最高。
4. **完整编排**（`Setup-FlashTap.ps1` + `一键安装FlashTap.bat`）：从未端到端跑通，只单跑过组件。
   风险：步骤顺序、env 文件跨提权传递、Python 自动下载（`InstallAllUsers=1` 需管理员）、UAC 提权钩子。
5. **不同机器网络/区域假设**：marketplace/open-vsx 可达性是在本机测的；换台机器可能遇到代理/防火墙，
   安装器虽有代理处理，但 modelscope 下载路径未验证。

**结论**：扩展安装这条"轻路径"已修好并验证；但**无法仅凭今日测试就断言空白电脑一遍跑通**。
建议补一个带 Guest Additions 的空白 VM（或单独真机），按 `一键安装FlashTap.bat` 端到端跑一次，
重点看上面 1–4 项，才能给出"一遍跑通"的认证。

---

## 2026-07-22 · "双击啥也没弹 / 受限模式只能看代码" 真因翻案与救急修复

> 背景：用户反馈——双击 FlashTap 桌面快捷方式"啥也没弹出"，手动开 VS Code 进入"保护模式 / 受限模式"，
> 所有功能（Continue 对话、C/C++）都用不了，只能看代码。
> 我前两次判断都错了（先说"双击正常"，再说"只是工作区信任没关"），最后靠**只读进真实环境诊断**才翻案。

### Bug #12: 安装器写死路径/用户，与真实机器完全不匹配（真凶）

**现象**：
- 桌面 `FlashTap.lnk` 双击"啥也没弹出来"（后续诊断发现 `TargetPath` 是**空**）。
- 手动开 VS Code 是"受限模式（保护模式）"，扩展全禁用，只能看代码。
- VS Code 当前窗口标题是 `…[WSL: Ubuntu]…`，打开的是 **WSL 远程工作区**而非本地 FlashTap 工作区。

**诊断过程（只读，不写，关键在 `C:\tmp\*.bat` 探针）**：
1. 查 `61959` 用户：`C:\Users\61959\.vscode\extensions` 不存在、`.continue` 不存在 → 扩展/配置**根本没装到预期用户**。
2. 查 `C:\FlashTap\cpp-workspace` → **不存在**（C++ 工作区从未创建）。
3. 桌面 `FlashTap.lnk` 的 `TargetPath`/`Arguments` 都为空 → **快捷方式损坏**。
4. 精确定位 `Code.exe`：`where code` 与进程镜像均指向 **`D:\Microsoft VS Code\Code.exe`**（非 `C:\Program Files`）。
5. 真实登录用户是 **`PYX` / `本人2`**，根本不是安装器里硬编码的 **`61959`**。

**根因**（推翻前两次判断）：
- 安装器（及此前救急脚本）把 **VS Code 路径写死成 `C:\…\Code.exe`**、把**目标用户写死成 `61959`**。
- 但这台真实机器 VS Code 装在 **`D:\Microsoft VS Code`**、登录用户是 **`PYX`**。
- 于是所有"用户级"内容（扩展目录、`.continue` 配置、工作区信任设置、C++ 工作区、桌面快捷方式）全写进了
  **不存在的 `61959` / 错的 `C` 盘路径**。桌面快捷方式因 `TargetPath` 探测不到 `C:\` 的 Code.exe 而被写成**空**——
  这就是"双击啥也没弹出来"的直接原因；手动开 VS Code 时，因 PYX 下没有扩展 + 旧逻辑残留打开 WSL 工作区 → "只能看代码"。

**救急修复（直接修好这台真实机器，未重装）**：
用**动态 `code` 命令（PATH 已有 `D:\Microsoft VS Code\bin`）+ 真实 `$env:USERPROFILE`（PYX）**，不写死任何盘符/用户：
- 装扩展（Continue / 中文语言包 / Code Runner）到当前真实用户；
- 写入 `C:\Users\PYX\AppData\Roaming\Code\User\settings.json` → `security.workspace.trust.enabled: false`（关受限模式）；
- 写 `.continue/config.yaml`（ollama + AUTODETECT）；
- 创建 `C:\FlashTap\cpp-workspace`；
- 重建桌面 `FlashTap.lnk` → `D:\Microsoft VS Code\Code.exe "C:\FlashTap\cpp-workspace"`（TargetPath 不再为空）；
- 杀掉旧的受限模式 / WSL 实例，用本地 C++ 工作区重新打开 VS Code。

> ⚠️ **踩坑提醒**：救急脚本第一版用了 `ConvertFrom-Json -AsHashtable`，
> 但本机是 **PowerShell 5.1**（Windows 默认），`-AsHashtable` 是 PS 7+ 才有的参数 → 该命令报错跳过，
> 导致信任没写上、工作区/lnk 没建。第二版改用 `Add-Member` 追加属性才成功。
> **再次印证 Bug #6 教训：不要依赖 PS 7+ 特性。**

**验证（用户实测）**：
- VS Code 窗口标题变为 `cpp-workspace - Visual Studio Code` ✅
- 桌面 `FlashTap.lnk` = `D:\Microsoft VS Code\Code.exe "C:\FlashTap\cpp-workspace"` ✅
- 信任已关、`.continue` 配置就位、ollama / `qwen2.5-coder:7b` 在线 ✅
- **用户在宿主机点 VS Code 的 Continue 能正常对话** ✅（修复闭环确认）

**影响文件**：本次为**宿主机救急**，直接改的是 `C:\Users\PYX\…` 与 `C:\FlashTap\…`，**未改安装器源码**。

---

### 遗留（必须根治，否则换机器必再翻车）

> 上面只是把**这台**机器救活了。`一键安装FlashTap.bat` / `Setup-FlashTap.ps1` **本身仍写死 `61959` 用户 + `C:\` 路径**，
> 在盘符/用户名不同的机器上必重现本次全部症状。

**待做（根治病）**：
1. **动态探测 VS Code 路径**：用 `where code` / 读 `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe`
   取真实安装位置，绝不再硬编码 `C:\Program Files\Microsoft VS Code\Code.exe`。
2. **用真实登录用户做用户级配置**：提权脚本里用 `Get-CimInstance Win32_ComputerSystem | Select-Object UserName`
   或 `$env:USERNAME` 的真实主用户，而不是写死 `61959`；所有 `--user-data-dir` / 扩展目录 / settings 写入都走该用户目录。
3. **桌面快捷方式兜底**：若探测不到 Code.exe 则报错提示，绝不能写出空 `TargetPath` 的损坏 lnk。
4. **README 第七节重写**：之前写的"已知问题"是按错误判断（"只是信任没关"）写的，需按本次真因（路径/用户写死）重述。

**结论**：本次问题不是"使用方式"或"单一信任开关"的问题，而是安装器**环境假设写死**导致在真实机器上全面错位。
救急已闭环（Continue 能对话），根治病待排期。

---

## 2026-07-22（第二轮）· 对照审查报告修复安装器源码致命 bug

> 背景：用户要求"看一下别人写的审查报告文档，有没有致命 bug 要修改"。
> 我把项目里几份审查/测试报告（`VM测试环境与全流程接手文档.md` 的 **R1–R6 根因清单**、
> `测试报告`、`端到端认证报告`、`缺陷修复与复测报告`）与**当前源码**逐条对账。
> 结论：报告说"已修"的大部分确实修了；但有几处**报告点名致命、源码仍残留**。

### 已修（源码层，非救急）

**1. R3（致命，已修）— 安装结束自动启动的 VS Code 不带工作区**
- 原非 WSL 分支 `$vscArgs = @('--locale=zh-cn')` 只带语言、**不带本地 C++ 工作区** → 安装完自动打开空白窗。
- 改为 `$vscArgs = @('--locale=zh-cn', "`"$CppWorkspace`"")`，与桌面快捷方式保持一致。

**2. `-AsHashtable`（PS 5.1 不兼容，已修）**
- 第 1116 行原 `ConvertFrom-Json -AsHashtable` 是 PS 7+ 专有参数，真实机器默认 PS 5.1 会抛异常、
  被 catch 吞掉 → 信任追加静默失败（救急时就踩过同一坑）。
- 改为 PS 5.1 兼容的 `PSObject.Properties | ForEach-Object { $h[$_.Name]=$_.Value }`。

**3. R5（潜在致命，已修）— WSL 分支与 Windows MinGW 架构自相矛盾**
- 原 699–1105 行完整保留 WSL 分支：用 `--remote wsl+` 打开 `/home/lc-cpp-workspace` 远程工作区，
  但 `setup-cpp-env.ps1` 装的是 Windows MinGW、配置 `C:\FlashTap\cpp-workspace`。两者冲突。
- 虽然因 `.wsl-distro-name` 已不再生成而当前不触发，但是颗"炸弹"。
- 处置：把原 WSL 分支内的 `$RealAppData/$RealUserProfile` 定义**提升到外层**（信任设置段需要），
  并用 `if ($false)` **永久禁用 WSL 分支**（零语法风险，不引入新 bug）。
- 注意：WSL 死代码（约 400 行）仍保留在 `if ($false)` 内，未物理删除（避免大段改动引入风险）；
  若后续要彻底瘦身可物理删除，但当前已无运行时影响。

**4. R1/R4（中危健壮性，已加固）— 提权 SID 导致扩展/配置装错用户**
- 原 `code --install-extension` 在提权进程按**进程访问令牌 SID** 落扩展目录，与 `code.cmd` 的
  环境变量重定义（`$env:USERPROFILE` 等）无关 → 跨账户 UAC 提权时扩展落到管理员账户，真实用户读不到 → 只能看代码。
- 处置：所有 `code` 调用（装扩展 / 启动 / 复用 / 桌面 lnk）**统一显式指定**
  `--user-data-dir=$env:APPDATA\Code`（即目标用户标准目录）。
  - `install-vscode.ps1` 的 `Invoke-CodeInstall`：追加 `--user-data-dir=Join-Path $env:APPDATA 'Code'`
    （`$env:APPDATA` 已在脚本开头重定义为目标用户）。
  - `Setup-FlashTap.ps1` 启动/复用段：`$launchArgs`/`$reuseArgs` 加 `"--user-data-dir=$RealAppData\Code"`。
  - 桌面 lnk：`Arguments` 加 `--user-data-dir="$env:APPDATA\Code"`。
- 该目录 = VS Code 默认 user-data 位置，故指定它**不改变用户默认配置位置、无副作用**；
  装扩展/启动/lnk 三处指向同一目录，与配置写入位置（`Copy-SettingsJson` 等写到 `$env:APPDATA\Code\User`）完全一致。

### 自检（修完确认无新 bug）
- **语法**：用 `[System.Management.Automation.Language.Parser]::ParseFile` 对两个脚本做**只解析不执行**校验，
  目标副本目录下 `Setup-FlashTap.ps1` / `install-vscode.ps1` 均 **SYNTAX_OK**（含 `if($false)` 块内大量 here-string 未破坏语法）。
- **变量作用域**：WSL 块内变量（`commitId`/`srvResult`/`wslWorkspace`/`distroFile`/`distroName`）**全部仅在 `if($false)` 块内**，
  块外无引用 → 不会因禁用产生"未定义变量"；`$RealAppData` 外层定义，信任段/启动段/复用段均可见；lnk 段用全局 `$env:APPDATA`（脚本开头 17/19 行已重定义）。
- **一致性**：`--user-data-dir` 在所有位置指向同一目录，与配置写入位置一致。
- **Lint**：两个文件 read_lints 均 0 error。

### 影响文件
- `Setup-FlashTap.ps1`（启动/复用/lnk 的 `--user-data-dir`、R3 工作区、WSL 分支 `if($false)` 禁用、信任段 PS5.1 兼容）
- `install-vscode.ps1`（`Invoke-CodeInstall` 加 `--user-data-dir`）

### 仍建议（非本次阻塞）
- `if($false)` 内的 WSL 死代码可考虑物理删除瘦身（当前无运行时影响）。
- 端到端空白环境实测仍是 VM 接手文档 R1–R6 未验证清单（VS Code 静默安装 / Ollama 安装 / 模型下载 / 完整编排），
  需在空白 VM 跑一次 `一键安装FlashTap.bat` 认证。

---

## 2026-07-22 · VM 端到端测试 6 轮（入口重构 + 10 bug 修复）

> **背景**：统一入口从"双击自动 UAC 提权"改为"右键→以管理员方式运行"。
> 旧流程：bat → 提权到 Administrator → flashtap-user.txt 传递用户上下文 → 安装。
> 新流程：bat → 直接检测管理员 → 用户右键以管理员运行 → 免用户上下文传递。
> **测试环境**：VirtualBox VM（flashtap_test），Win11 空白基线，Z: 共享文件夹映射到宿主机 C:\flashtap。

### Bug #13: 提权路径硬编码 VirtualBox 共享文件夹（C1, 致命）

**现象**：非 VM 环境下双击 bat → UAC 弹窗 → 点了"是" → 什么都没发生。

**原因**：`一键安装FlashTap.bat` 第 28 行提权时写死 `net use X: \\vboxsrv\flashtap`，物理机上该共享路径不存在，提权后的 cmd 找不到脚本。

**解决**：去掉自动 UAC 提权，改为管理员检测 + 明确提示用户右键以管理员运行。

**影响文件**：`一键安装FlashTap.bat`
**回合**：第 1 轮

### Bug #14: `$vscCandidates` 未定义导致 VS Code 安装后定位失败（C2）

**现象**：`install-vscode.ps1` 第 464 行 `foreach ($cand in $vscCandidates)` 遍历 null，安装后查找 VS Code 的代码路径静默跳过，全靠兜底。

**原因**：变量从未定义——前面定义了 `$userCandidates` 和 `$systemCandidates`，但 `$vscCandidates` 不存在。

**解决**：在 foreach 前加 `$vscCandidates = @($userCandidates) + @($systemCandidates)`。

**影响文件**：`install-vscode.ps1`
**回合**：第 1 轮

### Bug #15: 桌面快捷方式 `--user-data-dir` 用了错误的环境变量（M2）

**现象**：提权场景下快捷方式指向 `C:\Users\Administrator\AppData\Roaming\Code`，用户双击看不到已安装的扩展。

**原因**：`$shortcut.Arguments` 用了 `$env:APPDATA`，旧流程中会重写为正确用户，新流程未传入 `OriginalUserProfile` 参数时 `$env:APPDATA` 可能是当前（提权后）用户。

**解决**：改为 `$RealAppData`（在 VS Code 启动段中根据 `OriginalUserProfile` 正确计算）。

**影响文件**：`Setup-FlashTap.ps1`
**回合**：第 1 轮

### Bug #16: 安装器始终 `exit 0`，bat 看不到失败（N7）

**现象**：安装中途失败，bat 仍显示"安装成功"。

**原因**：`Setup-FlashTap.ps1` 末尾硬编码 `exit 0`，无论任何步骤失败都返回成功。

**解决**：新增 `$script:installFailed` 标志变量，VS Code 安装失败和全局异常均设置该标志，末尾 `exit $finalExitCode`。

**影响文件**：`Setup-FlashTap.ps1`
**回合**：第 1 轮

### Bug #17: `-Verb RunAsUser` 触发的安全弹窗（P1, 致命交互）

**现象**：VS Code 启动时弹出 Windows "以其他用户的身份运行" 安全窗口，用户点取消则 VS Code 没启动。

**原因**：新流程右键以管理员运行后，脚本以真实用户(61959)+管理员权限运行。`-Verb RunAsUser` 想"降权到当前登录用户"，但当前登录用户就是 61959 自己——Windows 无法降权，弹出用户选择对话框。

**解决**：新增 `$needDeElevate` 判断：仅当 `$OriginalUsername` 与当前用户名不同时才用 `RunAsUser`（旧 Administrator 切换用户场景）；新流程（同用户）跳过。

**影响文件**：`Setup-FlashTap.ps1`
**验证**：第 2 轮复现弹窗，第 3 轮修复生效。
**回合**：第 2 轮

### Bug #18: VS Code 以管理员运行导致 Electron JS 崩溃（P2）

**现象**：VS Code 启动后弹出 "A JavaScript error occurred in the main process"，报错 `r.toLowerCase is not a function`。

**原因**：去掉 RunAsUser 后 VS Code 继承管理员上下文。VS Code 官方不支持管理员运行——Continue 等扩展在提权上下文派生子进程触发 Electron 主进程 JS 崩溃。

**解决**：改为通过 `explorer.exe + .lnk 快捷方式` 中转启动 VS Code。explorer.exe 始终以非提权用户身份运行，通过它打开的 .lnk 文件启动 VS Code 可确保 VS Code 以普通用户权限运行。

**核心代码**：
```powershell
$lnk.TargetPath = $vscExe
$lnk.Arguments = "--locale=zh-cn ..."
$lnk.Save()
Start-Process explorer.exe -ArgumentList $lnkPath
```

**影响文件**：`Setup-FlashTap.ps1`
**验证**：第 3 轮复现崩溃，第 5 轮 explorer 方案通过。
**回合**：第 3 轮

### Bug #19: `--locale=zh-cn` 在两个启动命令中重复传递

**现象**：VS Code 输出 `Option 'locale' is defined more than once. Using value 'zh-cn'.`

**原因**：`$vscArgs` 已包含 `--locale=zh-cn`，`$reuseArgs` 又追加了一次 `--locale=zh-cn`。

**解决**：去掉 `$reuseArgs` 中重复的 `--locale=zh-cn`。

**影响文件**：`Setup-FlashTap.ps1`
**回合**：第 3 轮

### Bug #20: cpptools 安装无超时，网络波动导致流程无限挂死

**现象**：`code --install-extension ms-vscode.cpptools` 调用卡住不返回，整体安装流程挂死在 C++ 环境步骤，等 10 分钟无进展。

**原因**：`setup-cpp-env.ps1` 旧代码用 `& $installer --install-extension cpptools --force 2>&1 | Out-Null`，无超时机制。`code.cmd` 在后台启动 VS Code Server，若连不上 marketplace 可能永不返回。

**解决**：改用 `System.Diagnostics.Process` + `WaitForExit(90000)`，90 秒超时自动 kill 并跳过，不阻塞主流程。

**影响文件**：`setup-cpp-env.ps1`
**验证**：第 5 轮成功，cpptools 29 秒装完。
**回合**：第 5 轮

### Bug #21: F5 编译失败——tasks.json/launch.json 相对路径依赖 PATH

**现象**：VS Code 能打开工作区、能看到 main.cpp，但按 F5 无法编译/调试，提示找不到 g++/gdb。

**原因**：`launch.json` 的 `miDebuggerPath` 写成 `"gdb.exe"`，`tasks.json` 的 `command` 写成 `"g++.exe"`——都是相对路径，依赖 PATH。而 VS Code 通过 explorer.exe 中转启动后，可能未刷新到 `setup-cpp-env.ps1` 刚通过 `setx` 写入的 PATH。

**解决**：改为绝对路径：
- `"miDebuggerPath": "C:\\FlashTap\\mingw64\\bin\\gdb.exe"`
- `"command": "C:\\FlashTap\\mingw64\\bin\\g++.exe"`

**影响文件**：`setup-cpp-env.ps1`
**回合**：第 5 轮（待第 6 轮验证）

### Bug #22: 桌面快捷方式缺 `--locale=zh-cn` 导致双击打开无中文

**现象**：安装后直接启动 VS Code 是中文，但双击桌面的 FlashTap 快捷方式打开是英文。

**原因**：快捷方式 `$shortcut.Arguments` 包含 `--user-data-dir` 但不包含 `--locale=zh-cn`，而直接启动时 `$vscArgs` 包含。

**解决**：在快捷方式参数首部追加 `--locale=zh-cn`。

**影响文件**：`Setup-FlashTap.ps1`
**回合**：第 5 轮
**验证**：第 6 轮通过

### Bug #23: F5 编译仍失败（第 2 次）—`type: shell` Windows 管道路径不匹配

**现象**：g++ 绝对路径已改（Bug #21），但 F5 仍报 "launch: program not exist"。手动编译正常。

**原因**：`tasks.json` 用 `"type": "shell"`，命令经 cmd.exe 管道传递时，变量路径受 shell 引号处理影响，生成路径与 `launch.json` 的 `program` 不匹配。
**历史**：F5 MinGW 编译从未被端到端测试过（《缺陷修复与复测报告》写"F5 C++ 编译未测 | 需 WSL 前提"）。旧设计依赖 WSL，MinGW 是首次开荒。

**解决**：`"type": "shell"` → `"type": "process"`，绕开 shell 直接调 g++。

**影响文件**：`setup-cpp-env.ps1`
**验证**：第 7 轮 F5 编译成功，脚本启动和桌面快捷方式均通过。
**回合**：第 6 轮（修复）、第 7 轮（验证通过）

---

### 7 轮测试总结

| 轮次 | 时间 | 结果 | 关键发现 |
|:--:|------|:--:|------|
| 1 | 15:35 | ✅ 跑通（JS崩溃） | C1/C2/M2/N7 修复、RunAsUser 弹窗 |
| 2 | 15:56 | ✅ 跑通（JS崩溃） | RunAsUser 去掉但引发 P2 |
| 3 | ~16:19 | ❌ VM 重启中断 | C++ 后模型阶段 VM 自动重启 |
| 4 | 16:36 | ❌ 卡死 | cpptools 无超时，code CLI 挂死 |
| 5 | 16:52 | ✅ 全部通过 | explorer 中转方案、cpptools 超时生效 |
| 6 | 17:26 | F5 失败 | 快捷方式中文 ✅，"launch: program not exist" |
| 7 | 17:48 | ✅ 全部通过 | `process` 修复 F5 + 快捷方式中文 + 全部交互通过 |

**核心架构修改**：入口从"自动UAC提权"改为"右键以管理员运行"，消除 R1-R5 根因。
**4 交互缺陷**：RunAsUser 弹窗、JS 崩溃、locale 重复、快捷方式中文。
**2 健壮性缺陷**：cpptools 无超时、退出码恒为0。
**2 F5 编译缺陷**：相对路径（PATH丢失）+ shell 管道（路径不匹配）。
**F5 MinGW 编译是项目史上首次成功**——旧设计依赖 WSL，`缺陷修复与复测报告.md` 标注"F5 C++ 编译未测 | 需 WSL 前提"。