# S9l · 参考 fast_qr 高性能实现分析

> **状态**：现行　｜　日期：2026-09-11　｜　索引：[docs/README.md](../README.md) §2

> 承接 [S9k 性能瓶颈与理论上限](S9k-性能瓶颈与理论上限评估.md)：S9k 用差分探针定位了**本项目**
> 的成本分布（V40 8 轮 `score` 占 68%、V03 `wrap` 占 44%）。本文换到**参考实现一侧**——对本地检出的
> [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr)（commit `53e8c99`）做**逐文件精读**，
> 回答「fast_qr 为什么能做到高性能」，并把它的关键做法**移植到 MoonBit 做受控实验**，量化每项能带来多少。
>
> 日期：2026-09-11　｜　环境：`moon 0.1.20260904`、`wasm-gc` release（`moonrun` 边际斜率）、
> fast_qr 检出 `/root/.cache/fast_qr_wasm/fast_qr`　｜　范围：**分析 + 临时探针实验；未改任何入库代码**
> （探针测毕即删，复现法见 §6）。

---

## 0. 结论先行

fast_qr 的性能来自 **6 项相互独立的设计**，按「本项目可借鉴度 × 实测收益」排序如下
（收益为本仓库 `wasm-gc` 上的**受控实验实测**，非文献估算）：

| # | fast_qr 的做法 | 实码 | 本项目现状 | 实测收益（本仓库） |
|:-:|----------------|------|-----------|-------------------|
| 1 | **8 个就地特化掩码函数**：步长/对称几何，只遍历候选格，无每格 `match`/取模 | `datamasking.rs:31-160` | `apply_mask` 全矩阵扫描 + 每格 `match mask_idx` | **8 轮掩码 4.0–5.8×**（V40 0.676→0.130ms） |
| 2 | **u8 值类型 + 定长内联数组**：`Module(pub u8)`、`[Module; 31329]`，无堆/无逐格对象，clone=整块 memcpy | `module.rs:42`、`qr.rs:32` | `Array[Int]` 工作介质 + `Array[Module]` 结果容器（逐格对象） | 容器填格 **≈10×**（V40 0.40 vs 0.04ms，见 S9k §3.3） |
| 3 | **评分用切片 + 栈列缓冲**：`line(&[Module])` 无闭包；列收集进 `[Module;177]` 栈数组，无转置拷贝 | `score.rs:82,150-175` | `line_score(fn(i){…})` 每行/列闭包 + 列跳访 | 评分 **≈1.26×**（V40 4.24→3.35ms） |
| 4 | **栈定长中间缓冲**：RS `[u8;255]`/`[u8;5430]`、列缓冲，热路径零堆分配 | `polynomials.rs:83,106,119` | `Array::make` 逐次堆分配（division/slice/结构） | 小（S9k：V40 管线仅 2.5%），小版本相对重要 |
| 5 | **装配结构**：base 建一次，每轮 `qr.clone()` 后 mask+score | `placement.rs:94-118` | 同构（O1-b 还省了 fast 仍付的第 9 次 mask） | 结构已对齐，无额外收益 |
| 6 | **构建配置**：`lto`+`codegen-units=1`+`opt-level='s'`+`panic=abort`，wasm-opt `-Oz` | `Cargo.toml` release profile | MoonBit wasm-gc 自有后端，无等价旋钮 | 归入「语言/编译级」，见 §5 |

**一句话**：fast_qr 的最大杠杆**不是「1 字节介质」本身**（实验实测评分只快 1.26×），
而是 **(1) 掩码特化（≈5×）** 与 **(2) 避免逐格对象/堆分配（容器 ≈10×）**，其次才是评分的扫描结构。
按 §4 的叠加方案，本项目 V40 单次 auto 有望从 **5.90ms** 降到 **≈3.2–4.0ms**
（fast_qr 3.03ms，比值 0.57×→**0.76–0.95×**），V03 从 **0.23ms** 到 **≈0.12–0.14ms**。

---

## 1. 对象、方法与口径

- **参考侧**：fast_qr v0.14.0（`53e8c99`，本地检出），核心文件 `module.rs / qr.rs / datamasking.rs /
  score.rs / placement.rs / polynomials.rs / compact.rs / default.rs / encode.rs`。
- **本项目侧**：`lib/internal/matrix/{module,matrix,placement,datamasking,score}.mbt`、`lib/qr_build.mbt`、
  `lib/qr.mbt`、`lib/internal/{reedsolomon,bitstream,data_encoding}`。
- **对外基线**：[S9j](S9j-层②统一Node对比-wasm-gc与fast_qr.md) 同一 Node 进程口径（本仓库 `wasm-gc` B 口径）
  `0.207 / 0.739 / 5.306 ms` vs fast_qr-wasm32 `0.059 / 0.320 / 3.029 ms`（fast/ours `0.287 / 0.433 / 0.571×`）。
- **受控实验**：临时包 `lib/probe`（内部可见性要求，放在 `lib/` 下；测毕删除，§6 有复现法）。
  - 计时 = 同一命令跑 `N` 与 `N/2` 整程取最小，`marginal=(t(N)−t(N/2))/(N/2)`，剔除 `moonrun` 启动；
  - 加速比 = 同一批矩阵、同一 8 轮循环下两种实现的边际之比；
  - **逐位校验**：byte 评分结果与 `@matrix.score` 完全一致；8 个特化掩码结果与 `@matrix.apply_mask`
    完全一致（V03/V10/V40 全绿）——实验不是「近似」，是与现实现**逐位等价**的改写。

---

## 2. fast_qr 高性能设计逐项拆解

### 2.1 数据介质：u8 值类型 + 定长内联数组（结构级，最根本）

```rust
// module.rs:42
pub struct Module(pub u8);            // #[repr(u8)]，Copy：1 字节、纯值语义
// qr.rs:26-32
pub struct QRCode {
    // "fixed size array simply because of performance"
    pub data: [Module; QR_MAX_MODULES],   // 177*177 = 31329，内联定长（非 Vec）
    ...
}
```
- `[Module; 31329]` 是**值类型内联数组**：无堆分配、无 GC、无「数组元素是指针」的间接层；
  `Module` 本身 1 字节，`data` 就是一块 31329 字节的连续内存。
- 后果：`qr.clone()`（`placement.rs:98`）= **一条 31KB memcpy**；`qr[row][col]`（`qr.rs:92-104`）
  是对内联数组的切片，直接地址计算；不存在「逐格对象」。
- 对照本项目：`internal/matrix` 用 `Array[Int]`（4B/格，见 `module.mbt:6`），结果容器 `QRCode.data`
  是 `Array[Module]`（`qr.mbt:26`）——`Module` 在 wasm-gc 下是**逐格托管家对象**。
  S9k §3.3 实测：同 `size²` 填格，`Array[Module]` 比 `Array[Int]` 慢 **≈10×**。

### 2.2 掩码：8 个就地特化函数 + 步长/对称（算法级，实测收益最大）

fast_qr 不写「逐格套公式再判定」，而是**为每种掩码写一个专用循环**（`datamasking.rs:31-160`）：

| 掩码 | fast_qr 做法 | 遍历规模 |
|------|-------------|---------|
| 0 Checkerboard | `for row { for col in (row&1..).step_by(2) }` | ≈½ 格 |
| 1 Horizontal | `for row in step_by(2) { 全列 }` | ≈½ 格 |
| 2 Vertical | `for col in step_by(3) { 全行 }` | ≈⅓ 格 |
| 3 Diagonal | `start=(3-row%3)%3; step_by(3)` | ≈⅓ 格 |
| 4 LargeCheckerboard | 周期 6 内取 3 列块 | ≈⅙ 格 |
| 5/6 Fields/Diamonds | 行 `step_by(6)` + **利用矩阵对称**同时 toggle `(r,c)`/`(c,r)` + 稀疏 offsets | ≈⅙ 格 + 对称 |
| 7 Meadow | **上三角 `col from row`** + 对称 toggle | ≈½ 格 + 对称 |

- 关键点 1：**公式的常量被折叠进步长**（`x+y ≡ 0 (mod 2)` ⟺ 列从 `row&1` 起隔 2 列；
  `(x+y)%3==0` ⟺ 起始列 `(3-row%3)%3` 隔 3 列；大棋盘 ⟺ 周期 6 的 3 列块），
  因而**没有每格的 `match mask_idx`、没有每格 `%` 除法**。
- 关键点 2：**对称性**（掩码 5/6/7 的公式对 (x,y) 对称）把遍历减半。
- 关键点 3：**就地**（`&mut QRCode`）toggle，不产生额外整矩阵拷贝。
- 对照本项目 `datamasking.mbt:38-53`：`m.copy()` 后**全矩阵逐格** `is_data_byte && mask_at(x,y,idx)`，
  而 `mask_at`（`:22-33`）是 8 路 `match` + 每格取模。V40 下每轮 31329 格、8 轮 ≈25 万次分派 + 取模。

### 2.3 评分：切片扫描 + 栈列缓冲，无闭包、无转置

```rust
// score.rs:82 —— 直接吃切片，无回调/闭包
fn line(line: &[Module]) -> (u32, u32) { let mut buffer: u16 = 0; for &item in line { ... } }
// score.rs:150-175 —— 逐行评分 + 把该列收集进栈数组 [Module; 177] 再评分，避免 8 次整矩阵转置
let mut column = [Module::data(Module::LIGHT); QR_MAX_WIDTH];
for i in 0..n {
    let l = line(&qr[i]); line_score += l.1;
    for (module, &value) in column[..n].iter_mut().zip(qr.data[i..n*n].iter().step_by(n)) { *module = value; }
    let c = line(&column[..n]); col_score += c.1;
    patt_score += l.0 + c.0;
}
```
- 行扫描在连续切片上；列扫描先**收集到 177 元素的栈数组**再连续扫描（`step_by` 步进指针，无 `i*size+col` 乘法）。
- `matrix_score_squares`（`score.rs:42-75`）取 `line1=&qr[i]`、`line2=&qr[i+1]` 两条**连续行切片**滑窗；
  `dark_module_score`（`:178-187`）扫 `qr.data[..n*n]` 连续切片。
- 全部**零堆分配、零闭包、零间接调用**。
- 对照本项目 `score.mbt`：`line_rows`/`line_cols` 每行/列构造闭包 `fn(i){m[base+i]}` / `fn(i){m[i*size+col]}`
  （`:87`、`:102`）并逐格间接调用；列扫描是带乘法的跳访，无栈列缓冲。
- 注意：fast_qr 的评分仍是 **4 趟**（行、列、N2、N4），**趟数不减**；差距在「每趟怎么扫」。

### 2.4 中间缓冲：栈定长数组，热路径零堆分配

- RS 除法：`fn division(from,by) -> [u8;255]`，内部 `let mut from_mut = [0;255]`（`polynomials.rs:83-84`）；
  `structure(...) -> [u8;5430]`，内部 `[0; MAX_DATABITS + MAX_ERROR*MAX_GROUP_COUNT]`（`:106,119`）。
- 评分列缓冲 `[Module;177]`（`score.rs:156`）；`CompactQR::push_u8` 等标 `#[inline(always)]`（`compact.rs:144,165,176,212`）。
- 对照本项目 `reedsolomon.mbt:546-589`：`division` 内 `Array::make(255,…)`、`slice` 内 `Array::make(n,…)`、
  `structure` 内 `Array::make(5430,…)`——每块/每步都堆分配。S9k 实测 V40 管线仅 2.5%，故此项收益小，
  但对 V03（每次 build 固定开销占比高）有意义。

### 2.5 装配结构：与本项目已同构（且本项目更省一次）

`placement.rs:94-118`：`create_matrix` 一次 → `place_on_matrix_data` 一次 → 8 轮 `qr.clone()+mask+score`
选最优 → **在 base 上**写真实 Format 后**再 mask 一次**（`:114-115`，第 9 次掩码）。
本项目 `create_auto_qr`（`placement.mbt:112-137`）在 O1-b 后**复用最优轮已掩码矩阵**、把 Format 直接覆写其上，
**省掉了 fast_qr 仍要付的第 9 次掩码+整块复制**。此项我们**不落后、甚至领先**。

### 2.6 构建配置（语言/编译级）

`Cargo.toml` `[profile.release]`：`lto=true`、`codegen-units=1`、`opt-level='s'`、`panic='abort'`、
`strip="debuginfo"`；`wasm-pack` 档 `wasm-opt = ["-Oz"]`。Rust/LLVM 会把这些特化循环做
边界检查消除、强度削减、部分自动向量化。MoonBit `wasm-gc` 是独立后端，**没有等价旋钮**，
这构成 §5 的「残余差距」。

---

## 3. 受控实验：把 fast_qr 的做法搬到 MoonBit 上量

> 两项实验均为**逐位等价改写**（校验通过），只比较「实现方式」的差异。

### 3.1 实验一：评分——字节介质 + 切片扫描（无闭包）

用 `FixedArray[Byte]`（MoonBit 的定长字节缓冲）承载矩阵，`line` 改为直接吃 `(buf, off, len)`；
列评分先把列收集进可复用的 `FixedArray[Byte]` 缓冲再连续扫描。8 轮评分边际（ms）：

| 点 | 现状 `Array[Int]` + 闭包 `score` | 字节 + 切片 `score_byte` | 加速 |
|----|------------------------------:|------------------------:|-----:|
| V40H | 4.24 | 3.35 | **1.26×** |
| V10H | 0.479 | 0.361 | **1.33×** |

> 结论：**介质/闭包改动只值 ≈1.26–1.33×**，远小于「10×」的容器差距。评分的大头是**逐格计算与
> 后端代码质量**，不是字节宽度本身——这与 S9k §3.1「compute-bound 而非带宽-bound」一致。

### 3.2 实验二：掩码——8 个特化就地函数（步长/对称）

把 fast_qr 的 8 个特化掩码逐条移植到 `FixedArray[Byte]`（就地 toggle，含拷贝步骤以便与现状同口径：
现状 `apply_mask` 含 `copy`，实验含 `blit`）。8 轮掩码边际（ms）：

| 点 | 现状 `apply_mask`（copy+全扫+match） | 特化字节掩码（blit+步长/对称） | 加速 |
|----|-----------------------------------:|------------------------------:|-----:|
| V40H | 0.676 | **0.130** | **5.2×** |
| V10H | 0.0717 | **0.0123** | **5.8×** |
| V03H | 0.0153 | **0.0038** | **4.0×** |

> 逐位校验：8 个特化掩码的输出与 `@matrix.apply_mask` 在 V03/V10/V40 上 **完全一致**（校验和相等）。
> 结论：**这是 fast_qr 可借鉴做法里单项收益最大的一项**，比 S9k 对 K2（掩码特化）的保守估算
> （−0.25~0.35ms）更乐观——实测 V40 可省 **≈0.55ms（≈9% 单次 auto）**。

### 3.3 复核：容器——逐格 `Array[Module]` 的对象税

引 S9k §3.3（同探针）：同 `size²` 填格，`Array[Module]` vs `Array[Int]` 边际
V40 `0.400 vs 0.040ms`（**≈10×**）、V10 `0.027 vs 0.008`、V03 `0.007 vs 0.0025`。
`wrap_packed`（`qr_build.mbt:57-82`）还叠加了**恒 31329 槽**的定长分配（与版本无关，V03 浪费 37×）。

### 3.4 三项读数汇总

| fast_qr 做法 | 本项目现状成本（V40） | 实验后 | 单次 auto 占比 |
|-------------|---------------------:|-------:|---------------:|
| 掩码特化 | 0.660 | 0.130 | −0.53ms（−9%） |
| 容器/对象 | 0.590 | ≈0.05 | −0.54ms（−9%） |
| 字节+切片评分 | 4.007 | ≈3.18 | −0.82ms（−14%） |
| 评分**减趟**（fast_qr 未做，K1） | — | 见 S9k §4 | 额外 −0.7~1.5ms |
| 管线栈数组 | 0.147 | ≈0.10 | 小 |

---

## 4. 本项目如何参考该实现优化（分级落地）

> 每项**不得改变输出/择优结果**；逐项独立提交，验收沿用 [S9b §5/§6](S9b-性能优化.md) 与
> [S9k §6](S9k-性能瓶颈与理论上限评估.md)：快照逐位 diff + 109 测试 + `TOTAL_CHECKSUM` + 层② sha256 + 同尺子复跑。
> **复评修订（[S9n](S9n-优化方案复评与wasm-gc收敛审计.md)）**：P0/P2/P3 存在介质混杂与收益重复计数，
> 组合落地前须做合并探针，本表收益不得算术相加。

### P0 — 掩码特化（收益最大、风险低、改动集中）

- **做法**：在 `internal/matrix/datamasking.mbt` 新增 8 个特化函数（对照 `datamasking.rs:31-160`），
  用步长/对称几何就地 toggle；保留 `mask_at` 供白盒测试，`apply_mask` 改为按 `mask_idx` 分派到特化函数。
- **实测预期**：V40 −0.53ms、V10 −0.06ms、V03 −0.011ms（§3.2）。
- **风险/影响面**：低；只动 `datamasking.mbt`。**必须**加「8 掩码输出 == 原 `apply_mask`」的对拍测试。
- **前置**：建议与 P2 的介质改造同批评估（特化掩码在 `Array[Int]` 上同样成立，可先落地）。

### P1 — 容器与分配（小版本收益最大；需接口决策）

- **做法 A（不改公共字段）**：`wrap_packed` 内部按 `size²` 分配工作缓冲、优化写入，减少恒 31329 槽浪费。
- **做法 B（可进一步）**：让 `QRCode.data` 不再逐格装 `Array[Module]` 对象——把内部结果保留为
  `FixedArray[Byte]`/`Bytes`，公共 `data` 惰性物化或改窄介质。**注意** `data` 是 `pub(all)` 字段
  （`qr.mbt:24-26`），属**公共 API 语义变更**，须单独评审渲染/序列化依赖。
- **实测预期**：做法 A V03 −0.07~0.09ms、V40 −0.1ms 级；做法 B 再 V40 −0.4ms、V03 −0.01ms。
- **风险**：中（公共容器语义）。

### P2 — 评分结构：切片化 + 去闭包 + 栈列缓冲（大版本收益最大）

- **做法**：`score.mbt` 的 `line_rows/line_cols` 去掉每行/列闭包，改为直接扫描（列用可复用栈缓冲，
  对照 `score.rs:150-175`）；`score_squares` 改用两条连续行切片（对照 `score.rs:42-75`）。
- **实测预期**：score ≈1.26×（§3.1）。再叠加 S9k K1 **减趟**（N4 并入行趟、N2 并入行对）可望把
  V40 `score` 从 4.0ms 压到 **≈2.2–2.8ms**（`score` 4 趟→2 趟，理论上限）。
- **风险**：中（评分是对齐敏感区，逐位 diff 兜底）。

### P3 — 内部工作介质 `Array[Int]` → 定长字节缓冲

- **做法**：`internal/matrix` 全量工作矩阵由 `Array[Int]` 改为 `FixedArray[Byte]`（或 `Bytes`），
  位运算按字节做；与 P0/P2 协同（特化掩码与切片评分都需要窄介质才最顺）。
- **实测预期**：单看介质 ≈1.26×（§3.1）；与 P0/P2 叠加后是可达 V40 3.x ms 的组合前提。
- **风险**：高（改面大、白盒断言多）；**须先做独立微基准确认正收益**（S9b T6 的同一保留）。
- **API 约束**：`internal/*` 不是公共包，改其签名只影响 `lib` 调用方，`.mbti` 公共面不变。

### P4 — pipeline 栈缓冲（低优先）

- `reedsolomon.mbt` 的 `division/slice/structure` 改用预分配/复用缓冲（对照 `polynomials.rs`）。
- S9k：V40 管线仅 2.5%，故排最后；对 V03 的固定开销有小幅帮助。

### 叠加预期（基于 §3 实测 + S9k 成本表，非承诺）

| 场景 | V03H | V10H | V40H | V40 fast/ours |
|------|-----:|-----:|-----:|--------------:|
| 现状（S9j） | 0.207 | 0.739 | 5.306 | 0.57× |
| + P0 掩码特化 | ≈0.196 | ≈0.68 | ≈4.78 | 0.63× |
| + P1 容器 | ≈0.12 | ≈0.55 | ≈4.25 | 0.71× |
| + P2 评分切片化/减趟 | **≈0.10–0.12** | **≈0.40–0.48** | **≈3.2–3.7** | **0.82–0.95×** |
| + P3 字节介质 | ≈0.09–0.11 | ≈0.37–0.45 | **≈3.0–3.5** | **0.87–1.0×** |
| fast_qr-wasm32（参照） | 0.059 | 0.320 | 3.029 | 1.0× |

---

## 5. 差距归因与边界（为什么仍可能到不了 1.0×）

- **三块大致等量**：以现状 V40 5.31ms 计，评分差距 ≈1.6ms、掩码差距 ≈0.5ms、容器差距 ≈0.5ms，
  合计 ≈2.6ms ≈ 与 fast_qr 的差（2.28ms）同量级。**任何单一改动都追不平**，需组合。
- **残余「语言/编译级」差**：fast_qr 依赖 LLVM 的边界检查消除、切片迭代器优化、强度削减；
  MoonBit `wasm-gc` 后端在这些热循环上的代码质量是**实验里评分只快 1.26× 的主因**（改介质也没到 2×）。
  这部分**不随代码结构改动而消失**，故 §4 只承诺 **V40 0.82–1.0×**，**不承诺稳定追平**。
- **本项目已有/独占的优势**（fast_qr 未做）：
  1. O1-b 省第 9 次掩码+复制（`placement.mbt:112-137`）；
  2. 可进一步做 **N4/N2 合趟**（fast_qr 仍是 4 趟）——理论上限可**低于** fast_qr 的评分成本；
  3. 可选**行/列单趟融合**（用列状态数组），fast_qr 未采用。
- **不建议照搬**：`CompactQR` 的 `Vec<u8>`（我们已有等价 `Array[Byte]`）；`opt-level='s'` 等 Rust 旋钮在
  MoonBit 无对应项。

---

## 6. 验收与复现

- 门禁沿用 [S9b §5/§6](S9b-性能优化.md)：快照逐位 diff、109 全绿、`TOTAL_CHECKSUM`、
  层② sha256、`bench-layer2.sh` 同尺子复跑（**仅 `wasm-gc`**；`wasm`(WASI) 已移除）。
- 临时探针复现（**不出库**）：放 `lib/probe/`（`internal/*` 受可见性规则保护，只能在 `lib/` 子树 import），
  `moon.pkg` 声明 `pkgtype(kind:"executable")` + import `internal/{constants,data_encoding,reedsolomon,matrix}`。
  - **MoonBit 的 `Bytes` 无公开 setter**，定长可写缓冲用 `FixedArray[Byte]`（`FixedArray::make/set`、`blit_to`）。
  - 计时须用 **bash**（`TIMEFORMAT='%R'` + `time`）；zsh 不读该变量。
  - 掩码/评分改写**先跑逐位对拍**（byte 结果 vs `@matrix.apply_mask` / `@matrix.score`）再计时。

---

## 7. 明确边界

- 本文**未改任何入库代码**；探针为临时包，测毕删除。
- 不改择优语义、评分值、公共 API；P1-B/P3 涉及公共容器/内部介质，须单独评审与实验。
- 绝对毫秒绑定本环境（S9h）；跨环境只比同 run 成对比值与加速比。

---

## 8. 参考

- 参考实现（本地检出 `53e8c99`）：`src/module.rs`、`src/qr.rs`、`src/datamasking.rs`、`src/score.rs`、
  `src/placement.rs`、`src/polynomials.rs`、`src/compact.rs`、`src/default.rs`、`Cargo.toml`
- 本项目对应实码：`lib/internal/matrix/{module,placement,datamasking,score}.mbt`、`lib/qr_build.mbt`、
  `lib/qr.mbt`、`lib/internal/reedsolomon/reedsolomon.mbt`
- 成本分解与理论上限：[S9k 性能瓶颈与理论上限评估](S9k-性能瓶颈与理论上限评估.md)
- 对外基线与口径：[S9j 层②统一 Node 对比](S9j-层②统一Node对比-wasm-gc与fast_qr.md) ·
  [S9b 性能优化](S9b-性能优化.md) · [S9 性能基准](S9-性能基准.md) ·
  [S9h 环境归因](S9h-层②性能复测异常归因-Node版本与宿主漂移.md)
- 既有移植分析语料：`docs/移植参考/fast-qr-架构.md`（7 条性能决策）、`fast-qr-索引.md`
