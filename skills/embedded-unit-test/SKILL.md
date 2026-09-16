---
name: embedded-unit-test
description: "嵌入式 C 单元测试(Unity+CMock)：主机端编译跑测，HAL mock，支持 GD32/STM32/ESP32/STC8。"
version: 1.0.0
---

# 嵌入式 C 单元测试（Unity + CMock）

## 适用场景

- 用户完成一个模块（驱动、协议解析、算法），需要验证逻辑
- 用户要求"写个测试"、"验证一下这个函数"
- 重构后需要回归验证
- CI 中需要自动化测试

<!-- 层级归属：L0 单元测试，依据 embedded-dev-rules §4.6 驱动验证四层标准 -->
> **L0 单元测试（依据 embedded-dev-rules §4.6）**：驱动开发/改驱动后必须补 L0 单测并跑通——参数校验 / 边界 / 错误码 / 状态机全覆盖，mock HAL 不依赖硬件；改完即跑，P0 失败阻止提交。结果经 test-report 汇总入缺陷台账。

## 核心原则

1. **主机端运行**：测试在 PC（x86）上编译执行，不依赖目标 MCU
2. **隔离硬件**：通过 Mock 替换 HAL/寄存器操作，只测业务逻辑
3. **一个测试一个断言点**：每个 TEST 函数验证一个行为
4. **先写测试再写实现**（TDD）或写完立即补测试

## 项目结构

```
project/
├── src/                  # 产品代码
│   ├── uart_driver.c
│   └── protocol_parser.c
├── test/                 # 测试代码
│   ├── test_uart_driver.c
│   ├── test_protocol_parser.c
│   └── mocks/            # CMock 生成的 mock
├── vendor/
│   ├── unity/            # Unity 框架
│   └── cmock/            # CMock 框架
├── Makefile              # 或 CMakeLists.txt
└── platform/             # 平台抽象层（被 mock 的对象）
    ├── hal_gpio.h
    └── hal_uart.h
```

## 快速搭建

### 1. 获取 Unity 和 CMock

```bash
mkdir -p vendor
git clone https://github.com/ThrowTheSwitch/Unity.git vendor/unity
git clone https://github.com/ThrowTheSwitch/CMock.git vendor/cmock
```

### 2. 创建测试文件模板

```c
// test/test_protocol_parser.c
#include "unity.h"
#include "protocol_parser.h"
#include "mock_hal_uart.h"  // CMock 生成

void setUp(void) {
    // 每个测试前的初始化
    mock_hal_uart_Init();
}

void tearDown(void) {
    // 每个测试后的清理
    mock_hal_uart_Verify();
    mock_hal_uart_Destroy();
}

void test_parser_valid_frame(void) {
    uint8_t frame[] = {0xAA, 0x55, 0x03, 0x01, 0x02, 0x03, 0x06};
    
    // 期望 HAL 层被调用的方式
    mock_hal_uart_Send_Expect(frame, 7);
    
    int result = protocol_parse_and_send(frame, 7);
    TEST_ASSERT_EQUAL_INT(0, result);
}

void test_parser_checksum_error(void) {
    uint8_t frame[] = {0xAA, 0x55, 0x03, 0x01, 0x02, 0x03, 0xFF};
    
    int result = protocol_parse_and_send(frame, 7);
    TEST_ASSERT_EQUAL_INT(-1, result);  // 校验失败返回 -1
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_parser_valid_frame);
    RUN_TEST(test_parser_checksum_error);
    return UNITY_END();
}
```

### 3. Makefile（主机端编译）

```makefile
CC = gcc
CFLAGS = -Wall -Wextra -g -I src -I platform -I vendor/unity/src -I test/mocks
UNITY_SRC = vendor/unity/src/unity.c

TEST_BINS = $(patsubst test/test_%.c, build/test_%,$(wildcard test/test_*.c))

all: $(TEST_BINS)

build/test_%: test/test_%.c src/%.c $(UNITY_SRC)
	@mkdir -p build
	$(CC) $(CFLAGS) $^ -o $@

run: all
	@for t in $(TEST_BINS); do echo "=== $$t ==="; ./$$t; done

clean:
	rm -rf build

.PHONY: all run clean
```

### 4. CMock 生成 Mock

```bash
ruby vendor/cmock/lib/cmock.rb -oCmock:plugins:[:expect, :return_thru_ptr] platform/hal_uart.h
```

生成的 `mock_hal_uart.h/c` 放入 `test/mocks/`。

## 常用断言

```c
TEST_ASSERT_EQUAL_INT(expected, actual);
TEST_ASSERT_EQUAL_UINT8(expected, actual);
TEST_ASSERT_EQUAL_HEX32(expected, actual);
TEST_ASSERT_EQUAL_MEMORY(expected_ptr, actual_ptr, len);
TEST_ASSERT_EQUAL_STRING(expected, actual);
TEST_ASSERT_TRUE(condition);
TEST_ASSERT_NULL(ptr);
TEST_ASSERT_NOT_NULL(ptr);
TEST_ASSERT_FLOAT_WITHIN(delta, expected, actual);
```

## 测试分层策略

| 层级 | 测什么 | Mock 什么 | 示例 |
|------|--------|-----------|------|
| 算法层 | 纯计算逻辑 | 无需 mock | CRC、滤波、PID |
| 协议层 | 帧解析/组包 | Mock UART/SPI 发送 | Modbus、自定义协议 |
| 驱动层 | 状态机/时序逻辑 | Mock 寄存器读写 | UART DMA 驱动 |
| 应用层 | 业务流程 | Mock 所有底层 | 配网流程、OTA 升级 |

## 寄存器级 Mock 技巧

对于直接操作寄存器的代码（STC8、裸机 GD32），抽象一层：

```c
// platform/hal_gpio.h —— 可被 mock 的抽象层
void hal_gpio_set(uint8_t port, uint8_t pin);
void hal_gpio_clear(uint8_t port, uint8_t pin);
uint8_t hal_gpio_read(uint8_t port, uint8_t pin);
```

产品代码调用 `hal_gpio_set()` 而非直接 `GPIOB->BRR = ...`，测试时 mock 这一层。

## 与 Keil/ESP-IDF 项目集成

- 测试代码不参与 Keil 工程编译（不加入 .uvprojx）
- 测试用独立的 Makefile 或 CMake 在主机端构建
- ESP-IDF 项目可用 `idf.py --target linux` 做主机端编译（ESP-IDF 5.x 支持）
- CI 中 `make run` 即可跑全部测试

## Pitfalls

- 不要 mock 被测模块本身，只 mock 它的依赖
- volatile 变量在主机端测试时去掉 volatile 修饰（或用宏开关）
- 中断相关逻辑拆分为"ISR 收集数据"+"主循环处理数据"，只测后者
- 时间相关函数（delay、timeout）抽象为可注入的回调，测试时跳过真实等待
- CMock 的 Expect 顺序敏感，调用顺序不对会报 Unexpected call
- 每个 test 文件必须 include unity.h 并实现 setUp/tearDown

## Verification

- `make run` 全部 PASS，无 FAIL 或 ERROR
- 故意改错一行产品代码，确认对应测试能 FAIL（变异测试思想）
- 测试覆盖率检查（可选）：`gcc --coverage` + `gcov` 查看关键模块覆盖率

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| Unity 框架 API（`UNITY_BEGIN/RUN_TEST/UNITY_END`） | ✅ | ThrowTheSwitch Unity 标准宏 |
| Unity 断言宏（`TEST_ASSERT_EQUAL_INT/UINT8/HEX32` 等） | ✅ | ThrowTheSwitch Unity 标准断言 |
| CMock API（`Init/Verify/Destroy/Expect` 模式） | ✅ | ThrowTheSwitch CMock 标准模式 |
| CMock 生成命令 `ruby cmock.rb` | ✅ | CMock 官方文档 |
| `idf.py --target linux` 主机端编译 | ✅ | ESP-IDF v5.5.4 支持 linux target |
| Makefile 主机端编译模板（gcc + Unity） | ✅ | 标准嵌入式单元测试实践 |
| 寄存器级 Mock 抽象层设计 | ✅ | 嵌入式测试最佳实践 |
| 测试分层策略（算法→协议→驱动→应用） | ✅ | 嵌入式测试最佳实践 |