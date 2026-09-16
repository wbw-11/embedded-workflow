# Tools Changelog

## 2026-09-16	v1.0.1	发布（统一缩进规则 + README 部署指南）
- code-style-check.ps1 1.0.0 -> 1.0.1	patch	缩进规则反转为空格风格（禁用 Tab），与项目代码风格声明一致；三步法回归 3/3 PASS
- README 部署指南重写：真实 clone 地址、首次验证 3 命令、依赖说明

## 2026-09-02	版本发布工程初始化
- 新增 version-tools.ps1（版本登记/变更记录/缺失检测，单一真实源=脚本内嵌 version 行）
- 全量 35 个脚本统一登记 version: 1.0.0，生成 tools_version.json 聚合索引
- 变更记录规则：version-tools -Bump -Name <脚本.ps1> -How <patch|minor|major> -Message <说明> 自动入 changelog

### 2026-09-02	version-tools.ps1	1.0.0 -> 1.0.1	patch	修正自检显示行并补自身版本行
### 2026-09-02	version-tools.ps1	1.0.1 -> 1.0.2	patch	重构 changelog 追加逻辑，防文件末无换行导致条目粘连
### 2026-09-02	version-tools.ps1	1.0.2 -> 1.0.3	patch	换行保护实测：末行无换行时追加不粘连
### 2026-09-02	version-tools.ps1	1.0.3 -> 1.1.0	minor	Register 输出完整时间格式支持版本时效检测
### 2026-09-02	self-update.ps1	1.0.0 -> 1.1.0	minor	config 集成版本门禁与时效检查(改脚本未bump即告警)
### 2026-09-02	tool-guide.ps1	1.0.0 -> 1.1.0	minor	展示 tools_version.json 版本列并新增 version-tools 条目
### 2026-09-02	tool-guide.ps1	1.1.0 -> 1.1.1	patch	新增 self-update 条目
### 2026-09-02	version-tools.ps1	1.1.0 -> 1.2.0	minor	List 输出补充工具自身版本行
### 2026-09-02	self-update.ps1	1.1.0 -> 2.0.0	major	登记版本对齐界面命名 v2.0
### 2026-09-02	detect-chip.ps1	1.0.0 -> 1.1.0	minor	回溯此前 v1.3 迭代(日志特征识别等)，与基线 1.0.0 区分
### 2026-09-03	self-update.ps1	2.0.0 -> 2.0.1	patch	tools 模块非 git 仓库时视为跳过而非失败(no_git_sync)
### 2026-09-03	version-tools.ps1	1.2.0 -> 1.3.0	minor	新增 -Log 查看 changelog 最近记录
### 2026-09-03	self-update.ps1	2.0.1 -> 2.0.2	patch	config 新增 verify-check 回归时效门禁
### 2026-09-04	dev-flow.ps1	1.0.0 -> 1.1.0	minor	主流程新增存储寿命预检(扫描存储写API
### 2026-09-04	self-update.ps1	2.0.2 -> 2.1.0	minor	Update-Tools 未提交改动时 -AutoFix 自动 commit+push 闭环
### 2026-09-04	self-update.ps1	2.1.0 -> 2.2.0	minor	新增 Update-Knowledge(-Mode backup 三仓自动提交+skills/memory仓)
### 2026-09-04	preflight.ps1	1.0.0 -> 1.0.1	patch	新增开工预检工具
### 2026-09-04	preflight.ps1	1.0.1 -> 1.0.2	patch	preflight 新增缺包/未知工程类型的 Guide 指引，可显示具体安装路径
### 2026-09-04	preflight.ps1	1.0.2 -> 1.0.3	patch	-FixAuto 缺 DFP 时自动调 Keil Pack Installer 安装
### 2026-09-04	dev-flow.ps1	1.2.0 -> 1.2.1	patch	Keil 编译失败时输出缺器件包安装指引
### 2026-09-04	dev-flow.ps1	1.2.1 -> 1.2.2	patch	UV4 加 180s 超时防缺包弹窗挂死；缺包正则补 device/pack not found 特征
### 2026-09-09	dev-flow.ps1	1.2.2 -> 1.3.0	minor	主流程新增静态门禁(code-style-check overflow,defensive, -SkipStatic豁免)；版本门禁文件名不符默认拦截(exit 21, -SkipVersionGate豁免)；时间戳排除 managed_components/.git；版本缺失归档降级时间戳目录；产物查找补时间排序
