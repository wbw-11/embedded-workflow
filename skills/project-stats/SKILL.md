---
name: project-stats
description: "代码统计：行数/注释率/模块分布/最大文件。自动识别 ESP-IDF/Keil ARM/Keil C51/通用 C。"
version: 1.0.0
---

# 项目代码统计

## 适用场景

- 用户问"这个项目有多少行代码"
- 需要评估项目规模或代码质量
- 项目总结/交付时需要统计数据
- 代码审查时关注注释率和大文件

## 脚本位置

`$env:USERPROFILE\Tools\project-stats.ps1`

## 使用方法

```powershell
# 统计当前目录
project-stats

# 指定项目路径
project-stats -Path "<项目目录>"

# 显示每个文件的详细统计
project-stats -Detail

# 显示 Top 10 最大文件
project-stats -Top 10
```

## 输出解读

### 统计维度

| 维度 | 说明 |
|------|------|
| 文件统计 | 按文件类型（.c/.h/.cpp/.s/.py）分别统计数量和行数 |
| 代码质量 | 代码行/注释行/空行数量及占比，注释率进度条 |
| 模块分布 | 按目录统计代码分布（components/xxx、main 等） |
| Top N 最大文件 | 行数最多的文件列表 |
| 项目体积 | 总文件大小和文件数 |

### 注释率评估

| 注释率 | 评价 |
|--------|------|
| < 5% | 严重不足，需补充注释 |
| 5-15% | 偏低，建议关键模块补充 |
| 15-30% | 合理 |
| > 30% | 良好 |

### 排除规则

自动排除 build/、.git/、.vscode/、Debug/、Release/、Objects/、managed_components/ 等目录。

## 项目类型自动识别

| 标志 | 识别为 |
|------|--------|
| sdkconfig / idf_component_register | ESP-IDF |
| .uvprojx | Keil ARM |
| .uvproj | Keil C51 |
| 有 .c/.h 文件 | 通用 C |

## 与 AI 的协作流程

1. **运行统计**：
```powershell
cd <项目目录>
project-stats
```

2. **解读结果并给出建议**：
   - 注释率低 → 建议补充关键模块注释
   - 单个文件过大（>1000行）→ 建议拆分
   - 模块分布不均 → 建议重构

3. **写入 project_memory.md**：将统计摘要追加到项目记录中

## Pitfalls

- 深度中文路径下正常（使用 .NET IO）
- 大型项目（1000+文件）统计可能需要几秒
- 注释率只统计 C/C++/Python 注释，不统计文档文件
- `/* */` 块注释和 `//` 行注释都能正确识别

## Verification

- 总行数 = 代码行 + 注释行 + 空行
- 模块分布占比合计约 100%
