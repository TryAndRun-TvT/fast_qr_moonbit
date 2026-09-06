# S9d · moonbitqrcode 固定 mask0：缺陷分析 + 为何主流方案不这么做

> 承接 [S9d-moonbitqrcode快速原因与产物对比-分析.md](./S9d-moonbitqrcode快速原因与产物对比-分析.md)
> （moonbitqrcode 0.1.0 快的原因：lib 固定 `Mask::of_int(0)` 免 8 轮择优 + 自动最小版本）。
> 本文补两个问题：**① 固定 mask0 到底「缺」了什么（缺陷）；② 为什么主流 QR 编码方案不做固定 mask，
> 而做 8 掩码评分择优**。方法 = 源码级核实（moonbitqrcode ↔ 其参考 rsc.io/qr）+ ISO/IEC 18004 语义 +
> 主流库做法对照。
> 日期：2026-09-06　｜　范围：纯分析 + 文档，本仓库 lib 未改。

---

## 0. 一句话结论

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

## 1. 缺陷是什么（源码核实 + 规范语义）

### 1.1 moonbitqrcode 实际做了什么

```moonbit
// src/lib/qr.mbt:97 —— lib 层写死 mask0
let p = @coding.Plan::new(v, cl, @coding.Mask::of_int(0))
```

- `Plan::encode` 只应用一次 mask0（`mplan`）；**全库无 penalty/score/choose_best 任何函数**
  （已 grep 核实 `src/coding/*`、`src/lib/qr.mbt` 无评分逻辑）。
- 底层其实**支持 8 种掩码**（`Mask::M0..M7`，`pixel.mbt`），`Plan::new` 也可收任意 mask——
  但没有「择优」环节把它用起来。即：**有能力、缺策略**。

### 1.2 参考库 rsc.io/qr 也一样（忠实移植，非移植丢功能）

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

### 1.3 固定 mask0 可能造成的坏结果（风险，非必然）

QR 掩码的目的是打散数据区图案，避免解码器误判。固定 mask0 意味着：对某些数据/版本，最终矩阵
**恰好保留** ISO N3 想惩罚的「类 Finder 长图案」、过长同色游程、或极端明暗比例——从而：

- 扫描容差下降：低对比/运动模糊/镜头畸变/小尺寸打印时，本可解码的码更容易失败；
- 与解码器（尤其手机相机、工业扫描）的「最坏情况」预期不符；
- 同一内容在不同库下鲁棒性不一致（moonbitqrcode 会比做择优的库更容易踩到难读样本）。

> 注意：这**不是「一定坏」**——干净、高对比、无畸变场景下 mask0 也能扫；因此上篇用 moonqr decode
> 读回成功，两者不矛盾。缺陷是**没有兜底最坏情况**。

---

## 2. 主流为什么做 8 掩码评分择优

### 2.1 规范层面（ISO/IEC 18004）

- 标准并不强制「必须挑最低分」——但它定义 N1–N4 惩罚规则 + 要求写 Format 掩码号，意图就是**引导
  编码器去选一个对解码更友好的掩码**。不做择优 = 放弃规范提供的质量工具。
- 格式信息区（Format Info）本身包含 3-bit 掩码号 → 解码器能识别任意掩码；所以固定 mask0 能解，
  **但规范给的「择优推荐」被跳过**。

### 2.2 主流库做法（对照）

| 库 | 掩码策略 | 说明 |
|----|---------|------|
| fast_qr（本仓库对照的 Rust 参考，v0.14.0） | 8 轮 clone+mask+score 择优 | `placement.rs` 默认 `mask=None` 即择优 |
| 本仓库 fast_qr_moonbit | 8 轮择优（S5） | 与 fast_qr 参考逐位一致 |
| moonqr（naoto24kawa） | 自动择优（choose_mask） | encode 默认择优 |
| zxing / qrcodegen / 多数开源 | 8 掩码打分取最优 | 业界默认 |
| libqrencode（C） | 有择优（rsc.io/qr 用它做测试参考） | 业界常用 |
| **moonbitqrcode / rsc.io/qr** | **固定 mask0（TODO 未完成）** | 少数「最小实现」特例 |

### 2.3 为什么不「固定一个」就够（经济性视角）

- 择优的成本是**常数级**：8 轮 × 评分，对任何数据都是一次性、与版本面积成正比，但**换来的是所有
  数据上的最坏情况鲁棒性**。
- 固定 mask 的问题在于：**你不知道哪份数据会踩雷**——QR 内容千变万化，一个固定掩码不可能对所有
  内容都恰好友好；择优是把「运气」变成「保证」的机制。
- 因此主流把择优做成**默认**（而非可选优化），用户无需懂掩码也能拿到尽量可读的码。

---

## 3. 对本仓库/生态的含义

1. **不要因 moonbitqrcode 快就模仿固定 mask0**：它快在「少做择优」，代价是放弃最坏情况鲁棒性。
   本仓库/moonqr 的择优成本已在 S9b 成本模型中量化（V40H ≈86% 单次 auto 在择优）——但这是**质量的
   必要成本**，是「生成尽量可读码」的默认行为。
2. **若想给 moonbitqrcode 补择优**：其底层 `Mask::M0..M7` + `Plan::new(v,l,mask)` 已支持任意掩码，
   缺的只是一段「8 轮评分取最低」的封装（可参考 S9b N1–N4 评分或移植自 libqrencode/zxing 评分）；
   属生态贡献方向，非本仓库义务。
3. **对比口径提醒**：任何「moonbitqrcode 比择优库快」的结论，必须注明它**没做择优**；同口径公平对比
   应给它加择优后再比（详见快速原因分析 §1）。

---

## 4. 结论

- 固定 mask0 缺陷 = **放弃掩码择优带来的最坏情况解码鲁棒性**，不是「编不出合法码」。
- 主流不采用固定 mask = 择优是「小成本大保险」的默认质量机制，ISO 与业界一致推荐；
  固定 mask0 是 rsc.io/qr 这类「最小实现」的自留 TODO，moonbitqrcode 忠实继承之。
- 本仓库沿用择优是正确的；生态内可用对照仍以 moonqr 为准。

---

## 5. 参考

- 快速原因/产物对比：[S9d-moonbitqrcode快速原因与产物对比-分析.md](./S9d-moonbitqrcode快速原因与产物对比-分析.md)
- 全库性能与可比性：[S9d-与moonbit生态QR包性能对比-详细分析.md](./S9d-与moonbit生态QR包性能对比-详细分析.md)
- 本仓库择优实现/成本：[S9-性能基准-实现记录.md](./S9-性能基准-实现记录.md)（mask 自动择优）、
  [S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)（择优占 V40H ≈86%）
- 源码核实：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、`src/coding/plan.mbt`、`src/coding/pixel.mbt`
  （无 penalty/score 函数；lib 固定 mask0）；`github.com/rsc/qr` `qr.go`（`NewPlan(v,l,0)` +
  `// TODO: Pick appropriate mask.`、README "Basic QR encoder"、libqrencode 测试对照）
- ISO/IEC 18004（掩码与 N1–N4 惩罚规则语义，作为规范背景）
