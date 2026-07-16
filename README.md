# FlashTap — 本地 AI 编程助手 一键安装

适配：**RTX 5060 8GB 显存笔记本** | 支持：**Windows 10 / Windows 11** | 全自动安装，无需任何手动操作

---

## 📦 安装前准备（零门槛）

1. ✅ **确认硬件**：你的电脑必须有 **NVIDIA 显卡（8GB+ 显存）**
2. ✅ **不需要**：不需要提前装 Python、不需要装 VS Code、不需要装 Ollama，脚本全部自动搞定

---

## 🚀 傻瓜式安装（一步到位）

1. 把整个 FlashTap 文件夹解压到你想要安装的位置（比如 `D:\FlashTap\`）
2. 找到文件 **`一键安装FlashTap.bat`**
3. **直接双击运行**（脚本会自动请求管理员权限，不需要手动右键）
4. 等待约 15-30 分钟，全程自动完成，不用管

---

## 📁 文件清单

| 文件名 | 说明 |
|--------|------|
| `一键安装FlashTap.bat` | 启动入口，双击即可，自动提权 |
| `Setup-FlashTap.ps1` | 主控制脚本，按顺序执行安装（含 Python 自动安装） |
| `install-flashtap.ps1` | Ollama 安装 + 网络多镜像下载 + 配置 |
| `install-vscode.ps1` | VS Code 静默安装 + 扩展 + 配置文件复制 |
| `download-models.py` | 模型下载部署 |
| `configure-continue.py` | Continue 插件配置 |
| `setup-cpp-env.ps1` | C++ 编译环境配置（可选） |
| `check-environment.ps1` | 安装后环境自检 |
| `settings.json` | VS Code 用户配置 |
| `config.yaml` / `config.json` / `config.ts` | Continue 插件配置 |
| `extensions.list` | 扩展白名单 |

---

## ⚙️ 自动完成了什么

| 步骤 | 内容 |
|------|------|
| 0️⃣ | 自动检测并安装 Python 3.12（如未安装） |
| 1️⃣ | 自动下载并静默安装 Ollama（多镜像源，约 1.4GB） |
| 2️⃣ | 配置显存限制 `OLLAMA_MAX_VRAM=6144` |
| 3️⃣ | 自动下载并静默安装 VS Code（用户级安装） |
| 4️⃣ | 安装 Continue + WSL + 中文语言包 + Code Runner 扩展 |
| 5️⃣ | 复制 settings.json 和 Continue 配置文件 |
| 6️⃣ | 下载 Qwen2.5-Coder 7B 代码模型（约 4GB） |
| 7️⃣ | 启动 Ollama 服务，验证模型可用 |
| 8️⃣ | 环境自检，输出检测结果 |

---

## ✅ 安装完成后怎么用

1. 打开 VS Code
2. 按 `Ctrl+Shift+P`，输入 `Continue: Open Chat`
3. 开始用 FlashTap 写代码！

快捷键：默认 `Ctrl+L` 打开对话

---

## ❌ 常见问题及解决方法

### Q1: 一闪就没了（闪退）

**原因**：脚本运行异常，查看日志定位问题

**解决**：
1. 确保直接双击运行，不要右键管理员（脚本会自动提权）
2. 查看 `install.log` 和 `vscode-install.log` 日志文件，看最后几行的错误信息
3. 如果提示下载失败，检查网络连接

---

### Q2: Ollama 下载太慢或失败

**原因**：GitHub 在国内不稳定

**解决**：
- 脚本已内置 6 个镜像源，会自动切换尝试
- 也可以提前下载 `OllamaSetup.exe`（约 1.4GB），放在脚本同目录即可跳过下载
- 下载地址：https://ollama.com/download/OllamaSetup.exe

---

### Q3: 模型下载慢

**原因**：网络问题

**说明**：脚本自动使用国内源，支持断点续传。如果中断，重新运行即可继续下载。

---

### Q4: VS Code 安装失败（退出码 5）

**原因**：VS Code 正在运行，文件被锁定

**解决**：关闭所有 VS Code 窗口后重新运行脚本

---

### Q5: 显存溢出报错

**原因**：显卡显存不足

**解决**：
- 本项目需要 8GB+ 显存
- 确认 `OLLAMA_MAX_VRAM` 环境变量已设置为 `6144`

---

### Q6: 提示 "磁盘空间不足"

**原因**：模型 + Ollama + VS Code 大约需要 20GB 空间

**解决**：换个空间够的磁盘放 FlashTap 文件夹

---

## 🔧 技术细节

- 模型：Qwen2.5-Coder-7B-Instruct（约 4GB）
- 推理：Ollama 本地运行，不连外网
- 前端：VS Code + Continue.dev 扩展
- 安装方式：Ollama 多镜像源下载（6 个镜像自动切换），VS Code 直连官方
- Python：自动安装 3.12.7（python.org + 华为镜像兜底）
- 安全：不修改系统全局执行策略，只在当前进程绕过，用完即走

---

## 📝 许可证

MIT