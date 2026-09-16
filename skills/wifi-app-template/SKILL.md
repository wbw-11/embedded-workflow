---
name: "wifi-app-template"
description: "ESP-IDF WiFi 应用模板：STA/SoftAP/SmartConfig/NVS/MQTT 状态机与步骤。写 WiFi、配网、上报时调用。"
version: 1.0.0
---

# WiFi 应用开发模板（ESP-IDF）

> **骨架级说明**：本模板基于 ESP-IDF 官方组件体系（esp_netif / esp_wifi / esp_event / esp-mqtt），给出可靠的状态机骨架与步骤顺序。**具体 API 函数名与参数以所装 IDF 版本的头文件与官方文档为准**（红线：不凭记忆写库函数，落地时 grep 确认）。P1 实测校验后本模板再升级标注为"已验证"。

## 一、标准 STA 连接骨架（最长用）

流程顺序（每步为一个函数块）：

1. **NVS 初始化**（`nvs_flash_init`，WiFi 凭据缓存的基础）
2. **网络栈初始化**：esp_netif 默认创建（STA 接口）
3. **事件循环初始化**：esp_event_loop 创建，注册 WIFI_EVENT / IP_EVENT 处理器
4. **WiFi 驱动初始化**：wifi_init_config + esp_wifi_init + 设 mode=STA
5. **启动并连接**：esp_wifi_start → esp_wifi_connect（凭据来自 NVS 或硬编码首配）

### 状态机（必须写全，含异常路径）

```
DISCONNECTED ──connect()──> CONNECTING ──WIFI_EVENT_STA_START──> GOT_IP(IP_EVENT_STA_GOT_IP=上线)
     ▲                           │
     │                           └─WIFI_EVENT_STA_DISCONNECTED(原因码)
     └──────── 退避重连 ────────┘
```

- **重连退避**：失败重连用递增间隔（1s/2s/4s/…封顶 60s），禁止裸循环疯狂重连
- **上线标志**：以 `IP_EVENT_STA_GOT_IP` 为"连上了"的判定，不是 "connect 返回 OK"
- 断开原因码分类：密码错 / 信号丢失 / AP 踢掉，分别日志告警

## 二、SoftAP 模式（设备自建热点）

- 用于：无屏设备配网入口 / 局域直连调试
- 骨架：mode=APSTA（常用组合），配置 SSID/密码/信道 → DHCP 服务 esp_netif 自动
- 注意：信道与 STA 连接的信道冲突处理（APSTA 同信道限制）

## 三、配网三选一（产品定位决定）

| 方案 | 适用 | 说明 |
|---|---|---|
| SmartConfig（乐鑫） | 手机 App 一键配网 | 广播包携带凭据，对路由器兼容性有波动，要实测 |
| SoftAP+网页 | 稳定优先 | 手机连设备热点输密码，"重"但可靠 |
| BLE 配网（双模芯片） | C3/S3 等 | BLE 写凭据再走 WiFi，最稳，需双模 |

- 配到的凭据**必须写 NVS**（掉电保存），上电自动重连
- 配网状态机：未配网→配网中(限时 3 分钟超时)→已配网→可重配(长按键触发)

## 四、MQTT 上报骨架（小家电/家居标配）

- 组件：esp-mqtt（ESP-IDF 官方组件）
- 骨架：连接 broker → 订阅主题 → 事件回调（MESSAGE/DISCONNECTED）
- 与 WiFi 状态机联动：**MQTT 仅在 GOT_IP 后启动，DISCONNECTED 后停止**
- QOS 选择：遥测 QOS0/1，控制指令 QOS1
- 心跳：keepalive 建议 60s；长时间断线重连用指数退避

## 五、WiFi 通用红线

1. **任务栈**：WiFi/MQTT 事件任务栈 ≥ 8KB（示例常用配置），栈不足的标志是随机 abort
2. **Watchdog**：连接类阻塞操作放进事件回调或独立任务，禁止在应用主任务里裸等 connect 返回
3. **功耗**：电池产品用 WiFi Modem Sleep 策略（配合 power-analysis 技能）
4. **射频前提**：40MHz 晶振精度不达标 → 连不上/掉线，先按 bring-up-checklist 验晶振
5. 日志按 debug-log-standard 规范：连接状态变化、RSSI、原因码必须打日志

## 六、与其它技能联动

| 技能 | 关系 |
|---|---|
| esp-idf-build | 编译烧录 |
| esp32-panic-diagnosis / memory-leak-detection | 崩溃/内存排查 |
| bring-up-checklist | 晶振前提 |
| wireless-sniffer | 连不上时的抓包排查 |
| rf-verification | 适配层测试与认证 |
