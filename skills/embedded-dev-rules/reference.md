# 嵌入式开发规则 - 详细参考

> 本文件为 embedded-dev-rules 技能的详细清单与模板（自 SKILL.md 拆分）。SKILL.md 保留红线与核心工作流。

---

## 缺陷台账管理（2026-09-02 新增，产品级缺陷闭环）

> 适用：所有已进入开发阶段的项目。模板见工作区 `缺陷台账_模板.md`，复制到项目根目录后启用。
> 目的：缺陷可追踪、修复可验证、教训可沉淀，与 Gitee issue 形成"本地真相源 + 远程同步"闭环。

### 登记规则
- 登记时机：bug 发现 / 用户反馈"不行" / 自测失败 / 烧录后功能不符 → **立即登记**（允许一行先记，事后补全）
- ID 规则：`DEF-<年月>-<序号>`（如 DEF-2609-001）；严重级：S0 致命（死机/数据损坏）/ S1 严重（核心功能失效）/ S2 一般 / S3 轻微
- 状态机：新建 → 分析中 → 已修复 → 回归通过 → 关闭；无法复现 → 挂起（注明复现条件）

### 处理规则
- 同一现象累计 ≥3 条 → 升级专项分析（与 mass-production 良品率台账联动）
- 关闭条件：修复 + 回归验证（含独立上电复验）通过后才准关闭
- 软件类不良对策 → 回写设计文档 + release-notes（固件版本说明）
- 里程碑/收尾：未关闭条目用 MCP create_issue 同步到 Gitee 项目私有仓，标注相同 ID，并记录 issue 链接进台账同步记录表

## pre-commit 提交门禁（2026-09-02 新增）

> 新项目 `git init` 后的第一条命令：`install-precommit`（Tools 全局工具，含 .bat 入口）。

- 效果：暂存 .c/.h 自动跑 code-style-check 溢出+防御专项——**P0 致命隐患（退出码 3）阻止提交**；P1/规范级只警告放行；暂存含中文 .ps1 无 UTF-8 BOM 阻止提交
- 逃生门：确需强制提交用 `git commit --no-verify`，但必须 commit body 注明原因，事后补齐修复
- 工具：`install-precommit -Status/-Remove/-RepoPath` 管理钩子；检查逻辑在 Tools\pre-commit-check.ps1

## 外设调试排查 SOP（跨芯片通用，2026-08-29 GD32F407VE PWM 三连黑屏实战沉淀）

> 适用：任何芯片任何外设（PWM/串口/I2C/SPI/定时器/ADC...）配置后不工作。按顺序执行，严禁跳步。
> 本 SOP 与芯片无关（ARM/8051/ESP32 通用）；芯片特有差异（命名/复用表/模式语义）见 L2 chip-rules 或官方资料。

### 第 0 步：数据源/基础有效性校验（v2.5 新增，永远最优先）
- 任何"输出无声/无效/不动"排查，**先验证"预期数据/波形源"本身有效**：播放前打印 PCM `max|x|`、串口先发固定字节、PWM 写死 100%。数据源为 0/空 → 直接定位软件数据生成问题，禁止先查外设/寄存器/链路（2026-09-01 喇叭无声案例：数据源全零导致 10+ 轮硬件侧排查全部白费）
- 与"调试纪律强化"章节第 1 条同源，此处为 SOP 执行入口

### 第 1 步：现象定性（30 秒）
- **输出恒定**（背光恒灭/恒亮、引脚电平不动、无信号）→ 大概率信号没从外设出来：时钟未使能 / 引脚复用错 / 外设编号错 / 输出未使能
- **输出错乱**（乱码/花屏/错位/数值离谱）→ 信号出来了但时序 / 极性 / 速率 / 字节序 / 分频问题

### 第 2 步：查证链（按序，每项都用文档/寄存器确认，禁止凭记忆）
1. **时钟**：外设时钟使能了吗？挂哪条总线（APB1/APB2/APB）？总线分频算对了吗？
2. **引脚复用号**：查该芯片**官方数据手册（Datasheet）引脚复用表**（部分芯片用户手册不列，见 7.3.3 式指引；STM32 用户手册 8.3.1 则直接有）。逐挑官方分线板/核心板原理图交叉确认
3. **外设编号/命名**：核对芯片手册外设编号表（不同厂商编号不同义：GD32 TIMER1=ST TIM2；STC 与外设命名亦不同）。核对库头文件基址/宏
4. **模式/极性/时序语义**：查用户手册对应章节（PWM 模式 0/1、极性位、边沿对齐 vs 中央对齐、空闲电平）。同名配置在不同厂商语义可能相反
5. **寄存器诊断**：配置后读寄存器快照打印（控制/配置/比较值/复用选择寄存器），比对"落盘值 vs 期望值"，确认使能位/极性/模式/复用号都对

### 第 3 步：最小化验证
- 先固定最简单状态（如 PWM 占空比写死 100%、串口只发一个字节），确认通路通了再叠加功能（调光/调速/协议）
- 每次只改一个变量；**每个 bug 修复必须升版本号**（用固件版本字符串区分烧没烧对，禁止覆盖测试）

### 第 4 步：止损与回退
- 连续 3 版未解决 → 停止盲改，回退到已知可用基线（如 GPIO 直驱），再按查证链逐项排查（跨厂商防坑规则见 user_profile「嵌入式驱动开发防坑规则」第 4 条）
- 诊断打印验证后立即删除，不留正式代码（诊断代码最小化规则）

### 工具：芯片文档 PDF 解析
- 官方手册/数据手册 PDF 用 python pymupdf(fitz) 解析：`fitz.open()` + `page.find_tables()` 提取复用表/寄存器表，`get_toc()` 定位章节
- 手册页数多没关系，先查目录定位章节再精读


## 防坑执行清单（门禁 + 自动化检测）

> 本节是前面所有规则的**执行视图**，按"什么时候执行什么"整合。规则定义见前文各章节，本节只负责按时机组织，不重复规则内容。
>
> **核心原则**：不靠"下次记着"，靠门禁流程 + 自动化检测 + Memory 预载三种结构性机制兜底。

### Part A：开工前 Memory 预载（每次新 session 启动时执行）

**目标**：把过去踩过的坑先加载到当前上下文，避免重蹈覆辙

- [ ] A1. 按项目关键词搜 `user_profile.md`（用户偏好、技术栈、工具链路径）
- [ ] A2. 按项目关键词搜 `project_memory.md`（Lessons Learned、踩坑记录、引脚表）
- [ ] A3. 搜近 2 天 `topics.md`，找相关 session_id 后读 `session_memory_*.jsonl` 提取细节
- [ ] A4. 已有项目搜 knowledge-index：`knowledge-index -Search "<关键词>"`
- [ ] A5. 列出搜索结果中"踩过的坑"，标注本次项目是否可能踩同样的坑

**预算**：≤ 2-6 步搜索，不超过 30 秒

### Part B：嵌入式开发门禁流程

> 每道门禁未通过时**禁止**进下一步。用户确认判定标准见"人机互动开发规范"规则 1。

#### 门禁 B1：四步准备文档 OK

**触发**：任何嵌入式新项目开工
**未通过时禁止**：写任何 .c/.h 业务代码（仅允许写四步文档本身）

- [ ] B1.1 四步准备文档已完成（见"新项目启动流程"章节）
- [ ] B1.2 MCU↔外设连接表已输出（强制表格 + 每行有证据来源：网表行号/PDF 页码/原理图编号）
- [ ] B1.3 时钟源已确认（默认 IRC16M/HSI，禁用 HXTAL/HSE 除非用户书面确认起振✅）
- [ ] B1.4 V0 验证方式已选定（V0-A LED / V0-B UART / V0-C GPIO 三级兜底之一）
- [ ] B1.5 用户已用明确肯定性文字确认（按"用户确认判定标准"核对，❌ 模糊语气不算）

#### 门禁 B2：V0 验证通过

**触发**：V0 代码烧录后
**未通过时禁止**：写任何 V1 外设驱动代码

- [ ] B2.1 V0 代码已编译通过（0 Error, 0 Warning）
- [ ] B2.2 用户已烧录并描述具体现象（禁止自己脑补"应该没问题"）
- [ ] B2.3 现象符合预期（如 LED 在闪、频率正确、串口输出正常）
- [ ] B2.4 现象模糊时已用结构化追问清单追问（禁止猜原因，见"人机互动开发规范"规则 4）
- [ ] **B2.5 脱机复验（Q10，V0 级首次必做）**：连调试器跑通后，**拔掉调试器 USB → 断电 → 独立上电再验证一遍**，现象与连调试器时一致才通过。若不一致，排查：DBGMCU freeze 寄存器导致看门狗/定时器被调试器暂停时停了；SWD 引脚 PA13/PA14 被误当 GPIO 用；复位方式差异（硬件复位 vs SYSRESETREQ）

#### 门禁 B3：基线快照

**触发**：V0 验证通过后**立即**执行
**未通过时禁止**：改任何核心初始化代码

- [ ] B3.1 有 Git 工程：`git add -A && git commit -m "feat(v0): baseline passed, [V0方式]"`
- [ ] B3.2 无 Git 工程：复制工程目录为 `.baseline_v0_pass`
- [ ] B3.3 commit ID 或备份路径已记录到聊天窗口
- [ ] B3.4 后续出现"V0 原本能跑现在不行"时，立即与基线对比定位改坏的点

#### 门禁 B4：不确定抛选择（行动前三问法）

**触发**：见"人机互动开发规范"规则 7 的三问法自检
**通过条件**：用 AskUserQuestion 抛结构化选择题，用户做出选择
**未通过时禁止**：自己拍板决定

- [ ] B4.1 已用三问法自检（①需用户硬件操作？②需用户观察？③我 100% 把握？）
- [ ] B4.2 任一答"是" → 已抛选择题
- [ ] B4.3 推荐选项已标注（放第一项并标"(推荐)"）
- [ ] B4.4 选项互相排斥、说明充分（每个选项有 trade-off 说明）

#### 门禁 B5：每级 Vn 验证通过（脱机复验通用门禁）

**触发**：V1/V2/V3... 每一级验证代码烧录后
**未通过时禁止**：推进到下一级 V(n+1)

- [ ] B5.1 本级 Vn 代码已编译通过（0 Error, 0 Warning）
- [ ] B5.2 用户已烧录并描述具体现象（禁止自己脑补"应该没问题"）
- [ ] B5.3 现象符合预期
- [ ] **B5.4 脱机复验（Q10，每级必做）**：连调试器跑通后，**拔掉调试器 USB → 断电 → 独立上电再验证一遍**，现象与连调试器时一致才算本级通过。若不一致，排查：DBGMCU freeze 寄存器导致看门狗/定时器被调试器暂停时停了；SWD 引脚 PA13/PA14 被误当 GPIO 用；复位方式差异（硬件复位 vs SYSRESETREQ）
- [ ] **B5.5 为什么每级都要做（Q10 扩展依据）**：V0 只是最小系统，V1+ 开始加看门狗/定时器/复用 PA13/PA14 等驱动后才可能触发 DBGMCU freeze、看门狗误触发、SWD 冲突等"只在独立运行时才暴露"的问题。不要只验证 V0 一次就跳过后续各级

#### 门禁 B6：发布前版本控制检查

**触发**：准备交付固件（烧录到量产板/发给客户/打 release tag）前
**未通过时禁止**：打 tag、交付固件 bin

- [ ] B6.1 项目已 `git init` 且有 `.gitignore`（排除 build/、*.bin、*.hex、*.uvoptx、*.bak、*.log）
- [ ] B6.2 根目录有 `version.h`，含 `FW_VERSION_MAJOR/MINOR/PATCH/STRING` 宏
- [ ] B6.3 `version.h` 中的版本号与即将打的 tag 一致（如 version.h 写 v1.2.0，tag 就是 v1.2.0）
- [ ] B6.4 所有改动已提交，`git status` 无未提交文件（排除 .uvoptx 等已 ignore 的）
- [ ] B6.5 commit message 符合格式 `type(scope): subject`
- [ ] B6.6 当前分支正确（发布在 main 上，不在 feature 分支上直接发）
- [ ] B6.7 `git tag -a vX.Y.Z -m "Release vX.Y.Z: 简述"` 已打
- [ ] B6.8 固件 bin 中包含版本号字符串（可用 `strings firmware.bin | grep v` 验证）
- [ ] B6.9 `git log --oneline -5` 确认最近提交记录清晰可追溯
- [ ] B6.10 **交付构建必须是 Release 配置**（量产交付前置）：优化等级（Keil -O2 / C51 8~9）、DEBUG 宏关闭调试打印、看门狗启用、读保护开启、半主机关闭。详细对照表见 mass-production 技能"Release 构建配置"章节

### Part C：代码提交前自动化检测

**目标**：能写成正则匹配的坑，一律下沉为脚本检测，不靠人工审查

#### C1：必跑脚本

- [ ] C1.1 `code-style-check.ps1 -Path <目录或文件> -Checks overflow,defensive,brace,naming,header`
- [ ] C1.2 编译警告清零（C51/ARM/ESP32 自动识别，警告必须处理）
- [ ] C1.3 `pin-check.ps1`（引脚冲突检测）
- [ ] C1.4 `keil-clean.ps1`（如适用，清理中间文件）

#### C2：自动化检测已覆盖的坑类型

| 坑类型 | 严重程度 | 触发条件 |
|---|---|---|
| sprintf/strcpy/gets 等危险函数 | P0 致命 | 出现这些函数名 |
| snprintf 长度参数是裸数字 | P0 致命 | `snprintf(..., 数字, ...)` |
| 窄类型相乘未扩宽 | P0 致命 | `uint16_t * uint16_t` |
| memcpy 裸数字长度 | P0 致命 | `memcpy(..., 数字>4)` |
| 移位位数 ≥ 类型宽度 | P1 高 | `<< 32` / `<< 16` |
| 有符号/无符号比较 | P1 高 | `if (var < sizeof(...))` |
| 无符号循环递减死循环 | P1 高 | `for (uintX_t i=N; i>=0; --i)` |
| strlen 减法回绕 | P1 高 | `strlen(s) - N` |
| **Q1 struct 协议结构体缺 _Static_assert(sizeof)** | P0 致命 | `typedef struct {} xxx_t;` 后 6 行内无 `_Static_assert(sizeof(xxx_t)==N)` |
| **Q3 宏含运算符但缺最外层括号** | P1 高 | `#define FOO x*x` 宏值有 `+ - * / << >>` 且首尾非 `(...)` |
| **Q6 ISR 内调用看门狗喂狗** | P1 高 | `*IRQHandler/*_isr` 函数体内有 `fwdgt_counter_reload/iwdg_feed/...` |
| **Q7 main() 缺 NVIC 优先级分组设置** | P1 高 | `int main(` 出现但全文无 `nvic_priority_group_set/HAL_NVIC_SetPriorityGrouping/NVIC_PriorityGroupConfig` |
| switch 缺 default | P1 高 | switch 块结束无 default |
| 局部变量未初始化 | P2 中 | 函数体内声明未赋值 |
| Tab/空格混用 | 低 | 缩进行同时含 Tab 和空格 |
| 行宽超 120 | 低 | 单行 > 120 字符 |
| 大括号省略 | 中 | if/else/for/while 后无 `{` |
| 头文件无保护 | 中 | .h 文件无 `#ifndef/#define/#endif` |

#### C3：人工审查清单（脚本无法覆盖）

完整清单见 `embedded-code-review` 技能。重点项：

- [ ] C3.1 寄存器配置已查头文件确认（按 `datasheet-lookup` 5 步流程，红线规则 2）
- [ ] C3.2 ISR 中无耗时操作（printf/阻塞等待/复杂循环）
- [ ] C3.3 共享变量加 `volatile`
- [ ] C3.4 中断标志位清除方式正确
- [ ] C3.5 回调函数调用前非空校验
- [ ] C3.6 8 位 MCU 上 16/32 位共享变量有原子访问保护（Q5：读两遍相等法 `do { a=g_tick; b=g_tick; } while(a!=b);` 或读前关中断）
- [ ] C3.7 看门狗已启用（如需 7×24 运行），喂狗在主循环不在中断（Q6：自动化检测脚本已覆盖 ISR 内喂狗检测，但喂狗周期、FreeRTOS 任务优先级仍需人工确认）
- [ ] C3.8 通信总线有超时退出 + 错误恢复
- [ ] C3.9 安全降级模式设计（传感器故障不伪装正常，执行机构收到非法参数进安全态）
- [ ] C3.10 对外操作幂等性（init 有已初始化标志，Flash 写前比较，状态机非法转移进安全态）
- [ ] C3.11 **Q7 NVIC 优先级分组**：通信中断（UART/SPI/I2C）抢占级 > 定时器 > EXTI 按键；NVIC_PRIGROUP 已写死，不使用默认值（默认 0 抢占级所有中断同优先级，高优串口被 EXTI 长时间阻塞）
- [ ] C3.12 **Q8 SPI 切外设重配 CPOL/CPHA**：同一 SPI 挂多设备（Flash Mode0 / OLED Mode3）时，**每次片选拉低前先重新配置 SPI 的 CPOL/CPHA/数据位宽/波特率预分频**，不靠"上次配置还在"
- [ ] C3.13 **Q9 I2C 初始化加 SCL 脉冲恢复序列**：I2C init 时先检查 BUSY 标志，如果 BUSY 置位 → 把 SCL/SDA 切为 GPIO 推挽输出，手动发 9 个 SCL 脉冲（1 个字节 + ACK 位）+ 最后发 STOP 信号 → 再重新初始化为 I2C 外设模式。用于清除热插拔/中途复位导致的"从机一直拉低 SDA 死锁"
- [ ] C3.14 **Q10 每一级 Vn 验证追加脱机复验**：连调试器跑通后，拔掉调试器 USB、断电、独立上电再跑一遍，现象一致才算通过。不同时排查 DBGMCU freeze 配置、SWD 引脚复用冲突

#### C4：踩过的坑升级为自动化检测（每次踩坑后执行）

**规则**：凡是重复踩过两次的坑，优先考虑是否能写成正则匹配加入脚本，而不是只记到 memory

- [ ] C4.1 列出本次项目踩过的新坑
- [ ] C4.2 评估是否可以写成正则匹配
  - ✅ 可以 → 加入 `code-style-check.ps1` 的 Overflow/Defensive 类别
  - ❌ 不可以 → 加入 `embedded-code-review` 技能的人工审查项
- [ ] C4.3 记录到 `project_memory.md` 踩坑记录章节（见"错误学习机制"章节）
- [ ] C4.4 重建 knowledge-index：`knowledge-index -Index`

### Part D：脚本自身陷阱防护

**目标**：避免脚本本身的编码/语法陷阱（P3 类坑）

- [ ] D1. 中文 .ps1 脚本写完**立即加 UTF-8 BOM**（避免 PowerShell 5.x 读中文为乱码）
  ```powershell
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($path, $content, $utf8Bom)
  ```
- [ ] D2. PowerShell 脚本中避免反引号 `` ` `` 在双引号字符串中（用单引号或逐行匹配/替换）
- [ ] D3. 改 .uvprojx/.ioc/CMakeLists.txt 等工程文件**直接禁止**（红线规则 1，不是"小心点改"）
- [ ] D4. 脚本写好后自己先跑一遍验证（不交付未测试的脚本）
- [ ] D5. RunCommand 单次命令上限 32KB，长脚本写入临时 .ps1 文件再执行
- [ ] D6. 操作外部目录前先检查 sandbox.json 读写权限（红线规则 7）
- [ ] D7. PowerShell 参数传递用 `-File` + 脚本文件，避免 `-Command` 内嵌变量被 shell 吞掉

### Part E：Memory 闭环维护

**目标**：保证 Part A（Memory 预载）有东西可搜

- [ ] E1. 每次用户反馈"不行"后，**立即**记录到 `project_memory.md` 踩坑记录章节
- [ ] E2. 记录格式：`[日期] [模块名] [现象] [根本原因] [修复方法] [预防措施]`
- [ ] E3. 记录后重建 knowledge-index：`knowledge-index -Index`
- [ ] E4. 下次同类问题先搜 knowledge-index：`knowledge-index -Search "<关键词>"`
- [ ] E5. 跨项目通用规则写入 `user_profile.md`，项目级规则写入 `project_memory.md`（不散落为额外文件）
- [ ] E6. 重大踩坑（≥3轮）解决后执行链路体检四步：旧结论作废检查 → 规则落点分级 → 执行入口核对 → knowledge-index 重建（见「错误学习机制」第 4 步）

### 执行时机速查

| 时机 | 执行 Part |
|---|---|
| 每次新 session 启动 | Part A（Memory 预载） |
| 新项目开工 | Part B 全部门禁（B1→B2→B3→B4） |
| 已有项目继续开发 | Part B 门禁 B4（不确定抛选择） |
| 每次代码提交前 | Part C（自动化检测）+ Part D（脚本陷阱防护） |
| 每次踩坑后 | Part E（Memory 闭环）+ Part C4（升级自动化检测） |

### 三条关键原则

1. **门禁未通过禁止进下一步** — 宁可多问一句，不要自认为用户默认同意
2. **能自动化的不靠人工** — 凡是能写成正则匹配的坑，一律下沉为脚本检测
3. **Memory 预载前置** — 开工前先搜，比踩坑再排查便宜 100 倍

## 技能路由表

以下场景必须调用对应技能，不要自行实现：

| 场景 | 技能 |
|------|------|
| 写寄存器/查数据手册 | datasheet-lookup |
| 编译+烧录 Keil 项目 | keil-auto-flash |
| 编译+烧录 ESP32 项目 | esp-idf-build |
| 烧录失败排查 | hardware-detection |
| 串口监听/发送 | serial-debug |
| 内存占用分析 | memory-analysis |
| 代码审查 | embedded-code-review |
| 引脚分配检查 | pin-check |
| 头文件变更影响 | impact-analyze |
| 编译警告匹配 | log-analysis（Skill）+ warning-db（Tools 脚本） |
| 崩溃诊断（ARM） | hardfault-diagnosis |
| 崩溃诊断（ESP32） | esp32-panic-diagnosis |
| 跨项目经验搜索 | knowledge-index |
| 项目收尾清理 | project-cleanup |
| Git 提交/版本管理 | git-workflow |
| 新项目脚手架 | project-init |
| 切换开发板 | board-config |
| 主机端单元测试 | embedded-unit-test |
| 烧录后硬件自检 | peripheral-test-template |
| 生成测试报告 | test-report |
| FreeRTOS 基础 API 速查 | freertos-basics |
| FreeRTOS 与驱动集成 | freertos-driver-integration |
| ESP32-S3 双核 FreeRTOS | freertos-multicore |
| ESP32 实时断点调试 | live-debug-workflow |
| ESP32 内存泄漏检测 | memory-leak-detection |
| 低功耗分析与优化 | power-analysis |
| 通信协议抓包分析 | protocol-analysis |
| 原理图辅助阅读 | schematic-reading |
| 芯片间代码移植 | code-migration |
| 查库官方文档（ESP-IDF/FreeRTOS API） | mcp_context7 |
| WiFi 应用模板（STA/配网/MQTT） | wifi-app-template |
| BLE 透传(NUS)模板 | ble-nus-template |
| 无线抓包排障 | wireless-sniffer |
| 射频验证与认证 | rf-verification |
| 调试日志规范（格式/故障现场） | debug-log-standard |
| 新板 bring-up 上电查验 | bring-up-checklist |
| 软件设计文档生成 | software-design-doc |
| 量产流程/产测/良率台账 | mass-production |
| 生成发布说明 | release-notes |

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| 红线规则（9条） | ✅ | 通用嵌入式开发安全规范，v2.1 新增 sandbox 检查/头文件禁全局变量/局部变量必须初始化 3 条 |
| 修改代码检查流程（.c/.h 互检） | ✅ | 通用防御性编程规则，与 user_profile 中"修改代码强制检查规则"一致 |
| 初始化顺序（时钟→GPIO→外设→中断） | ✅ | GD32/STM32/STC8/ESP32 通用初始化最佳实践 |
| 编译验证路径（Keil/ESP-IDF） | ✅ | 与 user_profile 中"编译验证自动化"配置一致 |
| 新项目启动清单（8项） | ✅ | v2.3 升级为四步准备流程，8 项降为第一步摘要 |
| 错误学习机制 | ✅ | v2.1 更新为闭环：记录→重建索引→搜索前置 |
| 审查规则层级关系 | ✅ | v1.1.0 新增：精华→红线→完整清单三层文档化 |
| 技能路由表（31个技能引用） | ✅ | 所有引用的技能均已确认存在于技能目录，v2.1 新增 3 个，v2.2 新增 12 个（含 1 个 MCP） |
| MCP 工具使用规则 | ✅ | v2.2 新增：mcp_Filesystem/mcp_pdf-reader-mcp 禁用，mcp_context7 优先于 WebSearch |
| 新项目启动流程（四步准备流程） | ✅ | v2.3 新增：替代原 8 项清单，整合需求分析→硬件评估→软件架构→工具链四步 + V0 验证梯度 + 基线快照 + 执行门槛 |
| 人机互动开发规范（7 条） | ✅ | v2.3 新增：进度看板、阶段切换自检、烧录等待回报、模糊回答追问、选择题不脑补、出错透明化、决策边界三问法 |
| ├ datasheet-lookup | ✅ | 已安装技能 |
| ├ keil-auto-flash | ✅ | 已安装技能 |
| ├ esp-idf-build | ✅ | 已安装技能 |
| ├ hardware-detection | ✅ | 已安装技能 |
| ├ serial-debug | ✅ | 已安装技能 |
| ├ memory-analysis | ✅ | 已安装技能 |
| ├ embedded-code-review | ✅ | 已安装技能（本次验证） |
| ├ pin-check | ✅ | 已安装技能 |
| ├ impact-analyze | ✅ | 已安装技能 |
| ├ log-analysis（Skill）+ warning-db（Tools 脚本） | ✅ | log-analysis 为已安装 Skill；warning-db 为 Tools 脚本（RunCommand 调用，非独立 Skill） |
| ├ hardfault-diagnosis | ✅ | 已安装技能 |
| ├ esp32-panic-diagnosis | ✅ | 已安装技能 |
| ├ knowledge-index | ✅ | 已安装技能 |
| ├ project-cleanup | ✅ | 已安装技能 |
| ├ git-workflow | ✅ | 已安装技能 |
| ├ project-init | ✅ | 已安装技能 |
| ├ board-config | ✅ | 已安装技能 |
| ├ embedded-unit-test | ✅ | 已安装技能（v2.1 新增） |
| ├ peripheral-test-template | ✅ | 已安装技能（v2.1 新增） |
| └ test-report | ✅ | 已安装技能（v2.1 新增） |
| ├ freertos-basics | ✅ | 已安装技能（v2.2 新增） |
| ├ freertos-driver-integration | ✅ | 已安装技能（v2.2 新增） |
| ├ freertos-multicore | ✅ | 已安装技能（v2.2 新增） |
| ├ live-debug-workflow | ✅ | 已安装技能（v2.2 新增） |
| ├ memory-leak-detection | ✅ | 已安装技能（v2.2 新增） |
| ├ power-analysis | ✅ | 已安装技能（v2.2 新增） |
| ├ protocol-analysis | ✅ | 已安装技能（v2.2 新增） |
| ├ schematic-reading | ✅ | 已安装技能（v2.2 新增） |
| ├ code-migration | ✅ | 已安装技能（v2.2 新增） |
| └ mcp_context7（查官方文档） | ✅ | 已配置 MCP 服务器（v2.2 新增） |








| 调试纪律强化 + 数据源优先（5 条） | ✅ | v2.5 新增：数据源第一/软件读数≠真相/手册前置/资料验实物/memory 存疑，随外设调试 SOP 第 0 步执行 |
| ├ debug-log-standard | ✅ | 已安装技能（v2.4 新增） |
| ├ bring-up-checklist | ✅ | 已安装技能（v2.4 新增） |
| ├ software-design-doc | ✅ | 已安装技能（v2.4 新增） |
| └ mass-production | ✅ | 已安装技能（v2.4 新增） |
