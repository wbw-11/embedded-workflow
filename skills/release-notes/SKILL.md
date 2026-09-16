---
name: release-notes
description: "Release Notes/Changelog 自动生成：git log 提取变更分类整理。发布新版本/写更新日志时调用，支持 Markdown+gh release。"
version: 1.0.0
---

# Release Notes / Changelog 生成

## 适用场景

- 用户发布新固件版本，需要写 release notes
- 用户要求生成 CHANGELOG.md
- 用户要求创建 GitHub Release 并附带说明
- 用户问"上个版本到现在改了什么"

## 生成流程

### 第一步：确定版本范围

```bash
# 查看最近的 tag
git tag -l "v*" --sort=-v:refname | head -5

# 确定本次发布的范围
LAST_TAG=$(git tag -l "v*" --sort=-v:refname | head -1)
echo "从 $LAST_TAG 到 HEAD 的变更："
git log ${LAST_TAG}..HEAD --oneline
```

如果没有历史 tag，则从项目开始：
```bash
git log --oneline --all
```

### 第二步：提取并分类 commits

```bash
# 获取格式化的 commit 列表（type + scope + subject）
git log ${LAST_TAG}..HEAD --pretty=format:"%s" --no-merges
```

按 commit type 分类（依赖 git-workflow 技能的 commit 规范）：

| 分类 | 对应 type | 标题 |
|------|-----------|------|
| 新功能 | feat | ✨ New Features |
| 修复 | fix | 🐛 Bug Fixes |
| 性能 | perf | ⚡ Performance |
| 重构 | refactor | ♻️ Refactoring |
| 构建 | build | 🔧 Build System |
| 文档 | docs | 📝 Documentation |

### 第三步：生成 Release Notes

#### 模板

```markdown
# v{MAJOR}.{MINOR}.{PATCH} - {日期}

{一句话概述本次发布的核心变化}

## ✨ 新功能

- **{scope}**: {描述} ({commit hash})
- ...

## 🐛 修复

- **{scope}**: {描述} ({commit hash})
- ...

## ⚡ 性能优化

- ...

## 🔧 构建/工具链

- ...

## 📋 升级说明

{如有不兼容变更或特殊升级步骤，在此说明}

## 📊 资源占用

| 指标 | 上一版本 | 本版本 | 变化 |
|------|----------|--------|------|
| Flash (Code+RO) | xx KB | xx KB | +x KB |
| RAM (RW+ZI) | xx KB | xx KB | -x KB |

---
完整变更: {LAST_TAG}...v{NEW_VERSION}
```

### 第四步：生成 CHANGELOG.md（累积式）

CHANGELOG.md 采用 Keep a Changelog 格式，新版本追加在顶部：

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [v1.3.0] - 2026-07-28

### Added
- UART DMA 接收模式，支持不定长数据
- BLE 配网功能

### Fixed
- 低功耗唤醒后看门狗未喂导致复位
- I2C 总线锁死后无法恢复

### Changed
- 主循环改为事件驱动架构

## [v1.2.0] - 2026-06-15

### Added
- W25Q128 SPI Flash 驱动
- OTA 升级基础框架

...
```

### 第五步：发布 GitHub Release

```bash
# 生成 release notes 文件
# （将上面的模板内容写入 RELEASE_NOTES.md）

# 创建 GitHub Release
gh release create v1.3.0 \
  --title "v1.3.0 - BLE 配网 + 低功耗优化" \
  --notes-file RELEASE_NOTES.md

# 附带固件文件（如有）
gh release upload v1.3.0 ./build/firmware_v1.3.0.bin
```

## 面向不同受众的版本

### 内部开发版（详细）

包含所有 commit、技术细节、影响范围。

### 客户/产品版（简洁）

```markdown
# 固件更新 v1.3.0

**发布日期**: 2026-07-28
**适用硬件**: Rev 1.1 及以上

## 本次更新

1. 新增蓝牙配网功能，支持手机 App 一键配网
2. 优化待机功耗，续航从 15 天提升至 25 天
3. 修复偶发的传感器数据丢失问题

## 升级方式

通过 OTA 自动升级，或串口烧录 firmware_v1.3.0.bin

## 注意事项

- 本次升级后需重新配网
- 硬件 Rev 1.0 不支持 BLE 功能，请勿升级
```

## 自动化脚本

```bash
#!/bin/bash
# gen_release_notes.sh - 自动生成 release notes
LAST_TAG=$(git tag -l "v*" --sort=-v:refname | head -1)
NEW_TAG=$1  # 传入新版本号，如 v1.3.0

if [ -z "$NEW_TAG" ]; then
    echo "Usage: ./gen_release_notes.sh v1.3.0"
    exit 1
fi

echo "# $NEW_TAG - $(date +%Y-%m-%d)"
echo ""
echo "## ✨ 新功能"
git log ${LAST_TAG}..HEAD --pretty=format:"- %s (%h)" --no-merges | grep "^- feat" | sed 's/- feat(\([^)]*\)): /- **\1**: /'
echo ""
echo "## 🐛 修复"
git log ${LAST_TAG}..HEAD --pretty=format:"- %s (%h)" --no-merges | grep "^- fix" | sed 's/- fix(\([^)]*\)): /- **\1**: /'
echo ""
echo "## 🔧 其他"
git log ${LAST_TAG}..HEAD --pretty=format:"- %s (%h)" --no-merges | grep -v "^- feat\|^- fix"
```

## Pitfalls

- 生成前确认所有 commit 已推送到远程
- Merge commit 通常用 --no-merges 过滤，避免重复
- 如果 commit 不规范（没有 type 前缀），需要手动分类
- 资源占用数据需要从 memory-analysis 技能获取，不要编造
- 客户版不要暴露内部 commit hash 和技术细节
- 不兼容变更必须在"升级说明"中醒目提示

## Verification

- Release notes 中的条目数与 `git log --oneline` 的 commit 数大致匹配
- 每条描述准确反映实际变更（不夸大不遗漏）
- 版本号与 version.h 和 git tag 一致
- `gh release view v1.3.0` 确认发布成功
