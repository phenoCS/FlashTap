# FlashTap · 半离线本地 AI 编程环境部署包（说明文档）

> **本文档面向接手者 / 维护者。** 讲清四件事：这是什么、目标是什么、**半离线到底"半"在哪**、以及**稳定性与已知坑（最重要，避免重蹈覆辙）**。
> 旧的 README 已废弃（其中 WSL / RTX 5060 / D 盘等描述均已过时，请勿参考）。

---

## 一、这是什么（项目定位）

一个**一键部署本地 AI 编程助手**的安装包。面向一张**干净的 Windows 10 / 11**（没有 Python、没有 VS Code、没有 Ollama），用户只双击一个 `.bat`，约 15–30 分钟后得到：

| 产物 | 说明 |
|------|------|
| VS Code | 用户级静默安装 |
| Continue 插件 | 本地 AI 编程前端（对话 / 补全） |
| Qwen2.5-Coder-7B 模型 | 经 ollama 本地运行，代码不出本机 |
| 原生 C++ 编译环境 | MinGW-w64（GCC + GDB），替代 WSL，F5 直接编译调试 |

**核心价值**：装完之后 AI 推理 100% 本地，敏感代码不上云。

---

## 二、目标

1. **零命令行**：用户只需双击 `一键安装FlashTap.bat`，UAC 点"是"，全程不用敲命令。
2. **本地优先**：AI 推理走 `ollama + Qwen GGUF`，不连任何外部 API。
3. **半离线可部署**：关键大件（模型 / VS Code / Ollama / MinGW）允许**预置离线包**，弱网或断网也能装。
4. **安全**：不修改系统全局 PowerShell 执行策略（仅当前进程 `-ExecutionPolicy Bypass`），不驻留后台服务，不留全局环境变量污染。

---

## 三、什么是"半离线包"（边界说明）

"半离线"指：**联网能装，断网/弱网也能装，前提是提前把大件放进包里**。具体边界：

| 组件 | 离线方式（预置到 FlashTap 根目录） | 不预置时 |
|------|--------------------------------------|-----------|
| **模型** | `models/` 下放入 GGUF（如 `qwen2.5-coder-7b-instruct-q4_k_m.gguf`）+ `Modelfile.qwen` | 脚本用 `download-models.py` 从 ModelScope 拉（国内源，支持断点续传） |
| **VS Code** | 放入 `VSCodeUserSetup-*.exe` | 联网从官方下载 |
| **Ollama** | 放入 `OllamaSetup.exe` | 联网下载（内置多镜像源自动切换） |
| **MinGW-w64** | 放入 `mingw64.zip` / `mingw64.7z` | 联网下载并解压到 `C:\FlashTap\mingw64` |
| **VS Code 扩展**（Continue / 中文包 / Code Runner） | ❌ **不支持离线**，必须联网从 Marketplace / open-vsx 安装 | 联网安装 |

> 约定：离线包放好后，脚本会自动检测并使用，**跳过对应联网下载**。具体识别的文件名以各安装脚本中的检测逻辑为准。
> 最简"真·离线"条件：模型 GGUF + VS Code 安装器 + OllamaSetup + MinGW 包全部预置，且目标机能联网装扩展。

---

## 四、正确的安装姿势（务必看）

**统一入口：右键 → 以管理员方式运行**

| 操作 | 结果 |
|------|------|
| **右键** `一键安装FlashTap.bat` → **"以管理员方式运行"** | ✅ 正确入口。脚本以真实用户 + 管理员权限运行，扩展/配置自动装到正确用户目录。 |
| **双击** `一键安装FlashTap.bat` | ❌ 会提示"没有管理员权限"，无法继续。**请关闭后右键管理员运行。** |

> 为什么不用双击自动提权：旧版双击自动 UAC 提权方案依赖 VirtualBox 共享文件夹路径硬编码，在非 VM 环境会静默失败。统一为右键管理员运行后，无论在 VM、物理机、远程桌面都稳定。
> 2026-07-22 重构详情见 `DEVLOG.md` Bug #13–#18。

**安装中注意**：
- 必须**管理员权限**跑（`install.log` 首行 `[诊断] 管理员权限: 是`）。普通用户下 C++ 配置无法写系统 PATH，会失败。
- 主终端跑完前**不要关窗口**（约 15–20 分钟，含模型导入）。
- 安装完成**通过桌面"FlashTap"快捷方式**启动 VS Code（已预置打开 `C:\FlashTap\cpp-workspace`，含中文界面）。

---

## 五、自动完成的内容（顺序）

| 步 | 内容 |
|----|------|
| 0 | 检测并自动安装 Python 3.12（未装时；python.org + 华为镜像兜底） |
| 1 | 安装 Ollama（多镜像源，约 1.4GB）；设置显存上限 `OLLAMA_MAX_VRAM`（按显存选型，8GB 显存机用 `6144`） |
| 2 | 静默安装 VS Code（用户级） |
| 3 | 安装扩展：Continue、VS Code 中文语言包、Code Runner（扩展列表见 `extensions.list`） |
| 4 | 配置 Continue（`config.json/.ts/.yaml`，无条件 `AUTODETECT + ollama`，端口 11434） |
| 5 | 配置 C++ 编译环境：**Windows 原生 MinGW-w64**（不再依赖 WSL） |
| 6 | 拉取 / 导入 Qwen2.5-Coder-7B 模型，启动 Ollama 服务并验证可用 |
| 7 | 关闭 VS Code 工作区信任 + 创建桌面快捷方式 |
| 8 | `check-environment.ps1` 自检，输出结果 |

---

## 六、项目文件结构

```
flashtap_V0.01 - 副本/
│
├── 一键安装FlashTap.bat          ← 入口（右键→以管理员运行）
│
├── 【核心脚本】
├── Setup-FlashTap.ps1             ← 主编排脚本，按序调用各子脚本
├── install-flashtap.ps1           ← Ollama 安装 + 多镜像下载 + 配置
├── install-vscode.ps1             ← VS Code 静默安装 + 扩展 + 配置
├── setup-cpp-env.ps1              ← C++ 编译环境（MinGW-w64 GCC/GDB）
├── check-environment.ps1          ← 安装后环境自检
├── preflight-check.ps1            ← 网络可达性预检
│
├── 【Python 辅助脚本】
├── download-models.py             ← 模型下载 / 导入（ModelScope，断点续传）
├── configure-continue.py          ← Continue 插件配置生成
│
├── 【Continue 配置（三件套，AUTODETECT + ollama）】
├── config.json
├── config.ts
├── config.yaml
├── continue-config.json
├── continue-config.ts
│
├── 【VS Code 配置】
├── settings.json                  ← 工作区信任禁用 + 默认设置
├── extensions.list                ← 扩展白名单（仅装白名单内扩展）
│
├── 【离线包（可选，预置则跳过联网下载）】
├── mingw64.zip                    ← MinGW-w64 编译环境
├── VSCodeUserSetup-*.exe          ← VS Code 安装器
├── OllamaSetup.exe                ← Ollama 安装器
├── models/                        ← 离线模型（GGUF + Modelfile）
│   └── *.gguf / Modelfile.*
│
├── 【文档】
├── README.md                      ← 本文档（项目说明 + 稳定性 + 故障排查）
├── DEVLOG.md                      ← 开发日志（Bug #1–#23 完整记录）
├── flashtap开发思路.md            ← 设计哲学与取舍
├── Agent-VM协同测试工作流.md      ← Agent + VM 协同测试方法论
├── VM测试环境与全流程接手文档.md  ← VM 环境配置 + 快照 + 接手流程
├── 历史测试与修复记录.md          ← 2026-07-21~22 测试记录合并
└── 项目状态.txt                   ← 当前状态摘要
```

| 文档 | 用途 |
|------|------|
| `README.md` | **入门首选**：项目是什么、怎么装、已知坑、故障排查 |
| `DEVLOG.md` | **开发参考**：每个 bug 的根因、修复方案、影响文件 |
| `Agent-VM协同测试工作流.md` | **测试方法论**：Agent + 人类如何通过 VM 协同迭代 |
| `VM测试环境与全流程接手文档.md` | **环境交接**：VM 配置、快照、共享文件夹、guestcontrol 命令 |
| `历史测试与修复记录.md` | **历史档案**：早期测试报告与静态审查的合并记录 |

---

## 七、稳定性与已知问题（**最重要的一节**）

### A. 已修复的历史坑（接手者请勿再犯）

#### 🔴 A1. VS Code 打开后"只能看代码、所有功能用不了"（受限模式 / 保护模式）
- **现象**：桌面快捷方式启动 VS Code，扩展（Continue、C/C++）全被禁用，仅能浏览代码。
- **根因（双重）**：
  1. `Setup-FlashTap.ps1` 曾声称"已关闭工作区信任（settings.json）"，但**从未真正写入** `security.workspace.trust.enabled: false`。
  2. 更隐蔽：**主安装脚本是提权（Administrator）运行的**，脚本里写 VS Code 用户配置用的是 `$env:APPDATA` / `$env:USERPROFILE`，这些变量指向 **Administrator 目录**；而 VS Code 实际是以**普通用户**（`-Verb RunAsUser`）启动并读取**该普通用户**的 `Code\User\settings.json`。于是配置"写了但不生效"。
- **修复**（2026-07-22）：新增 `$RealUserProfile` / `$RealAppData`（取 `OriginalUserProfile` 参数，即真正运行 VS Code 的用户），所有用户级路径改用之，并**真正写入** `security.workspace.trust.enabled: false` 到该用户目录。
- **后人注意**：凡涉及 VS Code 用户级配置、扩展目录，绝不能用 `$env:USERPROFILE` / `$env:APPDATA`，一律用 `$RealUserProfile` / `$RealAppData`。

#### 🔴 A2. C++ 配置失败导致整个安装中断、VS Code 不启动
- **现象**："啥也没弹出来"，`install.log` 末行为 `脚本退出码: 1`，`cpp-env.log` 显示 C++ 配置失败。
- **根因**：`Setup-FlashTap.ps1` 在 C++ 配置失败时 `exit 1`，主流程直接中断，根本走不到"启动 VS Code"。
- **修复**（2026-07-22）：C++ 失败改为**仅告警、不中断**，保证 VS Code + 本地 AI 对话仍可用；F5 调试可在补齐 `mingw64.zip` 后重跑补全。
- **后人注意**：VS Code + 本地推理是核心功能，不应被可选项的失败阻断。

#### 🟠 A3. 扩展安装曾整批失败（参数传递 bug）
- **现象**：`--install-extension` 把 4 个扩展名当**一个字符串**传入，全部安装失败（DEVLOG Bug#11）。
- **状态**：已修复（逐条传参）。`extensions.list` 当前为：`continue.continue` / `ms-ceintl.vscode-language-pack-zh-hans` / `ms-vscode-remote.remote-wsl` / `formulahendry.code-runner`。
- **注意**：`remote-wsl` 是为旧 WSL 方案遗留的，当前 C++ 已改**原生 MinGW-w64**，该扩展实际已不使用，可保留不影响。

### B. 已知设计限制（非 bug，按需取舍）

- **扩展必须联网安装**：Continue / 中文包 / Code Runner 无离线机制，部署机需能连 Marketplace。
- **模型选型与显存**：默认 Qwen2.5-Coder-7B `q4_k_m` 量化约 4–5GB 显存，需 8GB+ 显存；小显存机型需换更小模型（改 `download-models.py` 的 `QWEN_MODEL_FILE` 与 Continue 配置）。
- **磁盘空间**：模型 + Ollama + VS Code 合计约 20GB+，安装目录所在盘需留足。
- **WSL 方案已废弃**：早期版本走"WSL + Ubuntu + 远端 C/C++ 扩展"，复杂且易失败；现统一为 **Windows 原生 MinGW-w64（GCC + GDB）**，F5 直接在 Windows 端编译调试，无需 WSL、无需 Visual Studio。

---

## 八、故障排查速查

| 现象 | 优先检查 |
|------|----------|
| 提示"没有管理员权限" | 关闭窗口 → 右键 `一键安装FlashTap.bat` → 以管理员方式运行 |
| VS Code 没弹出 | 看 `install.log` 末尾：是否出现 `[错误] VS Code 启动失败` |
| VS Code 能开但"只能看代码" | 受限模式：打开后点顶部黄色横幅"**信任此文件夹**"；或重装（已修工作区信任） |
| VS Code 弹 JS 错误弹窗 | 说明以管理员身份启动了 VS Code（非推荐方式）；从桌面快捷方式打开即可正常 |
| 扩展装不上 | 是否联网？Continue 等必须联网装 |
| F5 编译失败 | 检查 `C:\FlashTap\mingw64\bin\g++.exe` 是否存在；检查 `launch.json`/`tasks.json` 是否用绝对路径 |
| 模型验证警告 | 多半是 Ollama 那一瞬间未响应；确认 `http://localhost:11434` 能返回模型列表即可 |
| 下载慢/失败 | 预置对应离线包到 FlashTap 根目录（见第三节） |

**关键日志位置**（均在 FlashTap 根目录，随共享文件夹实时同步）：
`install.log`（主流程）、`cpp-env.log`（C++/MinGW）、`download.log`（模型）、`vscode-install.log`、`configure.log`。

---

## 九、给维护者的注意事项

1. **改动前先读 `DEVLOG.md`**，里面记录了 Bug #1–#23 的完整修复历史；本 README 第七节是其浓缩版。
2. **用户级路径陷阱**（见 A1）：任何写 VS Code 用户配置 / 扩展目录的代码，都用 `$RealUserProfile` / `$RealAppData`，**不要用 `$env:USERPROFILE` / `$env:APPDATA`**。
3. **不要改回 WSL 方案**：MinGW-w64 是当前稳定路径。
4. **不要因可选项失败而 `exit` 中断主流程**：核心交付物是 VS Code + 本地 AI 对话。
5. **扩展白名单**以 `extensions.list` 为准，脚本只装清单内扩展，绝不卸载用户已有扩展。
6. **安全底线**：保持"仅当前进程绕过执行策略、不驻留后台、不污染全局环境"，这是该包能在受限环境部署的前提。
7. **修改后必须同步到 `C:\flashtap`**：桌面副本是工作区，`C:\flashtap` 是 VM 共享源。同步命令见 `Agent-VM协同测试工作流.md` 或 `VM测试环境与全流程接手文档.md`。
8. **桌面上有两个 flashtap 文件夹**：`flashtap_V0.01`（旧版废弃）和 `flashtap_V0.01 - 副本`（当前工作区）。同步时务必确认路径，详见 `VM测试环境与全流程接手文档.md` 0.1 节。

---

## 附：许可证

MIT
