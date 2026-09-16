---
name: protocol-analysis
description: "协议抓包分析：解析 I2C/SPI/UART/CAN 逻辑分析仪/示波器数据，定位通信故障。"
version: 1.0.0
---

# 通信协议抓包分析

## 适用场景

- 外设通信不通（I2C 无 ACK、SPI 数据全 FF、UART 乱码）
- 用户提供了逻辑分析仪截图或 CSV/VCD 导出文件
- 需要确认时序是否满足芯片要求
- 对比预期波形与实际波形，定位问题环节

## 分析流程

### 第一步：确认通信参数

向用户确认或从代码中提取：

| 协议 | 需确认参数 |
|------|-----------|
| UART | 波特率、数据位、停止位、校验位、流控 |
| SPI | 时钟频率、CPOL、CPHA、位序、片选逻辑 |
| I2C | 时钟频率、7/10位地址、上拉电阻值 |
| CAN | 波特率、采样点、标准/扩展帧 |

### 第二步：各协议正常波形特征

#### UART

正常帧结构（以 115200-8N1 为例）：
```
空闲(高) → 起始位(低,1bit) → 数据位(LSB first,8bit) → [校验位] → 停止位(高,1bit) → 空闲(高)
```

常见问题判断：
- 全 0xFF：TX/RX 未连接或波特率严重不匹配
- 乱码但能看出帧结构：波特率偏差（>3% 会出错）
- 偶发错误字节：信号完整性问题（线太长、无共地）
- 只有起始位没有数据：发送端卡死

#### SPI

四种模式（CPOL/CPHA 组合）：
```
Mode 0 (0,0): 空闲低，上升沿采样  ← 最常用
Mode 1 (0,1): 空闲低，下降沿采样
Mode 2 (1,0): 空闲高，下降沿采样
Mode 3 (1,1): 空闲高，上升沿采样
```

常见问题判断：
- MISO 全高/全低：从机未供电或 CS 未拉低
- 数据位移 1 bit：CPOL/CPHA 配置错误
- 前几个字节正确后面错乱：CS 在传输中被意外释放
- 时钟正常但数据全 FF：MOSI/MISO 接反

#### I2C

正常事务：
```
S → [7bit地址 + R/W] → ACK → [数据字节] → ACK → ... → P
```

常见问题判断：
- 无 ACK（第 9 个时钟为高）：地址错误 / 从机未上电 / 上拉电阻缺失
- SDA 被持续拉低：总线锁死（从机卡在发送状态），需 9 个时钟脉冲恢复
- 时钟拉伸过长：从机处理不过来
- 多主冲突：SDA 出现非预期电平

总线恢复方法：
```c
// 主机发送 9 个时钟脉冲释放总线
for (int i = 0; i < 9; i++) {
    SCL_HIGH(); delay_us(5);
    SCL_LOW();  delay_us(5);
}
// 然后发送 STOP
SDA_LOW(); delay_us(5);
SCL_HIGH(); delay_us(5);
SDA_HIGH(); delay_us(5);
```

#### CAN

正常帧结构：
```
SOF(1) → ID(11/29) → RTR(1) → IDE(1) → DLC(4) → Data(0-64bit) → CRC(15) → ACK(2) → EOF(7)
```

常见问题判断：
- 只有发送没有 ACK：总线上无其他节点 / 波特率不匹配
- 错误帧频繁：采样点设置不当 / 终端电阻缺失（120Ω×2）
- 总线关闭（Bus Off）：错误计数器溢出，检查接线和波特率

### 第三步：解读抓包数据

#### 逻辑分析仪截图

当用户提供截图时：
1. 识别各通道对应的信号（CLK/MOSI/MISO/CS 或 SDA/SCL）
2. 测量时钟频率，确认与配置一致
3. 找到帧起始（CS 下降沿 / START 条件 / 起始位）
4. 逐位/逐字节解码数据
5. 与预期数据对比，标注异常位置

#### CSV/VCD 文件解析

```python
# 解析 Saleae/PulseView 导出的 CSV
import csv

def parse_spi_csv(filepath, cpol=0, cpha=0):
    """解析逻辑分析仪 SPI 导出"""
    frames = []
    with open(filepath) as f:
        reader = csv.DictReader(f)
        for row in reader:
            # 根据导出格式适配列名
            clk = int(row['CLK'])
            mosi = int(row['MOSI'])
            miso = int(row['MISO'])
            cs = int(row['CS'])
            # ... 按边沿解码
    return frames
```

#### 串口原始数据分析

```python
# 解析 UART hex 日志
def parse_uart_log(hex_string):
    """将 'AA 55 03 01 02 03 06' 格式解析为帧"""
    data = bytes.fromhex(hex_string.replace(' ', ''))
    # 按协议帧头帧尾切分
    frames = []
    i = 0
    while i < len(data) - 1:
        if data[i] == 0xAA and data[i+1] == 0x55:
            length = data[i+2]
            frame = data[i:i+3+length+1]  # 帧头+长度+数据+校验
            frames.append(frame)
            i += len(frame)
        else:
            i += 1
    return frames
```

### 第四步：时序合规性检查

对照数据手册的时序参数：

| 参数 | 含义 | 典型要求 |
|------|------|----------|
| tSU (Setup) | 数据在时钟边沿前稳定的时间 | I2C: ≥250ns(Fast) |
| tHD (Hold) | 时钟边沿后数据保持时间 | I2C: ≥0ns |
| tHIGH/tLOW | 时钟高/低电平最小宽度 | I2C Fast: ≥0.6μs |
| CS setup/hold | 片选相对时钟的建立/保持 | SPI: 通常 ≥1 CLK |

从截图中测量：
- 用逻辑分析仪的时间标尺量取脉冲宽度
- 与数据手册最小/最大值对比
- 标注不满足的参数

## 常见故障排查决策树

```
通信不通
├── 时钟信号正常？
│   ├── 无时钟 → 检查外设初始化、时钟源配置
│   └── 有时钟 → 继续
├── 数据线有变化？
│   ├── 无变化（恒定高/低）→ 检查接线、供电、上拉
│   └── 有变化 → 继续
├── 数据内容正确？
│   ├── 全 FF/00 → CS/地址错误、主从接反
│   ├── 移位错误 → CPOL/CPHA/波特率配置
│   └── 偶发错误 → 信号完整性（线长、干扰、共地）
└── 时序满足？
    ├── 不满足 → 降频、检查上拉电阻值
    └── 满足 → 检查协议层（帧格式、校验）
```

## Pitfalls

- 逻辑分析仪采样率需 ≥ 信号频率的 4 倍（推荐 10 倍以上）
- I2C 上拉电阻过大（>10kΩ）在 Fast Mode 下会导致上升沿过缓
- SPI 长线（>20cm）不加串联电阻容易振铃，导致多次采样
- UART 两端共地是必须的，"只接 TX/RX 不接 GND"是经典错误
- CAN 总线两端各需 120Ω 终端电阻，缺一个会导致反射
- 逻辑分析仪的 GND 必须接到被测系统的 GND

## Verification

- 解码出的数据与固件 printf 输出一致
- 时序参数全部满足数据手册最小/最大要求
- 连续传输 1000 帧无错误（压力验证）
- 问题修复后对比修复前后波形，确认异常消失

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| UART 帧结构（起始位+数据位 LSB first+停止位） | ✅ | UART 通信标准 |
| SPI 四种模式（CPOL/CPHA 组合） | ✅ | SPI 通信标准 |
| I2C 7位地址+R/W+ACK 时序 | ✅ | I2C 通信标准 |
| CAN 帧结构（SOF→ID→RTR→IDE→DLC→Data→CRC→ACK→EOF） | ✅ | CAN 2.0 标准 |
| I2C 总线恢复（9 个时钟脉冲） | ✅ | I2C 标准恢复流程 |
| UART 常见故障（全 FF/乱码/偶发错误） | ✅ | 串口调试通用经验 |
| SPI 常见故障（位移/CS 释放/MOSI-MISO 接反） | ✅ | SPI 调试通用经验 |
| I2C 常见故障（无 ACK/总线锁死/时钟拉伸） | ✅ | I2C 调试通用经验 |
| CAN 终端电阻 120Ω×2 | ✅ | CAN 物理层标准 |
| 时序参数（tSU/tHD/tHIGH/tLOW） | ✅ | I2C/SPI 时序标准 |
| 逻辑分析仪采样率 ≥4 倍信号频率 | ✅ | 数字采样定理 |
| Python CSV 解析模板代码 | ✅ | Python 标准库 csv |