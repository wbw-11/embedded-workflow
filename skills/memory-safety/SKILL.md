---
name: memory-safety
version: 1.0.0
description: |
  当用户处理 malloc/free（何时分配、如何安全释放、链表删除的 next 保存）、strcat/strcpy 缓冲区溢出防护、或 malloc 失败处理时调用。 核心: 每个 malloc/calloc/返回指针只能 free 一次且不得再用；free 链表项前先保存 next；strcat/strcpy 由调用方保证目标足够大（本书原话 "s must be big enough"）。 步骤: 画清指针所有权→释放前保存必要字段→缓冲区长度显式传递并检查→malloc 失败返回 NULL 要处理。 不适用于: 栈上数组/静态缓冲区的非法最大长度假设、开启 ASLR/栈保护后的编译器行为细节；自建分配器/内存池的实现细节（→ 路由入口 allocator-pattern）。 Triggers: malloc/free/内存泄漏/悬挂指针/缓冲区溢出/strcat/链表释放/double free/内存安全
metadata:
  cangjie.generated-by: cangjie-tools v2.5.0
  cangjie.capability-id: cap.cprogramming.memory-safety
  cangjie.capability-revision: 1
  cangjie.bundle-id: bundle.cprogramming
  cangjie.source-title: C 程序设计语言（K&R 第2版）
  cangjie.tags: c, memory, safety
---
# 动态内存与缓冲区安全：malloc/free 纪律

## R — 原文 (Reading)

> "如果释放一个不是通过调用malloc或calloc函数得到的指针所指向的存储空间，将是一个很严重的错误。使用已经释放的存储空间同样是错误的。"（第7章 §7.8.5）
>
> "for(p = head; p != NULL; p = p->next) /* WRONG */ free(p); …正确的处理方法是，在释放项目之前先将一切必要的信息保存起来。"（第7章 §7.8.5）
>
> "strcat: concatenate t to end of s; s must be big enough"（第2章 字符串函数）
>
> — B. W. Kernighan & D. M. Ritchie, 第2章/第7章

---

## I — 方法论骨架 (Interpretation)

动态内存安全有一条铁律和三条纪律：

- **铁律**：谁 malloc，谁负责 free——只释放 `malloc/calloc/realloc` 返回过的指针，不重复释放，释放后不再通过该指针访问（悬挂指针是未定义行为）；
- **释放链表/结构前先保存 next**：`free(p)` 后再取 `p->next` 是在读已释放内存，必须先把 next 保存到临时变量；
- **缓冲区大小由调用方担保**：`strcat/strcpy/getline` 这类不带长度参数的函数，C 约定由调用方确保目标足够大，不然就是溢出（未定义行为）；
- **malloc 返回值要检查**：分配失败返回 NULL，多数场景应检查（本书在哈希表 install 里明确"空间不足返回 NULL"）。

本质思维：**跟踪每一块内存的"归属权 + 生存期"**，并在释放动作与后续访问之间设置明确的先后顺序。

---

## A1 — 书中的应用 (Past Application)

### 案例 1: 书中的释放反例与正解
- **问题**: 读者复制"遍历释放整条链表"，写下 `for(p=head; p!=NULL; p=p->next) free(p);`。
- **方法论的使用**: 作者标注 /* WRONG */，说明 free 后 p 与 p->next 已不可信。
- **结论**: "在释放项目之前先将一切必要的信息保存起来"。
- **结果**: 正确写法先存 next，再 free 当前（第7章 §7.8.5）。

### 案例 2: 哈希表 install 的 malloc 错误处理
- **问题**: 为新符号分配节点时可能空间不足。
- **方法论的使用**: `scanf` 式检查——malloc 返回 NULL 则 install 返回 NULL，调用方据此处理。
- **结论**: 动态分配的失败路径必须在接口契约里显式表达（返回值传失败）。
- **结果**: 符号表 install/lookup 成为"分配+检查"标准模板（第6章 §6.6）。

### 案例 3: 自建 malloc/free
- **问题**: 需要向 OS 申请大块并按首次适应切分管理，且释放顺序任意。
- **方法论的使用**: 自由链表 + 邻块合并 + 对齐头部；free 把块并入并把相邻空闲块合一，避免碎片。
- **结论**: "把存储释放顺序任意化"本身就是释放纪律的工程化实现。
- **结果**: 第8章 §8.7 的 malloc/free 教学实现（分配器细节见 allocator-pattern）。

---

## A2 — 触发场景 (Future Trigger) ★

### 用户会在什么情境下需要这个 skill?

1. 程序频繁崩溃/内存泄漏，怀疑重点在 free 时机与链表释放；
2. 写 C 的增删改查：动态数组/链表/树节点的分配与释放；
3. 用 strcat/strcpy/sprintf 拼接字符串想确保安全不溢出；
4. 嵌入式或服务端代码审查时检查"谁负责释放"；
5. 遇到 double-free、use-after-free、heap corruption 报错需要定位纪律问题。

### 语言信号 (用户的话里出现这些就应激活)

- "这个内存该在哪释放 / 什么时候 free？"
- "遍历释放链表怎么防止崩溃？"
- "strcat 会不会溢出 / 怎么防缓冲区溢出？"
- "malloc 返回值要检查吗？"
- "double free / use after free / heap corruption / memory leak / buffer overflow"

### 与相邻 skill 的区分

- 与 `undefined-behavior` 的区别: 内存违规往往是未定义行为的一种实例，但 memory-safety 专讲分配/释放/缓冲区的资源纪律与所有权，UB 专讲表达式与语言契约。
- 与 `allocator-pattern` 的区别: 那讲如何自己实现分配器（存储实现细节），这里讲如何正确使用 malloc/free（使用纪律）。

---

## E — 可执行步骤 (Execution)

1. **建立内存所有权台账**
   - 完成标准: 对每块 malloc 内存，标出"分配点、持有者、释放点、是否可能被别名/共享"；悬挂/重复释放风险点圈出。
   - 判停条件: 若内存被多个函数共享，先明确唯一释放方（或引用计数），否则提示设计风险。

2. **🔴 CHECKPOINT · 仅所有权归属不唯一时确认**
   - 完成标准: 每块内存有唯一明确的释放方时，直接进入步骤 3，不打断用户。
   - 判停条件: 仅当内存被多处共享、释放方无法一眼确定（函数间传递所有权、回调中释放）时，向用户确认"由谁负责释放"，据此继续。

3. **审查释放序列**
   - 完成标准: 遍历释放前先保存 next（`p = head; while(p){ q = p->next; free(p); p = q; }`）；free 后不再引用该块。
   - 判停条件: 发现 free 后又用的代码，标为 use-after-free 未定义行为并给出修正顺序。

4. **审查缓冲区操作**
   - 完成标准: 每个 `strcat/strcpy/sprintf/getline` 目标都有可验证的容量上限；不能保证时改用带长度的变体或显式检查返回值。
   - 判停条件: 目标缓冲是变长（用户输入/拼接结果），提示需要动态分配或限长 API。

5. **🛑 STOP · 仅溢出修复影响既有接口时确认**
   - 完成标准: 修复仅加长度参数/改用限长 API、不改变既有调用契约时，直接给出修订方案。
   - 判停条件: 仅当修复需改函数签名（如给 strcat 改传大小参数、或把固定缓冲区改为动态分配）会牵连调用方时暂停，明确告知"该修复会改动 N 处调用点"，由用户确认后再落方案。

6. **给出修订方案**
   - 完成标准: 输出重构后的分配/释放/拼接代码与理由；重点标注修正的"顺序"而非仅"加检查"。

---

## B — 边界 (Boundary) ★

### 不要在以下情况使用此 skill

- 用户问的是栈上数组/静态缓冲区的合法上界（那是数组边界问题，与堆无关）；
- 用户问的是 OS 级内存管理/虚拟内存/内存池配置（超出本书，见 allocator-pattern 的边界）；
- C++ new/delete、RAII 语义（本书是 C）。

### 作者在书中警告的失败模式

- free 后继续遍历链表（第7章 §7.8.5 WRONG 示例）；
- 释放非 malloc 所得指针（第7章 §7.8.5"很严重的错误"）；
- strcat/strcpy 假定目标足够大（"s must be big enough"）；
- 释放后使用（第7章§7.8.5"使用已经释放的存储空间同样是错误的"）。

### 作者的盲点 / 时代局限

- 本书时代无 AddressSanitizer/静态分析；现代应结合工具自动检测，不能只靠人工纪律。
- C23 增加了 `_BitInt` 等但内存语义不变；嵌入式环境无 OS 堆时需自建分配器（allocator-pattern）。

### 容易混淆的邻近方法论

- `allocator-pattern`（如何实现分配器 vs 如何使用分配器）；
- `linked-list-pattern`（链表遍历/插入的结构设计常与释放纪律同时出现，但结构问题≠内存问题）。

---

## 相关 skills (阶段 3 填充)

- composes-with: allocator-pattern, linked-list-pattern, undefined-behavior
- contrasts-with: data-organization

---

## 审计信息

- **验证通过**: V1 ✓ / V2 ✓ / V3 ✓
- **蒸馏时间**: 2026-09-10