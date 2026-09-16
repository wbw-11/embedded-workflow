# ARM Cortex-M 系列规则（L2 芯片系列层）

> 适用范围：GD32F4xx、STM32F4xx 等所有 ARM Cortex-M 芯片。本文件为系列级通用规则，型号级约束以各项目 `project_memory.md`（L3）为准。

## 工具链

- 编译：Keil ARMCC（动态检测路径，优先环境变量 `KEIL_ROOT` → 注册表 → 候选路径；当前验证路径 D:\Keil_v5\ARM\ARMCC\bin\armcc.exe），工程文件 `.uvprojx`
- 编译方式：必须 **Rebuild All**（UV4 -r），禁止增量编译（UV4 -b）
- 调试器：CMSIS-DAP（用户在 Keil 魔法棒中手动配置）
- 调试产物：`.hex` + `.axf` + `.map`
- 版本归档：编译通过后自动复制 `hex + axf + map` 到 `<项目根>/Firmware_Build/Vxx/`，命名 `<芯片>_Vxx.<后缀>`（如 GD32F407VE_V46.hex）。详细规则见 user_profile「固件版本管理」章节（L1 强制，全局通用）

## 时钟

- 默认优先内部 RC、外部晶振必须验证起振的门禁规则见 user_profile「四步准备」/ embedded-dev-rules（L1），此处不重复
- 系统时钟宏写死并核对注释状态（如 `__SYSTEM_CLOCK_168M_PLL_8M_HXTAL`），HXTAL_VALUE 与晶振频率一致
- 外部晶振未起振会导致 `SystemInit()` 卡死、代码到不了 main（现象 = 没反应）

## 中断（NVIC）

- 中断优先级可配置（NVIC），ISR 位置与参考项目一致
- ISR 内禁止 printf/耗时操作等红线见 user_profile「嵌入式代码审查最佳实践」（L1），此处不重复
- 注意复位/初始化序列对中断使能寄存器的影响（如软复位会清中断使能）

## 内存

- 小端字节序（与 8051 大端相反）；volatile/局部变量初始化/头文件禁全局变量等红线见 user_profile 与 embedded-dev-rules（L1），此处不重复

## 寄存器与库函数

- **不凭记忆写寄存器/库函数名**，按 datasheet-lookup 优先级查阅
- 库函数命名：小写 + 模块前缀（如 `usart_baudrate_set`）
- 标准库函数名随版本变化（V2.x vs V3.x），以项目头文件为准

## GPIO

- 复用功能需配置 AF 模式 + 复用号（如 USART0 TX = AF7）
- 区分推挽/开漏、上拉/下拉；位操作使用无符号数（1U）

## 系列踩坑（ARM 特有）

- GD32 与 STM32 寄存器大多兼容，但库函数/API 不同，不能直接搬代码
- 跨厂商通用防坑规则（禁止改官方库源码 / 官方例程基线对照 / 3 版本止损）见 user_profile.md「嵌入式驱动开发防坑规则」（L1），此处不重复

## GD32 外设适配检查清单（2026-08-29 lvgl_demo V5.3-V5.6 三连黑屏换来的铁律，GD32 专属）
> 前提：GD32 与 STM32 引脚/寄存器大多兼容，但**命名和细节不同**，严禁照搬 ST 经验直接写 GD32 外设配置。

写任何 GD32 外设驱动（尤其定时器/PWM/复用引脚）前，按顺序查证 5 项：

1. **定时器编号核对**：GD32 TIMER 编号 ≠ ST！GD32 TIMER0=ST TIM1(高级)、TIMER1=ST TIM2(通用)、TIMER2=ST TIM3(通用)、TIMER7=ST TIM8(高级)。核对 `gd32f4xx_timer.h` 基址表（TIMER1=0x0, TIMER2=0x400, TIMER3=0x800）。按 ST 习惯写 TIMER2 会配到 ST TIM3！
2. **引脚复用通道查 GD 官方 Datasheet**（不是用户手册！）：用户手册 7.3.3 明写"端口备用功能分配见芯片数据手册"。例：GD32 PB10=TIMER1_CH2、PB11=TIMER1_CH3（STM32 里 PB10=TIM2_CH3）。GD 官网 gd32mcu.com 下载 Datasheet PDF（如 GD32F407xx Datasheet Rev2.5，134 页）
3. **模式/极性语义查用户手册**（GD32F4xx 用户手册 Rev3.3）：例 PWM 模式——GD32 PWM0(CHxCOMCTL=110)=ST 的 PWM1 语义（CNT<CCR 输出有效电平）；PWM1(111) 输出无效电平。驱动低有效外设（如背光）用 PWM0 + POLARITY_LOW
4. **时钟核对**：定时器挂 APB1/APB2，PSC+period 算出 PWM 频率（19.8kHz 背光无闪烁）
5. **寄存器诊断**：配置后读寄存器快照打印验证落盘值（CTL0/CHCTL2/CHxCV/GPIOx_AFSELz），确认 CHxEN/极性/模式/复用号都对了再收工

查证工具：GD32 PDF 用 python pymupdf(fitz) 直接解析（`fitz.open()` + `page.find_tables()` 提表），mcp_pdf-reader 的路径基准在本环境不可靠；用户手册 1014 页、Datasheet 官网可下。
> 通用排查方法论（跨芯片）见 embedded-dev-rules「外设调试排查 SOP」（L1），此处只保留 GD32 特有差异。

## 与 L3 的关系

- 型号级硬约束（如 GD32F407 的 USB PHY 时序、引脚表）在对应项目 `project_memory.md`，本文件不重复
- L3 与本文冲突时以 L3 为准

## 项目目录结构（2026-08-27 用户指定，L2 强制）
- Keil 系（GD32/STM32）新项目从零搭建使用六目录：**Doc\\**（项目文档）、**Firmware\\**（芯片 BSP：CMSIS/标准库/startup，官方源码不改）、**Hardware\\**（引脚表+证据链/原理图要点/外设映射）、**Library\\**（第三方库如 tinyusb）、**Project\\**（工程文件，干净无日志）、**User\\**（main.c + 配置 + bsp\\ 一外设一文件）
- 附加目录：**Firmware_Build\\**（每版产物 + src 快照 + 日志）、**Logs\\**（运行日志）
- 已在用项目保持原结构（防破坏工程相对路径）
- 完整标准见 user_profile「新项目目录结构标准」（L1）
## USB DWC2（GD32/STM32 核复用，2026-09-03 从 L1 下沉）
- USB 任务先读 sy 项目 Firmware_Build/V52.13/src 快照，不从零探索
- EP0 IN 先写 TX FIFO 再 EPENA+CNAK；DAINT(0x818) 是 W1C 勿当掩码、DAINTMSK(0x81C)；枚举后回 SERIAL_STATE(DCD|DSR) 否则 UI 卡死；printf 只在总线安静时（阻塞杀 SET_ADDRESS 窗口）；ISR 禁 printf 用事件环缓冲