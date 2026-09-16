# ESP-IDF 编译烧录 - 参考

> 本文件为 esp-idf-build 技能的排查表/命令速查/踩坑记录（自 SKILL.md 拆分）。

---

## 常见错误排查

### 1. 编译错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `idf.py : 无法识别的命令` | 环境未初始化或 PATH 不对 | 执行上方"初始化环境"步骤 |
| `fatal error: xxx.h: No such file` | 缺少头文件或组件未声明 | 在 `idf_component_register` 的 `REQUIRES` 中添加组件 |
| `undefined reference to xxx` | 链接错误，函数未定义 | 检查源文件是否加入组件，检查组件依赖 |
| `ninja: build stopped: subcommand failed` | 编译失败 | 往上翻找具体错误信息 |

### 2. 烧录错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `A fatal error occurred: Failed to connect` | 串口连接失败 | 检查 USB 线、串口号、驱动是否安装 |
| `A fatal error occurred: Invalid head of packet` | 波特率不匹配或芯片未进入下载模式 | 按住 BOOT 键再烧录，或降低波特率 |
| `Serial port COM5 not found` | 串口号错误 | 用设备管理器确认正确的串口号 |
| `Permission denied` | 串口被占用 | 关闭串口助手、监控等占用串口的程序 |

### 3. 监控错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| 乱码 | 波特率不匹配 | 确认 menuconfig 中波特率设置（默认 115200） |
| 无输出 | 芯片未运行或 TX/RX 接反 | 检查接线，确认芯片已烧录并正常运行 |

## 常用命令速查

| 命令 | 功能 |
|------|------|
| `idf.py build` | 编译项目 |
| `idf.py -p COM5 flash` | 烧录到指定串口 |
| `idf.py -p COM5 monitor` | 串口监控 |
| `idf.py -p COM5 build flash monitor` | 编译+烧录+监控一条龙 |
| `idf.py clean` | 清理编译产物（保留配置） |
| `idf.py fullclean` | 完全清理（包括配置，切换芯片前用） |
| `idf.py menuconfig` | 图形化配置菜单 |
| `idf.py set-target esp32s3` | 切换目标芯片 |
| `idf.py size` | 查看内存占用详情 |
| `idf.py size-components` | 查看各组件内存占用 |
| `idf.py erase-flash` | 擦除整个 Flash |
| `idf.py -p COM5 monitor baud 921600` | 指定监控波特率 |

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `export.ps1` 存在 | ✅ | `<ESP_IDF_ROOT>\export.ps1` |
| `idf.py build/flash/monitor/clean/fullclean` 命令 | ✅ | ESP-IDF 标准 CLI 命令 |
| `idf.py set-target/menuconfig/size/erase-flash` 命令 | ✅ | ESP-IDF 标准 CLI 命令 |
| `Ctrl + ]` 退出 monitor | ✅ | `esp_idf_monitor/base/key_config.py` L30 (`EXIT_KEY = ']'`) |
| `CONFIG_IDF_TARGET` 在 sdkconfig 中 | ✅ | ESP-IDF 构建系统标准变量 |
| `dl.espressif.cn` 国内镜像 | ✅ | Espressif 官方国内 CDN |
| MSYS 环境变量误判问题 | ✅ | ESP-IDF 已知问题，需清除 MSYSTEM/MSYS/CHERE_INVOKING |
| 动态路径检测（环境变量→候选列表） | ✅ | 与 user_profile 中 esp-idf-env.ps1 一致 |
| 工具链版本号动态检测 | ✅ | tools/ 目录下版本号因安装时间不同而异 |
