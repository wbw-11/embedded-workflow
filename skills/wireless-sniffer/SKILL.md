---
name: "wireless-sniffer"
description: "无线抓包排障：BLE/WiFi 工具选型、监听搭建、Wireshark 分析、断连速查。连不上时调用。"
version: 1.0.0
---

# 无线抓包排障流程

无线问题"看不见摸不着"，抓包是唯一客观证据。本技能给出工具清单、搭建方法与问题速查表。

## 一、工具清单（按投入递进）

| 档位 | 工具 | 成本 | 能力 |
|---|---|---|---|
| 入门 | **nRF52840 USB Dongle**（刷 Sniffer 固件） | ~60-100 元 | BLE 全功能抓包（广播/连接/ATT），最推荐 |
| 入门 | ESP32 抓包固件（混杂模式，WiFi） | 手边就有 | WiFi 管理帧/数据帧 MAC 层抓包 |
| 进阶 | nRF Connect for Desktop + Bluetooth Low Energy App | 免费 | 与 Dongle 配套的扫描/连接/数据分析 |
| 中端 | 商业 USB 协议分析仪（如 Frontline BPA） | 数千元 | BLE+BR/EDR，带协议解码 |
| 高端 | Ellisys / 专业射频室 | 实验室级 | 全协议全场景，量产实验室用 |

**软件层**：Wireshark（免费）+ BLE 插件；nRF Connect 软件套件。

## 二、抓包搭建步骤

### BLE 抓包（nRF Dongle）

1. Dongle 刷入 RFU Sniffer 固件（nRF Connect 程序化写入，open source）
2. 电脑开 Wireshark → nRF Sniffer 插件 → 选 Dongle 接口
3. Dongle 放目标设备 1 米内
4. 触发目标：重新上电目标设备（抓广播）或重连（抓连接全流程）
5. 过滤语法：`btle.` 前缀过滤 ATT/GAP 层

### WiFi 抓包（ESP32 混杂模式）

1. ESP32 烧 sniff 示例（乐鑫官方 esp-idf 内置混杂模式 demo）
2. 保存空口帧经 UART 转发（或 PCAP 到 SD）
3. 注意：WPA2 加密数据帧内容不可解，**管理帧（Probe/Beacon/Association）明文可见**——连不上类问题看管理帧就够

## 三、分析速查表（常见病对照）

| 现象 | 抓包看什么 | 典型根因 |
|---|---|---|
| 手机扫不到设备 | 广播包有没有/间隔 | 广播没启动、间隔太长、广播名非法 |
| 连上即断 | ATT 交换后哪方发 Terminate | 从机响应超时、连接参数被主机拒绝、栈崩溃 |
| 连接建立慢/失败 | Establish 过程重试 | 连接间隔不合规、地址类型错(public/random) |
| 透传慢/丢包 | ATT 通知流控、链路层重传 | MTU 小、Notify 无流控、连接间隔大 |
| WiFi 连不上 AP | Association/Auth 帧交互 | 密码错、信道不匹配、RSSI 太弱 |
| WiFi 频繁掉线 | Deauth 帧来源 | AP 侧踢（信号/权限）、功率不足 |

## 四、排障流程（无线问题标准动作）

1. **先抓包**拿到客观证据（禁止先改代码瞎试）
2. 对照上表定位发生在协议哪一层（GAP / ATT / 链路层 / 应用层）
3. 设备端日志（debug-log-standard 规范）与空口帧**时间线对拍**——谁先断开一目了然
4. 每次判断"我方问题/对方问题/环境干扰"——环境干扰的特征是重传率高

## 五、与其它技能联动

| 技能 | 关系 |
|---|---|
| ble-nus-template / wifi-app-template | 提供正确参数基准 |
| protocol-analysis | 有线协议抓包同方法论 |
| debug-log-standard | 设备端日志与空口对拍 |
| hardfault-diagnosis | 栈崩溃会导致无线瞬断 |
