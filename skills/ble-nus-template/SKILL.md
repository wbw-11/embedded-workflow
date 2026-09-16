---
name: "ble-nus-template"
description: "BLE 透传(NUS)模板：GATT 服务/广播连接参数/通知状态机。ESP32-C3/S3(nimble) 或 nRF52 串口透传时调用。"
version: 1.0.0
---

# BLE 透传（NUS）开发模板

> **骨架级说明**：本模板给出 BLE NUS（Nordic UART Service）透传的标准骨架——消费电子（小家电/穿戴）蓝牙最常用形态。ESP32-C3/S3 走 ESP-IDF nimble 栈，nRF52 走 Nordic SDK，**架构相同（GATT 服务模型），API 落地时以所装 SDK 头文件为准**。P1 实测后升级标注。

## 一、NUS 标准服务（行业通用 UUID）

- 服务 UUID：`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`（Nordic UART Service）
- 特征 1 **RX（手机→设备写）**：`6E400002-...`，Write / Write-no-response
- 特征 2 **TX（设备→手机通知）**：`6E400003-...`，Notify
- 用通用 UUID 的好处：nRF APP、微信小程序、各类调试 App 免配置直连

## 二、初始化骨架（nimble 路径）

顺序：
1. NVS 初始化（绑定信息存储）
2. 控制器初始化（controller init，C3 内置）
3. 主机栈初始化（nimble host）→ GAP 服务注册
4. GATT 服务注册（NUS 定义上表）
5. 广播参数 + 广播启动
6. 连接参数更新策略

### 广播参数要点

- 广播间隔：首连期 100~200ms（快被发现），稳定后可放宽
- 广播名：建议 `产品名-后四位 MAC`（多设备并排可区分）
- 定向广播 vs 普通广播：配网场景用普通即可

### 连接参数要点（掉线高频根因）

| 参数 | 建议值 | 说明 |
|---|---|---|
| 连接间隔 | 30~50ms | 透传吞吐与功耗折中 |
| 从机延迟 | 0 | 透传场景要低延迟 |
| 超时时间 | 2000ms 以上 | 太短易被误判断连 |
| MTU | 协商到 ≥185（或 247） | 通知丢包率显著下降 |

- 手机侧可发起参数更新请求，设备要准备好接受

## 三、透传数据流状态机

```
广播 ──连接(GAP CONNECT)──> 已连接(停止广播, MTU 协商)
已连接 ──RX 特征收到──> UART 输出/命令解析
已连接 ──UART 收到──> TX 特征 Notify 发送
断开(GAP DISCONNECT)──> 清缓冲, 重新广播
```

- **Notify 发送前确认 CCCD 已使能**（客户端订阅了才发）
- 高速透传注意：Notify 速率受连接间隔限制（每间隔最多包数有限），大块数据要分包+流控标志
- 连接时 UART 缓冲策略：满则丢弃+计数告警（配合 debug-log-standard）

## 四、BLE 通用红线

1. **Flash 预算**：nimble 栈 + GATT 表 + 应用，C3 4MB Flash 充足；小 Flash 芯片先算账
2. **栈任务**：蓝牙主机栈独立任务，栈大小照官方示例
3. **配对**：消费级常见 JustWorks（无配对绑定）；有数据安全需求再上 Passkey/OOB
4. **认证**：使用蓝牙 SIG 认证模组（见 rf-verification）免 BQB 认证
5. **测试**：连接类问题先 wireless-sniffer 抓包定位 ATT 层

## 五、nRF52 对照（换芯片时架构同）

| 概念 | ES-IDF nimble | Nordic SDK |
|---|---|---|
| 主机栈 | nimble | SoftDevice |
| GATT 注册 | 服务表 + 回调 | ble_gatts 系列 API |
| 通知 | os_mbuf + notify | sd_ble_gatts_hvx |

## 六、与其它技能联动

esp-idf-build / esp32-panic-diagnosis / wireless-sniffer（抓包看连接为何断）/ rf-verification（认证）
