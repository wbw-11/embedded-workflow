---
name: c-algorithms
description: |
  当用户要在 C 语言中实现/迁移经典算法（折半查找、排序、关键词表查找）、想知道表长安全求法（sizeof 编译期）、指针版折半边界规则、或以函数指针注入比较逻辑时调用。 核心: sizeof tab/sizeof tab[0] 编译期求元素个数；指针版 mid=low+(high-low)/2（指针不能相加）；qsort 用函数指针参数解耦比较逻辑。 步骤: 定数据结构→算表长→选查找/排序策略→(需要不同排序标准时)抽比较函数为参数。 不适用于: C++ STL/Rust 泛型容器、需要稳定排序但未显式处理时；递归vs迭代的取舍选型（经路由入口由 recursion 能力处理）；链表/树等数据结构的实现套路与 struct vs union 选型（→ data-organization 或路由 linked-list）；静态关键字表的 struct 组织方式（→ data-organization）。 Triggers: 折半查找/二分/排序/shellsort/qsort/sizeof 算表长/函数指针/回调/算法 C 语言
metadata:
  cangjie.generated-by: cangjie-tools v2.5.0
  cangjie.capability-id: cap.cprogramming.c-algorithms
  cangjie.capability-revision: 1
  cangjie.bundle-id: bundle.cprogramming
  cangjie.source-title: C 程序设计语言（K&R 第2版）
  cangjie.tags: c, algorithm, sorting
---
# 经典算法落地 C：折半/排序/查找惯用法

## R — 原文 (Reading)

> "int binsearch(int x, int v[], int n) { int low, high, mid; low = 0; high = n - 1; while (low <= high) { mid = (low+high)/2; if (x < v[mid]) high = mid - 1; else if (x > v[mid]) low = mid + 1; else return mid; } return -1; }"（第3章 §3.3）
>
> "将排序算法与比较函数分离…qsort 的第四个参数指定" "通过将比较函数作为参数传给 qsort，便可以实现按照不同的标准排序"（第5章 §5.11）
>
> "#define NKEYS (sizeof keytab / sizeof(keytab[0]))"（第6章 §6.3）
>
> — B. W. Kernighan & D. M. Ritchie, 第3/5/6章

---

## I — 方法论骨架 (Interpretation)

算法本身和语言无关，但"在 C 里落地"有几个反复踩的关键点，抽成四条惯例：

- **折半查找三路判定**：`x<v[mid] → high=mid-1`；`x>v[mid] → low=mid+1`；否则命中。用 -1 作哨兵（数组下标从 0 起，负数天然表失败）；
- **指针版高/低/中值得称道**：书中关键字统计把折半改成指针后，`mid = (low+high)/2` 必须写成 `mid = low + (high-low)/2`——因为"指针不能相加，只能相减"；
- **表长用 sizeof 编译期求**：`sizeof tab / sizeof tab[0]` 代替手数元素个数，改类型不改数字，杜绝越界；
- **比较逻辑用函数指针注入**：把 strcmp/numcmp 作为参数传给 qsort，让同一算法支持任意排序标准（字典序/数值序），算法与比较解耦；
- 配套惯用结构：`else-if` 做三路判定、`for` 三段式集中循环控制、递归或迭代选型（见 recursion-modeling）。

---

## A1 — 书中的应用 (Past Application)

### 案例 1: 折半查找 binsearch
- **问题**: 在有序表里查一个数。
- **方法论的使用**: else-if 三路判定 + -1 哨兵，循环用 while(low<=high)。
- **结论**: 三路判定最自然地落在 else-if 上；-1 因下标从 0 起可安全表示失败。
- **结果**: 成为第 3 章控制流示例，后在第 6 章升级为指针版（第3章 §3.3）。

### 案例 2: 指针版折半（关键字表按字母序查找）
- **问题**: 用指针算 mid 时 `(low+high)` 表达式非法——指针不能相加。
- **方法论的使用**: 改用 `mid = low + (high-low)/2`，只做减法和除法。
- **结论**: "指针不能相加，只能相减"是 C 指针算术硬约束（对象间距无定义）。
- **结果**: 指针版 binsearch 与 `sizeof keytab/sizeof keytab[0]` 一起成为静态表查找标准样板（第6章 §6.3）。

### 案例 3: sort 程序 + 参数化比较
- **问题**: 同一排序要支持字典序（strcmp）与数值序（numcmp），且可用 -n 切换。
- **方法论的使用**: qsort 的比较函数作为参数传入；不同标准 = 不同比较函数。
- **结论**: "把比较抽象成回调"让算法与排序策略解耦。
- **结果**: 升级后的 sort 支持 -n（数值）/-r（逆序）/-f（忽略大小写）组合（第5章 §5.6–5.11）。

---

## A2 — 触发场景 (Future Trigger) ★

### 用户会在什么情境下需要这个 skill?

1. 在 C 里实现/迁移数组查找（折半）、排序（Shell/qsort）、静态表查找，想知道惯用写法与边界处理；
2. 想用一个排序函数支持多个比较标准（按名字/按序号/忽略大小写）；
3. 静态关键字/配置表想知道安全求长度与遍历的方法；
4. 面试/作业要求用 C 手写折半或快排，怕边界写错；
5. 阅读开源代码遇到 `sizeof.../sizeof...` 或 `qsort` 比较回调想理解。

### 语言信号 (用户的话里出现这些就应激活)

- "C 里怎么写折半查找 / 二分？"
- "qsort 怎么自定义比较？"
- "数组长度怎么用 sizeof 算？"
- "pointer version binary search mid 为什么不能相加？"
- "binary search in C / qsort callback / sizeof array length / three-way comparison"

### 与相邻 skill 的区分

- 与 `recursion-modeling` 的区别: 那管"递归 vs 迭代选型"（含快排/树遍历），本 skill 管算法实现的 C 细节（表长/指针边界/比较注入）——若用户只问"递归还是迭代"，经路由入口由 recursion 能力处理。
- 与 `data-organization` 的区别: 那管数据如何组织（struct 静态表、链表声明），本 skill 管在这些数据上跑什么算法；静态关键字表的 struct 组织方式归 data-organization。
- 与 `linked-list-pattern`（路由）的区别: 链表/树的遍历插入删除实现套路不经本 skill，走路由入口。

---

## E — 可执行步骤 (Execution)

1. **确定数据结构与表长**
   - 完成标准: 数组/静态表给出类型与长度来源；静态表用 `sizeof tab/sizeof tab[0]`，动态结构记录长度字段。
   - 判停条件: 若用指针且需 mid，先确认 mid 计算用减法形式（指针不能相加）。

2. **🔴 CHECKPOINT · 仅抽象度选择时确认**
   - 完成标准: 目标明确不需要泛化（单个固定类型、固定排序标准）时，直接进入步骤 3，不打断用户。
   - 判停条件: 仅当需要多类型/多排序标准（用户提到"按不同字段/不同类型排序、通用函数"）时，向用户确认是否采用 void* + 比较回调的通用设计（或保持具体类型优先），确认后再继续。

3. **选择算法并落实三路判定 / 循环控制**
   - 完成标准: 折半写出 low/high/mid 三变量与 -1 哨兵；排序选定 Shell 或 qsort 并明确终止条件。
   - 判停条件: 需要多种排序标准时，改用比较函数参数注入（见步骤 4）。

4. **（可选）抽象比较函数**
   - 完成标准: 定义形如 `int (*comp)(void*, void*)`（或具体类型）的比较回调；对数值用 numcmp/差值比较，对字符串用 strcmp。
   - 判停条件: 若既有 -n 又有 -r/-f，把各选项折叠进单个比较函数的返回符号（负=小于、0=等于、正=大于）。

5. **🛑 STOP · 仅性能/精度取舍时确认**
   - 完成标准: 结论是标准算法（折半/Shell/qsort）+ 常规边界处理时，直接给出实现。
   - 判停条件: 仅当用户处在大规模数据 / 要求极致性能 / 在意稳定性时暂停，明确说明所选算法的复杂度与稳定性特征（如 Shell 不稳定、快排最坏 O(n²)、递归栈深），由用户确认是否可接受或改选。

6. **验证边界与可移植性**
   - 完成标准: 空表/单元素表/重复键三种边界跑通；所有下标或指针表达式不越界；比较结果符号语义一致。

---

## B — 边界 (Boundary) ★

### 不要在以下情况使用此 skill

- 用户要的不是"在 C 里实现"而是算法复杂度/正确性理论讨论（可给出但非本 skill 重点）；
- 输入是链表/树等非数组结构（那是 linked-list-pattern/recursion-modeling）；
- 用户要求泛型（void* + 回调）但数据量小且类型固定（用具体类型更简单，勿过度设计）。

### 作者在书中警告的失败模式

- "指针不能相加，只能相减"——写 `(low+high)/2` 的指针版会编译失败/错误（第6章 §6.3）；
- 手数表长而新增/删除元素后忘改——用 `sizeof tab/sizeof tab[0]` 编译期自维护（第6章 §6.3）；
- 固定大小数组截断输入（第1章 getline 的 lim 参数毒性）——超长输入静默截断，应与缓冲区上界配合（见 memory-safety）。

### 作者的盲点 / 时代局限

- 书中的 qsort 是简化教学版；现代可用标准库 qsort/bsearch（本书也提供）或 C23 泛型 `_Generic`。
- 未讨论稳定排序（Shell 不稳定）、大数据量下递归栈深度（快排最坏 O(n) 栈）——现代应结合复杂度与栈预算再选型。

### 容易混淆的邻近方法论

- bsearch/qsort 与本书手写版的等价性——本 skill 章示例偏实现教学，标准库用法参照包内能力卡；
- `data-organization` 的静态表（struct 数组）与本 skill 的查找落地——二者常配合（先组织再查找）。

---

## 相关 skills (阶段 3 填充)

- composes-with: data-organization, call-by-value-pointer, argc-argv-callback
- contrasts-with: recursion-modeling

---

## 审计信息

- **验证通过**: V1 ✓ / V2 ✓ / V3 ✓
- **蒸馏时间**: 2026-09-10