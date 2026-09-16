---
name: data-organization
version: 1.0.0
description: |
  当用户设计 C 数据结构（struct vs union vs typedef vs 位字段选型）、疑惑结构大小与对齐空穴、要按位封装硬件标志、或以 union 做寄存器/协议字段视图时调用。 核心: struct 组织异质字段单元并可整体赋值/传参/返回；联合成员偏移全 0 共享存储取最大者；typedef 只是别名非新类型；位字段在成员层声明 成员:位数。 步骤: 按"同存异存"选 struct/union→用 sizeof 求真长→位密集用位字段→对外固定布局用偏移工具。 不适用于: 需要严格二进制内存布局可移植性保证（跨编译器时位字段/union 布局是实现定义的）；链表/树的遍历插入删除实现套路（→ 路由入口 linked-list 能力）；算法实现本身（→ c-algorithms）。 Triggers: 结构体/联合体/typedef/位字段/对齐/空穴/寄存器/协议字段/struct/union/bitfield
metadata:
  cangjie.generated-by: cangjie-tools v2.5.0
  cangjie.capability-id: cap.cprogramming.data-organization
  cangjie.capability-revision: 1
  cangjie.bundle-id: bundle.cprogramming
  cangjie.source-title: C 程序设计语言（K&R 第2版）
  cangjie.tags: c, struct, embedded
---
# 结构/联合/typedef/位字段：数据组织与内存布局

## R — 原文 (Reading)

> "结构是一个或多个变量的集合，这些变量可能为不同的类型，为了处理的方便而将这些变量组织在一个名字之下。"（第6章 §6.1）
>
> "千万不要认为结构的长度等于各成员长度的和。因为不同的对象有不同的对齐要求，所以，结构中可能会出现未命名的'空穴'。"（第6章 §6.7）
>
> "联合是可以（在不同时刻）保存不同类型和长度的对象的变量…联合提供了一种方式，以在单块存储区中管理不同类型的数据。"（第6章 §6.8）
>
> "C语言提供了一个称为typedef的功能，它用来建立新的数据类型名。"（第6章 §6.7）
>
> — B. W. Kernighan & D. M. Ritchie, 第6章

---

## I — 方法论骨架 (Interpretation)

四个工具管"数据怎么在内存里组织"，各有明确分工：

- **struct（结构）**：把不同类型相关字段捆成一个**可整体赋值/传参/返回**的单元；它描述"多个字段并存"，是链表、表结构等复杂数据的地基；
- **union（联合）**：所有成员**共享同一段存储**，偏移全为 0，空间取最大成员——"同一时刻只存一种类型"，用于寄存器视图、类型双关、窄宽度数据孔洞管理；
- **typedef**：只是**给已有类型起别名**，不是新类型（与 #define 文本替换不同，遵守作用域规则），用于隐藏机器相关类型、简化函数指针写法；
- **位字段（bit-field）**：结构成员一级的 `unsigned nf : 3` 语法，按位封装标志/窄字段，免手动掩码——压缩存储、对接硬件寄存器。

两条硬知识：**结构大小 ≠ 成员之和**（有对齐空穴），一律用 `sizeof`；**联合成员偏移都是 0**、初始化只能用第一个成员类型。

---

## A1 — 书中的应用 (Past Application)

### 案例 1: 图形点与矩形
- **问题**: 用两个坐标表示点、两个点表示矩形。
- **方法论的使用**: 定义 `struct point { int x, y; }`、`struct rect { struct point pt1, pt2; }`，嵌套结构。
- **结论**: 结构把相关坐标捆成单元，可用 `screen.pt1.x` 逐层访问；ANSI 起结构可整体赋值/传参/返回。
- **结果**: 图形域对象模型的标准样板（第6章 §6.1–6.2）。

### 案例 2: 关键字统计表（struct 数组 + typedef）
- **问题**: 把关键字与计数绑在一起组织成查找表。
- **方法论的使用**: `struct key { char *word; int count; } keytab[]` + `typedef` 简化说明，`sizeof keytab/sizeof keytab[0]` 算表长。
- **结论**: 结构数组是"名称→数据"映射的天然载体；表长应在编译期计算以防越界。
- **结果**: 关键字计数程序的静态表（第6章 §6.3）。

### 案例 3: 自建分配器用 union 保证对齐
- **问题**: malloc 返回的块要能装任意类型，需要对齐保证。
- **方法论的使用**: `union header { struct { union header *ptr; unsigned size; } s; Align x; }`——用最受限类型（long/Align）的 union 保证对齐。
- **结论**: union 的"取最大成员 + 满足最严格对齐"特性正中用途。
- **结果**: 第8章 §8.7 分配器头部即 union 应用的经典示例（见 allocator-pattern）。

---

## A2 — 触发场景 (Future Trigger) ★

### 用户会在什么情境下需要这个 skill?

1. 设计 C 数据结构时纠结"该用 struct 还是 union 还是位字段"；
2. 计算 struct 占用内存/序列化时发现尺寸和成员和不一致（对齐空穴）；
3. 嵌入式里解析硬件寄存器/协议帧，想把标志位按位封装或实现类型双关；
4. 想把机器相关类型（长度、指针组合）封装成可移植名字（typedef）；
5. 阅读库文件/头文件时遇到 `union`、`unsigned : n`、`typedef struct` 看不懂。

### 语言信号 (用户的话里出现这些就应激活)

- "结构体为什么比成员加起来大？"
- "什么时候用 union / 什么时候用位域？"
- "typedef 和 #define 有什么区别？"
- "寄存器/协议字段怎么定义？"
- "struct vs union / bitfield syntax / alignment padding / typedef purpose"

### 与相邻 skill 的区分

- 与 `pointer-array` 的区别: 它管指针/数组的下标换算，本 skill 管 struct/union/typedef/位字段的组织与布局；
- 与 `c-algorithms` 的区别: 那管在这些数据上跑查找/排序，本 skill 管数据本身怎么声明与存放；
- 与 `linked-list-pattern`（路由）的区别: 链表/树的遍历插入删除实现套路不经本 skill，走路由入口；
- 与 `allocator-pattern` 的区别: union 对齐在分配器中只是应用之一，分配器本体主题在另一能力卡。

---

## E — 可执行步骤 (Execution)

1. **按"数据并存性"选择容器**
   - 完成标准: 确定字段是"同时存在"（struct）还是"不同时刻只存其一"（union）；最大成员/共享存储说明写清。
   - 判停条件: 若字段多到需要分组语义（嵌套），先设计内层结构再组合。

2. **🔴 CHECKPOINT · 仅容器选型歧义时确认**
   - 完成标准: struct/union 选择在字段语义清晰（并存 vs 互斥）时直接进入步骤 3，不打断用户。
   - 判停条件: 仅当字段既有并存又有互斥部分、或用户需求含"类型双关/叠加同一存储"意图模糊时，向用户复述拟选容器与理由，确认后再继续。

3. **声明并确认布局**
   - 完成标准: 写出 struct/union/typedef 声明；对 struct 用 `sizeof` 给出真实大小并说明空穴来源；对 union 说明首成员与最大成员。
   - 判停条件: 涉及硬件/串行化固定布局时，提示位字段与 union 布局是实现定义的，跨编译器需偏移断言或工具确认。

4. **🛑 STOP · 仅可移植性风险时确认**
   - 完成标准: 布局不涉及跨编译器固定格式（无位字段跨字节/无字节序敏感/无 packed 依赖）时，直接给出结论。
   - 判停条件: 仅当结论依赖实现定义的布局（位字段跨字节、union 字节序、对齐假设）时暂停，明确告知"该布局跨编译器可能不一致"，由用户决定是否接受；绝不静默承诺"到处都一样"。

5. **选用位字段或掩码**
   - 完成标准: 标志/窄字段（数位上限明确）用位字段 `unsigned f:1`，否则用掩码宏；给出两种写法的等价说明。
   - 判停条件: 位字段跨字节/字节序敏感时，提示实现定义与可移植性风险。

6. **验证可移植性**
   - 完成标准: 指出哪些成员顺序/对齐假设是本书环境成立但跨实现的（如 Align 用 long）；必要时用静态断言（sizeof/offsetof）。

---

## B — 边界 (Boundary) ★

### 不要在以下情况使用此 skill

- 用户问的是数组（pointer-array）、字符串（基础语法）等非结构场景；
- 需要严格二进制序列化格式且跨编译器的业务（位字段/union 布局是实现定义的，需额外机制）；
- C++ 的 class/struct 语义不同（本 skill 是 C）。

### 作者在书中警告的失败模式

- "千万不要认为结构的长度等于各成员长度的和"——对齐空穴导致手算错误（第6章 §6.7）；
- 联合只能用第一个成员类型初始化（第6章 §6.8）；
- 无符号/有符号位字段取值规则与对齐由实现决定，构造字面值要用 unsigned（附录A）。

### 作者的盲点 / 时代局限

- 书中默认 16/32 位机器；现代对齐规则与 `_Alignof`/`offsetof` 工具未覆盖，位字段跨字节实现差异依旧存在。
- 未讨论 packed/对齐控制（那是编译器扩展），序列化场景需额外说明。

### 容易混淆的邻近方法论

- typedef vs #define（别名 vs 文本替换）；
- union vs struct（共享存储 vs 并行存储）；
- 位字段 vs 掩码位运算（声明期 vs 表达式期的两套做法）。

---

## 相关 skills (阶段 3 填充)

- composes-with: c-algorithms, allocator-pattern, memory-safety
- contrasts-with: pointer-array

---

## 审计信息

- **验证通过**: V1 ✓ / V2 ✓ / V3 ✓
- **蒸馏时间**: 2026-09-10