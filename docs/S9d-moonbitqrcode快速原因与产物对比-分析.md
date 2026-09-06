# S9d · moonbitqrcode 为何这么快 · 源码归因 + 各库产物记录与对比

> 承接 [S9d-与moonbit生态QR包性能对比-详细分析.md](./S9d-与moonbit生态QR包性能对比-详细分析.md)
> （全库性能总表）与 [S9d-与moonbit生态QR包性能对比-实现记录.md](./S9d-与moonbit生态QR包性能对比-实现记录.md)。
> 本文回答两件事：**① moonbitqrcode 0.1.0 为什么「最快」（0.046ms/次，每模块 0.074µs）**——逐行读源码
> 归因；**② 记录四库对同一输入的真实产物并交叉对比**（尺寸、结构行、能否被第三方解码器 moonqr decode
> 读回）——确认「快」不等于「可用」，并给出各库产物质量结论。
> 日期：2026-09-06　｜　范围：纯源码研读 + 跑测 + 文档；本仓库 lib 未改；门禁 109 全绿。

---

## 0. 一句话结论

- **moonbitqrcode 快的原因（源码级）**：它在 lib 公开层**固定 mask0、不跑 8 轮择优/评分**，且
  只做**自动最小版本**（20B@Q → V2，25×25=625 格）——择优是其他库（本仓库/moonqr）自动路径的
  **主要成本**（S9b：V40H 择优 ≈86% 单次 auto），跳过它自然一个量级地快；其余管线（RS、放置、
  Format）并不比别家少。**它测的是「不择优的小码」成本，不是同语义完整码成本。**
- **产物对比（用 moonqr 解码器交叉读回）**：
  | 库 | 产物尺寸 | 结构 | moonqr 解码读回 |
  |----|---------|------|:---:|
  | 本仓库 V03H | 29×29 | 标准（Format/版本/mask 择优齐全） | ✅（见 S9c 层② sha256 = fast_qr 参考） |
  | moonqr auto-H | 29×29 | 标准 | ✅ 读回输入（v=3） |
  | moonbitqrcode auto-Q | 25×25 | 标准（固定 mask0 但可解码） | ✅ 读回输入（v=2） |
  | qrc auto-H | 25×25 | ⚠️ **V2 < 最小 V3，疑似容量单位 bug** | ❌ 解码失败 |
  | qrc forced V3H | 29×29 | ⚠️ 缺 Format/mask（README 自述、代码核实） | ❌ 解码失败 |
- 结论：moonbitqrcode 的「快」来自**少做了择优 + 小版本**，且其产物**可解码**（质量 OK，只是不择优）；
  qrc 的「居中快」则建立在**产出不可解码码**上——生态内目前**可对齐同口径对比的只有 moonqr**。

---

## 1. moonbitqrcode 为什么快（源码逐层归因）

> 源码：`PaiGack/moonbitqrcode@0.1.0`（rsc.io/qr 移植）。
> `src/lib/qr.mbt` → `encode` → `src/coding/plan.mbt`（Plan::new/vplan/fplan/lplan/mplan + encode）。

### 1.1 lib 层：固定 mask0、无择优（决定性原因）

```moonbit
// src/lib/qr.mbt:97
let p = @coding.Plan::new(v, cl, @coding.Mask::of_int(0))  // ← 固定 mask 0
let code = p.encode([enc])
```

- `Mask::of_int(0)` = **固定 mask 0**：`Plan::encode` 后只做一次 `mplan(p, mask0)` 应用，
  **没有** `for mask in 0..8 { apply+score }` 的择优循环。
- 对比：
  - 本仓库/moonqr 自动路径：8 轮 `apply_mask+score` 选最低分（S9b 成本模型：V40H 择优 ≈6.86ms /
    单次 auto 7.99ms ≈ **86%**）。
  - moonbitqrcode：0 轮择优 → 直接省掉约一个量级的「评分主循环」。
- **量级旁证**：本仓库 S9b 固定 mask 路径 V40H ≈1.13ms vs auto ≈7.99ms —— 即「有没有择优」本身就是
  ~7× 差距来源；moonbitqrcode 与同尺寸择优库的差距同理。

### 1.2 版本策略：只做自动最小版本（小矩阵 → 更少格）

- `encode` 只在**最小适配版本**停（`src/lib/qr.mbt:86-92`）：20B@Q → V2（25×25=625 格）。
- 本仓库/moonqr 做 H 档 → V3（29×29=841 格）。同样输入、仅因 ECL/尺寸差异，moonbitqrcode 的工作格数
  就少 ~26%；但这不是它快的主因，**主因仍是 1.1 的免择优**。

### 1.3 其余管线并非更省（避免误读）

- RS 纠错、位流打包、放置（zigzag）、Format/版本信息、`add_check_bytes` 一应俱全（`plan.mbt`
  `vplan/fplan/lplan/mplan/encode/add_check_bytes`）——**不是「残缺所以快」**。
- 数据面也是逐模块判定 + 位运算，与别家同量级；故把速度全归给「免择优」是准确的。

### 1.4 总结（一句话）

> moonbitqrcode 快 = **固定 mask0（跳过 8 轮择优）+ 自动最小版本（小矩阵）**；产物仍可解码
> （§2），只是 mask 非最优、ECL 仅到 Q、无法强制版本——它是「最小可行编码器」，不是「同口径快手」。

---

## 2. 各库产物记录与对比（同输入 `https://example.com/`）

### 2.1 方法：产物 → RGBA → moonqr decode 交叉读回

- 各库产物矩阵栅格化（1 module=4px、margin 16px、黑 30/白 220）→ RGBA Bytes →
  交给 **moonqr 的 `decode`**（与生产方无关的第三方解码器）尝试读回文本与版本。
- 本仓库产物已由 S9c 层② 与 **fast_qr-wasm32 逐位 sha256 一致**（那是生产级 Rust 库）作等效性确认，
  此处不再重复喂解码器。

### 2.2 产物记录表

| 库/路径 | ECL | 版本/SIZE | 结构要点（实码核对） | moonqr 解码 |
|--------|-----|----------|---------------------|:---:|
| 本仓库 V03H | H | V3 / 29 | Format/版本/mask 择优齐全（与 fast_qr-wasm32 sha256 一致） | ✅（层②已证） |
| moonqr auto-H | H | V3 / 29 | 完整（self decode v=3） | ✅ 读回输入 |
| moonbitqrcode auto-Q | Q | V2 / 25 | 完整但固定 mask0（self decode v=2） | ✅ 读回输入 |
| qrc auto-H | H | **V2 / 25** | ⚠️ V2 < 最小 V3（疑似容量单位 bug） | ❌ FAIL |
| qrc forced V3H | H | V3 / 29 | ⚠️ 缺 Format/mask（README 自述 + 代码核实） | ❌ FAIL |

### 2.3 结构行抽样（佐证「完整 vs 不完整」）

- 功能图案行（第 6 行 = timing）：本仓库与 moonqr 均为标准 `1111111010101010…`；qrc 强制 V3 同位置
  内容明显偏离标准布局。
- Format 行（第 8 行）：本仓库与 moonqr 均含真实 Format（位置掩码异或后图案）；qrc 强制路径该区域
  为占位/空（无真实 Format 写入）——与其「No format information」自述一致。
- 结论：**qrc 两类产物都无法被 moonqr 解码** → 目前 qrc 0.1.1 不产出「可用的完整 QR」；其性能数字
  只代表内部管线成本，不能当生成可用码的性能。

### 2.4 质量/「快」的解释边界

| 库 | 快但少做了什么？ | 产物可用？ |
|----|----------------|:---:|
| moonbitqrcode | 固定 mask0（不择优）+ 只到 Q + 只自动版本 | ✅ 可解码（mask 非最优） |
| qrc | 自动版本疑似容量 bug / 强制路径缺 Format+mask | ❌ 当前不可解码 |
| moonqr | （对照）完整择优 + 可强制版本 | ✅ |
| 本仓库 | （对照）完整择优 + 可强制版本 + 与 fast_qr 参考逐位一致 | ✅ |

---

## 3. 结论

1. **moonbitqrcode 快 ≠ 算法更优**：快在「固定 mask0 免 8 轮择优 + 自动最小版本」，产物可解码但
   mask 非最优、能力面窄（仅 L/M/Q、无强制版本）。要与择优库比，须走其 `src/coding` 的择优通路
   （非 lib 稳定面）。
2. **生态质量现状**：四库中「完整择优 + 可强制版本 + 产物可解码」目前只有本仓库与 moonqr；qrc 0.1.1
   产物不可解码（容量单位 bug + 缺 Format/mask），moonbitqrcode 仅最小可用。→ 本仓库的完整性与性能
   是生态里有区分度的部分。
3. **后续**：若想给 moonbitqrcode 一个「公平的择优版」数字，可 fork/走 coding.Plan 择优后重测
   （参考 S9b 固定 vs auto 的 ~7× 差异作量级预期）；属可选，非本仓库义务。

---

## 4. 门禁与参考

- 纯源码研读 + 跑测 + 文档，本仓库 lib 未改；`moon fmt --check` / `moon check --deny-warn` /
  `moon test`（109 全绿）与双后端 release 构建不受影响。
- 前置：S9d [详细分析](./S9d-与moonbit生态QR包性能对比-详细分析.md) / [方案](./S9d-与moonbit生态QR包性能对比-方案.md)；
  层② sha256 基准 [S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)；
  择优成本模型 [S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)
- 生态包源码（mooncakes 检出）：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、
  `PaiGack/moonbitqrcode/src/coding/plan.mbt`；`bobzhang/qrc/qrc.mbt`；`naoto24kawa/moonqr`（decode 作
  交叉读回工具）
