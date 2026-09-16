---
name: knowledge-index
description: "跨项目知识索引搜索：从各项目 project_memory 提取引脚表/踩坑/配置/接线建索引。问「哪个项目类似」「现成串口配置」时调用。"
version: 1.0.0
---

# 跨项目知识索引

## 适用场景

- 用户问"之前哪个项目遇到过 I2C 不通的问题"
- 新项目启动时，查找类似项目的引脚配置
- 遇到某个坑，想知道之前有没有踩过
- 项目总结时，汇总所有项目的踩坑记录

## 脚本位置

`$env:USERPROFILE\Tools\knowledge-index.ps1`

## 使用方法

### 建立/更新索引

```powershell
knowledge-index -Index
```

扫描 `$projectsDir`（脚本内配置，默认 `$env:USERPROFILE\Projects`）下所有 project_memory.md，提取以下章节：
- 引脚分配表
- 踩坑记录
- 配置说明
- 硬件连接

索引保存到 `$env:TEMP\knowledge_index.json`。

### 搜索知识

```powershell
knowledge-index -Search "串口"
knowledge-index -Search "DMA"
knowledge-index -Search "看门狗"
```

搜索匹配行高亮显示，输出项目名、文件路径和相关上下文。

### 列出所有索引

```powershell
knowledge-index -List
```

显示各分类的记录数和项目列表。

### 生成知识汇总报告

```powershell
knowledge-index -Report
```

输出 `knowledge_report.md`，汇总所有项目的踩坑记录和引脚配置。

## 知识提取规则

从 project_memory.md 中按 `## 章节标题` 提取以下部分：

| 章节 | 提取内容 |
|------|----------|
| `## 引脚分配表` | GPIO 编号和用途映射 |
| `## 踩坑记录` | 问题描述、原因、解决方案 |
| `## 配置说明` | 编译配置、menuconfig 设置 |
| `## 硬件连接` | 外设接线关系 |

## 与 AI 的协作流程

当用户遇到嵌入式问题且可能之前有经验时：

1. **先搜索知识库**：
```powershell
knowledge-index -Search "<关键词>"
```

2. **如果有匹配结果**：
   - 告诉用户哪个项目遇到过类似问题
   - 展示之前的解决方案
   - 读取对应的 project_memory.md 获取完整上下文

3. **如果无匹配**：
   - 告知用户这是新问题
   - 解决后将经验写入当前项目的 project_memory.md
   - 重新运行 `-Index` 更新全局索引

## 索引维护建议

- 每完成一个项目功能模块后运行 `-Index` 更新
- 新项目创建后运行一次 `-Index`
- 索引文件在 `$env:TEMP`，重启后丢失，需重新建立

## Pitfalls

- 默认搜索 `$projectsDir` 目录（脚本内配置），如果项目在其他位置需修改脚本中的变量值
- 搜索是正则匹配，特殊字符需要转义
- 索引只包含 project_memory.md 中的内容，代码注释中的知识不会被索引
- 搜索结果默认最多显示 10 行上下文，完整内容需直接读取源文件

## Verification

- `-List` 输出的项目数与实际项目数一致
- `-Search` 结果能通过直接打开对应 project_memory.md 验证
