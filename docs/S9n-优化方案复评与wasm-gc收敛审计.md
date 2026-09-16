# S9n · 优化方案复评与 wasm-gc 收敛审计

> **状态**：现行　｜　日期：2026-09-12　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §2

> 承接 [S9k（成本分解）](./S9k-性能瓶颈与理论上限评估.md) ·
> [S9l（fast_qr 参考）](./S9l-参考fast_qr高性能实现分析.md) ·
> [S9m（ReadOnlyArray）](./S9m-ReadOnlyArray适用性评估.md)：S9k/S9l/S9m 各自给出了成本、参考做法与
> 局部结论，但三套编号（K1–K5 / P0–P4 / T-R1–T-R5）**互相重叠且未统一**，且部分实验存在
> **介质-算法混杂、收益重复计数、基线互串**。本文做两件事：
> ① 审计「移除 `wasm`(WASI)/`js`、仅 `wasm-gc`」是否收敛干净；
> ② 对三份方案做**批判性复评**——找漏洞、去重复、收敛为**单一优先级清单**。
>
> 日期：2026-09-12　｜　环境：`moon 0.1.20260904`、**仅 `wasm-gc` release**、全量单测（审计时 109，P0/P2 落地后 111）
> ｜　范围：**审计 + 评估 + 文档修订；未改任何入库代码**（证据均为只读复跑：`moon fmt --check`、
> `moon check --deny-warn`、`moon test --target wasm-gc`、lint、core 源码、`supported_targets` 实测）。
>
> > 项目决策：`wasm`(WASI)、`js` 后端均已移除，**现仅支持 `wasm-gc`**；本文所有结论只针对 `wasm-gc`。

---

## 0. 结论先行

1. **收敛结论：代码/CI/脚本已收敛到 `wasm-gc`，但「面向用户的 README 顶部」漏改**——
   `README.md:6`「`wasm-gc` / `wasm` 双后端回归通过」、`:29`「`wasm-gc` 主推 + `wasm`/WASI 兼容」、
   `:59`「双后端产物」、`:161-165` 本地构建循环 `for t in wasm-gc wasm` 仍在。属收敛遗漏（本次修）。
2. **`supported_targets="+wasm-gc"` 是硬边界（实测）**：`moon build lib --target native`
   直接报 `Package '…/lib' does not support target backend 'native'. Supported backends: [wasm-gc]`。
   即下游**原生/JS 消费者被拒**——纯 MoonBit 库本可编译，这是有意的分发范围收缩，**必须显式写进 README**。
3. **方案复评发现 6 个方法学漏洞（H1–H6，见 §2）**，其中最关键的是：
   - **H1 重复计数**：S9l §3.1 的 1.26× 是「字节介质 + 去闭包 + 切片/列缓冲」**三改合一**的结果，
     却被 P2（切片/去闭包）与 P3（字节介质）**各自再引用一次**；
   - **H2 掩码特化被介质污染**：§3.2 的 4–5.8× 是在 `FixedArray[Byte]` 上测的，而 P0 提议先在
     `Array[Int]` 上落地——**该倍数未必迁移**；
   - **H3 基线互串**：S9k 基线 `5.900ms`（moonrun 边际）与 S9l §4 基线 `5.306ms`（S9j Node B）混用，
     绝对减法不可加；
   - **H4 `Bytes` 从未 A/B**，P3 却把它列为候选；本仓库 `lib/cmd` 全无 `Bytes` 使用（`git grep` 为空）。
4. **统一优先级（§3，单一事实源）**：`P0 掩码特化 → P1a wrap 按 size² → P2 评分去闭包/切片 →
   P2b 评分减趟 → P3 介质（须先三向微基准）→ P4 RS 栈缓冲`；`T-R1/T-R2` 降为「类型对齐」。
   **P0/P2/P3 落地前必须先做组合实测**，不得把独立实验收益直接相加。
5. **结论方向不变、口径更保守**：V40 现实 **≈3.2–3.9ms**（`fast/ours ≈0.8–0.95×`）；
   **不承诺追平 V03**。S9m 的「ReadOnlyArray 不是性能杠杆」成立，且其 RS 占比应更保守——
   `pipe`(encode+RS) 才占 2.5%，**RS 单项更低**。
6. **已按本清单落地 P0 + P2 + P2b(N4)**（2026-09-12，见 §6）：V40 单次 auto 实测
   **5.97→4.42ms（−26%）**、V10 **−24%**、V03 **−4%**，输出**逐位不变**（`TOTAL_CHECKSUM`/快照全同）；
   111 测试全绿。**ReadOnlyArray（T-R1/T-R2/T-R4）亦已落地**（§6.5–6.6，类型对齐为主；
   受控探针复验 `division` ≈1.30–1.34×、整 build ≈0.9%）；
   P1 受阻于公共契约、P2b(N2)/P3/T-R5 仍待做。

---

## 1. wasm-gc 收敛审计

### 1.1 已收敛（复核通过）

| 位置 | 现状 | 证据 |
|------|------|------|
| `moon.mod` | `supported_targets = "+wasm-gc"`、`preferred_target = "wasm-gc"` | 实测 native 被拒 |
| `AGENTS.md` §二.3 / §二.4 | 只支持 `wasm-gc`；回归循环 `for t in wasm-gc` | 与 CI 一致 |
| `.cnb.yml` | 注释「仅默认后端 wasm-gc（js、wasm(WASI) 已移除）」 | — |
| `scripts/{bench,bench-size,bench-layer2,build-and-run}.sh` | 去 `MOON_TARGET=wasm` 分支、去 `--moon-wasm`、只构建 wasm-gc | 已删 `wasm-compare.mjs` |
| `scripts/gc-compare.mjs` / `wasm-size.mjs` | 只保留 wasm-gc 通道 | — |
| 构建产物 | `_build/wasm-gc/`；`*.mbti` 未入库（`git ls-files` 为空） | AGENTS 合规 |

### 1.2 收敛遗漏（本次修）

| # | 位置 | 现状文本 | 处置 |
|:-:|------|---------|------|
| A1 | `README.md:6` | 「`wasm-gc` / `wasm` 双后端回归通过」 | 改单后端 |
| A2 | `README.md:29` | 「`wasm-gc` 主推 + `wasm`/WASI 兼容」 | 改唯一后端 + 注明 native 边界 |
| A3 | `README.md:59` | 「**双后端产物**…+ `wasm`（WASI，宿主接入灵活）」 | 改单后端 |
| A4 | `README.md:161-165` | `for t in wasm-gc wasm; do …` | 改 `wasm-gc` |
| A5 | `cmd/qr-min/moon.pkg:9` | 「moonrun（wasm-gc）/ WASI 宿主（wasm）下输出恒为…」 | 删 WASI 半句 |
| A6 | `docs/S9k-…:256-257` | 验收「wasm-gc/wasm」「双后端 checksum」 | 改 wasm-gc |
| A7 | `docs/S9l-…:195,266` | 验收「双后端 checksum」 | 改 wasm-gc |

> S2–S8、S9c–S9g、`wasm-编译与运行-结果分析.md`、`moonbit-重写-roadmap-详细分析.md` 中的「双后端全绿」
> 属**当时里程碑的历史记录**，不构成现口径，保留原文（其中多数已加历史注记）。

### 1.3 `supported_targets` 的硬边界（实测）

```bash
$ moon build lib --target native --release
Error: failed to run build for target Native
Caused by:
    Package 'TryAndRun-TvT/fast_qr_moonbit/lib' does not support target backend 'native'.
    Supported backends: [wasm-gc]
```

- 该库是**纯计算 MoonBit、无后端专属代码**，本可编译到 native/JS；`supported_targets="+wasm-gc"`
  是**有意的范围收缩**，代价是下游这些后端无法依赖本模块。此取舍须在 README「能力与局限」明示。
- `moon check`/`moon test` 默认走 `preferred_target`，不受影响。

### 1.4 宿主要求（wasm-gc 专属）

| 项 | 要求 |
|----|------|
| 引擎 | **支持 wasm-gc（GC 提案）的运行时**：Node ≥ 22 / V8、启用 GC 的 wasmtime 等 |
| 导入 | `spectest.print_char`（CLI `println` 路径）——非标准 WASI |
| 不再提供 | WASI preview1 通用兜底（`wasm` 后端已移除）——宿主接入面比双后端时期**变窄** |

---

## 2. 优化方案复评（S9k K / S9l P / S9m T-R）

### 2.1 方法学漏洞表

| # | 漏洞 | 影响 | 修订 |
|:-:|------|------|------|
| **H1** | S9l §3.1 的 **1.26×** 是「`FixedArray[Byte]` 介质 + 去闭包 + 列切片缓冲」**三改合一** | P2 与 P3 **各自引用同一次实验** → 收益重复计数、叠加表虚高 | 1.26× 归为 **P2+P3 联合**上限；P2、P3 单因子须各自微基准 |
| **H2** | S9l §3.2 掩码 4–5.8× 是在 **`FixedArray[Byte]`** 上测；P0 拟先在 **`Array[Int]`** 落地 | 倍数**未必迁移**到现有介质 | P0 先做 `Array[Int]` 小样对拍+计时；达不到再并入 P3 同批 |
| **H3** | S9k 基线 **5.900ms**（moonrun 边际）与 S9l §4 叠加表 **5.306ms**（S9j Node B）混用 | 绝对减法/加法跨 harness 不可比 | 每张表只用一个基线；比值可跨，绝对值不可 |
| **H4** | `Bytes` 从未 A/B（本仓库 `lib/cmd` 零使用），P3 却写「`FixedArray[Byte]`（或 `Bytes`）」 | 可能漏掉更优介质 | P3 先做 `Array[Int]` / `FixedArray[Byte]` / `Bytes` **三向**微基准再定 |
| **H5** | P0/P1/P2/P3 分别用**独立探针**验证，§3/§4 叠加表**按算术相加** | 忽略交互（掩码/评分都改写同一批热循环） | 宣称叠加收益前**必须做合并探针**；表内标注「未合并实测」 |
| **H6** | S9l **P4** 与 S9m **T-R5** 是同一件事（RS 栈缓冲/分配复用），却分列两套编号 | 读者误当两项、重复立项 | 合并为 **P4**；`T-R1/T-R2` 降级为类型对齐 |

### 2.2 逐项复评

- **P0 掩码特化**（S9l P0 / S9k K2）：**收益真实但需重测介质前提**（H2）。实验本身是**逐位等价**
  改写，可信度高；注意**不可省 `copy`**——S9b 已否决 O1-a「就地翻转免 copy」（S9k §2.2），
  P0 的「就地 toggle」指**在每轮副本上就地**，仅免每格 `match`/取模，不是免拷贝。
- **P1 容器**（S9k K3 / S9l P1）：`Array[Module]` 逐格对象税 ≈10× 站得住（S9k §3.3 直接对照）。
  拆成 **P1a**（`wrap_packed` 按 `size²` 分配，不动公共字段）与 **P1b**（`QRCode.data` 容器语义，
  公共 `pub(all)`，须单独评审）——P1a 低风险先做。
- **P2 评分结构**（S9l P2 / S9k K4+K1）：**去闭包 + 列切片缓冲**与**减趟**作用于同一批扫描，
  收益**不可简单相加**（S9k K1 已自注「含在 K1 内」。建议顺序：先去闭包/切片（结构）→ 再减趟（N4/N2 并入），
  每步独立提交。
- **P3 介质**（S9l P3 / S9k K5）：**唯一前置门槛最高的一项**，须三向微基准（H4）；在 H1 未澄清前，
  **不得**引用 1.26× 作为 P3 独立收益。
- **P4 RS 栈缓冲**（S9l P4 / S9m T-R5）：目标一致，合并。V40 上 `pipe`(encode+RS) 仅 **2.5%**，
  **RS 单项更低**；`division` 表只读化（S9m T-R1）实测 ≈1.25×（division）→ 整 build
  **≈0.4–0.5%**，且 RS 分配复用（T-R5）≈1.13× 与之叠加后仍受 `pipe` 封顶。**低优先**。

### 2.3 S9m 复评补充（复核其结论）

- **core 事实复核为真**：`ReadOnlyArray` 是 `FixedArray` 的 `%identity` 封装（
  `core/builtin/readonlyarray.mbt:16-23`），无 set，读路径零开销——S9m §1.1 成立。
- **口径修正**：S9m 多处写「RS 全链占 V40 ≈2.5%」，精确说法应为 **`pipe`(=encode+RS) 占 2.5%**，
  RS 单项占比更低 → **结论更保守，不改变方向**。
- **未覆盖项**：未测 `Bytes`（H4）；`structure` 未直接计时（仅 `division` 代理）；`T-R3`（公共
  `QRCode.data` 只读化）性能 ≈0 且 API 风险中，**建议不做**。
- **lint 复核**：`moon check --warn-list "+prefer_readonly_array"` 命中 **恰好 4 处**——生产 `offsets`
  (`matrix.mbt:59`)、`pad` (`bitbuffer.mbt:129`)；测试 `mods`、`bits`。与 S9m §5 一致，
  模块级表（`log_table`/`antilog_table`）确实**不被覆盖**。

---

## 3. 统一优化优先级（单一事实源）

> 编号收敛三套方案；「独立收益」为**分因子**量级（不叠加）；落地前按 §4 门禁。

| 顺序 | 编号 | 项 | 来源 | 独立收益（V40） | 前置/重叠 | 风险 |
|:----:|------|----|------|----------------:|-----------|------|
| 1 | **P0** | 掩码 8 特化（免每格 `match`/取模；**保留 copy**） | S9l P0 / S9k K2 | −0.4~0.55ms（**须在 `Array[Int]` 复测**） | 无 | 低 |
| 2 | **P1a** | `wrap_packed` 按 `size²` 分配（不动公共字段） | S9k K3-A | V03 −0.07~0.09ms | 无 | 低 |
| 3 | **P2** | `score` 去闭包 + 列切片缓冲（`score.mbt`） | S9l P2 / S9k K4 | 与 P3 联合 ≈1.26× | 与 P3 同批测 | 中 |
| 4 | **P2b** | `score` 减趟（N4 并入行、N2 并入行对） | S9k K1 | −0.7~1.5ms | 与 P2 重叠，须合并实测 | 中 |
| 5 | **P3** | 内部介质窄化（先三向微基准：`Array[Int]`/`FixedArray[Byte]`/`Bytes`） | S9l P3 / S9k K5 | 联合上限 ≈1.26× | **依赖微基准门槛** | 高 |
| 6 | **P1b** | `QRCode.data` 容器语义（`pub(all)`） | S9l P1-B / S9k K3-B | V40 −0.4ms、V03 −0.01ms | **须公共 API 评审** | 中 |
| 7 | **P4** | RS 栈缓冲 + `T-R1/T-R2` 表只读化（类型对齐） | S9l P4 / S9m T-R1/T-R5 | 整 build ≈0.4–0.7%（`pipe` 封顶） | 无 | 低 |

**明确不做**：`T-R3`（`QRCode.data` 只读化，性能≈0）；O1-a（就地翻转免 copy，S9b 已否决）；
「追平 V03」（固定成本约束，非目标）；为 ≈0.5% 的 RS 项单独立项。

> **落地状态（2026-09-12）**：**P0 / P2 / P2b(N4) / P4 的 T-R1·T-R2·T-R4 已实施**（§6.1–§6.6）；
> **P1 受阻于公共契约**（`data().length()==QR_MAX_MODULES` 被测试断言，实为 P1a=P1b）；P2b(N2)/P3/T-R5 待做。

---

## 4. 落地与验收（**wasm-gc only**）

每项独立提交，统一门禁：

1. `moon fmt --check` / `moon check --deny-warn` / `moon test --target wasm-gc` 全绿（P0/P2 落地后为 **111**）；
2. 快照逐位 diff 零差异（择优 mask 不变）+ `cmd/bench` `TOTAL_CHECKSUM` 不变；
3. 层② `bash scripts/bench-layer2.sh` 同尺子复跑（`wasm-gc` vs fast_qr-wasm32，Node 进程内）；
4. **组合实测**：P0/P2/P3 任两项以上同批落地时，先做**合并探针**再回填收益（H5），禁止算术相加；
5. `T-R1/T-R2` 改表容器后，`division` 余数须**逐位不变**（全量单测 + checksum 兜底）。

> **历史口径**：不再有「双后端 checksum 互证」；跨后端护栏（wasm-gc vs wasm）随 `wasm` 移除退场，
> 只保留「Node shim vs `moonrun` 跨宿主一致」。

---

## 5. 复现（只读，未入库）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt --check && moon check --deny-warn && moon test --target wasm-gc   # 111 全绿
moon check --warn-list "+prefer_readonly_array"                            # 恰好 4 处命中
moon build lib --target native --release                                   # 预期被 supported_targets 拒绝
```

---

## 6. 落地记录（2026-09-12：P0 + P2 + P2b-N4）

> 实施遵循 §3 顺序与 §4 门禁；**输出逐位不变**由 `TOTAL_CHECKSUM` 与快照逐位 diff 兜底。

### 6.1 已落地改动

| 项 | 改动 | 位置 |
|----|------|------|
| **P0** | `apply_mask` 由「逐格 `match`+取模」改为 **8 个特化循环**：0–4 号用步长几何生成候选格，5–7 号按 x 周期 6 逐行只算 6 个余数步进；保留 `mask_at` 与越界通用回退 | `lib/internal/matrix/datamasking.mbt` |
| **P2** | `line_rows/line_cols` **去闭包**；列评分改「先收进复用缓冲、再连续扫描」（对照 `score.rs:150-175`） | `lib/internal/matrix/score.mbt` |
| **P2b(N4)** | **N4 暗格计数并入行趟**（`line_scan_buf` 同时返回 dark），`score` 不再单独全矩阵扫 | `lib/internal/matrix/score.mbt` |

新增护栏测试：特化 `apply_mask` 与逐格 `mask_at` 参考**逐位对拍**（8 掩码 × 6 尺寸 × 混合类型）；
`score` 四规则**分解不变式**（N4 并入后总分＝分量之和）。测试 109 → **111 全绿**。

### 6.2 受控 A/B（wasm-gc，`cmd/bench`，宿主 wall time R=3 取最小）

| 点 | N | baseline | +P0/P2 | +P2b(N4) | 总降幅 | `TOTAL_CHECKSUM` |
|----|--:|---------:|-------:|---------:|-------:|------------------|
| V03H | 8000 | 1.672s | 1.649s | **1.602s** | **−4.2%** | 328000（三项一致）|
| V10H | 1500 | 1.192s | 1.109s | **0.924s** | **−22.5%** | 121500（三项一致）|
| V40H | 300 | 1.852s | 1.664s | **1.386s** | **−25.2%** | 69000（三项一致）|

边际（扣宿主固定项）：V40 **5.97→4.42ms**、V10 0.755→0.576ms、V03 0.202→0.193ms；
其中 V40 基线与 [S9k §2.1](./S9k-性能瓶颈与理论上限评估.md) 的 5.90ms 吻合。
**三项 checksum 与基线完全相同 ⇒ 择优结果与矩阵逐位不变**（非近似改写的直接证据）。

> 读法：V40/V10 收益大 = 命中 `score`/`apply_mask` 主导（S9k 68%/11%）；V03 收益小 = 其主导项是
> `wrap` 容器（44%，属 P1，未动）。与 [S9k](./S9k-性能瓶颈与理论上限评估.md) 成本模型一致。

### 6.3 复评更新（实施后才明确）

- **P1a 无法按原描述落地**：`qr.data().length() == QR_MAX_MODULES` 由
  `lib/fast_qr_moonbit_test.mbt:46`、`lib/fast_qr_moonbit_wbtest.mbt:111` 断言，且 `data` 是 `pub(all)`；
  **不动公共契约就无法省掉恒 31329 槽的分配**——即 P1a 与 P1b 实为同一决策，须先做公共 API 评审（未实施）。
- **P2b 本轮只合并 N4**：N2(`score_squares`) 仍为独立趟；将其并入行对扫描的收益与风险须单独设计。
- **P3 仍未动**：介质窄化必须**先做 `Array[Int]`/`FixedArray[Byte]`/`Bytes` 三向微基准**（H4），
  且不得再引用 P2 的 1.26×（H1）。
- **P4 / `T-R1/T-R2` 已随 ReadOnlyArray 落地**（§6.5，性能复验见 §6.6）：`pipe`(encode+RS) 仅 2.5%，
  整 build 实测 **≈0.9%**（分辨率边缘）；T-R5（RS 分配复用）仍待做。

### 6.4 下一步

1. P2b(N2 合并) 或 `score_squares` 局部优化（须保留四规则分解护栏）；
2. P3 三向微基准，确认正收益再定重构；
3. P1 公共 `QRCode.data` 容器语义评审（决定是否允许 `length=size²`）；
4. T-R5 RS 工作区复用（受 `pipe` 2.5% 封顶，低优先）。

### 6.5 ReadOnlyArray 落地（2026-09-12：T-R1 / T-R2 / T-R4）

| 项 | 改动 | 位置 |
|----|------|------|
| **T-R1** | `log_table`/`antilog_table` → `ReadOnlyArray[Byte]`（热路径查找表） | `lib/internal/reedsolomon/reedsolomon.mbt` |
| **T-R2** | **全部常量表**只读化（`capacity_table`、`data_codewords_table`、`alignment_grid_table`、`ecc_to_groups_table`、`generator_polys`、`generator_index`、`format_information_table`、`percent_score_table`、`max_bytes/information/missing_bits`）+ `keep_last` + 局部只读字面量 `offsets`/`pad`（含测试 `mods`/`bits`/`sizes`） | `lib/internal/{constants,matrix,bitstream}` |
| **顺带收益** | `get_polynomial`/`alignment_grid` 改**零拷贝只读视图**（免每次 `.copy()` 分配）；`division` 的 `by` 参数收窄为 `ReadOnlyArray[Byte]` | 同上 |
| **T-R4** | `moon.mod` 加 `warnings = "+prefer_readonly_array"`（lint 防回归；用临时探针实测生效） | `moon.mod` |

**验证**：111 测试全绿；`TOTAL_CHECKSUM` 三点与基线一致；`QR_MIN_CHECKSUM=283`（文档定值）；
lib 公共 `.mbti` **零漂移**（变更全部在 internal 层）；`prefer_readonly_array` lint **零命中**。

**性能读数（诚实口径）**：仅看整 build 的跨轮对比（V03/V10/V40 差异 +5.5%/+1.5%/+2.6%）**不足以判定**——
绝对毫秒混入启动与 [S9h](./S9h-层②性能复测异常归因-Node版本与宿主漂移.md) 宿主漂移，且当时误判「无回归」
的推理掩盖了「收益是否真实存在」的问题。**已用受控探针实验定论（见 §6.6）**：T-R1 收益真实存在
（`division` ≈1.30–1.34×），整 build ≈0.9% 处于分辨率边缘；定性维持「类型对齐为主、性能为辅」。

### 6.6 ReadOnlyArray 性能复验（2026-09-12，受控探针 ABAB 交替）

> 方法（对齐 [S9m §6](./S9m-ReadOnlyArray适用性评估.md)，探针测毕即删）：临时包 `lib/probe`
> 直测**真实 `@reedsolomon.division`**（除式 = V40-H `get_polynomial(39,3)`，31B）；两态为
> **A = HEAD（ReadOnlyArray）** 与 **B = 临时回退 RS 链为 `Array[Byte]`**（`log/antilog` 表、
> `generator_polys`、`division.by` 参数、`get_polynomial` 恢复 `.copy()`）；两态 checksum **逐位一致**
> （15B=3827410、220B=3818836，语义护栏）；计时 = bash `TIMEFORMAT='%R'` 整程、N 与 N/2 斜率、
> **R=5 取最小**；**ABAB 交替**两轮抵消宿主漂移。

**探针结果（µs/division）**：

| 态 | 15B（真实 V40H 块长，两轮） | 220B（上限档，两轮） |
|----|---------------------------:|---------------------:|
| B `Array[Byte]` | 1.685 / 1.650 | 24.35 / 29.60 |
| A `ReadOnlyArray` | 1.255 / 1.270 | 15.30 / 15.55 |
| **比值 B/A** | **≈1.30–1.34×** | ≈1.59–1.90×（B 态抖动大） |

**整 build 同轮 ABBA（V40，N=300，各 3 次取最小）**：A min **1.408s** vs B min **1.420s**
（`TOTAL_CHECKSUM` 两态同为 69000）→ Δ≈12ms/300 ≈ **40µs/build ≈0.9%**，符号与探针外推一致
（81 块 × ~0.43µs ≈ 32µs）。

**结论（修订 S9m 量级）**：
1. **T-R1 收益真实**：真实块长（15B）下 `division` **≈1.30–1.34×**，略高于 S9m 历史口径 ≈1.25×
   （同向，量级确认；差值属环境/轮次分辨率）；
2. **整 build 占比升至 ≈0.7–0.9%**：绝对节省 ≈32–40µs 不变，但分母已从 S9m 时的 5.90ms
   缩至 P0/P2/P2b 后的 **4.42ms**——**优化主线推进后，低优先项的相对收益会自然放大**；
3. 定性不变：RS 受 `pipe` 封顶，ReadOnlyArray 是**类型对齐 + 有限性能**项，主线仍是
   P2b(N2)/P3/P1（见 §6.4）。

---

## 7. 参考

- 成本分解：[S9k](./S9k-性能瓶颈与理论上限评估.md)（K1–K5、五段分解）
- 参考实现与受控实验：[S9l](./S9l-参考fast_qr高性能实现分析.md)（P0–P4）
- 容器/查找表专项：[S9m](./S9m-ReadOnlyArray适用性评估.md)（T-R1–T-R5）
- 对外口径与护栏：[S9j](./S9j-层②统一Node对比-wasm-gc与fast_qr.md) · [S9b](./S9b-性能优化.md) ·
  [S9h](./S9h-层②性能复测异常归因-Node版本与宿主漂移.md)
- 实测依据：`moon.mod`、`AGENTS.md` §二.3/§二.4、`cmd/qr-min/moon.pkg`、
  `lib/internal/matrix/{score,datamasking,matrix}.mbt`、`lib/internal/bitstream/bitbuffer.mbt`、
  `lib/internal/reedsolomon/reedsolomon.mbt:547,569,582,604`、core `builtin/readonlyarray.mbt`
