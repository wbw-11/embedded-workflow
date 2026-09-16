---
name: local-ocr-npu
description: "本地 NPU OCR：图片/截图/发票/文档文字提取(中英混)。离线、批量 OCR、验证码。"
version: 1.0.0
---
# 本地NPU OCR文字识别

## 概述

从图片中识别文字（中英文混合）。使用 Intel NPU 本地推理，无需联网。支持单张图片或整个目录批量识别。基于 PP-OCRv5-server 高精度模型。

**使用时机：**
- 需要识别图片中的文字时
- 需要提取截图中的文字内容时
- 需要OCR识别发票、文档上的文字时

**硬件要求：**
- 需要 Intel NPU 硬件支持（Core Ultra系列）
- 内存需求：1GB以上

## 首次部署（一次性）

在技能 scripts/ 目录下执行：

```powershell
# 1. 下载 PP-OCRv5-server 模型（首次耗时较长）
powershell -ExecutionPolicy Bypass -File scripts\download.ps1
```

## 启动服务

```powershell
# 2. 启动本地 NPU OCR 服务（阻塞运行）
powershell -ExecutionPolicy Bypass -File scripts\run.ps1
```

## 自检

```powershell
# 3. 验证服务可用性（可选）
powershell -ExecutionPolicy Bypass -File scripts\test.ps1
```

## 使用

用户提供图片路径后：

- 单张图片：识别其中全部文字（中英文混合）
- 目录批量：逐个识别目录内所有图片，结果汇总

识别结果按图片命名整理输出，供后续提取发票、文档或截图内容使用。

## 维护

- 模型丢失/损坏：重新执行 download.ps1
- 换机部署：重复"首次部署"步骤
