# 嵌入式代码审查清单 (全量参考 reference.md)

> 注意：本文件是 SKILL.md 的完整参考：一~二十章全量检查项 + 快速参考表（2026-08-12 备份版恢复）。
> 快速场景入口（按"改了什么代码"选清单）见 SKILL.md。新增检查项时优先维护本文件。
>
> 恢复说明（2026-08-29）：原 2026-08-27 版中 2.6/2.7 两节因覆盖丢失，已依据 user_profile 规则6 与 chip-rules 重建补回；
> 备份版基础之上，正文已包含重建后的 2.6/2.7。

---


## 一、中断安全（ISR）

> ⚠️ **功能优先原则**：本清单中的 ISR 规范是**优化建议**，不是强制要求。修改已有项目时，**先保证功能正常**，再逐步优化。如果原始代码在 ISR 中调用了 printf 等耗时操作但能正常工作，不要为了满足规范而盲目重构，否则可能破坏原有功能。

### 1.1 ISR 中禁止耗时操作
- [ ] ISR 中没有 `printf`、`sprintf` 等格式化操作
- [ ] ISR 中没有阻塞等待（`while(!flag);`、`delay_ms()` 等）
- [ ] ISR 中没有复杂循环（循环次数固定且极少）
- [ ] ISR 执行时间是否足够短（理想 < 10us）

**错误示例：**
```c
/* ❌ ISR 中 printf + 阻塞 */
void USART0_IRQHandler(void)
{
    /* 判断串口接收中断标志 */
    if (/* 接收中断标志置位 */) {
        g_rx_buf[g_rx_cnt++] = /* 读取串口数据寄存器 */;
        printf("收到: 0x%02X\n", g_rx_buf[g_rx_cnt - 1]);  /* 禁止！ */
        while (!/* 发送缓冲区空标志 */);    /* 禁止！ */
        /* 发送串口数据 */(g_rx_buf[g_rx_cnt - 1]);
    }
}
```

**正确示例：**
```c
/* ✅ ISR 只做最少的事，用 volatile 标志位通知主循环 */
void USART0_IRQHandler(void)
{
    /* 判断串口接收中断标志 */
    if (/* 接收中断标志置位 */) {
        if (g_rx_cnt < RX_BUF_SIZE) {
            g_rx_buf[g_rx_cnt++] = /* 读取串口数据寄存器 */;
        }
        g_rx_ready = 1;  /* volatile 标志位 */
    }
}
```

### 1.2 中断标志位清除
- [ ] 优先使用 `xxx_interrupt_flag_clear()` 清标志，而非读数据寄存器
- [ ] 确认清除的是正确的标志位
- [ ] 在处理完数据后再清标志（避免丢失数据）

### 1.3 中断优先级与嵌套
- [ ] 关键中断（如通信接收）优先级是否合适
- [ ] 如果启用中断嵌套，确认优先级分组配置正确
- [ ] ISR 位置与参考项目保持一致（不凭经验自行调整）

### 1.4 EXTI 按键消抖（实战踩坑）

> ⚠️ **踩坑记录**：机械按键直接接 EXTI 中断，按下一次会连续触发多次中断（抖动导致）。

- [ ] 所有使用 EXTI 中断的按键**必须**加消抖处理
- [ ] 消抖方式：状态机消抖（推荐）或定时器延时消抖
- [ ] 消抖时间建议 10~20ms

**状态机消抖示例（推荐）：**
```c
/* ✅ 首次触发启动定时器，定时器到期后重新读取 GPIO 状态确认 */
typedef enum {
    KEY_STATE_IDLE,
    KEY_STATE_PRESSED,
    KEY_STATE_CONFIRMING
} key_state_e;

void EXTI0_IRQHandler(void)
{
    if (exti_interrupt_flag_get(EXTI_0)) {
        if (g_key_state == KEY_STATE_IDLE) {
            g_key_state = KEY_STATE_CONFIRMING;
            g_key_timer = 0;  /* 启动消抖定时器 */
        }
        exti_interrupt_flag_clear(EXTI_0);
    }
}

/* 在定时器中断中（每1ms）检查 */
void key_debounce_tick(void)
{
    if (g_key_state == KEY_STATE_CONFIRMING) {
        g_key_timer++;
        if (g_key_timer >= 20U) {  /* 20ms 消抖 */
            if (gpio_input_bit_get(KEY_PORT, KEY_PIN) == 0U) {
                g_key_state = KEY_STATE_PRESSED;  /* 确认有效按键 */
                g_key_flag = 1U;
            } else {
                g_key_state = KEY_STATE_IDLE;  /* 抖动，丢弃 */
            }
        }
    }
}
```

## 二、缓冲区与内存安全

### 2.1 缓冲区越界保护
- [ ] 所有数组写入操作前有边界检查
- [ ] 环形缓冲区的读/写指针回绕逻辑正确
- [ ] 中断接收缓冲区用 `if (rx_cnt < RX_BUF_SIZE)` 严格判断

**错误示例：**
```c
/* ❌ 无边界检查 */
void uart_rx_handler(uint8_t data)
{
    g_rx_buf[g_rx_cnt++] = data;  /* 可能溢出！ */
}
```

**正确示例：**
```c
/* ✅ 严格边界检查 */
void uart_rx_handler(uint8_t data)
{
    if (g_rx_cnt < RX_BUF_SIZE) {
        g_rx_buf[g_rx_cnt++] = data;
    }
    /* 满了就丢弃，或设置溢出标志 */
}
```

### 2.2 栈空间
- [ ] ISR 中没有大数组局部变量
- [ ] 递归深度可控（嵌入式建议完全避免递归）
- [ ] 局部变量总大小合理（建议单函数栈使用 < 256 字节）

### 2.3 动态内存
- [ ] 裸机系统中不使用 `malloc`/`free`（无内存保护，碎片风险）
- [ ] 如果必须用，确认有内存池或静态分配替代方案

### 2.4 回调函数非空校验（实战踩坑）

> ⚠️ **踩坑记录**：回调函数指针未初始化时为 NULL，直接调用会导致 HardFault。

- [ ] 所有通过函数指针调用的回调，调用前**必须**检查非 NULL
- [ ] 回调注册函数中可设默认空实现，但调用处仍建议校验

**错误示例：**
```c
/* ❌ 直接调用，可能 NULL */
void USART0_on_recv(uint8_t* data, uint32_t len)
{
    g_rx_callback(data, len);  /* g_rx_callback 未初始化 → HardFault */
}
```

**正确示例：**
```c
/* ✅ 调用前校验非空 */
void USART0_on_recv(uint8_t* data, uint32_t len)
{
    if (data == NULL || len == 0U) return;  /* 参数校验 */
    if (g_rx_callback != NULL) {
        g_rx_callback(data, len);
    }
}
```

### 2.5 数据溢出专项审查（P0+P1，强制项）

> ⚠️ **本小节为强制检查项**，代码审查时必须逐项过一遍。溢出导致的 HardFault / 野写内存是嵌入式最难排查的 Bug 之一，静态检查能发现 80% 的隐患。

#### P0-1：格式化字符串溢出（sprintf 危险）

**检查项：**
- [ ] 禁止使用 `sprintf` / `vsprintf`（无长度限制，必炸）
- [ ] `snprintf` 的长度参数 = 目标缓冲区实际 `sizeof`，不是随便写的数字
- [ ] `snprintf` 返回值检查（若返回值 >= 缓冲区大小，说明内容被截断）
- [ ] `%s` 格式化的源字符串长度可控（防止超过目标缓冲区）

**错误示例：**
```c
/* ❌ P0 致命：sprintf 无长度限制 */
char log_buf[16];
sprintf(log_buf, "ADC=%d,volt=%.2f", adc_raw, voltage);
/* adc_raw=999999 + voltage 小数 → 远超 16 字节，飞栈！ */

/* ❌ P0 致命：snprintf 长度写死（buf 改成 32 字节后这里忘了改） */
snprintf(log_buf, 16, "ADC=%d", adc_raw);
```

**正确示例：**
```c
/* ✅ 用 snprintf + sizeof 动态传长度 */
char log_buf[32];
int n = snprintf(log_buf, sizeof(log_buf), "ADC=%d,volt=%.2f", adc_raw, voltage);
if (n < 0 || (size_t)n >= sizeof(log_buf)) {
    /* 截断或出错，记录溢出标志 */
    g_log_overflow_flag = 1U;
}
```

#### P0-2：不安全字符串函数（strcpy/strcat/gets）

**检查项：**
- [ ] 禁止使用 `gets()`（C11 标准已删除，无任何安全边界）
- [ ] 禁止使用 `strcpy` / `strcat`（无长度限制）
- [ ] 替代方案：`strncpy` / `strncat`，长度参数严格传 `sizeof(dst)-1`，并手动补 `\0`
- [ ] 或自定义安全字符串函数（返回拷贝的实际字节数 + 截断标志）

**错误示例：**
```c
/* ❌ P0 致命：strcpy 不检查长度 */
char name[8];
strcpy(name, user_input);   /* user_input 是串口输入，长度未知 → 溢出 */

/* ❌ P0 致命：gets 已被废弃 */
char cmd[32];
gets(cmd);                  /* 任何时候都不应该出现！ */
```

**正确示例：**
```c
/* ✅ strncpy + 手动补终止符 */
char name[8];
strncpy(name, user_input, sizeof(name) - 1U);
name[sizeof(name) - 1U] = '\0';   /* 强制补 0，防止 src 刚好等于长度时无终止符 */
```

#### P0-3：整数运算溢出（隐式类型提升）

**检查项：**
- [ ] 两个窄类型（uint8_t/uint16_t）相乘前，是否先强制扩展到宽类型再运算
- [ ] 加法/减法运算结果是否有上限/下限判断（尤其是累加计数器）
- [ ] `size_t`（无符号）与 `int`（有符号）混用前，是否显式转换并做范围检查

**错误示例：**
```c
/* ❌ P0 致命：隐式按 uint16_t 算，溢出后再扩展 */
uint16_t width  = 480U;
uint16_t height = 360U;
uint32_t pixel_count = width * height;   /* 480*360=172800 > 65535 → uint16 溢出=41728 → 再扩成 32 位 */

/* ❌ P0 致命：累加计数器无上限判断 */
g_total_bytes += rx_len;   /* g_total_bytes 是 uint32_t，连续收 4GB 数据后回绕 0 */
```

**正确示例：**
```c
/* ✅ 先强制提升到结果类型再运算 */
uint16_t width  = 480U;
uint16_t height = 360U;
uint32_t pixel_count = (uint32_t)width * (uint32_t)height;  /* 先扩 32 位再乘 */

/* ✅ 累加前判断上限 */
if (g_total_bytes <= (UINT32_MAX - rx_len)) {
    g_total_bytes += rx_len;
} else {
    g_overflow_flag = 1U;
}
```

#### P0-4：memcpy/memmove/memset 长度校验

**检查项：**
- [ ] `memcpy(dst, src, len)` 的 `len` 是否 **同时** <= `sizeof(dst)` 和 <= `sizeof(src)`（或 src 实际有效长度）
- [ ] 长度参数优先使用 `sizeof(目标)` 或已校验过的变量，**禁止裸数字**（除非是 sizeof 宏）
- [ ] 目标缓冲区和源缓冲区的类型是否匹配（`uint8_t*` 按字节算，结构体按 sizeof 算）
- [ ] DMA 拷贝完成后再 memcpy 时，长度是 DMA 实际接收的字节数，不是缓冲区总大小

**错误示例：**
```c
/* ❌ P0 致命：裸数字 128，但 rx_buf 实际只有 64 字节 */
uint8_t rx_buf[64];
memcpy(rx_buf, dma_rx_buf, 128);   /* 越界写 64 字节 → 覆盖栈/全局变量 → HardFault */

/* ❌ P0 致命：结构体字节对齐导致 sizeof 计算错误（少见但致命） */
typedef struct { uint8_t cmd; uint32_t data; } pkt_t;  /* 实际 8 字节（对齐填充） */
memcpy(&pkt, raw_data, 5);   /* 只拷 5 字节，data 高 3 字节未初始化 = 随机值 */
```

**正确示例：**
```c
/* ✅ 长度用 sizeof，且两端都校验 */
uint8_t rx_buf[64];
uint8_t dma_rx_buf[256];
uint32_t copy_len = MIN((uint32_t)sizeof(rx_buf), dma_actual_len);
memcpy(rx_buf, dma_rx_buf, copy_len);

/* ✅ 结构体按实际 sizeof 拷 */
pkt_t pkt;
_Static_assert(sizeof(pkt_t) == 8U, "pkt_t size must be 8 bytes");  /* 编译期断言对齐 */
memcpy(&pkt, raw_data, sizeof(pkt_t));
```

---

#### P1-1：移位溢出（shift >= 类型位数）

**检查项：**
- [ ] `uint8_t` 移位不超过 7 位（`x << 8` 及以上是 UB 未定义行为）
- [ ] `uint16_t` 移位不超过 15 位
- [ ] `uint32_t` 移位不超过 31 位
- [ ] 移位位数是**变量**时，移位前先判断 `if (shift_bits < 32U)`
- [ ] 位操作用 `1U << n`，若 n>=31 必须用 `1UL << n`（防止 1U 是 32 位时溢出）

**错误示例：**
```c
/* ❌ P1 高风险：uint8_t 左移 8 位 — C 标准是 UB，不同编译器结果不同 */
uint8_t val = 0xAB;
uint16_t reg = (uint16_t)((val << 8) | 0xCD);
/* 可能结果 1：val 先提升 int 再移 → 正确 0xABCD */
/* 可能结果 2：val 按 uint8_t 移 8 → 先变 0 → 结果 0x00CD */

/* ❌ P1 高风险：移位位数是变量未判断 */
uint32_t build_mask(uint8_t bits) {
    return (1U << bits) - 1U;   /* bits == 32 时，1U << 32 是 UB！ */
}
```

**正确示例：**
```c
/* ✅ 先强制提升到目标类型再移位 */
uint8_t val = 0xAB;
uint16_t reg = (((uint16_t)val) << 8) | 0x00CDU;

/* ✅ 移位位数是变量时先判断范围 */
uint32_t build_mask(uint8_t bits) {
    if (bits == 0U)       { return 0U; }
    if (bits >= 32U)      { return 0xFFFFFFFFU; }
    return ((1UL << bits) - 1UL);  /* 用 1UL 防 32 位边界 */
}
```

#### P1-2：类型截断溢出（宽 → 窄赋值）

**检查项：**
- [ ] `uint32_t` → `uint16_t` / `uint8_t` 赋值前，是否判断值在窄类型范围内
- [ ] 定时器/计数器读取后放到小类型变量时，是否确认不会回绕
- [ ] `float` → `int` 转换前，是否判断在 int 范围内（且不是 NaN/Inf）

**错误示例：**
```c
/* ❌ P1 高风险：不加判断直接截断，1000 变成 232 */
uint32_t adc_sum = 1000U;     /* 累加 5 次 200 */
uint8_t  adc_avg = adc_sum / 5U;  /* 200 → 没问题 */
/* 但某次累加异常：adc_sum=10000 → avg=10000/5=2000 → uint8_t 截断成 208 */
```

**正确示例：**
```c
/* ✅ 截断前做范围判断，超出时处理饱和 */
uint32_t adc_sum = get_adc_sum();
uint32_t avg32 = adc_sum / 5U;
uint8_t  adc_avg;
if (avg32 > UINT8_MAX) {
    adc_avg = UINT8_MAX;   /* 饱和截断 */
    g_adc_sat_flag = 1U;
} else {
    adc_avg = (uint8_t)avg32;
}
```

#### P1-3：有符号/无符号隐式转换（四维防护 + 高危场景）

> **核心原则**：有符号/无符号混合运算是 C 语言中无数 Bug 的万恶之源。从以下四个维度系统防护。

**维度 1：优先使用有符号数（signed）**
- [ ] 存储数量和进行数学运算时，优先使用有符号类型（`int32_t` 而非 `uint32_t`）
- [ ] 即使值逻辑上应为非负（如长度、计数），也优先用有符号 — 避免"万一为负"时隐式转成巨大无符号数
- [ ] C++ 社区（含 Bjarne Stroustrup）强烈倡导此实践

**维度 2：明确无符号数的使用边界**
- [ ] 无符号类型**仅限以下场景**使用：
  - 位操作：位掩码、内存地址、硬件寄存器（`1U << 4`）
  - 明确的溢出行为：加密算法、随机数生成等需要模运算的场景
  - 系统级返回值：`size_t`（`sizeof`）、`strlen` 返回值等不可避免时

**维度 3：强制显式类型转换**
- [ ] 混合运算时**绝不依赖隐式转换**，必须显式 cast：`(size_t)len` / `(int32_t)u_val`
- [ ] 比较运算两端类型必须一致：`if ((size_t)len < sizeof(buf))` 而非 `if (len < sizeof(buf))`
- [ ] cast 前必须确保值在目标类型合法范围内（负数转无符号 = 灾难）

**维度 4：开启编译器严格警告**
- [ ] GCC/Clang：添加 `-Wsign-conversion -Wconversion` 编译选项
- [ ] MSVC（Keil ARMCC）：开启 `/W4` 或最高警告等级
- [ ] 警告必须清零，不能 suppress

**高危场景 1：无符号循环变量递减死循环**
- [ ] 禁止用无符号类型做递减循环边界判断

```c
/* ❌ 死循环：i 减到 0 后 --i 变成 UINT_MAX，永远 >= 0 */
for (uint8_t i = 10; i >= 0; --i) { ... }  /* uint8_t 永远 >= 0，条件恒真 */

/* ✅ 用有符号类型，或改用递增循环 */
for (int8_t i = 10; i >= 0; --i) { ... }   /* 有符号可以到 -1 退出 */
for (uint8_t i = 0; i <= 10; ++i) { ... }  /* 递增不会回绕 */
```

**高危场景 2：strlen 减法回绕**
- [ ] `strlen(s) - 1` 前必须先判断字符串非空

```c
/* ❌ 空字符串时 strlen 返回 0，0 - 1 = SIZE_MAX → 越界访问 */
size_t len = strlen(s) - 1;  /* s="" → len = 0xFFFFFFFF */
buf[len] = '\0';             /* 写到buf[4294967295] → HardFault */

/* ✅ 先判空再减 */
if (strlen(s) > 0) {
    size_t len = strlen(s) - 1;
    buf[len] = '\0';
}
```

**常规检查项：**
- [ ] `if (len < sizeof(buf))` 中 `len` 是 `int`（有符号）、`sizeof` 是 `size_t`（无符号）→ len 为负时恒真
- [ ] 循环变量用 `int` 但和 `size_t`/`uint*_t` 比较时，是否先转成一致类型
- [ ] 返回错误码（负整数，如 `-1`）和无符号成功码混用的地方，是否统一类型

**错误示例：**
```c
/* ❌ P1 高风险：len=-1 时被转成 size_t(0xFFFFFFFF)，恒大于 sizeof → 越界写 */
int parse_data(const char* input, int len) {
    char buf[64];
    if (len < sizeof(buf)) {              /* len=-1 → -1 转 size_t = 4294967295 */
        memcpy(buf, input, (size_t)len);  /* 拷 4GB → HardFault */
    }
}
```

**正确示例：**
```c
/* ✅ 统一用无符号类型 + 先判断合法性 */
int parse_data(const char* input, int len) {
    char buf[64];
    if (len <= 0) { return -1; }                                  /* 先排除非法长度 */
    if ((size_t)len < sizeof(buf)) {                              /* 再转同类型比较 */
        memcpy(buf, input, (size_t)len);
    }
}
```

### 2.6 运行时监控与调度语义（2026-08-27 SYGPAD V1 实战新增）

> 权威来源：`user_profile.md` 规则 6「时间基准铁律」（L1 强制，跨项目适用）。此处为审查清单精简版，冲突以 L1 为准。

- [ ] 周期/节拍/延时调度只允许用硬件时钟源（SysTick 计数、定时器、DWT 周期计数），禁止用主循环圈数或第三方任务函数的超时参数当时钟
- [ ] 用第三方 API 前必须查源码确认语义：阻塞/非阻塞、timeout 参数是否真实生效（例：TinyUSB 裸机 `tud_task_ext(timeout)` 的 timeout 被忽略，函数非阻塞）
- [ ] 周期性日志必须带真实时间戳（t5s/t10s 格式），无时间戳的计数值禁止用于推断运行时长
- [ ] 日志出现异常大小的计数值，先假设代码 bug，用外部事实（真实时钟、用户体感）交叉验证后再下结论
- [ ] 主循环 & 任务中禁止用"圈数计数"实现延时/心跳（圈数随代码路径变化，几毫秒 vs 500ms 不可控）

### 2.7 芯片系别差异审查表（按当前芯片动态加载，2026-08-27 新增）

> 权威来源：`chip-rules` 技能 `rules/` 目录各系别文件（L2 芯片系列层）。此处仅列出审查时需重点核对的高风险差异，新增条目时同步更新 chip-rules。

#### ARM Cortex-M（GD32/STM32 等，Keil）

- [ ] 中断优先级可配置（NVIC），ISR 抢占级顺序与项目一致（通信>定时>EXTI）；分组 PRE2_SUB2 写死在 main 首行
- [ ] 小端字节序；`volatile`/局部变量初始化等红线见 user_profile（L1）
- [ ] 库函数名不凭记忆写（`usart_baudrate_set` 风格），按 datasheet-lookup 查头文件
- [ ] GD32 与 STM32 库 API 不同，不能直接搬代码；GD32 外设配置前查 GD 官方资料（定时器编号/引脚复用表/PWM 模式语义）

#### 8051（STC8/STC15，Keil C51）

- [ ] **大端字节序**（与 ARM 小端相反），移植时注意
- [ ] 存储类型显式声明：`data`/`idata`/`xdata`/`code`；内存模型 small/large 与 RAM 匹配
- [ ] 8 位数据类型（u8/u16）与 ARM uint8_t 差异，运算提升规则不同
- [ ] 中断优先级不可配或有限（IE/IP 寄存器，部分型号查手册）
- [ ] 寄存器名因型号而异（STC8H 与 STC15 不同），按 datasheet-lookup 查阅
- [ ] GPIO 4 模式：准双向/推挽/开漏/高阻（PnM0/PnM1），上电默认准双向驱动弱

#### Xtensa / ESP32（FreeRTOS 环境，ESP-IDF）

- [ ] 基于 FreeRTOS 任务调度（非裸机前后台），ISR 与任务用队列/信号量/任务通知通信
- [ ] ESP32-S3 双核需考虑任务核心亲和性、跨核通信（自旋锁）
- [ ] 内存用 `heap_caps_malloc` 管理（可指定 PSRAM），长运行监控内存水位
- [ ] ESP32-C3 为 RISC-V 内核但工具链相同，内核差异注意
- [ ] 优先用 IDF API 避免直接操作寄存器；引脚分配用 pin-check 检查模组保留引脚

#### 新芯片系列（chip-rules 无对应规则文件时）

- [ ] 工具链/调试器/产物格式按官方文档确认（编译器、烧录工具、hex/axf/bin 类型）
- [ ] 字节序、数据类型宽度、中断模型先查手册再写代码
- [ ] 库函数命名风格以官方头文件为准，按 datasheet-lookup 查阅，禁止凭记忆写寄存器
- [ ] 向 `chip-rules` 新增 `rules/<系列>.md` 后再继续开发（按当前芯片自动加载机制）

---


## 三、volatile 规范

### 3.1 必须使用 volatile 的场景
- [ ] ISR 中修改的全局变量，主循环中读取的 → `volatile`
- [ ] 硬件寄存器映射（库头文件通常已处理，自定义寄存器访问需确认）
- [ ] 多任务（主循环 + 中断）共享的变量 → `volatile`
- [ ] ISR 回调和主循环任务共享的状态变量 → `volatile`（如 `cur_state`）

**检查示例：**
```c
/* ❌ 缺少 volatile，编译器优化后可能读不到更新 */
uint8_t g_rx_ready = 0;
void USART0_IRQHandler(void)
{
    g_rx_ready = 1;
}
/* 主循环中 while(!g_rx_ready); 可能被优化成死循环 */

/* ✅ 正确 */
volatile uint8_t g_rx_ready = 0;
```

### 3.2 volatile 不足的场景
- [ ] 16/32 位变量在 8 位 MCU 上的读写不是原子的 → 需要关中断保护
- [ ] 多变量的一致性 → 需要关中断或临界区

```c
/* 8 位 MCU 上 16 位变量读写需要保护 */
volatile uint16_t g_adc_value;
uint16_t read_adc_safe(void)
{
    uint16_t val;
    __disable_irq();        /* 或 EA = 0 */
    val = g_adc_value;
    __enable_irq();         /* 或 EA = 1 */
    return val;
}
```

## 四、GPIO 与外设配置

### 4.1 GPIO 复用配置
- [ ] USART TX 引脚配置为 AF（复用功能）模式，不是普通 OUTPUT
- [ ] 确认 `GPIO_output_af` 函数实际配置的是 `GPIO_MODE_AF`（函数名含 output 但配置的是 AF）
- [ ] RX 引脚可配为 INPUT 或 AF（GD32 上两者都能工作，AF 是标准做法）
- [ ] 换到 STM32 等芯片时需确认复用配置兼容性

### 4.2 未使用引脚
- [ ] 未使用引脚配置为模拟输入或上拉/下拉输入，不要悬空
- [ ] 或配置为输出并保持低电平

### 4.3 时钟配置
- [ ] 使用外设前确认已使能对应时钟（RCU）
- [ ] 确认 APB1/APB2 总线频率与外设要求匹配
- [ ] UART 波特率计算用的时钟源是否正确

## 五、代码规范

### 5.1 命名规范
- [ ] 函数和变量：下划线命名（如 `hal_gpio_set`，不用驼峰）
- [ ] 全局变量：`g_` 前缀（如 `g_ms_count`）
- [ ] 静态变量：`s_` 前缀（如 `s_rx_buf`）
- [ ] 宏定义：全大写（如 `LED_PIN`、`MAX_SIZE`）
- [ ] 结构体类型：`_t` 后缀（如 `pid_t`、`fifo_buf_t`）
- [ ] 枚举类型：`_e` 后缀（如 `usart_state_e`）
- [ ] 枚举值：全大写 + 模块前缀（如 `USART_STATE_IDLE`）

### 5.2 缩进
- [ ] 使用空格缩进（不是 Tab），禁止 Tab 与空格混用
- [ ] 单行不超过 120 字符，超出需合理换行
- [ ] if/else/for/while 即使只有一行也必须用 `{}` 包裹

### 5.3 不发明的函数
- [ ] 只使用项目中已有的封装函数
- [ ] 不凭经验发明不存在的函数（如 `GPIO_input_af`）
- [ ] 如果需要新函数，先确认参考项目中是否有类似实现

### 5.4 无符号常量加 U 后缀（实战踩坑）

> ⚠️ **踩坑记录**：无符号整型运算中，裸数字默认 int 类型，可能导致符号扩展和运算错误。

- [ ] 所有无符号整型常量加 `U` 后缀（如 `0U`、`1U`、`100U`）
- [ ] 位操作用 `1U` 而不是 `1`（如 `1U << 5U`）
- [ ] 16/32 位位运算用 `1UL`（如 `1UL << 31U`）
- [ ] 魔法数字替换为命名宏或枚举（如 `if (state == 3)` → `if (state == STATE_RUNNING)`）

**示例：**
```c
/* ❌ 裸数字，类型不明确 */
for (int i = 0; i < 8; i++) {
    state |= (1 << i);
}
if (state == 0xFFFF) { ... }
while(1) { ... }

/* ✅ U 后缀，类型明确 */
for (uint8_t i = 0U; i < 8U; i++) {
    state |= (1UL << i);  /* 32位用 1UL */
}
if (state == 0xFFFFU) { ... }
while(1U) { ... }
```

### 5.5 浮点字面量加 f 后缀（实战踩坑）

> ⚠️ **踩坑记录**：`3.3` 默认是 double 类型，混合运算时会触发隐式 double→float 转换，可能引入精度误差和性能开销。

- [ ] 所有 float 类型字面量加 `f` 后缀（如 `3.3f`、`4095.0f`）
- [ ] 浮点运算表达式中的常量都要加 f（如 `adc * 3.3f / 4095.0f`）

**示例：**
```c
/* ❌ double 隐式转换 */
float vol = adc * 3.3 / 4095;       /* 3.3 和 4095 是 double */
float duty_f = (duty / 100.0) * period;  /* 100.0 是 double */

/* ✅ float 直接运算 */
float vol = adc * 3.3f / 4095.0f;   /* 全是 float */
float duty_f = (duty / 100.0f) * (float)period;
```

### 5.6 const 最大化
- [ ] 只读变量加 `const`
- [ ] 函数参数中不被修改的指针加 `const`（如 `void send(const uint8_t* data, uint32_t len)`）
- [ ] 查找表加 `const`（如 `static const uint8_t table[] = {...}`，存到 Flash 省 RAM）

### 5.7 static 最大化
- [ ] 不对外暴露的函数加 `static`
- [ ] 仅文件内使用的全局变量加 `static`
- [ ] 头文件中只声明 `extern`，定义放 `.c` 文件

## 六、头文件一致性检查（修改代码时强制执行）

### 6.1 修改 .c 文件时
- [ ] 检查对应 .h 文件中的函数声明是否与实现签名一致（参数类型、返回值、个数）
- [ ] 如果新增/修改了宏定义，检查 .h 中是否有相关宏需要同步
- [ ] 如果修改了结构体定义，检查 .h 中的 extern 声明是否匹配
- [ ] 如果新增了全局变量，检查 .h 中是否需要添加 extern 声明

### 6.2 修改 .h 头文件时
- [ ] 检查所有 #include 该头文件的 .c 文件，确认引用处是否受影响
- [ ] 函数声明变更 → 找到所有调用处确认参数匹配
- [ ] 宏定义值变更 → 找到所有使用该宏的代码确认兼容
- [ ] 结构体增删字段 → 找到所有初始化代码确认需要更新
- [ ] 条件编译变更 → 确认编译路径正确

### 6.3 常见隐患
- [ ] 只改 .c 不看 .h → 声明与实现不一致，编译警告或运行错误
- [ ] 只改 .h 不看 .c → 引用处未更新，编译报错
- [ ] 宏改了但没全局搜索 → 其他文件的旧宏值导致逻辑错误
- [ ] 结构体加了字段但没更新初始化 → 未初始化字段值不确定

**检查方法：**
```
1. 用 Grep 搜索所有引用了被修改函数/宏/结构体的文件
2. 逐个确认是否需要同步修改
3. 特别注意跨文件引用和条件编译
```

## 七、工程文件红线

- [ ] 不用 PowerShell/XML 工具修改 Keil 工程文件（.uvprojx），会损坏 XML 结构
- [ ] 不碰 .uvprojx / .uvoptx 文件（由用户在 Keil IDE 中管理）
- [ ] 不碰厂商中断文件（如 gd32f4xx_it.c / stm32fxxx_it.c / stc8_it.c 等，除非用户明确要求）
- [ ] ISR 位置与参考项目保持一致

## 八、低功耗安全（实战踩坑）

> ⚠️ **踩坑记录**：进入睡眠模式后立即被 SysTick 中断唤醒，无需按键。

### 8.1 WFI/WFE 前关闭非必要中断
- [ ] 进入 `WFI`/`WFE` 低功耗模式前，关闭所有非必要中断源（尤其是 SysTick）
- [ ] 唤醒后恢复被关闭的中断
- [ ] 确认只有唤醒源（如 EXTI）的中断是使能的

**错误示例：**
```c
/* ❌ SysTick 每 1ms 触发一次，WFI 立即被唤醒 */
void sleep_mode(void)
{
    printf("before sleep\n");
    __WFI();  /* 立即被 SysTick 唤醒！ */
    printf("after sleep\n");  /* 立即打印，没真正睡眠 */
}
```

**正确示例：**
```c
/* ✅ 进入睡眠前关闭 SysTick，唤醒后恢复 */
void sleep_mode(void)
{
    printf("before sleep\n");
    SysTick->CTRL &= ~SysTick_CTRL_TICKINT_Msk;  /* 关闭 SysTick 中断 */
    __WFI();  /* 等待 EXTI 唤醒 */
    SysTick->CTRL |= SysTick_CTRL_TICKINT_Msk;   /* 恢复 SysTick 中断 */
    printf("after sleep\n");  /* 按键后才打印 */
}
```

### 8.2 唤醒后优先处理唤醒源
- [ ] 从低功耗唤醒后，立即处理唤醒源事件，不要走常规消抖/延时流程
- [ ] 睡眠期间不会有按键抖动，唤醒后无需消抖

## 九、长时间运行可靠性审查（条件强制项）

> ⚠️ **本节为条件强制项**：当项目需要 7×24 小时连续运行（工业控制 / 物联网 / 数据采集等）时，**必须逐项检查**。短期验证项目可跳过。
>
> 长时间运行最典型的故障现象：运行几小时/几天后死机、复位、数据错乱、通信中断——这些问题在开发阶段几乎无法复现，必须在代码审查阶段提前消除。

### 9.1 看门狗是否启用及喂狗位置

**检查项：**
- [ ] 项目中是否启用了看门狗（IWDG / WDT / Task WDT）
- [ ] 喂狗代码在**主循环**中，**不是**在中断里（中断可能还在跑但主循环已死锁）
- [ ] 喂狗周期合理：不能太短（正常耗时任务误触发），不能太长（故障恢复慢）
- [ ] 多任务系统（FreeRTOS）中，喂狗任务优先级要低，确保所有高优先级任务正常才喂狗

**错误示例：**
```c
/* ❌ 在定时器中断里喂狗 — 主循环死了但中断还在跑，看门狗永远不会触发 */
void TIM2_IRQHandler(void)
{
    g_ms_count++;
    if (g_ms_count % 1000U == 0U) {
        fwdgt_counter_reload();  /* 禁止！中断里喂狗 */
    }
}
```

**正确示例：**
```c
/* ✅ 在主循环末尾喂狗 — 只有主循环正常跑到这里才喂 */
int main(void)
{
    system_init();
    while (1U) {
        task_uart_process();
        task_sensor_read();
        task_comm_handle();
        fwdgt_counter_reload();  /* 所有任务跑完才喂狗 */
    }
}
```

### 9.2 所有通信总线必须有超时退出

**检查项：**
- [ ] I2C 读/写等待有超时退出（不能 `while(!flag);` 死等）
- [ ] SPI 等待 TXE/RXNE 有超时退出
- [ ] UART 等待发送完成有超时退出
- [ ] MODBUS/CAN 等协议等待响应有超时退出
- [ ] 超时后有错误恢复动作（总线复位 / 重新初始化 / 报错）

**错误示例：**
```c
/* ❌ 死等 I2C 应答 — 从器件故障时整个系统挂死 */
void i2c_wait_ack(void)
{
    while (I2C_SDA_READ()) {
        ;  /* 从器件无应答 → 永远卡在这里 */
    }
}
```

**正确示例：**
```c
/* ✅ 超时退出 + 错误恢复 */
#define I2C_ACK_TIMEOUT  200U  /* 超时计数器上限 */

uint8_t i2c_wait_ack(void)
{
    uint16_t timeout = 0U;
    while (I2C_SDA_READ()) {
        timeout++;
        if (timeout >= I2C_ACK_TIMEOUT) {
            i2c_bus_reset();       /* 总线复位 */
            return 1U;              /* 返回错误码 */
        }
        i2c_delay();
    }
    return 0U;  /* 正常应答 */
}
```

### 9.3 Flash 存储磨损均衡

**检查项：**
- [ ] 频繁写入的参数（校准值 / 计数器 / 配置）不能总写同一地址
- [ ] 使用环形结构分散写入（写满一圈再擦除，而非每次写同一位置）
- [ ] 写入前检查是否需要擦除（Flash 只能 1→0，需先擦除整扇区）
- [ ] Flash 擦写次数在芯片规格书限制内（典型 10 万次/扇区）

**错误示例：**
```c
/* ❌ 每次都写同一地址 — 10万次后该扇区写坏 */
void save_config(config_t *p_cfg)
{
    flash_erase_page(CONFIG_ADDR);
    flash_write(CONFIG_ADDR, p_cfg, sizeof(config_t));
}
```

**正确示例：**
```c
/* ✅ 环形写入：每次写下一个槽位，写满一圈再擦除 */
#define CONFIG_SLOT_COUNT  64U   /* 64 个槽位轮流写 */
#define CONFIG_SLOT_SIZE   256U  /* 每个槽位对齐 Flash 页大小 */

typedef struct {
    uint16_t magic;        /* 魔数，标识有效数据 */
    uint16_t seq;          /* 序列号，找最新数据用 */
    config_t config;       /* 实际配置 */
    uint16_t crc;          /* CRC 校验 */
} config_slot_t;

void save_config_wear_level(config_t *p_cfg)
{
    /* 1. 找当前最新槽位 */
    uint16_t latest_seq = 0U;
    uint16_t latest_idx = 0U;
    for (uint16_t i = 0U; i < CONFIG_SLOT_COUNT; i++) {
        config_slot_t *p_slot = (config_slot_t *)(CONFIG_BASE_ADDR + i * CONFIG_SLOT_SIZE);
        if (p_slot->magic == CONFIG_MAGIC && p_slot->seq > latest_seq) {
            latest_seq = p_slot->seq;
            latest_idx = i;
        }
    }
    /* 2. 写下一个槽位（环形） */
    uint16_t next_idx = (latest_idx + 1U) % CONFIG_SLOT_COUNT;
    if (next_idx == 0U) {
        /* 一圈写完，擦除整扇区 */
        flash_erase_sector(CONFIG_BASE_ADDR);
    }
    config_slot_t new_slot;
    new_slot.magic = CONFIG_MAGIC;
    new_slot.seq   = latest_seq + 1U;
    new_slot.config = *p_cfg;
    new_slot.crc   = calc_crc16((uint8_t *)&new_slot.config, sizeof(config_t));
    flash_write(CONFIG_BASE_ADDR + next_idx * CONFIG_SLOT_SIZE, &new_slot, sizeof(new_slot));
}
```

### 9.4 关键参数多份存储 + CRC 校验

**检查项：**
- [ ] 关键参数（校准值 / 设备地址 / 运行状态）存 **3 份**，读取时取多数一致
- [ ] 每份存储区附带 CRC16/CRC32 校验
- [ ] 读取时校验失败则使用默认安全值，不能使用损坏数据
- [ ] 三份都损坏时进入安全降级模式并报警

**正确示例：**
```c
/* ✅ 三份冗余 + CRC 校验，取多数一致 */
typedef struct {
    uint32_t magic;
    calib_data_t calib;
    uint16_t crc;
} calib_store_t;

calib_data_t load_calib_safe(void)
{
    calib_store_t copies[3];
    /* 读取三份 */
    for (uint8_t i = 0U; i < 3U; i++) {
        flash_read(CALIB_BASE_ADDR + i * sizeof(calib_store_t), &copies[i], sizeof(calib_store_t));
    }
    /* CRC 校验 */
    uint8_t valid[3] = {0U, 0U, 0U};
    for (uint8_t i = 0U; i < 3U; i++) {
        uint16_t crc_calc = calc_crc16((uint8_t *)&copies[i].calib, sizeof(calib_data_t));
        if (copies[i].magic == CALIB_MAGIC && copies[i].crc == crc_calc) {
            valid[i] = 1U;
        }
    }
    /* 取多数一致（至少两份相同且有效） */
    for (uint8_t i = 0U; i < 3U; i++) {
        for (uint8_t j = i + 1U; j < 3U; j++) {
            if (valid[i] && valid[j] &&
                memcmp(&copies[i].calib, &copies[j].calib, sizeof(calib_data_t)) == 0) {
                return copies[i].calib;  /* 两份一致，可信 */
            }
        }
    }
    /* 只有一份有效或没有有效 → 用默认安全值 */
    calib_data_t default_calib = get_default_calib();
    return default_calib;
}
```

### 9.5 全局计数器/索引无无限增长

**检查项：**
- [ ] 所有 `g_xxx_count++` 类型的计数器，确认是否会溢出（uint32_t 约 42 亿，uint16_t 约 6.5 万）
- [ ] 环形缓冲区的读写指针有 `% SIZE` 回绕
- [ ] 累计统计量（总字节数 / 总次数）超过上限后有处理策略（回绕 / 清零 / 报警）
- [ ] 时间戳变量类型足够大（`uint32_t` 毫秒计数约 49 天回绕，长期运行必须考虑）

**错误示例：**
```c
/* ❌ 环形缓冲区指针不回绕 — 跑一会儿就越界 */
volatile uint16_t g_rx_head = 0U;
void uart_rx_handler(uint8_t data)
{
    g_rx_buf[g_rx_head++] = data;  /* g_rx_head 不断增长 → 越界！ */
}
```

**正确示例：**
```c
/* ✅ 指针回绕 + 计数器用 uint32_t 并考虑回绕 */
#define RX_BUF_SIZE  256U
volatile uint16_t g_rx_head = 0U;
volatile uint32_t g_rx_total = 0U;  /* 总接收字节数（统计用，可回绕） */

void uart_rx_handler(uint8_t data)
{
    if (g_rx_head < RX_BUF_SIZE) {
        g_rx_buf[g_rx_head] = data;
        g_rx_head = (g_rx_head + 1U) % RX_BUF_SIZE;  /* 回绕 */
    }
    g_rx_total++;  /* 统计量回绕无影响（只是统计值） */
}
```

### 9.6 安全降级模式设计（M3）

> ⚠️ **实战教训**：传感器掉线/外设故障时，程序继续用错误数据计算 → 输出非法控制量 → 执行机构误动作，造成事故。必须在故障时进入"安全状态"，哪怕功能降级、全部停掉，也比输出错误结果强。

**检查项：**
- [ ] 系统是否定义了**全局安全状态枚举**（正常 / 降级 / 故障安全停止）和状态转移逻辑
- [ ] 所有外部输入通道（传感器/通信/按键）检测异常时是否有明确的故障分支，不是"继续用旧值/随机值"
- [ ] 执行机构（电机/阀门/加热器/高压输出）在收到非法参数或检测到系统异常时，是否自动切换到安全位置（关闭 / 停止 / 泄压）
- [ ] 通信链路超时后是否自动进入安全降级（不是死等，也不是用上次数据假装正常）
- [ ] Watchdog 复位 / 上电复位后，是否先执行自检并进入安全态，确认无故障才开始正常输出
- [ ] 是否有报警通道（LED 闪烁 / 蜂鸣器 / 上位机报警帧），通知用户当前处于降级模式

**错误示例：**
```c
/* ❌ 传感器读取失败时，直接返回旧值 — 系统无法区分是正常还是故障 */
int32_t read_temperature(void)
{
    static int32_t s_last_temp = 250;  /* 上次温度 */
    int32_t raw = spi_read_temp_raw();
    if (raw < 0) {
        return s_last_temp;  /* 错误：返回旧值，调用者不知道是假数据！ */
    }
    s_last_temp = raw;
    return raw;
}

void control_heater(void)
{
    int32_t t = read_temperature();
    if (t < TARGET_TEMP) {
        heater_on();  /* 如果传感器坏了永远返回旧值，加热器可能一直开着！ */
    } else {
        heater_off();
    }
}
```

**正确示例：**
```c
/* ✅ 安全降级模式：系统状态 + 错误码 + 故障分支进入安全态 */
typedef enum {
    SYS_STATE_RUNNING = 0U,   /* 正常运行 */
    SYS_STATE_DEGRADED = 1U,  /* 部分功能失效，输出保持上次安全值 */
    SYS_STATE_SAFESTOP = 2U   /* 故障安全：所有输出关闭，报警 */
} sys_state_e;

typedef struct {
    sys_state_e state;
    uint32_t    fault_mask;   /* 每一位对应一种故障来源 */
} sys_status_t;

volatile sys_status_t g_sys_status;  /* 全局系统状态，ISR 也能读 */

/* 传感器读取：返回错误码，不伪装数据 */
bool read_temperature_safe(int32_t *p_temp_out)
{
    if (p_temp_out == NULL) { return false; }
    int32_t raw = spi_read_temp_raw();
    if (raw < 0 || raw > 1250) {  /* 物理范围检查（-40°C ~ +125°C ×10） */
        return false;             /* 调用者明确知道失败 */
    }
    *p_temp_out = raw;
    return true;
}

/* 控制循环：所有输入都经过有效性检查 + 状态转移 */
void control_loop(void)
{
    int32_t temp;
    if (!read_temperature_safe(&temp)) {
        /* 传感器故障：标记 + 进入故障安全停止 */
        g_sys_status.fault_mask |= FAULT_TEMP_SENSOR;
        enter_safe_stop("TEMP_FAULT");
        return;
    }
    /* ... 正常控制逻辑 ... */
}

/* 故障安全进入点：所有执行机构关闭 + 报警 */
void enter_safe_stop(const char *reason)
{
    g_sys_status.state = SYS_STATE_SAFESTOP;
    heater_off();       /* 关闭所有执行机构 */
    motor_stop();
    valve_close();
    alarm_blink_start();/* 启动 LED 报警 */
    log_event(reason);  /* 记录故障原因（便于事后排查） */
    /* 之后主循环只跑安全态子循环，不再进入控制逻辑 */
}
```

### 9.7 对外操作幂等性设计（M4）

> ⚠️ **实战教训**：网络重传 / 用户重复点击按钮 / 通信超时重试导致初始化函数被调用两次 → 全局变量被清零 / Flash 被重复擦写 / 状态机被重置。结果是系统正常运行一段时间后突然掉状态。

**检查项：**
- [ ] `xxx_init()` 函数是否幂等：调用两次与调用一次结果相同（先检查是否已初始化，避免重复初始化）
- [ ] Flash 写 / 配置保存操作是否有幂等保护：写前判断内容是否已一致，相同则不擦不写
- [ ] 状态机转移是否有非法转移检测：`CURR_STATE → NEXT_STATE` 不合法时进入安全态，而不是直接赋值
- [ ] 所有通过外部事件触发的动作（按键 / 通信指令）是否有"去重"机制，短时间重复触发只执行一次
- [ ] `xxx_deinit()` / 资源释放函数被重复调用时是否安全（指针判空、已释放后再释放不报错）

**错误示例：**
```c
/* ❌ 非幂等：多次调用会破坏已运行的状态 */
void uart_init(void)
{
    usart_deinit(USART0);            /* 先关 */
    usart_baudrate_set(USART0, 115200U);
    usart_enable(USART0);
    g_rx_head = 0U;                   /* 把运行中收到的数据指针清零 */
    g_uart_initialized = 1U;
    /* 如果运行中因总线复位/网络重传再次调用，缓冲区丢数据 */
}

/* ❌ 非幂等配置保存：每次都擦写 Flash，哪怕值没变 */
void save_config(const config_t *p_cfg)
{
    flash_erase_page(CONFIG_ADDR);  /* 每次都擦（10万次寿命很快耗完） */
    flash_write(CONFIG_ADDR, p_cfg, sizeof(config_t));
}
```

**正确示例：**
```c
/* ✅ 幂等 init：先判断是否已初始化，已初始化直接返回 */
uint8_t g_uart_inited = 0U;
void uart_init_safe(void)
{
    if (g_uart_inited) { return; }   /* 已初始化 → 跳过 */
    usart_deinit(USART0);
    usart_baudrate_set(USART0, 115200U);
    usart_enable(USART0);
    g_rx_head = 0U;
    g_uart_inited = 1U;
}

/* ✅ 幂等配置保存：比较后再写，相同不擦不写 */
config_t s_shadow_config;     /* 运行时的配置影子副本，上电时从 Flash 读入 */
uint8_t s_shadow_valid = 0U;

bool save_config_safe(const config_t *p_cfg)
{
    if (p_cfg == NULL) { return false; }

    /* 1. 与影子副本比较，完全相同则跳过，减少 Flash 磨损 */
    if (s_shadow_valid && memcmp(&s_shadow_config, p_cfg, sizeof(config_t)) == 0) {
        return true;  /* 没变化，不写 Flash */
    }
    /* 2. 写新配置（磨损均衡已由 9.3 环形机制保障） */
    if (!flash_write_config(p_cfg)) {
        return false;
    }
    /* 3. 更新影子副本 */
    s_shadow_config = *p_cfg;
    s_shadow_valid = 1U;
    return true;
}

/* ✅ 幂等状态转移：只有合法转移才生效 */
typedef enum {
    STATE_IDLE, STATE_RUNNING, STATE_PAUSED, STATE_STOPPED
} fsm_state_e;
fsm_state_e g_fsm = STATE_IDLE;

void fsm_transition(fsm_state_e next)
{
    /* 合法转移表（白名单），其余一律拒绝并警告 */
    bool valid = false;
    switch (g_fsm) {
    case STATE_IDLE:    valid = (next == STATE_RUNNING);                              break;
    case STATE_RUNNING: valid = (next == STATE_PAUSED || next == STATE_STOPPED);      break;
    case STATE_PAUSED:  valid = (next == STATE_RUNNING || next == STATE_STOPPED);    break;
    case STATE_STOPPED: valid = (next == STATE_IDLE);                                break;
    }
    if (valid) {
        g_fsm = next;
    } else {
        log_warn("FSM invalid transition %u -> %u", g_fsm, next);
        enter_safe_stop("FSM_INVALID");
    }
}
```

### 9.8 NVIC 中断抢占优先级分组（Q7，实战必踩）

> ⚠️ **踩坑记录**：同一外设中断默认优先级下，EXTI 按键中断（或外部长脉冲中断）抢占级不低于 UART/SPI/I2C 通信中断，导致按键抖动消抖回调/长 ISR 阻塞串口 RX 数据溢出丢包，事后抓不到原因。
> 另一坑：未显式调用 `NVIC_PriorityGroupConfig()` / `nvic_priority_group_set()`，默认优先级分组 0 意味着"所有中断抢占级相同，仅次优先级排序"，即所有 ISR 互相不能抢占，系统相当于轮询+无法紧急抢占响应。

**检查项：**
- [ ] 已在 `main()` 开头（任何外设初始化前）显式写死 NVIC 优先级分组，**不依赖默认值**。GD32：`nvic_priority_group_set(NVIC_PRIGROUP_PRE2_SUB2)`；STM32：`HAL_NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_2)`
- [ ] 抢占级严格顺序：**通信中断（UART/SPI/I2C） > 定时器 > EXTI 按键/通用外部中断 > 看门狗/其他**
  - 抢占级数字越小优先级越高（GD32/STM32/Cortex-M 约定），例：PRE2 分组下 UART=0/0，TIMER=1/0，EXTI_KEY=2/0，DMA=0/1
- [ ] 次优先级仅用于"抢占级相同、同时到达"的排队，不可当抢占级用
- [ ] 有 FreeRTOS 的项目：`configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`（或 `configMAX_SYSCALL_INTERRUPT_PRIORITY`）已设为合理值（例 5），优先级低于该阈值的 ISR 方可调用 `FromISR` API；高于该阈值的高优硬件 ISR（紧急信号）不得调用任何 FreeRTOS API
- [ ] DMA 通道优先级与外设抢占级匹配：高速 UART DMA 不被低速 SPI DMA 抢占

**错误示例：**
```c
/* ❌ 默认 NVIC_PRIGROUP 0（0 抢占/4 子优先级）——所有 ISR 互相不能抢占，
   UART 正在收包时 EXTI 进来 2ms 消抖，RX Overrun 丢包却找不到原因 */
// 全项目没有任何 nvic_priority_group_set() 调用

/* ❌ 抢占级顺序写反 — 按键中断抢占级 0（最高），通信中断抢占级 2 */
nvic_irq_enable(EXTI10_15_IRQn, 0, 0);   /* EXTI 按键 */
nvic_irq_enable(USART0_IRQn,   2, 0);   /* UART 收数据 */
```

**正确示例：**
```c
/* ✅ main() 开头写死分组 + 严格抢占顺序 */
int main(void)
{
    nvic_priority_group_set(NVIC_PRIGROUP_PRE2_SUB2);  /* 必须第一时间设置 */
    system_clock_config();

    /* 抢占级：UART(0) > TIMER(1) > EXTI(2) */
    nvic_irq_enable(USART0_IRQn,    0, 0);  /* 最高抢占级，不被任何人阻塞 */
    nvic_irq_enable(TIMER1_IRQn,    1, 0);  /* 定时器次高 */
    nvic_irq_enable(EXTI10_15_IRQn, 2, 0);  /* 按键最低抢占级 */
    ...
}
```

---

## 十、外设特定坑

### 10.1 OLED 中文编码（实战踩坑）

> ⚠️ **踩坑记录**：OLED 字库芯片（如 GT30L32S4W）按 GB2312 编码查找字模地址，如果 main.c 是 UTF-8 编码，汉字字符串字面量会变成 UTF-8，导致字库芯片按错误地址查找。

- [ ] 使用 GB2312 字库芯片的 OLED，汉字字符串必须用 GB2312 编码
- [ ] 如果文件编码必须是 UTF-8，汉字字符串用 GB2312 八进制转义序列表示

**示例：**
```c
/* ❌ UTF-8 文件中直接写汉字，字库芯片按 UTF-8 字节查 GB2312 地址 → 乱码 */
printf("中文字库");          /* OLED 显示乱码 */
OLED_show_str("电压");

/* ✅ 用 GB2312 八进制转义序列，文件编码保持 UTF-8 */
/* "中文字库" 的 GB2312 编码：D6 D0 CE C4 D7 D6 BF E2 */
printf("\326\320\316\304\327\326\277\342");
OLED_show_str("\265\347\321\271");  /* "电压" */
```

### 10.2 I2C 时序（实战踩坑）

> ⚠️ **踩坑记录**：软件 I2C 在 FAST 模式下时序参数配置不当，导致 OLED 显示乱码。

- [ ] 软件 I2C 驱动需严格按 datasheet 配置时序参数
- [ ] 不同速率模式（标准/快速）下需单独验证
- [ ] 延时函数需根据时钟频率精确计算

### 10.3 DMA 函数名（实战踩坑）

> ⚠️ **踩坑记录**：凭记忆写了 `dma_struct_para_init()`，实际 GD32F4xx 标准库中是 `dma_single_data_para_struct_init()`。

- [ ] 调用厂商库函数前，**必须**先用 Grep 搜索头文件确认函数名和参数
- [ ] 不凭记忆写库函数名，不同厂商/不同系列可能完全不同

### 10.4 ADC 多通道采集
- [ ] 多通道扫描模式，确认每个通道都等待转换完成
- [ ] DMA 循环模式下，确认缓冲区大小与通道数匹配
- [ ] 插入通道和规则通道不要混用，除非明确理解差异

### 10.5 SPI 切外设重配 CPOL/CPHA（Q8，多设备必踩）

> ⚠️ **踩坑记录**：同一 SPI 总线挂多个从设备（如 Flash W25Q=Mode0, OLED SSD1331=Mode3, ADC AD7606=Mode2），先初始化一次 SPI 配置为 Mode0，后续切片选后以为"CPOL/CPHA 配置还在"就直接收发，结果 OLED/ADC 拿到的数据全是错的或偶发错误——因为某个从设备中途响应了一个命令导致模式寄存器被意外改写（或早期芯片在 CS 释放后仍维持总线状态），或者中途调用过别的驱动做了重配。

**检查项：**
- [ ] **同一 SPI 挂多个设备时，每次片选拉低前先重新完整配置 SPI**：CPOL/CPHA、数据位宽（8/16 位）、波特率预分频、MSB/LSB First、全双工/半双工/单线模式，**不要假设"上次配置还在"**
- [ ] SPI 切设备时序：`SPI 重新配置 → 延时 20ns（或 1 个 SPI_CLK 周期）→ CS 拉低 → 收发 → CS 拉高`（部分 Flash 要求 CS 高电平最小脉宽 tSLSH ≥ 50ns，也要满足）
- [ ] 每个从设备写独立的 `xxx_spi_begin()/xxx_spi_end()` 封装，begin 内部先做重配再拉低 CS
- [ ] 若有低速外设（OLED 400KHz）和高速外设（Flash 40MHz）共总线，每次切设备必须同时重设 `baudrate_psc`（否则 OLED 切到 40MHz 直接丢数据）
- [ ] SPI DMA 收发时，切设备前先确认 DMA 传输已完成（`dma_transfer_done()` / `HAL_SPI_GetState()`）再重配寄存器，避免 DMA 还在跑时改寄存器导致错位

**错误示例：**
```c
/* ❌ 假设 SPI 配置不变，切设备只拉 CS */
void flash_read(uint32_t addr, uint8_t *buf, uint16_t len) {
    gpio_bit_reset(GPIOA, GPIO_PIN_4);  /* Flash CS 拉低 */
    spi_transfer(0x03);
    ...
    gpio_bit_set(GPIOA, GPIO_PIN_4);
}
void oled_cmd(uint8_t cmd) {
    gpio_bit_reset(GPIOB, GPIO_PIN_0);  /* OLED CS 拉低，直接发！*/
    spi_transfer(cmd);                  /* 如果 Flash 是 Mode0，OLED 是 Mode3 — 全错 */
    gpio_bit_set(GPIOB, GPIO_PIN_0);
}
```

**正确示例：**
```c
/* ✅ 每个从设备 begin() 里完整重配 SPI */
static void spi_cfg_flash_mode0(void) {
    spi_parameter_struct sp;
    sp.trans_mode     = SPI_TRANSMODE_FULLDUPLEX;
    sp.master_mode    = SPI_MASTER;
    sp.frame_size     = SPI_FRAMESIZE_8BIT;
    sp.clock_polarity = SPI_CK_PL_LOW;       /* Mode0: CPOL=0 */
    sp.clock_phase    = SPI_CK_PH_1EDGE;     /* Mode0: CPHA=0 */
    sp.prescale       = SPI_PSC_4;           /* 高速 40MHz */
    spi_init(SPI0, &sp);
    spi_enable(SPI0);
}
static void spi_cfg_oled_mode3(void) {
    spi_parameter_struct sp;
    sp.trans_mode     = SPI_TRANSMODE_FULLDUPLEX;
    sp.master_mode    = SPI_MASTER;
    sp.frame_size     = SPI_FRAMESIZE_8BIT;
    sp.clock_polarity = SPI_CK_PL_HIGH;      /* Mode3: CPOL=1 */
    sp.clock_phase    = SPI_CK_PH_2EDGE;     /* Mode3: CPHA=1 */
    sp.prescale       = SPI_PSC_64;          /* 低速 2.5MHz */
    spi_init(SPI0, &sp);
    spi_enable(SPI0);
}

void oled_begin(void)  { spi_cfg_oled_mode3();  __NOP(); __NOP(); gpio_bit_reset(GPIOB, GPIO_PIN_0); }
void flash_begin(void) { spi_cfg_flash_mode0(); __NOP(); __NOP(); gpio_bit_reset(GPIOA, GPIO_PIN_4); }
void oled_end(void)    { gpio_bit_set(GPIOB, GPIO_PIN_0); }
void flash_end(void)   { gpio_bit_set(GPIOA, GPIO_PIN_4); }
```

### 10.6 I2C SCL 9 脉冲恢复序列 + BUSY 死锁（Q9，量产必踩）

> ⚠️ **踩坑记录**：客户现场热插拔 I2C 设备或主芯片中途看门狗复位（复位时 I2C 外设正在通信，从机收到了半个字节正等第 9 个 CLK），从机把 SDA 拉低不放，主芯片 I2C BUSY 标志一置位就再也清不掉——"上电好的，工作 3 天后 I2C 所有设备读不出来，重启恢复"。
> 经典根因：从机收到 8 个 CLK 后要回 ACK（SDA 拉低），但主芯片因复位/热插拔没发那第 9 个 CLK，从机永远卡在"等待第 9 个 CLK 释放 SDA"状态，除非收到 9 个 CLK 或断电。

**检查项：**
- [ ] I2C 初始化流程第一步：先读 `I2C_STAT0_BUSY` 标志，若已置位 → 走 SCL 9 脉冲软件恢复序列，再重初始化 I2C 外设
- [ ] SCL 9 脉冲恢复序列完整步骤：
  1. 失能 I2C 外设
  2. 把 SCL / SDA 引脚切为 GPIO 开漏输出（或推挽+外部上拉），电平先置高
  3. 先尝试发 START → SDA 拉低 → SCL 拉低 → 若读回 SDA 仍然低 → 从机在拉，必须脉冲清
  4. 循环 9 次：SCL 拉高（延时 tLOW ≥ 4.7us 标准 / 1.3us 快速模式）→ SCL 拉低 → 延时；每步读回 SDA 确认释放
  5. 9 次脉冲后发 STOP：SDA 拉低 → SCL 拉高 → SDA 拉高（释放 STOP 条件）
  6. 切回 I2C 外设复用模式，重新 `i2c_init()`，再查 BUSY 标志应清零
- [ ] 每次 I2C 收发超时（I2C_TIME_FLAG=1）走一次恢复序列，而不是只 `i2c_deinit()`/`i2c_init()`（纯 deinit/init 对"从机拉低 SDA"完全无效，因为根因在外设之外的物理引脚状态）
- [ ] 量产项目有热插拔可能时：SDA/SCL 加 TVS 管防 ESD；上拉电阻选型标准模式 4.7kΩ / 快速模式 1kΩ 左右
- [ ] 若软件 I2C：在每次 `i2c_start()` 中内置 SCL 脉冲恢复（发现 SDA 拉低时自动走 9 脉冲），不要等上层超时才处理

**错误示例：**
```c
/* ❌ 只做 deinit + init，碰到从机拉低 SDA 的死锁完全无效 */
void i2c_reset_bad(void) {
    i2c_deinit(I2C0);
    i2c_init(I2C0, 100000);       /* 重新 init 后 BUSY 还在，从机一直拉低 SDA 不放 */
    i2c_enable(I2C0);
}
```

**正确示例（SCL 9 脉冲恢复 GD32 模板）：**
```c
/* ✅ 9 脉冲恢复序列：主芯片用 GPIO 模拟 CLK 把从机内部移位寄存器推完一整字节 */
#define I2C_SCL_PORT GPIOB
#define I2C_SCL_PIN  GPIO_PIN_6
#define I2C_SDA_PORT GPIOB
#define I2C_SDA_PIN  GPIO_PIN_7

static void i2c_gpio_recover_9clk(void) {
    /* 1. 关 I2C 外设 */
    i2c_disable(I2C0);

    /* 2. 切 SCL/SDA 为 GPIO 推挽（或开漏，取决于硬件设计）+ 初始高 */
    gpio_mode_set(I2C_SCL_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SCL_PIN);
    gpio_output_options_set(I2C_SCL_PORT, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, I2C_SCL_PIN);
    gpio_bit_set(I2C_SCL_PORT, I2C_SCL_PIN);

    gpio_mode_set(I2C_SDA_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
    gpio_output_options_set(I2C_SDA_PORT, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, I2C_SDA_PIN);
    gpio_bit_set(I2C_SDA_PORT, I2C_SDA_PIN);
    delay_us(5);

    /* 3. 若此时 SDA 读回来仍然低 → 从机卡住，开始 9 脉冲 */
    if (gpio_input_bit_get(I2C_SDA_PORT, I2C_SDA_PIN) == RESET) {
        for (uint8_t i = 0; i < 9; i++) {
            gpio_bit_reset(I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
            gpio_bit_set  (I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
        }

        /* 4. 发送 STOP 条件：SDA 低 → SCL 高 → SDA 高（释放） */
        gpio_bit_reset(I2C_SDA_PORT, I2C_SDA_PIN); delay_us(5);
        gpio_bit_set  (I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
        gpio_bit_set  (I2C_SDA_PORT, I2C_SDA_PIN); delay_us(5);   /* STOP 发完，SDA 应为高 */
    }

    /* 5. 切回 I2C 复用功能 */
    gpio_mode_set(I2C_SCL_PORT, GPIO_MODE_AF, GPIO_PUPD_PULLUP, I2C_SCL_PIN);
    gpio_mode_set(I2C_SDA_PORT, GPIO_MODE_AF, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
}

/* ✅ 任何 I2C 初始化 / 超时错误回调都先调恢复序列 */
static inline void i2c_init_safe(uint32_t speed) {
    i2c_gpio_recover_9clk();
    i2c_init(I2C0, speed);
    i2c_enable(I2C0);
}
```

---

## 十一、编译与链接

> ⚠️ **强制项**：每次构建前必须确认。很多"Debug 版正常、Release 版死机"的问题都出在这里。

### 11.1 编译警告清零

**检查项：**
- [ ] 编译警告全部开启（GCC: `-Wall -Wextra`，Keil: Options → C/C++ → Warnings → All Warnings）
- [ ] 构建输出中 **0 个 warning**（不是"忽略"，是全部修复）

**常见被忽略的警告：**
```c
/* warning: implicit declaration of function 'xxx' → 头文件没包含，函数签名可能变了 */
/* warning: assignment from integer without a cast → 类型截断，可能丢数据 */
/* warning: comparison between signed and unsigned → 有符号/无符号比较，可能逻辑错 */
/* warning: unused variable 'xxx' → 声明了没用，可能是忘写逻辑了 */
```

### 11.2 优化级别对代码行为的影响

**检查项：**
- [ ] Debug 版（`-O0`）和 Release 版（`-O2`/`-Os`）都测试通过
- [ ] 延时循环用 `volatile` 计数器（否则 `-O2` 会直接删掉循环）
- [ ] 硬件寄存器读操作的结果被使用（否则编译器可能删掉读操作）

**错误示例：**
```c
/* ❌ 优化后延时循环被删除 */
void delay_bad(uint32_t count)
{
    while (count--) { }  /* -O2 直接删掉，count 是局部变量，没有副作用 */
}

/* ✅ 用 volatile 防止优化 */
void delay_good(volatile uint32_t count)
{
    while (count--) { }  /* volatile 保证每次都读内存，循环不会被删 */
}
```

### 11.3 结构体 `__packed` 与非对齐访问

**检查项：**
- [ ] `__packed`/`#pragma pack` 结构体不直接解引用成员指针（用 `memcpy` 替代）
- [ ] Cortex-M0/M0+（GD32F1/STM32F0/ESP32-C3 等）上**禁止**非对齐访问（`uint32_t*` 指向非 4 字节对齐地址 → HardFault）
- [ ] 网络协议帧解析时，不从帧体直接 cast 指针，用 `memcpy` 到对齐的局部变量

**错误示例：**
```c
typedef __packed struct {
    uint8_t  type;
    uint32_t value;  /* 偏移 1，非 4 字节对齐 */
} pkt_t;

/* ❌ M0/M0+ 上直接解引用 → HardFault */
uint32_t val = ((pkt_t*)buf)->value;

/* ✅ 用 memcpy 安全读取 */
uint32_t val;
memcpy(&val, &buf[1], sizeof(uint32_t));
```

### 11.4 链接脚本与芯片内存匹配

**检查项：**
- [ ] 链接脚本（`.ld` / Keil 的 Target → ROM/RAM 设置）中 Flash 起始地址和大小与芯片型号一致
- [ ] RAM 起始地址和大小与芯片型号一致
- [ ] 栈顶地址指向 RAM 末尾（不是 Flash 末尾）
- [ ] Bootloader 和 App 的地址划分不重叠

### 11.5 大小端处理

**检查项：**
- [ ] 网络协议 / 文件解析涉及多字节时，显式用 `htons`/`htonl`/`ntohs`/`ntohl`
- [ ] 不依赖 CPU 大小端（某些芯片大小端可配置，换配置后代码就错）

**错误示例：**
```c
/* ❌ 直接 cast，假设 CPU 是小端 */
uint16_t value = *(uint16_t*)&buf[2];

/* ✅ 显式拼装，不依赖大小端 */
uint16_t value = ((uint16_t)buf[2] << 8) | buf[3];  /* 大端 */
```

## 十二、栈与堆管理

> ⚠️ **强制项**：涉及 RTOS 或深层函数调用时必须检查。栈溢出是嵌入式最难排查的 Bug 之一。

### 12.1 RTOS 任务栈大小

**检查项：**
- [ ] 每个任务的栈大小经过实际测量（用 `uxTaskGetStackHighWaterMark` 获取剩余最小值）
- [ ] 剩余空间 > 20%（留余量应对最坏情况的中断嵌套）
- [ ] 包含大局部数组 / 深层调用的任务，栈大小适当加大

```c
/* FreeRTOS 运行一段时间后检查栈水位 */
UBaseType_t remaining = uxTaskGetStackHighWaterMark(NULL);
if (remaining < configMINIMAL_STACK_SIZE / 4) {
    log_error("Task stack near overflow: %u remaining", remaining);
}
```

### 12.2 启动文件栈大小

**检查项：**
- [ ] 启动文件（`startup_gd32f4xx.s` 等）中的 `Stack_Size` 与实际需求匹配
- [ ] 裸机主循环 + 中断嵌套的最坏情况栈深度已评估

### 12.3 禁止递归调用

**检查项：**
- [ ] 项目中无递归函数（嵌入式栈有限，深度不可控）
- [ ] 必须用递归的算法（如树遍历）改为迭代实现

### 12.4 栈溢出检测

**检查项：**
- [ ] 有硬件栈溢出检测（MPU 区域设置 / `configCHECK_FOR_STACK_OVERFLOW`）
- [ ] 或使用编译器栈保护（`-fstack-protector` / `__stack_chk_guard`）

```c
/* FreeRTOS 栈溢出钩子 */
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    log_error("Stack overflow in task: %s", pcTaskName);
    NVIC_SystemReset();  /* 复位，不能继续跑 */
}
```

## 十三、RTOS 多任务

> ⚠️ **条件强制项**：使用 FreeRTOS / RT-Thread 等 RTOS 时必须逐项检查。裸机项目可跳过。

### 13.1 共享资源互斥保护

**检查项：**
- [ ] 多任务访问的全局变量/缓冲区有互斥保护（队列/信号量/互斥锁）
- [ ] 不直接用裸全局变量在任务间传数据（用队列或 `taskENTER_CRITICAL`）

**错误示例：**
```c
/* ❌ 两个任务直接读写全局变量，数据竞争 */
volatile uint32_t g_sensor_value;

void task_sensor(void) { g_sensor_value = read_adc(); }
void task_display(void) { show_value(g_sensor_value); }  /* 可能读到半更新的值 */
```

### 13.2 临界区时间

**检查项：**
- [ ] `taskENTER_CRITICAL()` / `portENTER_CRITICAL()` 内不调用阻塞 API（`vTaskDelay`/`xQueueReceive`）
- [ ] 临界区内只做快速的读/赋值，不做耗时操作

### 13.3 互斥锁获取顺序一致

**检查项：**
- [ ] 所有任务按相同顺序获取多把锁（如总是先锁 A 再锁 B）
- [ ] 不存在任务 1 先锁 A 再锁 B、任务 2 先锁 B 再锁 A 的交叉情况

### 13.4 优先级反转防护

**检查项：**
- [ ] 保护共享资源用互斥锁（`xSemaphoreCreateMutex`，带优先级继承），不用二值信号量
- [ ] 二值信号量只用于中断→任务通知，不用于资源保护

### 13.5 任务优先级设置

**检查项：**
- [ ] 中断处理相关任务优先级高（如通信接收任务）
- [ ] 非实时任务优先级低（如日志/显示/统计任务）
- [ ] 同优先级任务用时间片轮转，不依赖精确时序

## 十四、固件更新与 Bootloader

> ⚠️ **条件强制项**：项目含 OTA / IAP 升级功能时必须逐项检查。

### 14.1 Flash 地址划分

**检查项：**
- [ ] Bootloader 和 App 的 Flash 地址范围明确划分，不重叠
- [ ] App 的中断向量表偏移已正确设置（`SCB->VTOR = APP_FLASH_BASE`）

```
/* 典型 Flash 划分（GD32F4 512KB） */
0x08000000 - 0x0800FFFF  Bootloader (64KB)
0x08010000 - 0x0807FFFF  App (448KB)
0x08010000              App 中断向量表起始
```

### 14.2 固件完整性校验

**检查项：**
- [ ] 升级前校验固件 CRC32（不是校验和，CRC32 能检测多位翻转）
- [ ] 校验通过后再擦写 Flash
- [ ] 有签名验证（安全要求高的场景，用 RSA/ECDSA 签名）

### 14.3 双区 A/B 切换或回滚

**检查项：**
- [ ] 有 A/B 双区机制（升级写 B 区，启动时选最新的有效区）
- [ ] 或有回滚机制（升级失败 N 次后自动回到旧版）
- [ ] 升级标志写在 Flash / EEPROM，不是 RAM（掉电不丢）

### 14.4 升级过程看门狗

**检查项：**
- [ ] 升级前先喂一次看门狗
- [ ] 升级过程中定期喂狗（或临时延长看门狗超时）
- [ ] 升级完成后恢复正常看门狗周期

## 十五、启动与初始化顺序

### 15.1 初始化顺序正确

**检查项：**
- [ ] 初始化顺序：时钟 → GPIO → 外设（UART/SPI/I2C/ADC）→ 中断 → 业务逻辑
- [ ] 外设时钟使能在外设配置之前

**错误示例：**
```c
/* ❌ 外设时钟没开就配置寄存器，配置无效 */
void uart_init_bad(void)
{
    usart_baudrate_set(USART0, 115200U);  /* 时钟没开，写入无效 */
    rcu_periph_clock_enable(RCU_USART0);  /* 时钟开晚了 */
    usart_enable(USART0);
}

/* ✅ 先开时钟，再配置 */
void uart_init_good(void)
{
    rcu_periph_clock_enable(RCU_USART0);  /* 1. 先开时钟 */
    usart_baudrate_set(USART0, 115200U);  /* 2. 再配置 */
    usart_enable(USART0);                 /* 3. 最后使能 */
}
```

### 15.2 全局变量初始化顺序

**检查项：**
- [ ] 全局变量不依赖其他全局变量的构造/初始化（C 标准不保证跨文件初始化顺序）
- [ ] 有依赖关系的初始化放到 `main()` 里显式调用

### 15.3 看门狗早期启动

**检查项：**
- [ ] 看门狗在初始化早期就启动（`main()` 开头或 Bootloader 中）
- [ ] 初始化阶段如果耗时较长，在关键步骤之间插入喂狗

## 十六、错误处理体系

### 16.1 外设操作返回值检查

**检查项：**
- [ ] 所有外设操作（`HAL_SPI_Transmit`/`i2c_master_receive` 等）的返回值必须检查
- [ ] 失败时有明确的恢复路径（重试/报错/进安全态），不是默默忽略

**错误示例：**
```c
/* ❌ 返回值被忽略，I2C 读失败时用错误数据继续算 */
uint8_t buf[4];
i2c_master_receive(addr, buf, 4);  /* 返回值丢了 */
uint32_t value = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];

/* ✅ 检查返回值，失败时进安全态 */
if (i2c_master_receive(addr, buf, 4) != HAL_OK) {
    log_error("I2C read failed, entering safe mode");
    enter_safe_stop("I2C_READ_FAIL");
    return;
}
```

### 16.2 统一错误码体系

**检查项：**
- [ ] 有统一的错误码枚举（`err_t`），不是各模块各定义一套
- [ ] 错误码能区分故障类型（超时/忙/参数错/硬件故障）

```c
typedef enum {
    ERR_NONE      = 0,
    ERR_TIMEOUT   = -1,
    ERR_BUSY      = -2,
    ERR_PARAM     = -3,
    ERR_HARDWARE  = -4,
    ERR_NOT_INIT  = -5,
} err_t;
```

### 16.3 断言使用

**检查项：**
- [ ] Debug 版本启用断言（`assert_param` / 自定义 `ASSERT` 宏）
- [ ] Release 版本可关闭断言，或保留关键路径断言（空指针/除零检查）
- [ ] 断言条件有意义（检查不可恢复的前置条件，不做常规参数校验）

### 16.4 断言失败处理

**检查项：**
- [ ] 断言失败不只是 `while(1)`，要记录原因（日志/全局错误码）
- [ ] 记录后复位或进入安全态（不能死循环让看门狗都救不了）

```c
#define ASSERT(cond) do { \
    if (!(cond)) { \
        log_error("ASSERT failed: %s @ %s:%d", #cond, __FILE__, __LINE__); \
        NVIC_SystemReset(); \
    } \
} while (0)
```

## 十七、安全防护（量产）

> ⚠️ **条件强制项**：产品量产前必须逐项检查。开发阶段可跳过。

### 17.1 Flash 读保护

**检查项：**
- [ ] Flash 读保护已启用（STM32 RDP Level 1 / GD32 FMC_SPC_1）
- [ ] Level 1：调试接口可读但 Flash 内容不可读（通过 SWD 读不出固件）
- [ ] Level 2（一次性）：永久关闭调试接口（仅用于最终量产固件，不可逆！）

### 17.2 调试接口保护

**检查项：**
- [ ] 生产版本关闭或锁定 SWD/JTAG（或保留 RDP 保护下的受限访问）
- [ ] 有需要时可通过特定解锁流程重新打开（如售后维修）

### 17.3 密钥/证书存储

**检查项：**
- [ ] 密钥/证书存储在受保护区域（Option Bytes / eFuse / Flash 安全区）
- [ ] 不硬编码在代码里（`#define WIFI_PASSWORD "12345678"` → 固件被读出就泄漏）
- [ ] 不通过日志/串口输出明文密钥

### 17.4 防回滚保护

**检查项：**
- [ ] 固件版本号写入 OTP / eFuse（一次性可编程，不可修改）
- [ ] Bootloader 启动时比较 App 版本号与 OTP 记录，低于记录则拒绝启动
- [ ] 防止攻击者刷旧版本（有已知漏洞的固件）绕过安全修复

## 十八、可测性与调试

### 18.1 调试 GPIO 预留

**检查项：**
- [ ] 预留 1-2 个 GPIO 用于调试（翻转测时间、示波器看执行时间）
- [ ] Debug 版本在关键路径翻转 GPIO，Release 版本可关闭

```c
/* 测量 ISR 执行时间 */
void USART0_IRQHandler(void)
{
    DEBUG_GPIO_HIGH();  /* 示波器通道 1 */
    /* ... ISR 处理 ... */
    DEBUG_GPIO_LOW();
}
```

### 18.2 日志系统

**检查项：**
- [ ] 日志有级别（DEBUG/INFO/WARN/ERROR），可运行时调整级别
- [ ] 日志用环形缓冲，不直接 `printf`（会阻塞 ISR / 浪费 CPU）
- [ ] ERROR 级日志存储到 Flash / EEPROM（掉电不丢，便于事后排查）

### 18.3 固件版本号

**检查项：**
- [ ] 固件版本号硬编码在代码里（`#define FW_VERSION "1.2.3"`）
- [ ] 可运行时读取（通过串口命令 / 日志输出 / 上位机查询）
- [ ] 版本号与 Bootloader 中的防回滚记录对应

## 十九、可移植性

### 19.1 平台相关代码隔离

**检查项：**
- [ ] 平台相关代码（寄存器操作 / 库函数调用）隔离到 HAL 层
- [ ] 业务逻辑层不直接操作寄存器，只调用 HAL 接口
- [ ] 换芯片时只改 HAL 层，业务逻辑不用改

### 19.2 标准数据类型

**检查项：**
- [ ] 使用 `stdint.h` 类型（`uint8_t`/`uint16_t`/`uint32_t`），不用 `unsigned char`/`unsigned int`（大小不固定）
- [ ] `size_t` 用于表示大小/长度，不用 `int`

### 19.3 避免位域

**检查项：**
- [ ] 不使用 C 位域（`struct { uint8_t a:3; uint8_t b:5; }`），不同编译器布局不同
- [ ] 用移位掩码代替位域操作

```c
/* ❌ 位域，不同编译器布局可能不同 */
typedef struct {
    uint8_t type  : 3;
    uint8_t flag  : 1;
    uint8_t code  : 4;
} header_t;

/* ✅ 用移位掩码，布局确定 */
typedef uint8_t header_t;
#define HEADER_TYPE(h)  ((h) & 0x07)
#define HEADER_FLAG(h)  (((h) >> 3) & 0x01)
#define HEADER_CODE(h)  (((h) >> 4) & 0x0F)
```

## 二十、审查流程

1. **先读参考项目** —— 确认已有的函数和风格
2. **逐项检查** —— 按上述清单逐条过
3. **列出问题** —— 发现的问题按严重程度排序
4. **提出修改** —— 给出具体代码修改建议
5. **等用户验证** —— 修改后由用户烧录验证

## 快速参考表

| 类别 | 关键检查项 | 严重程度 |
|------|-----------|---------|
| ISR | [M] 无 printf/阻塞操作 | 致命 |
| ISR | [M] 标志位清除方式正确 | 高 |
| ISR | [M] 位置与参考项目一致 | 高 |
| ISR | [M] EXTI 按键必须消抖 | 高 |
| 缓冲区 | [M] 越界保护 | 致命 |
| 缓冲区 | [M] 无动态内存 | 中 |
| 缓冲区 | [M] 回调函数非空校验 | 致命 |
| **溢出 P0** | **[A] 禁止 sprintf/vsprintf/strcpy/strcat/gets** | **致命** |
| **溢出 P0** | **[A] snprintf 长度必须用 sizeof，不能写死数字** | **致命** |
| **溢出 P0** | **[A] 窄类型相乘前先扩宽类型（uint16*uint16→先转uint32）** | **致命** |
| **溢出 P0** | **[A] memcpy 长度必须 sizeof 或校验过的变量，禁止裸数字** | **致命** |
| **溢出 P1** | **[M] 移位位数 < 类型宽度（uint8<8，uint32<32），变量移位前判断** | **高** |
| **溢出 P1** | **[M] 宽→窄赋值前范围判断（uint32→uint8 前 <=UINT8_MAX）** | **高** |
| **溢出 P1** | **[A] 有符号/无符号混合运算四维防护（优先有符号/无符号边界/显式cast/编译器警告）+ 高危场景（无符号循环递减死循环、strlen减法回绕）** | **高** |
| volatile | [M] ISR 共享变量加 volatile | 致命 |
| volatile | [M] 8位MCU上16位变量原子访问 | 高 |
| GPIO | [M] TX 引脚配 AF 模式 | 高 |
| GPIO | [M] 未用引脚不悬空 | 中 |
| 时钟 | [M] 外设时钟已使能 | 致命 |
| 命名 | [M] 符合下划线/g_/s_前缀规范 | 低 |
| 规范 | [A] 无符号常量加 U 后缀 | 中 |
| 规范 | [M] float 字面量加 f 后缀 | 中 |
| 规范 | [M] while(1) 用 while(1U) | 低 |
| 规范 | [M] 魔法数字替换为宏/枚举 | 中 |
| 规范 | [M] const/static 最大化 | 中 |
| 工程文件 | [M] 不碰 .uvprojx | 致命 |
| 头文件一致性 | [M] 改.c必须检查.h声明 | 高 |
| 头文件一致性 | [M] 改.h必须检查所有引用处 | 高 |
| 头文件一致性 | [M] 宏/结构体变更全局搜索 | 高 |
| 低功耗 | [M] WFI 前关闭非必要中断 | 致命 |
| 低功耗 | [M] 唤醒后优先处理唤醒源 | 中 |
| OLED | [M] GB2312 字库需 GB2312 编码 | 高 |
| I2C | [M] 软件 I2C 时序参数验证 | 高 |
| DMA | [M] 库函数名必须查头文件确认 | 高 |
| **长运行** | **[M] 看门狗已启用 + 喂狗在主循环不在中断** | **致命** |
| **长运行** | **[A] Q7 NVIC 优先级分组：main() 开头显式 set_priority_group（脚本自动检测缺失）+ [M] 抢占级数值顺序（通信>定时>EXTI）** | **致命** |
| **长运行** | **[M] 所有通信总线有超时退出 + 错误恢复** | **致命** |
| **长运行** | **[M] Flash 磨损均衡（环形写入，不总写同一地址）** | **高** |
| **长运行** | **[M] 关键参数 3 份冗余 + CRC 校验** | **高** |
| **长运行** | **[M] 计数器/索引有回绕，无无限增长** | **高** |
| **防御 D1** | **[A] switch 必须有 default 分支** | **高** |
| **防御 D2** | **[A] 函数体内局部变量声明必须初始化（=0/{0}）** | **中** |
| **防御 M3** | **[M] 有全局安全状态机，故障时进入安全降级/停止，不输出错误数据** | **致命** |
| **防御 M4** | **[M] 对外操作（init/Flash 写/状态转移）幂等，重复调用不破坏状态** | **高** |
| **编译链接** | **[M] 编译警告全部开启并清零（-Wall -Wextra）** | **高** |
| **编译链接** | **[M] __packed 结构体在 M0/M0+ 上禁止非对齐访问** | **致命** |
| **编译链接** | **[M] 链接脚本 Flash/RAM 地址与芯片匹配** | **致命** |
| **编译链接** | **[M] 优化级别对 volatile/延时循环的影响已验证** | **高** |
| **编译链接** | **[M] 多字节网络协议用 htons/htonl，不依赖大小端** | **高** |
| **栈管理** | **[M] RTOS 任务栈大小经实测（uxTaskGetStackHighWaterMark）** | **致命** |
| **栈管理** | **[M] 禁止递归调用（嵌入式栈有限）** | **高** |
| **栈管理** | **[M] 有栈溢出检测机制（MPU/stack guard）** | **中** |
| **RTOS** | **[M] 共享资源有互斥保护，不用裸全局变量** | **致命** |
| **RTOS** | **[M] 临界区内不调用阻塞 API** | **高** |
| **RTOS** | **[M] 互斥锁获取顺序一致（防死锁）** | **高** |
| **RTOS** | **[M] 用互斥锁（优先级继承）而非二值信号量保护资源** | **高** |
| **Bootloader** | **[M] Bootloader 与 App Flash 地址不重叠** | **致命** |
| **Bootloader** | **[M] 升级前 CRC32 完整性校验** | **致命** |
| **Bootloader** | **[M] 有 A/B 双区或回滚机制** | **高** |
| **初始化** | **[M] 初始化顺序：时钟→GPIO→外设→中断→业务** | **高** |
| **初始化** | **[M] 看门狗在初始化早期启动** | **高** |
| **错误处理** | **[M] 外设操作返回值必须检查** | **高** |
| **错误处理** | **有统一错误码体系（err_t）** | **中** |
| **错误处理** | **断言失败要记录+复位，不只 while(1)** | **中** |
| **量产安全** | **Flash 读保护（RDP Level 1/2）已启用** | **高** |
| **量产安全** | **密钥不硬编码在代码里** | **高** |
| **量产安全** | **防回滚：版本号写入 OTP/eFuse** | **中** |
| **可测性** | **预留调试 GPIO + 日志分级环形缓冲** | **中** |
| **可移植性** | **平台相关代码隔离到 HAL 层** | **中** |
| **可移植性** | **避免位域，用移位掩码代替** | **中** |

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `gpio_af_set` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L397 |
| `gpio_mode_set` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L374 |
| `gpio_output_options_set` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L376 |
| `gpio_input_bit_get` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L388 |
| `rcu_periph_clock_enable` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_rcu.h` L1078 |
| `i2c_clock_config` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_i2c.h` L331 |
| `i2c_enable` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_i2c.h` L349 |
| `i2c_ack_config` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_i2c.h` L339 |
| `exti_interrupt_flag_get` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_exti.h` L267（已修正大小写） |
| `exti_interrupt_flag_clear` 函数签名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_exti.h` L269（已修正大小写） |
| `GPIO_MODE_AF` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L290 |
| `GPIO_MODE_INPUT` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L288 |
| `GPIO_AF_4` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L357 |
| `GPIO_OTYPE_OD` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L332 |
| `GPIO_OSPEED_50MHZ` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L344 |
| `GPIO_PUPD_PULLUP` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L296 |
| `I2C_DTCY_2` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_i2c.h` L319 |
| `I2C_ACK_ENABLE` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_i2c.h` L267 |
| `dma_single_data_para_struct_init` 函数名 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_dma.h` L360（踩坑记录已验证） |
| `SysTick->CTRL` / `SysTick_CTRL_TICKINT_Msk` | ✅ | CMSIS 5.9.0 `core_cm7.h` / `cmsis_armclang.h` |
| `__disable_irq` / `__enable_irq` | ✅ | CMSIS 5.9.0 `cmsis_armclang.h` L737/L750 |
| `EA = 1`（STC8 全局中断使能） | ✅ | 8051 标准 SFR（地址 0xA8），所有 STC8 系列芯片通用 |
| 命名规范（下划线/g_/s_/t/_e 等） | ✅ | 通用嵌入式 C 最佳实践，与用户偏好一致 |
| U 后缀 / f 后缀规范 | ✅ | C 语言标准，防御性编程通用规则 |
| volatile 使用规则 | ✅ | 通用嵌入式 C 最佳实践 |
| 缓冲区越界保护规则 | ✅ | 通用嵌入式 C 最佳实践 |
| 低功耗 WFI 前关中断 | ✅ | Cortex-M 架构标准做法 |
| 禁止 sprintf/strcpy/gets（P0 溢出） | ✅ | CERT C Secure Coding 标准：STR05-C、STR06-C、MEM35-C |
| snprintf 长度用 sizeof（P0 溢出） | ✅ | CERT C Secure Coding 标准：STR07-C |
| 窄类型相乘先扩宽（P0 溢出） | ✅ | CERT C Secure Coding 标准：INT30-C / INT02-C 整数溢出 |
| memcpy 禁裸数字长度（P0 溢出） | ✅ | CERT C Secure Coding 标准：ARR38-C / MEM35-C |
| 移位 < 类型位数（P1 溢出） | ✅ | ISO C11 标准 §6.5.7p3（未定义行为）+ INT34-C |
| 宽→窄赋值前范围判断（P1 溢出） | ✅ | CERT C Secure Coding 标准：INT31-C（整数截断） |
| 有符号/无符号比较统一类型（P1 溢出） | ✅ | CERT C Secure Coding 标准：INT02-C（隐式转换）+ Bjarne Stroustrup 倡导"优先有符号" |
| 无符号循环递减死循环检测（P1 溢出） | ✅ | 高危场景：uint8_t i=10; i>=0; --i → UINT_MAX 回绕死循环 |
| strlen 减法回绕检测（P1 溢出） | ✅ | 高危场景：strlen(s)-1 当 s="" → SIZE_MAX 越界访问 |
| 编译器警告选项 -Wsign-conversion/-Wconversion | ✅ | GCC/Clang 官方文档：有符号/无符号隐式转换警告 |
| 看门狗喂狗位置（长运行） | ✅ | IEC 60730 Class B 安全标准 §表H.11.12.5（软件看门狗） |
| 通信总线超时退出（长运行） | ✅ | IEC 60730 Class B 安全标准 §H.11.12.6（通信错误检测） |
| Flash 磨损均衡（长运行） | ✅ | JEDEC Standard No.2201 §4.4（Flash 存储器磨损均衡） |
| 关键参数多份+CRC（长运行） | ✅ | IEC 61508 功能安全标准 §7.4.8（数据完整性） |
| 计数器回绕（长运行） | ✅ | CERT C Secure Coding 标准：INT30-C（无符号整数回绕） |
| D1：switch 必须有 default | ✅ | MISRA-C:2012 Rule 16.4（switch 必备 default） |
| D2：局部变量必须初始化 | ✅ | MISRA-C:2012 Rule 9.1（所有对象使用前初始化） |
| M3：安全降级模式设计 | ✅ | IEC 61508 功能安全 §7.4.5 安全状态 + IEC 60730 Class B §H.11.12 |
| M4：对外操作幂等性 | ✅ | IEC 61508 §7.4.4 失效隔离 + 嵌入式系统重试/重传通用设计原则 |
