# S9d-b — 生态包专项分析（moonbitqrcode / qrc 产物质量）

> **状态**：历史　｜　日期：2026-09-06　｜　索引：[docs/README.md](../README.md) §7　｜　并入：
> 生态对比现行口径见 [S9u](S9u-生态对比复测-moonqr-moonCLI直调.md)；本文两篇专项目的结论已
> 摘入 [moonbit-重写-roadmap-详细分析](../03-过程/moonbit-重写-roadmap-详细分析.md) §S9 生态专项

> **本文是 [S9d](S9d-与moonbit生态QR包性能对比.md) 的「专题分析」承接篇**（拆篇缘由见 S9d 文末）：
> S9d 承载生态对比的**方案/记录/详细分析**；本文承载两个**独立专题**——
> ① moonbitqrcode 为何「最快」（源码级归因 + 四库产物交叉读回）；
> ② 固定 mask0 到底缺了什么、主流为何一律做 8 掩码评分择优。
> **正文一字未改**（仅摘除拆篇说明）。

---

## 专题分析：moonbitqrcode 快速原因与产物对比

> 承接 [S9d 详细分析](S9d-与moonbit生态QR包性能对比.md#详细分析)（全库性能总表）与 [S9d 实现记录](S9d-与moonbit生态QR包性能对比.md#实现记录)。
> 本文回答两件事：**① moonbitqrcode 0.1.0 为什么「最快」（0.046ms/次，每模块 0.074µs）**——逐行读源码
> 归因；**② 记录四库对同一输入的真实产物并交叉对比**（尺寸、结构行、能否被第三方解码器 moonqr decode
> 读回）——确认「快」不等于「可用」，并给出各库产物质量结论。
> 日期：2026-09-06　｜　范围：纯源码研读 + 跑测 + 文档；本仓库 lib 未改；门禁 109 全绿。

---

### 0. 一句话结论

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

### 1. moonbitqrcode 为什么快（源码逐层归因）

> 源码：`PaiGack/moonbitqrcode@0.1.0`（rsc.io/qr 移植）。
> `src/lib/qr.mbt` → `encode` → `src/coding/plan.mbt`（Plan::new/vplan/fplan/lplan/mplan + encode）。

#### 1.1 lib 层：固定 mask0、无择优（决定性原因）

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

#### 1.2 版本策略：只做自动最小版本（小矩阵 → 更少格）

- `encode` 只在**最小适配版本**停（`src/lib/qr.mbt:86-92`）：20B@Q → V2（25×25=625 格）。
- 本仓库/moonqr 做 H 档 → V3（29×29=841 格）。同样输入、仅因 ECL/尺寸差异，moonbitqrcode 的工作格数
  就少 ~26%；但这不是它快的主因，**主因仍是 1.1 的免择优**。

#### 1.3 其余管线并非更省（避免误读）

- RS 纠错、位流打包、放置（zigzag）、Format/版本信息、`add_check_bytes` 一应俱全（`plan.mbt`
  `vplan/fplan/lplan/mplan/encode/add_check_bytes`）——**不是「残缺所以快」**。
- 数据面也是逐模块判定 + 位运算，与别家同量级；故把速度全归给「免择优」是准确的。

#### 1.4 总结（一句话）

> moonbitqrcode 快 = **固定 mask0（跳过 8 轮择优）+ 自动最小版本（小矩阵）**；产物仍可解码
> （§2），只是 mask 非最优、ECL 仅到 Q、无法强制版本——它是「最小可行编码器」，不是「同口径快手」。

---

### 2. 各库产物记录与对比（同输入 `https://example.com/`）

#### 2.1 方法：产物 → RGBA → moonqr decode 交叉读回

- 各库产物矩阵栅格化（1 module=4px、margin 16px、黑 30/白 220）→ RGBA Bytes →
  交给 **moonqr 的 `decode`**（与生产方无关的第三方解码器）尝试读回文本与版本。
- 本仓库产物已由 S9c 层② 与 **fast_qr-wasm32 逐位 sha256 一致**（那是生产级 Rust 库）作等效性确认，
  此处不再重复喂解码器。

#### 2.2 产物记录表

| 库/路径 | ECL | 版本/SIZE | 结构要点（实码核对） | moonqr 解码 |
|--------|-----|----------|---------------------|:---:|
| 本仓库 V03H | H | V3 / 29 | Format/版本/mask 择优齐全（与 fast_qr-wasm32 sha256 一致） | ✅（层②已证） |
| moonqr auto-H | H | V3 / 29 | 完整（self decode v=3） | ✅ 读回输入 |
| moonbitqrcode auto-Q | Q | V2 / 25 | 完整但固定 mask0（self decode v=2） | ✅ 读回输入 |
| qrc auto-H | H | **V2 / 25** | ⚠️ V2 < 最小 V3（疑似容量单位 bug） | ❌ FAIL |
| qrc forced V3H | H | V3 / 29 | ⚠️ 缺 Format/mask（README 自述 + 代码核实） | ❌ FAIL |

#### 2.3 结构行抽样（佐证「完整 vs 不完整」）

- 功能图案行（第 6 行 = timing）：本仓库与 moonqr 均为标准 `1111111010101010…`；qrc 强制 V3 同位置
  内容明显偏离标准布局。
- Format 行（第 8 行）：本仓库与 moonqr 均含真实 Format（位置掩码异或后图案）；qrc 强制路径该区域
  为占位/空（无真实 Format 写入）——与其「No format information」自述一致。
- 结论：**qrc 两类产物都无法被 moonqr 解码** → 目前 qrc 0.1.1 不产出「可用的完整 QR」；其性能数字
  只代表内部管线成本，不能当生成可用码的性能。

#### 2.4 质量/「快」的解释边界

| 库 | 快但少做了什么？ | 产物可用？ |
|----|----------------|:---:|
| moonbitqrcode | 固定 mask0（不择优）+ 只到 Q + 只自动版本 | ✅ 可解码（mask 非最优） |
| qrc | 自动版本疑似容量 bug / 强制路径缺 Format+mask | ❌ 当前不可解码 |
| moonqr | （对照）完整择优 + 可强制版本 | ✅ |
| 本仓库 | （对照）完整择优 + 可强制版本 + 与 fast_qr 参考逐位一致 | ✅ |

---

### 3. 结论

1. **moonbitqrcode 快 ≠ 算法更优**：快在「固定 mask0 免 8 轮择优 + 自动最小版本」，产物可解码但
   mask 非最优、能力面窄（仅 L/M/Q、无强制版本）。要与择优库比，须走其 `src/coding` 的择优通路
   （非 lib 稳定面）。
2. **生态质量现状**：四库中「完整择优 + 可强制版本 + 产物可解码」目前只有本仓库与 moonqr；qrc 0.1.1
   产物不可解码（容量单位 bug + 缺 Format/mask），moonbitqrcode 仅最小可用。→ 本仓库的完整性与性能
   是生态里有区分度的部分。
3. **后续**：若想给 moonbitqrcode 一个「公平的择优版」数字，可 fork/走 coding.Plan 择优后重测
   （参考 S9b 固定 vs auto 的 ~7× 差异作量级预期）；属可选，非本仓库义务。

---

### 4. 门禁与参考

- 纯源码研读 + 跑测 + 文档，本仓库 lib 未改；`moon fmt --check` / `moon check --deny-warn` /
  `moon test`（109 全绿）与双后端 release 构建不受影响。
- 前置：[S9d 详细分析](S9d-与moonbit生态QR包性能对比.md#详细分析) / [S9d 实现方案](S9d-与moonbit生态QR包性能对比.md#实现方案)；
  层② sha256 基准 [S9c-性能测试与fast_qr-wasm对比.md](S9c-性能测试与fast_qr-wasm对比.md)；
  择优成本模型 [S9b-性能优化.md](S9b-性能优化.md)
- 生态包源码（mooncakes 检出）：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、
  `PaiGack/moonbitqrcode/src/coding/plan.mbt`；`bobzhang/qrc/qrc.mbt`；`naoto24kawa/moonqr`（decode 作
  交叉读回工具）

---

## 专题分析：moonbitqrcode 固定 mask0 缺陷与主流对比

> 承接 [上文「moonbitqrcode 快速原因与产物对比」](#专题分析moonbitqrcode-快速原因与产物对比)
> （moonbitqrcode 0.1.0 快的原因：lib 固定 `Mask::of_int(0)` 免 8 轮择优 + 自动最小版本）。
> 本文补两个问题：**① 固定 mask0 到底「缺」了什么（缺陷）；② 为什么主流 QR 编码方案不做固定 mask，
> 而做 8 掩码评分择优**。方法 = 源码级核实（moonbitqrcode ↔ 其参考 rsc.io/qr）+ ISO/IEC 18004 语义 +
> 主流库做法对照。
> 日期：2026-09-06　｜　范围：纯分析 + 文档，本仓库 lib 未改。

---

### 0. 一句话结论

- **固定 mask0 不是「编码错误」**：QR 规范允许任意掩码（格式信息区会写明用了哪个），moonbitqrcode
  产物**可解码**（上篇已用 moonqr decode 读回 ✅）。它是**质量/鲁棒性取舍缺失**。
- **它缺的是「掩码评价」**：ISO/IEC 18004 定义 4 条惩罚规则（N1 同色连、N2 2×2、N3 类 Finder 图案、
  N4 明暗比例），编码器应**跑 8 个候选掩码 → 挑惩罚分最低者**，让矩阵更难被低质量扫描误读。
  固定 mask0 等于**跳过这个决策**，可能得到「恰好难读」的码。
- **为什么主流不做固定 mask**：因为 QR 的主要风险在**解码端**（污损/低对比/镜头畸变/小尺寸），
  掩码择优是编码端**几乎免费**就能给出的鲁棒性余量；从 ISO、zxing、qrcodegen 到 fast_qr/moonqr 的
  默认路径全做择优。rsc.io/qr（moonbitqrcode 参考）是少数以「最小实现」为目标的库，源码里自己都留了
  `// TODO: Pick appropriate mask.`——**固定 mask0 是继承自参考库的「未完成项」，不是有意设计。**

---

### 1. 缺陷是什么（源码核实 + 规范语义）

#### 1.1 moonbitqrcode 实际做了什么

```moonbit
// src/lib/qr.mbt:97 —— lib 层写死 mask0
let p = @coding.Plan::new(v, cl, @coding.Mask::of_int(0))
```

- `Plan::encode` 只应用一次 mask0（`mplan`）；**全库无 penalty/score/choose_best 任何函数**
  （已 grep 核实 `src/coding/*`、`src/lib/qr.mbt` 无评分逻辑）。
- 底层其实**支持 8 种掩码**（`Mask::M0..M7`，`pixel.mbt`），`Plan::new` 也可收任意 mask——
  但没有「择优」环节把它用起来。即：**有能力、缺策略**。

#### 1.2 参考库 rsc.io/qr 也一样（忠实移植，非移植丢功能）

`github.com/rsc/qr`（Go）`qr.go`：

```go
p, err := coding.NewPlan(v, l, 0)   // mask = 0 固定
...
// TODO: Pick appropriate mask.      // ← 作者自留 TODO
```

- rsc.io/qr 自称 **"Basic QR encoder"**（README），且其测试里比对的是 **C libqrencode** 的封装——
  libqrencode（业界常用 C 库）**是有掩码择优的**；rsc.io/qr 自己却始终 mask0。
- **结论**：moonbitqrcode 固定 mask0 = **忠实移植 rsc.io/qr 的未完成择优 TODO**，属「继承缺陷」，
  不是移植时丢功能。

#### 1.3 固定 mask0 可能造成的坏结果（风险，非必然）

QR 掩码的目的是打散数据区图案，避免解码器误判。固定 mask0 意味着：对某些数据/版本，最终矩阵
**恰好保留** ISO N3 想惩罚的「类 Finder 长图案」、过长同色游程、或极端明暗比例——从而：

- 扫描容差下降：低对比/运动模糊/镜头畸变/小尺寸打印时，本可解码的码更容易失败；
- 与解码器（尤其手机相机、工业扫描）的「最坏情况」预期不符；
- 同一内容在不同库下鲁棒性不一致（moonbitqrcode 会比做择优的库更容易踩到难读样本）。

> 注意：这**不是「一定坏」**——干净、高对比、无畸变场景下 mask0 也能扫；因此上篇用 moonqr decode
> 读回成功，两者不矛盾。缺陷是**没有兜底最坏情况**。

---

### 2. 主流为什么做 8 掩码评分择优

#### 2.1 规范层面（ISO/IEC 18004）

- 标准并不强制「必须挑最低分」——但它定义 N1–N4 惩罚规则 + 要求写 Format 掩码号，意图就是**引导
  编码器去选一个对解码更友好的掩码**。不做择优 = 放弃规范提供的质量工具。
- 格式信息区（Format Info）本身包含 3-bit 掩码号 → 解码器能识别任意掩码；所以固定 mask0 能解，
  **但规范给的「择优推荐」被跳过**。

#### 2.2 主流库做法（对照）

| 库 | 掩码策略 | 说明 |
|----|---------|------|
| fast_qr（本仓库对照的 Rust 参考，v0.14.0） | 8 轮 clone+mask+score 择优 | `placement.rs` 默认 `mask=None` 即择优 |
| 本仓库 fast_qr_moonbit | 8 轮择优（S5） | 与 fast_qr 参考逐位一致 |
| moonqr（naoto24kawa） | 自动择优（choose_mask） | encode 默认择优 |
| zxing / qrcodegen / 多数开源 | 8 掩码打分取最优 | 业界默认 |
| libqrencode（C） | 有择优（rsc.io/qr 用它做测试参考） | 业界常用 |
| **moonbitqrcode / rsc.io/qr** | **固定 mask0（TODO 未完成）** | 少数「最小实现」特例 |

#### 2.3 为什么不「固定一个」就够（经济性视角）

- 择优的成本是**常数级**：8 轮 × 评分，对任何数据都是一次性、与版本面积成正比，但**换来的是所有
  数据上的最坏情况鲁棒性**。
- 固定 mask 的问题在于：**你不知道哪份数据会踩雷**——QR 内容千变万化，一个固定掩码不可能对所有
  内容都恰好友好；择优是把「运气」变成「保证」的机制。
- 因此主流把择优做成**默认**（而非可选优化），用户无需懂掩码也能拿到尽量可读的码。

---

### 3. 对本仓库/生态的含义

1. **不要因 moonbitqrcode 快就模仿固定 mask0**：它快在「少做择优」，代价是放弃最坏情况鲁棒性。
   本仓库/moonqr 的择优成本已在 S9b 成本模型中量化（V40H ≈86% 单次 auto 在择优）——但这是**质量的
   必要成本**，是「生成尽量可读码」的默认行为。
2. **若想给 moonbitqrcode 补择优**：其底层 `Mask::M0..M7` + `Plan::new(v,l,mask)` 已支持任意掩码，
   缺的只是一段「8 轮评分取最低」的封装（可参考 S9b N1–N4 评分或移植自 libqrencode/zxing 评分）；
   属生态贡献方向，非本仓库义务。
3. **对比口径提醒**：任何「moonbitqrcode 比择优库快」的结论，必须注明它**没做择优**；同口径公平对比
   应给它加择优后再比（详见快速原因分析 §1）。

---

### 4. 结论

- 固定 mask0 缺陷 = **放弃掩码择优带来的最坏情况解码鲁棒性**，不是「编不出合法码」。
- 主流不采用固定 mask = 择优是「小成本大保险」的默认质量机制，ISO 与业界一致推荐；
  固定 mask0 是 rsc.io/qr 这类「最小实现」的自留 TODO，moonbitqrcode 忠实继承之。
- 本仓库沿用择优是正确的；生态内可用对照仍以 moonqr 为准。

---

### 5. 参考

- 快速原因/产物对比：[本文上节](#专题分析moonbitqrcode-快速原因与产物对比)
- 全库性能与可比性：[S9d 详细分析](S9d-与moonbit生态QR包性能对比.md#详细分析)
- 本仓库择优实现/成本：[S9-性能基准.md](S9-性能基准.md)（mask 自动择优）、
  [S9b-性能优化.md](S9b-性能优化.md)（择优占 V40H ≈86%）
- 源码核实：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、`src/coding/plan.mbt`、`src/coding/pixel.mbt`
  （无 penalty/score 函数；lib 固定 mask0）；`github.com/rsc/qr` `qr.go`（`NewPlan(v,l,0)` +
  `// TODO: Pick appropriate mask.`、README "Basic QR encoder"、libqrencode 测试对照）
- ISO/IEC 18004（掩码与 N1–N4 惩罚规则语义，作为规范背景）

---
