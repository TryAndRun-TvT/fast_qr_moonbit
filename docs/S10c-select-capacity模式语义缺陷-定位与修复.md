# S10c — `select_capacity` 模式语义缺陷定位与修复（v5）

> **状态**：历史　｜　日期：2026-09-13　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §3　｜　并入：用例已并入 [S10](S10-测试用例设计与完善roadmap.md)，缺陷已修复

> 本文是 [S10 测试 roadmap](./S10-测试用例设计与完善roadmap.md) §T3-d 落地过程中
> **发现的实现 bug**的完整记录：定位、实测证据、修法、与参考的逐参数对照、回归与变异项。
>
> 日期：2026-09-13　｜　基线：`moon test` 135 → **140 用例全绿**　｜
> 参考检出：fast_qr v0.14.0 `53e8c99`（钉版）

---

## 1. 概述

这是「测试基础设施 → 探针 → 发现实现 bug」的完整闭环，也是
[S10 测试 roadmap](./S10-测试用例设计与完善roadmap.md) 立项时最想得到的东西：
**独立证据链不只是验证参考，它能抓到我们自己实现里的大洞。**

本文同时是 **T3-d（`cmd/bench --dump-case`）首跑价值的证据**：该探针在写完当天即暴露
本 bug，且旧实现下 54 组语料中有 **4 组**的输出矩阵**交给第三方解码器直接返回 NULL**。

| 项 | 值 |
|---|---|
| 缺陷位置 | `lib/qr_build.mbt::QRCode::select_capacity`（+ 新增 `lib/internal/constants/capacity.mbt::fits_at_version`） |
| 严重度 | **高**（静默错数据，非报错） |
| 触发条件 | 显式指定 `mode`（Alphanumeric / Byte），且输入长度 > 该模式在当前最小版本下的容量 |
| 发现方式 | T3-d 多内容探针（`cmd/bench --dump-case`）+ jsQR 第三方解码 |
| 修复验证 | 与参考 fast_qr `53e8c99` 在 **83,160 组参数**上零差异 |
| 回归保护 | 4 条黑盒用例 + M22/M23 两条变异项 + 11 条 T3-c 固化向量 |

## 2. 现象与根因

`QRCode::select_capacity(input, mode, ecl, v)` 解析出 `mode_idx` 后**从未把它传给容量判定**：
`@constants.version_for(mode_idx, ecl_idx, len)` 被写成对 `mode_idx` 求值，但旧实现里
`version_for` 的调用点**恒用 Numeric 语义**（mode 序号被算出来却只写进返回值）。后果两条：

| # | 触发条件 | 错误行为 |
|:-:|---|---|
| **A** | `mode=Some(Alnum/Byte)` + `v=None` | 按 **Numeric 预算**求最小版本（如 '1'×41 → 选 V01，而 Byte-L-V01 只装 17 字节） |
| **B** | `mode=Some(...)` + `v=Some(uv)` | 只校验 **Numeric 容量**；`Byte-H-V01 len=18`（V01-H Byte 上限 7）**不报错** |

**这不是「报错偏严/偏松」，而是静默错数据**：选出的版本装不下实际模式编码出的位流，
`structure`/`placement` 按 `data_codewords` 消费数据区时**后半段被丢弃**。

## 3. 实测证据（可复现）

`cmd/bench --dump-case 52`（Byte / ECL H / `version=None` / 40 字节）在**修复前**的矩阵
交给 jsQR 解码：

```
旧实现：jsQR decode -> NULL（矩阵不可解码）
新实现：jsQR decode -> "zzzz…"（40 个 z，与输入一致）
```

T3-d 语料中有 **4 组**属于此形态（下标 50/51/52/53：Alnum-H、Alnum-Q、Byte-H、Byte-Q）。

## 4. 修法

对照参考 fast_qr v0.14.0 `Version::get(mode, ecl, len)` + `QRCode::new` 的两段式判定：

1. `v=None` → `version_for(mode_idx, ecl_idx, len)`（**按声明模式**，与后续编码器一致）；
2. `v=Some(uv)` → 先判全谱系上界（`version_for(...) < 0` → `EncodedData`），
   再用新增的 `@constants.fits_at_version(mode, ecl, uv, len)` 做**位流口径复算**：
   `4(模式头) + cci_bits(uv, mode) + 负载(mode, len) <= data_bits(ecl, uv)`。
   这一步额外覆盖了**指定版本自身的 CCI 档位**（V10→V27 跨档时容量表会失真）。

## 5. 与参考的逐参数对照（本次实跑）

用 Rust harness 在钉版 `53e8c99` 上跑参考实现，与 MoonBit 侧同参数逐一比对：

| 对照面 | 参数组合数 | 差异 |
|---|---:|---:|
| 三模式 × 4 ECL × 40 版本 × len 0..40，`v=None`/`v=Some` 两路 | **19,680** | **0** |
| 同上 × 各版本容量边界 ±1 与 V40 上限邻域 | **64,480** | **0** |

即修复后 `select_capacity` 的错误面与参考**完全一致**（含 `EncodedData` 与
`SpecifiedVersion` 的**优先级**：全谱系装不下时先返回 `EncodedData`）。

## 6. 新增回归与变异项

| 项 | 内容 | 效果 |
|---|---|---|
| `public_select_capacity_explicit_mode_respected` | 同一 '1'×41 在三种模式下给出**三个不同最小版本**（V01/V02/V03） | 锁「模式被尊重」 |
| `public_select_capacity_specified_version_mode_aware` | Byte-H-V01 上限 7（8 越界）、Byte-L-V01 上限 17（18 越界）、Numeric-L-V01 上限 41 | 锁「指定版本按模式判定」 |
| `public_select_capacity_too_big_mode_aware` | Byte-Q-V40 上限 1663、Byte-H-V40 上限 1273 | 锁错误面 |
| `public_builder_explicit_mode_uses_mode_encoder` | `QRBuilder` 链式路径同源；'1'×30 + Byte → V02（非 V01） | 锁端到端 |
| **M22** | `version_for(mode_idx,…)` → `version_for(0,…)`（丢弃模式） | ✅ 7 条失败 |
| **M23** | `fits_at_version(mode_idx,…)` → `fits_at_version(0,…)` | ✅ 1 条失败 |

## 7. 教训

1. **「参数算出来了」≠「参数被用上了」**：`mode_idx` 一直在返回值里，看起来完全正确；
   静态审阅极难发现它没进判定。**只有把行为拿去做端到端对照（含第三方解码）才暴露。**
2. **静默错数据 > 报错**：这条 bug 不会抛异常、不会让既有 135 条测试变红（因为既有用例
   命中的都是 Numeric/自动路径）——它是**错误面缺口**，不是**断言缺口**。
3. **探针（T3-d）比向量（T3-c）更早发现它**：多内容 × 多 ECL 的**组合覆盖**才把
   「显式模式 + 自动版本」这一组合踩出来。向量固化是**事后防回归**，探针是**事前发现**。
