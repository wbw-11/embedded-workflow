---
name: project-cleanup
description: "项目清理收尾：清中间文件/归档日志/查 git 状态/生成改动总结。「清理项目」「收尾」或删 .bak/build 时调用。支持 Keil/ESP-IDF。"
version: 1.0.0
---

# 项目清理与收尾

## 适用场景

- 项目功能完成后需要清理
- 用户说"清理一下"、"删掉中间文件"
- 删除 .bak 备份文件
- 归档串口日志
- 提交代码前检查 git 状态

## 脚本位置

| 脚本 | 用途 |
|------|------|
| `$env:USERPROFILE\Tools\keil-clean.ps1` | 清理 Keil/ESP-IDF 中间文件 |
| `$env:USERPROFILE\Tools\project-finalize.ps1` | 完整收尾（清理+归档+git+总结） |

## 使用方法

### 快速清理中间文件

```powershell
cd <项目目录>

# 自动检测项目类型并清理
keil-clean

# 强制清理（跳过确认）
keil-clean -Force

# 同时清理 Keil 和 ESP-IDF 文件
keil-clean -All
```

清理范围：

**Keil 项目**：.bak, .obj, .omf, .lst, .crf, .o, .d, .axf, .map, .htm, .sbr, .m51, JLinkLog.txt, *.uvgui.* 等

**ESP-IDF 项目**：build/, sdkconfig.old, managed_components/, .cache/

### 完整项目收尾

```powershell
cd <项目目录>

# 完整收尾流程
project-finalize

# 预演模式（只看要做什么，不实际执行）
project-finalize -DryRun

# 跳过确认直接执行
project-finalize -Force
```

完整收尾执行 5 步：

1. **扫描并清理 .bak 文件**（需用户确认）
2. **归档串口日志**（serial_log_*.txt → logs/ 目录）
3. **检查 git status**（显示分支、修改/新增/未跟踪文件数）
4. **生成改动总结模板**（提示用户填入 project_memory.md）
5. **检查待办事项**（未关闭 todo、未烧录验证的代码）

## 与 AI 的协作流程

当用户完成一个功能模块并说"收尾"时：

1. **先运行 project-stats** 了解项目状态
2. **运行 keil-clean 或 project-finalize** 清理中间文件
3. **解读 git status** 结果，建议 commit message
4. **将改动总结写入 project_memory.md**

```powershell
# 完整收尾流程
cd <项目目录>
project-stats              # 1. 了解规模
keil-clean -Force          # 2. 清理中间文件
project-finalize -DryRun   # 3. 预览收尾操作
project-finalize           # 4. 执行收尾
```

## Pitfalls

- keil-clean 默认需要用户确认，`-Force` 跳过
- project-finalize 的 .bak 删除也需要确认，`-Force` 跳过
- ESP-IDF 的 managed_components/ 被清理后下次编译需要重新下载组件
- 清理前建议先 git commit，避免误删未提交的文件
- DryRun 模式不会实际执行任何操作，适合先预览

## Verification

- 清理后 `project-stats` 显示的文件数减少
- git status 确认没有意外删除
- logs/ 目录包含归档的串口日志
