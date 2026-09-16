---
name: local-img2img
description: 基于本地AI大模型的图片修改与图生图(仅限英特尔AIPC平台)
version: 1.0.0
---

# 本地图生图

## 概述

根据输入图片和文字提示在本地修改图片。首次自动下载FLUX.2-klein量化模型并构建运行环境，保持服务进程常驻以支持快速重复编辑。

**使用时机：**
- 需要修改图片内容时
- 需要风格转换时
- 需要根据文字描述生成或修改图片时

**硬件要求：**
- 仅限英特尔AIPC平台（需要NPU支持）
- 内存需求：8.5GB以上

## 首次部署（一次性）

在技能 scripts/ 目录下执行（RunCommand，PowerShell）：

```powershell
# 1. 创建虚拟环境并安装依赖（生成 venv 目录 + 安装 requirements.txt）
powershell -ExecutionPolicy Bypass -File scripts\install-env.ps1
```

> install-env.ps1 行为：`python -m venv t2i-tts` → 激活 → `pip install -r requirements.txt`。
> 模型下载逻辑见 scripts\model_download.py；下载失败时重试或按脚本约定手动放置模型。

## 启动服务

```powershell
# 2. 启动常驻服务（阻塞运行，成功后保持该终端）
powershell -ExecutionPolicy Bypass -File scripts\run.ps1
```

> run.ps1 激活 venv 后执行 `python server.py`。服务常驻后可多次提交图片编辑请求，无需重复启动。

## 使用

用户提供图片路径 + 文字提示后，向本地服务提交：

- 图片修改（改内容 / 换背景 / 换风格）
- 图生图（按描述生成同题材新图）

返回的新图片落盘到约定输出位置并展示给用户。

## 维护

- 服务异常：先停掉旧进程，再重新运行 run.ps1
- 换机部署：重复"首次部署"步骤，模型会自动重新下载
