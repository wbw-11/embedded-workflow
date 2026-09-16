# ESP-IDF v5.5.4 环境初始化脚本（统一入口）
# 使用方式：. "$env:USERPROFILE\.trae-cn\skills\esp-idf-build\esp-idf-init.ps1"
#
# 本脚本为轻量包装器，实际环境加载由 Tools\esp-idf-env.ps1 完成。
# 主脚本支持动态检测 ESP-IDF 安装位置：
#   1. 优先使用环境变量 $env:ESP_IDF_ROOT
#   2. 其次扫描候选路径列表
#   3. 最后提示用户手动配置
#
# 如需 -Check 验证模式，请直接调用主脚本：
#   . $env:USERPROFILE\Tools\esp-idf-env.ps1 -Check

$envScript = "$env:USERPROFILE\Tools\esp-idf-env.ps1"
if (Test-Path $envScript) {
    . $envScript @args
} else {
    Write-Error "未找到 ESP-IDF 环境脚本: $envScript"
    Write-Host "请确认 Tools 目录已正确安装" -ForegroundColor Yellow
}