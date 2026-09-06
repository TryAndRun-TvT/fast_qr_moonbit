# S7 · 输出层 to_str 与 SVG · 实现方案评估与优化 · 记录

> 复核已合入的 [S7 详细实现方案](./S7-输出层to_str与SVG-实现方案.md)（PR #36），
> 目标：**独立重读仓库代码与既有文档 + 检出 fast_qr v0.14.0 参考源码（commit `53e8c99`）逐行核对**，
> 找出方案中「与参考源码不一致 / 语义清单缺漏 / 可优化点」，供 S7 实现阶段直接执行前兜底。
> 结论：**方案方向正确、无致命漏洞**；但发现 **4 处值得补进语义清单/落地清单的核对缺口** 与
> 若干优化建议（详见 §2/§3）。
>
> 日期：2026-09-06　｜　复核基线：main（PR #36 已合，S7 方案 270 行为权威前向计划）。
> 参考源码复核介质：本评审临时 `git clone --depth 1 https://github.com/erwanvivien/fast_qr`
> 于 `/tmp/fast_qr`（v0.14.0，`53e8c99`），与方案 §0 所述介质一致，不入库。

---

## 0. 一句话结论

S7 两块交付（终端 `to_str`/`print` + SVG `SvgBuilder`）定位为「输出面补齐」、纯确定性字符串渲染的判定准确；
复用 S4-S6「Rust 一次生成参考全串快照 → 逐字节对齐」链路**比参考 tests/svg.rs 的 contains 更严**的策略正确。
本评审**独立检出参考源码逐行复核**，确认方案 §2.3/§4 的核心语义转述**基本准确**，但可**补 4 处易翻车的精确
核对点**（circle 形状特例、`<svg>` 的 `xmlns`、多 shape → 多 `<path>`、坐标已含 margin 的语义），并给出若干
实现/测试层面的优化建议。方案无需重写，建议把本记录 §2 清单并入实现时的最终核对表。

---

## 1. 复核范围与基线（独立重读 + 参考源码逐行核对）

| 对象 | 复核点 | 复核结论 |
|------|--------|---------|
| `lib/module.mbt` / `lib/qr.mbt` | `Module::value()`（true=DARK）、`QRCode::size/get` 是否满足输出层只读消费 | ✅ 一致（`value()` bit0 明暗、`get(row,col)` 行主序） |
| `lib/helpers.mbt` | 当前确为注释骨架（方案 §2.2 缺口 1 属实） | ✅ 属实 |
| `cmd/main/main.mbt` | 当前仅 `println` 字面量、未调库（方案 §1「补 M1 CLI 输出欠账」属实） | ✅ 属实 |
| README / roadmap | S7 方案链接、§4.2 指引、M2/M3 里程碑定位 | ✅ 已收口 |
| fast_qr `src/helpers.rs` | 四态映射 / 边距构成 / 末行处理 | ✅ 转述准确（见 §2.1） |
| fast_qr `src/qr.rs:174-185` | `to_str` 委托 `helpers`、`print` 走 `println` | ✅ 转述准确 |
| fast_qr `src/convert/{mod,svg}.rs` | Shape 6 path 片段 / `SvgBuilder` 默认值 / `to_str`/`path` 结构 | ⚠️ 大体准确，4 处需补精确核对点（见 §2） |
| fast_qr `src/tests/svg.rs` | 确为 `contains`（非全串） | ✅ 方案比参考更严的判定属实 |

---

## 2. 发现：与参考源码核对后需补进 S7 方案的精确核对点

以下均为**逐行读参考源码**得到、方案 §2.3/§4 语义清单**未显式列出或转述略粗**、且易在手写时翻车、
但**全串快照都能兜底**的点。建议实现前并入最终核对表（补进 §4 核对清单或作为本记录引用）。

### 2.1 终端画：四态映射转述正确，但补充「非白底视觉」观察
- 方案 §4 #1 的 `(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'` **与源码 `print_line` 完全一致**（真=DARK）。
- **补充观察**：参考 `Module::DARK=true`，但该映射把「两行皆暗」打成空格、把「全亮」打成 `█`，**并非直观的
  「黑模块→实块」白底画**；顶边距 `[empty(true);177]` + `[empty(false);177]` 两行合一实际整行输出 `▄`
  （`(真,假)→'▄'`）。因此**勿凭视觉臆测，务必用参考工具生成全串快照锁定**；方案 §7「不靠目测、靠全串快照」
  是对的，此处仅为强化该风险提示。
- 奇数边长（QR 尺寸恒为 `version*4+17`，恒奇数）下 `(0..size-1).step_by(2)` 覆盖除末行外所有行，末行单独与
  `[empty(false);177]`（全亮下行）合并；**偶数尺寸分支在真实 QR 上不可达**，无需特判。

### 2.2 SVG：`<svg>` 起始标签含 `xmlns`，方案 §4 #8 清单未显式列出
- 参考 `svg.rs::to_str` 起始标签是 `<svg viewBox="0 0 {W} {W}" xmlns="http://www.w3.org/2000/svg">`——
  **`viewBox` 之外还有 `xmlns`**。方案 §4 #8 只写了 `viewBox`/`<rect>` 尺寸与色，未列出 `xmlns`；
  且**各元素间无任何空格/换行分隔**，整个 SVG 是一整行（`<svg …><rect …/><path …/></svg>`）。
- 全串快照能兜底，但清单补这两点（xmlns + 单行无分隔）可让手写先一次到位。

### 2.3 SVG：`circle` 形状 path 是全部 6 个中最易抄错的特例
- 参考 `circle(y, x, _) = format!("M{},{y}.5a.5,.5 0 1,1 0,-.1", x + 1)`，即实际输出为
  `M{x+1},{y}.5a.5,.5 0 1,1 0,-.1`——**第一个坐标是 `x+1` 且为整数无小数**、第二个是 `{y}.5`（带 `.5`），
  不是直观的 `M{x},{y}...`。
- 方案 §2.3 对 circle 只写了 `M{},{}…a.5,…`，过于粗。建议实现时以「整串常量格式串 + 占位」照抄，快照仍为最终兜底。

### 2.4 SVG：多 shape → 多个 `<path>`；坐标传给 shape 时**已含 margin**
- 参考 `path()`：commands 为空用 `[square]`（方案 §4 #9 正确）；用户调 `shape(A).shape(B)` 时**每个 command
  各产一个 `<path>`**，最后 `join("")` 串联（`<path d="…"/><path d="…"/>`）。方案把字段设计为
  `shapes:Array[Shape]`，实现须还原「N 个 shape → N 个顺序 `<path>`」。
- 且 shape 被调用为 `command(y + margin, x + margin, cell)`——**传入 shape 的 y/x 已是 row+margin / col+margin**。
  方案 §4 #6「勿 x/y 颠倒」方向对，但需再强调：写进 shape 片段的是**加过 margin 的坐标**，不是原始 row/col
  （快照会精确校验）。
- 每命令取色：无 `shape_color`（S7 已裁）时全部落到 `dot_color`；仅 rounded_square 的 `<path>` 额外加
  `stroke-width=".3" stroke-linejoin="round" stroke="{color}"`（方案 §4 #7 正确）。

---

## 3. 优化 / 待办建议（非阻断）

| # | 建议 | 理由 |
|:-:|------|------|
| 1 | **补 `Shape` ↔ 名字符串的双向映射工具**（`square/circle/.../rounded_square` ↔ 枚举），对齐参考 `From<Shape> for &str` / `From<String> for Shape`。 | S7 现只落 6 固定枚举、无 `Command`；但参考/未来 wasm `qr_svg` 都按字符串名选形状，先补一个轻量映射即可让 CLI/宿主后续无需再造轮子。 |
| 2 | **把 6 形状 path 片段定义为「含占位符的整串常量」集中放一处**（`circle` 等最易抄错的放最醒目位置），集中 + 注释里贴参考原文。 | 降低手抄风险；快照兜底虽稳，集中常量更易 review 对照。 |
| 3 | **快照用例建议加一条「多 shape + rounded_square」**（如 `shape(Square).shape(RoundedSquare)`）以覆盖 §2.4 的「多 `<path>` + rounded 描边特判」。 | 方案 §5.2 的 6 形状各一条是单 shape；多 shape 是参考支持的独立行为，值得单独锁一条。 |
| 4 | **SVG `to_str` 尺寸建议复用 `QRCode::size` 一次取好**、避免循环里反复读；参考 `path` 里 `qr.size` 每次外层 `for y` 现算，MoonBit 逐格遍历可把 `size` 提局部变量。 | 纯微优化，非本阶段（S7 无性能门槛）目标，列作提示。 |
| 5 | 方案 §4 #12 的 `print`/`println` 双后端说明正确；补充一句：**快照只测 `to_str`，`print` 归 CLI/人工冒烟**，与 S6「不把手写视觉当验收」口径一致。 | 已基本覆盖，仅强化。 |

---

## 4. 门禁与收尾（沿用 AGENTS §二.4 / 方案 §5.4）

本记录为**纯文档变更**，未触 MoonBit 代码；不改动 S7 方案已锁定的范围（无 PNG/image、无 wasm 嵌图子集、
无 feature 门、`to_str`/`print` 落 lib 公共层、SVG 常驻）。S7 实现阶段仍按方案 §5.4 门禁执行。

---

## 5. 参考
- [S7-输出层to_str与SVG-实现方案.md](./S7-输出层to_str与SVG-实现方案.md) — 被复核的 S7 详细方案（PR #36）
- 参考源码 fast_qr v0.14.0（`53e8c99`）：`src/helpers.rs`、`src/qr.rs:174-185`、`src/convert/{mod,svg}.rs`、`src/tests/svg.rs`
- [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) §4.2/§4.4 — S7 / 输出面 / M2-M3
