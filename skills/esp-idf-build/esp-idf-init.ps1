# ESP-IDF v5.5.4 环境初始化脚本（统一入口）
# 使用方式：. "<本技能目录>\esp-idf-init.ps1"
#
# 本脚本为轻量包装器，实际环境加载由仓库 tools\esp-idf-env.ps1 完成。
# 主脚本支持动态检测 ESP-IDF 安装位置：
#   1. 优先使用环境变量 $env:ESP_IDF_ROOT
#   2. 其次扫描候选路径列表
#   3. 最后提示用户手动配置
#
# 如需 -Check 验证模式，请直接调用主脚本：
#   . "<仓库>\tools\esp-idf-env.ps1" -Check

$envScript = Join-Path $PSScriptRoot '..\..\tools\esp-idf-env.ps1'
if (Test-Path $envScript) {
    . $envScript @args
} else {
    Write-Error "未找到 ESP-IDF 环境脚本: $envScript"
    Write-Host "请确认已克隆 embedded-workflow 仓库（esp-idf-init.ps1 位于 skills\esp-idf-build\）" -ForegroundColor Yellow
}