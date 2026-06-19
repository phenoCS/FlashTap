#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
为 LocalCoder 配置 Continue 插件，使用本地 Ollama 模型。
同时写入 config.json（Continue 0.8+ 新版格式）和 config.yaml（旧版兼容）。
"""

import json
import sys
import shutil
import traceback
from pathlib import Path
from datetime import datetime

BASE_DIR = Path(__file__).parent.resolve()
LOG_FILE = BASE_DIR / "configure.log"

# ── 新版 JSON 配置（Continue 0.8+ 使用 config.json，字段 title 替 name） ──
# 参考：https://docs.continue.dev/reference/config
CONFIG_JSON = {
    "models": [
        {
            "title": "Autodetect",
            "provider": "ollama",
            "model": "AUTODETECT"
        }
    ],
    "tabAutocompleteModel": {
        "title": "Autodetect",
        "provider": "ollama",
        "model": "AUTODETECT"
    },
    "allowAnonymousTelemetry": False
}

# ── 旧版 YAML 配置（Continue <0.8 向后兼容，使用 name 字段） ──
CONFIG_YAML = """name: LocalCoder
version: 1.0.0
schema: v1
models:
  - name: Autodetect
    provider: ollama
    model: AUTODETECT
allowAnonymousTelemetry: false
"""


def write_log(message: str, level: str = "INFO"):
    timestamp = datetime.now().strftime("%H:%M:%S")
    log_line = f"[{timestamp}] {message}"
    try:
        print(log_line)
    except UnicodeEncodeError:
        print(log_line.encode("ascii", errors="replace").decode("ascii"))
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(log_line + "\n")
    except Exception:
        pass


def configure():
    write_log("正在配置 Continue 插件...")
    home_dir = Path.home()
    config_dir = home_dir / ".continue"

    if not config_dir.exists():
        config_dir.mkdir(parents=True, exist_ok=True)
        write_log("已创建配置目录")

    config_json_file = config_dir / "config.json"
    config_yaml_file = config_dir / "config.yaml"
    config_ts_file = config_dir / "config.ts"

    # 备份现有配置
    for cf in [config_json_file, config_yaml_file, config_ts_file]:
        if cf.exists():
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_file = config_dir / f"{cf.name}.backup.{timestamp}"
                shutil.copy2(cf, backup_file)
                write_log(f"已备份 {cf.name}")
            except Exception as e:
                write_log(f"备份 {cf.name} 失败: {e}")

    # 写入新版 JSON 配置（Continue 0.8+ 优先读取）
    try:
        with open(config_json_file, "w", encoding="utf-8") as f:
            json.dump(CONFIG_JSON, f, indent=2, ensure_ascii=False)
        write_log("config.json 已写入（Continue 新版格式，title 字段）")
    except Exception as e:
        write_log(f"config.json 写入失败: {e}")

    # 写入旧版 YAML 配置（Continue <0.8 兼容）
    try:
        with open(config_yaml_file, "w", encoding="utf-8") as f:
            f.write(CONFIG_YAML)
        write_log("config.yaml 已写入（Continue 旧版兼容格式）")
    except Exception as e:
        write_log(f"config.yaml 写入失败: {e}")

    # 写入 TypeScript 配置（Continue 1.0+ 格式，兼容最新版本）
    config_ts_content = '''export function modifyConfig(config) {
    config.models = [
        {
            title: "Autodetect",
            provider: "ollama",
            model: "AUTODETECT"
        }
    ];
    config.tabAutocompleteModel = {
        title: "Autodetect",
        provider: "ollama",
        model: "AUTODETECT"
    };
    return config;
}
'''
    try:
        with open(config_ts_file, "w", encoding="utf-8") as f:
            f.write(config_ts_content)
        write_log("config.ts 已写入（Continue 1.0+ 最新格式）")
    except Exception as e:
        write_log(f"config.ts 写入失败: {e}")

    # ── 验证配置 ──
    write_log("正在验证配置...")
    errors = []
    for cf in [config_json_file, config_yaml_file, config_ts_file]:
        if cf.exists():
            content = cf.read_text(encoding="utf-8")
            if "AUTODETECT" in content and "ollama" in content:
                write_log(f"  [OK] {cf.name} 验证通过")
            else:
                errors.append(f"{cf.name} 内容不完整")
        else:
            errors.append(f"{cf.name} 未生成")

    if errors:
        write_log(f"配置验证发现问题: {', '.join(errors)}")
    else:
        write_log("Continue 配置验证全部通过")


def main():
    write_log("=" * 50)
    write_log("LocalCoder Continue 配置")
    write_log("=" * 50)

    try:
        configure()
        write_log("启动 VS Code 后按 Ctrl+L 唤起 Continue 面板开始使用")
        return 0
    except Exception as e:
        write_log(f"配置失败: {e}")
        write_log("异常堆栈（用于排查）:")
        for line in traceback.format_exc().strip().split('\n'):
            write_log(f"  {line}")
        return 1
    finally:
        write_log("配置脚本退出")
        sys.stdout.flush()
        sys.stderr.flush()


if __name__ == "__main__":
    sys.exit(main())