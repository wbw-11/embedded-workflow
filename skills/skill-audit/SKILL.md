---
name: skill-audit
description: "技能库审查修补：扫描硬编码路径/内容重复/超长短文件/编码，按优先级修复。「审查技能」「skill audit」时调用。"
version: 1.0.0
---

# 技能库质量审查与批量修补

## 适用场景

- 用户要求"审查技能"、"整理技能库"、"检查技能质量"
- 技能数量增长后定期体检（建议每新增 5-10 个技能跑一次）
- 换机器前检查所有技能是否可移植（无硬编码路径）
- 用户反馈某个技能不生效，排查 description 触发词覆盖问题

## 审查流程

### 第一步：扫描与编码检测

```powershell
# 获取所有技能文件
# 技能根目录：.trae-cn 优先，兼容历史 .qoderworkcn
$skillRoot = @(
    "$env:USERPROFILE\.trae-cn\skills",
    "$env:USERPROFILE\.qoderworkcn\skills"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$skillFiles = Get-ChildItem "$skillRoot\*\SKILL.md"

# 统计行数 + 检测编码
foreach ($f in $skillFiles) {
    $lines = (Get-Content $f.FullName).Count
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    # 检查 BOM 或尝试 UTF-8 解码是否出现乱码
    $isUtf8 = $true
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $null = $utf8.GetString($bytes)
    } catch { $isUtf8 = $false }
    Write-Output "$($f.Directory.Name) | $lines 行 | $(if($isUtf8){'UTF-8'}else{'非UTF-8(可能GB2312)'})"
}
```

记录每个技能的：名称、行数、编码格式。

### 第二步：子代理批量评审

用 Agent 工具并行审查（每批 8-12 个技能），每个技能检查 5 个维度：

| 维度 | 检查内容 | 判定标准 |
|------|----------|----------|
| 结构完整性 | frontmatter（name/description/version）、步骤、陷阱、验证 | 缺少 frontmatter 或无实际步骤 = 不合格 |
| 硬编码路径 | 搜索 `C:\Users\具体用户名`、`D:\具体目录` 等绝对路径 | 存在即标记（环境变量引用除外） |
| 内容重复 | 与其他技能共享大段相同内容（配置表、命令列表） | 相同内容 >10 行即标记 |
| 篇幅合理性 | 行数统计 | <30 行过短（可能空壳），>500 行过长（应拆分） |
| description 质量 | 触发词覆盖、第三人称、具体场景 | 过于笼统或缺少触发关键词 = 需优化 |

子代理 prompt 模板：

```
请阅读以下技能文件，对每个技能按 5 个维度评分（通过/警告/不合格）并给出具体问题描述：
1. 结构完整性 2. 硬编码路径 3. 内容重复 4. 篇幅合理性 5. description 质量
输出格式：技能名 | 维度 | 状态 | 问题描述
```

### 第三步：问题分类（P0-P3）

按严重程度排序：

- **P0（无法使用）**：文件为空壳（<30行无实质内容）、frontmatter 缺失、编码损坏
- **P1（换机器失效/严重影响体验）**：硬编码绝对路径、超长文件（>1000行）导致加载慢
- **P2（维护隐患）**：内容重复（多处维护同一数据）、description 触发词不足
- **P3（建议优化）**：篇幅偏长（500-1000行可拆分）、缺少验证步骤、缺少陷阱段落

输出审查报告给用户确认后再动手修补。

### 第四步：逐项修补（编码策略选择）

**关键决策点：根据文件编码选择修补方式。**（2026-09-02 实测：本环境 Edit 工具仅限工作目录内文件，`.trae-cn/skills` 下技能必须用 PowerShell 可靠替换法。）

#### 工作目录内的文件 → 可直接用 Edit 工具

- 在项目工作区内的技能文件可用 Edit 精确替换（old_string 带 3+ 行上下文确保唯一）
- `.trae-cn` / `.qoderworkcn` / `C:\Users\...\Tools` 等目录 → Edit 报 Access denied，必须走下面的 PowerShell 方案

#### 任意文件通用 → PowerShell 可靠替换法（推荐，唯一稳妥路径）

```powershell
# ① 精确字符串替换（UTF-8 无损，保留原 BOM 状态）
$p = '<SKILL.md 路径>'
$bytes = [System.IO.File]::ReadAllBytes($p)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text = [System.IO.File]::ReadAllText($p)
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }   # 先探测原换行符
$old = '<精确匹配文本，用原文换行符拼接>'
$new = '<新文本>'
$cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($cnt -ne 1) { throw "匹配数 $cnt ≠ 1，禁止写入！" }       # 替换计数校验，防改错位置
$enc = New-Object System.Text.UTF8Encoding($hasBom)
[System.IO.File]::WriteAllText($p, $text.Replace($old, $new), $enc)
```

```powershell
# ② 行级插入/删除（按 `---` 定位 frontmatter 结束，避免中文匹配问题）
$lines = [System.IO.File]::ReadAllLines($p)
$idx = -1; for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '---') { $idx = $i; break } }
# 新数组用 `+=` 拼接（示例：在 $idx 前插入一行）
$newLines = @(); $newLines += $lines[0..($idx-1)]; $newLines += 'version: 1.0.0'; $newLines += $lines[$idx..($lines.Count-1)]
[System.IO.File]::WriteAllText($p, (($newLines -join $nl) + $nl), $enc)
```

注意事项（2026-09-02 实测踩坑，全部真实发生）：
- **数组拼接禁 AddRange**：`List[string].AddRange($object[])` 报类型转换错误且 RemoveRange 已删行→内容丢失。一律用 `+=` 拼接新数组
- **换行符先探测**：CRLF 文件用 "`n" 拼 old 字符串必然匹配数 0；用 Contains("`r`n") 判 CRLF/LF
- **双引号内变量后接冒号/字母**："$nl" 后接 "version:" 会把冒号解析进变量名报 ParserError，必须写 "${nl}"
- **反引号转义**：双引号字符串中 "`v" 是垂直制表符（写 version 变成不可见 VT + ersion）；要写代码块标记用单引号 '```'
- **改完必须重读验证**：WriteAllText+Replace 是单点修改首选；批量整篇处理才用 WriteAllLines（会统一换行风格）

#### 非 UTF-8 文件（GB2312/GBK）→ 全量重写（顺带转 UTF-8）

1. 先用 Read 工具读取完整内容（Read 能正确识别多种编码）
2. 修改后在 PowerShell 中用 `New-Object System.Text.UTF8Encoding($false)` 写入（无 BOM UTF-8）
3. 写入后重读验证中文无乱码
#### 超长文件拆分

对于 >500 行的技能：
1. 保留核心工作流在 SKILL.md（目标 150-250 行）
2. 将详细参考（命令列表、配置表、完整示例）移到同目录 reference.md
3. 在 SKILL.md 中注明"完整参考见同目录 reference.md"

### 第五步：去重

当两个或多个技能维护相同数据时：

1. **指定权威来源**：选择最完整、最常被引用的技能作为权威
2. **修改非权威方**：删除重复内容，替换为引用说明

```markdown
> 权威配置表维护在 **memory-analysis** 技能中。
> 此处仅列出本技能需要的子集，新增条目时请同步更新权威来源。
```

3. **保留运行时副本时加注释**：如果脚本中必须内联数据，加注释标明同步来源

```powershell
# 芯片配置（权威数据维护在 memory-analysis 技能中，此处为运行时副本）
# 新增芯片时请同步更新 memory-analysis 的配置表
```

### 第六步：验证

修补完成后重新执行第一步扫描，确认：
- 所有文件编码为 UTF-8
- 无硬编码绝对路径（Grep 搜索 `C:\\Users\\\w+\\` 和 `[D-Z]:\\` 排除环境变量引用）
- 行数在合理范围（30-500）
- 重复内容已消除或标注引用

输出最终修补摘要。

## 陷阱与注意事项

- **本环境无 skill_manage 工具**（2026-09-02 确认）：不存在的 `skill_manage action=patch/edit`，一切修补走 PowerShell 可靠替换法（见第四步）。
- **去重不能简单删除**：必须保留引用注释指向权威来源，否则后续维护者不知道数据在哪，会重新创建一份。
- **超长技能不要截断**：应拆分为 SKILL.md + reference.md，核心工作流留在主文件，详细参考放辅助文件。
- **修补前备份（强制，2026-08-29 事故教训）**：对要 edit / 按行段裁剪 / 拆分的技能，先把完整原文落盘到工作目录或独立备份盘（Copy-Item 或 WriteAllText 原样副本，注意：内容勿含个人盘符路径）。禁止『读进内存 → 裁剪 → 覆盖写同一路径』三步连做而不对磁盘留任何副本：PowerShell 变量随命令进程结束即销毁，不落盘 = 没备份。本次事故：embedded-code-review 1948 行按行段裁剪覆盖为 173 行，原文件被毁，仅靠备份目录的早期版本恢复，8/13-8/27 新增的 2.6/2.7 两节永久丢失（后依据 user_profile / chip-rules 重建）。
- **不要一次改太多**：每修补一个技能就验证一个，避免批量改完后发现某个改坏了难以定位。
- **description 修改要谨慎**：改 description 可能影响技能触发，修改后让用户实际调用一次确认能触发。

## 输出格式（审查报告模板）

```markdown
# 技能库审查报告

**审查时间**: YYYY-MM-DD
**技能总数**: N 个
**问题技能**: M 个

## P0 - 无法使用
| 技能 | 问题 | 建议操作 |
|------|------|----------|
| xxx  | 仅28行空壳 | 补全或删除 |

## P1 - 换机器失效
| 技能 | 问题 | 建议操作 |
|------|------|----------|
| xxx  | 硬编码 D:\Keil_v5 | 改为动态检测 |

## P2 - 维护隐患
| 技能 | 问题 | 建议操作 |
|------|------|----------|
| xxx + yyy | 芯片配置表重复 | 指定权威来源 |

## P3 - 建议优化
| 技能 | 问题 | 建议操作 |
|------|------|----------|
| xxx  | 2189行过长 | 拆分 + reference.md |

## 修补记录
- [x] 技能A：patch 修复路径（UTF-8）
- [x] 技能B：edit 全量重写（原 GB2312）
- [ ] 技能C：待用户确认是否删除
```
