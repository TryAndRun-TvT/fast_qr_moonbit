# S9b · 性能优化

> 本文件由原 S9b-性能优化-评估与路线 / S9b-性能优化-再评估与实施建议 / S9b-性能优化-O1实施记录 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 评估与路线

> 承接已合入的 S9 性能三基准点实现（PR #45，见 [S9-性能基准.md](./S9-性能基准.md)），
> 本文档对 S9 之后的性能优化做**逐热点评估**：建立进程级差分成本模型、定位头号优化靶点、
> 给分优先级落地路线（P1/P2）与统一验收口径。
> 范围：**纯评估文档、未越界做性能改写**——改写仍遵循 roadmap「S5 O1 主循环重构单列 P2」约束，
> 留给后续专项在前置（本路线）下推进。
> 日期：2026-09-06　｜　前置：S9 基准载体已合入 main（测试 109 基线）。

---

### 0. 一句话结论

**头号优化靶点 = 自动择优 8 轮掩码评分主循环**（`lib/internal/matrix/placement.mbt` 的
`create_auto_qr`，即 S5 评审 §4 O1 所指）。用**进程级差分实测**建立成本模型后确认：8 轮择优开销
随版本**超线性放大**——V40H 时占单次 auto 构建成本约 **86%**（≈6.86ms / 单次 7.99ms）。
非择优管线（encode→structure→matrix→放置→wrap）已相对紧凑、非优先。分优先级给出
P1（O1-a 就地翻转、O1-b 复用最优轮矩阵）与 P2（O2/O3）路线，验收统一走快照逐位 diff +
109 测试 + 双后端 checksum。

---

### 1. 背景与范围

- **为何做评估**：S9 实现记录（PR #45）已把基准载体落地并给出层①跨后端选型数字，但只测基线、
  未做性能改写（S5 O1 单列 P2 不并入 S9）。S9 之后自然承接「如何进一步优化」。
- **评估对象**：`QRCode::build`（`lib/qr_build.mbt`）自动择优完整管线。
  输入 `https://example.com/`（**20 字节**，S9 评估已更正）、ECL=H、强制版本 V03/V10/V40、mask 走自动择优。
- **方法论约束**：
  - 用**同点同输入、只差「自动择优 vs 固定 mask」**做**进程级差分**，把 8 轮择优成本从完整管线里剥出。
  - 固定 mask 路径（`build_fixed` / `QRCode::build` 的 `Some(mask)` 分支）已被 S5 §2.1 证实
    输出等价参考强制掩码旁路（跳过 8 轮评分为合理优化），故其耗时可视为「无择优基线」。
  - 探针必须用**编译期常量 + 消费结果**：argv 驱动探针会被编译器整段折叠（测量坑，详见 §2.3）。

---

### 2. 成本模型（进程级差分实测）

#### 2.1 差分口径与可信性

- 环境：容器内自装 MoonBit 工具链，wasm-gc 后端 release 计时（主口径同 S9 层①）。
- 差分：同点同输入，仅差自动择优（`build` mask=None）vs 固定 mask（`build_fixed`，选 S5 实测最优掩码）。
- 可信性交叉验证：
  - CMD 层 `cmd/bench` 数字与 PR #45 入库记录**完全吻合**（V40H N=40 ≈0.45s、`TOTAL_CHECKSUM`=9200）。
  - 常量探针 V40H auto n=100 → 0.78s / n=200 → 1.58s，**线性缩放**，排除死代码折叠。

#### 2.2 实测数字

| 基准点 | 单次 auto | 单次 fixed(无择优) | **8 轮择优开销** | 择优占 auto |
|--------|------:|------:|------:|------:|
| V03H | 0.39ms | 0.169ms | ≈0.22ms | ≈57% |
| V10H | 1.08ms | 0.233ms | ≈0.85ms | ≈73% |
| V40H | 7.99ms | 1.13ms | **≈6.86ms** | **≈86%** |

#### 2.3 测量坑记录（供后续复测/性能专项避坑）

> **argv 驱动探针会被编译器整段折叠**：若用 `argv` 传入迭代次数驱动循环且结果不消费，MoonBit 编译器
> 会因纯函数/常折叠把整段循环裁掉，得到「0ms」假象。必须用**编译期常量**（如 `let N = 100` 内联）+ 把
> 每轮 `build` 的 `Result` **累加消费**（size+代表性模块字节进 checksum）防空循环。S9 实现记录的
> `cmd/bench` 已按此口径落地，本评估探针同口径。

---

### 3. 逐热点分析（按成本贡献排序）

#### 3.1 热点①：`create_auto_qr` 8 轮择优主循环（`placement.mbt:109-134`）——头号靶点

```moon
let base = create_matrix(version_idx)
place_on_matrix_data(base, size, structure)
let mut best_score = 2147483647; let mut best_mask = 0; let mut k = 0
while k < 8 {
  let masked = apply_mask(base, size, k)   // ① 每轮全量 copy
  let s = score(masked, size)              // ② 每轮多趟全矩阵扫描评分
  ...
}
create_matrix_format_info(base, size, ecl_idx, best_mask)
let masked_out = apply_mask(base, size, best_mask)  // ③ 末尾再一次全量 copy
(masked_out, best_mask)
```

- **① 每轮 `apply_mask` 全量 copy（8 次）+ 末尾最优轮再 1 次 = 共 9 次整矩阵 copy**。
  源码 `apply_mask` 首行 `let out = m.copy()`，即每轮都复制一张完整 `Array[Int]`（V40 为 177×177=31329
  格）。8 轮择优 = 8 次整矩阵 copy，V40 下开销与评分同量级。
- **② 每轮 `score` 多趟全矩阵扫描**：`score` 内 `line_rows`（N1 行 + N3 行一次扫）+ `line_cols`
  （N1 列 + N3 列）+ `score_dark`（全扫）+ `score_squares`（全扫）≈ 4 趟全矩阵。8 轮 ≈ 32 趟。
- **③ 末尾最优轮再 copy 一次**：`masked_out = apply_mask(base, size, best_mask)` 为第 9 次全量 copy，
  可复用第①轮已产出的最优轮矩阵省掉（O1-b）。
- **随版本超线性放大**：copy 与扫描成本均 ∝ size² = (4·version+21)²，V40 vs V03 矩阵面积差 ~29×，
  故择优占 auto 成本从 V03H ≈57% 升至 V40H ≈86%。

> **非择优管线为何非优先**：encode→structure→create_matrix→放置→Format→wrap 均只在 base 上做**一次**，
> 成本线性单趟、无 8 倍放大。从差分口径看 V40H fixed(无择优) 仅 ≈1.13ms（auto 的 ~14%），说明
> 管线其余部分已相对紧凑，优化收益远低于择优主循环。

#### 3.2 热点②：`score` 评分趟数偏多（`score.mbt`）——次要靶点

`score` 现拆 4 趟（N1 行/N3 行、N1 列/N3 列、N2、N4）。其中 N1 与 N3 在 `line_rows`/`line_cols`
内**已同行合并**返回 `(run, patt)`（`line_score` 一趟同时结算 N1 run + N3 pattern 窗口），故「减趟」
空间主要在：能否把 N1 行扫与 N1 列扫合并（现行列分离、列靠 `m[i*size+col]` 跳跃访问）；N4 dark 计数
能否在已有趟顺带累加。属常数系数级优化（P2），收益 < 热点①。

#### 3.3 热点③：`wrap_packed` 恒量整表分配（`qr_build.mbt`）

`wrap_packed` 内 `Array::make(QR_MAX_MODULES, ...)` 对**任何版本**都分配整张 `QR_MAX_MODULES`（V40 上限）
容量，再只填前 `size*size` 格——小版本（V01-V10）浪费可观。但该分配每 `build` 只做一次、不随 8 轮放大，
且 `QRCode.data` 为固定容量容器设计（公共类型字段），改按 `size*size` 分配属**接口/容器语义权衡**，非纯
局部改动（见 P2 O3 备注）。

---

### 4. 优化路线（分优先级）

> 全部路线**不得改变输出明暗/元数据语义**；验收统一见 §5。O1/O2 逐步独立提交以缩小回归面兜底。
> 代码改写阶段仍遵循 roadmap「S5 O1 单列 P2」约束——本文档只给路线，不越界落地改写。

#### P1 —— 首选落地

- **O1-a 就地翻转（自逆 toggle）免每轮全量 copy**：`apply_mask` 改为**就地** toggle（toggle 为自逆操作：
  `toggle→score→还原` 无净副作用），单 base 缓冲复用，免 8 次全量 copy。但**列评分必须在掩码后做**
  （S5 历史 bug 铁律），故可行形态 = 对当前轮 mask 做 `toggle → score → 还原` 三连，score 仍在已掩码副本
  视角下做（逐格即时翻转），无全量 clone。预期：V40H 择优 6.86ms → ≈3~4ms（削掉 ~4ms copy 大头）。
- **O1-b 复用最优轮矩阵省末尾一次 copy**：择优循环中记下**最优轮已 apply_mask 的矩阵**（O1-a 就地形态下
  即还原前最优点留用），末尾 `masked_out = apply_mask(base, best_mask)`（第 9 次 copy）可直接复用。
  低风险、−≈1/9 择优 copy。

#### P2 —— 常数系数级

- **O2 score 融合减趟**：在保持 4 规则分值逐位不变前提下，合并可并行的趟（如 N4 dark 顺带在已有趟计数、
  N1 行列扫的内存布局权衡）；收益为常数系数、风险中等（评分是对齐敏感区）。
- **O3 wrap_packed 按 size*size 分配**：省小版本恒量浪费。⚠️ 需先评估 `QRCode.data` 固定容量容器语义
  （公共字段、快照/API 是否依赖整表），属接口权衡项、非纯局部改动，单列审慎。

#### 层②/③ 对比收尾（非性能改写）

- 层②（MoonBit-wasm vs fast_qr-wasm32 逐位对齐 + 同口径计时）与本优化路线正交、可并行推进；
  **2026-09-06 已落地**（Node.js 调用 wasm，三基准点逐位对齐零差异 + 计时在案），见
  [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md) 与
  [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
  （复测 + N 扫描成本分解：**边际单次 build** MoonBit 0.304/1.162/9.01ms vs fast_qr 0.061/0.335/3.18ms，
  每模块 0.29–0.36µs vs 0.07–0.10µs，即 P1/P2 落地前后同一把尺子），
  收敛 roadmap M3（M3 ✅）。层③（native 注记）仍可选（需 fast_qr native + C 工具链环境，非 M3 门槛）。

---

### 5. 验收口径（统一）

无论 O1/O2/O3 落地与否，性能专项的每步独立提交须过：

1. **快照逐位 diff 零差异**：自动择优输出矩阵对既有 S1-S7 参考快照逐位一致（mask 择优结果不变）。
2. **109 测试全绿**：`moon fmt --check` / `moon check --deny-warn` / `moon test`。
3. **双后端 checksum 一致**：wasm-gc/wasm 各点 `TOTAL_CHECKSUM` 不变（复用 S9 `cmd/bench`）。
4. lib 公共 `.mbti` 零漂移（O1/O2 若只改 internal/matrix 内实现，公共接口不变，天然满足）。

> 目标量级（参考，非承诺）：V40H 单次 auto 由 ≈7.99ms 通过 O1-a 削 8 轮 copy 后望向 ≈3~4ms。

---

### 6. 参考

- 前置：S9 [实现方案](./S9-性能基准.md)（PR #42）、[评估记录](./S9-性能基准.md)
  （PR #44）、[实现记录](./S9-性能基准.md)（PR #45）；roadmap §4.2 S9 / §4.4 M3。
- S5 评审 §4 O1：见 [S5-掩码评分与择优.md](./S5-掩码评分与择优.md)。
- 实码：`lib/qr_build.mbt`（build/build_fixed/wrap_packed）、`lib/internal/matrix/placement.mbt`
  （create_auto_qr/create_fixed_qr）、`datamasking.mbt`（apply_mask）、`score.mbt`（score 4 规则）。

---

## 再评估与实施建议

> 承接 本文件「评估与路线」部分（优化热点与 P1/P2 路线）、
> [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md) 与
> [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
> （层②跨库实测）。本文在既有内部成本模型之上，**用层②边际/每模块成本数据 + 逐热点实码核对**，对
> 「本项目如何优化」做再评估：量化每个优化项的预期量级、风险与影响面，给实施顺序与验收口径。
> 范围：**纯评估与建议文档，未改任何代码**；优化是否落地、何时落地由后续实施阶段按 roadmap 约束决定。
> 日期：2026-09-06　｜　前置：层②实测在案（M3 ✅），回归 109 全绿基线未动。

---

### 0. 一句话结论

层②跨库分解给出**可量化的优化靶量**：MoonBit `wasm` 产物每模块边际成本约为 fast_qr-wasm32 的 **3–5×**
（V40H ≈2.8×、V10H ≈3.5×、V03H ≈5.0×），且差距来源**分两层**——① **算法层冗余**（可消，占大头）：
自动择优 8 轮 × `apply_mask` 全量 copy + `score` 多趟全矩阵扫描，共 9 次整矩阵 copy、8 轮 × ~4 趟扫描
（≈32 趟）；
② **表示/实现层系数**（难消，残留底）：`Array[Int]`（4B/格 + wasm-gc 托管）vs fast `Module(u8)` 固定数组。
本仓库内部差分已证：V40H 单次 auto ≈7.99ms 中择优管线 ≈**86%**（≈6.86ms，S9b §2），固定 mask 路径仅
≈1.13ms → **优化第一优先级仍是把择优主循环的 copy/扫描成本打下来**（S9b P1 O1-a/O1-b 方向正确），
随后才轮到表示宽度、评分减趟、固定容器分配等系数级优化。

> **预期量级（不承诺，供排序）**：仅落地 O1-a/O1-b（免 8 次 copy + 省末次 copy）+ mask 判定特化，
> V40H 边际有望从 ≈9.01ms 降至 **≈5–6.5ms**；再叠加评分减趟（O2）望向 **≈4–5ms**（fast 3.18ms 的
> 1.3–1.6×）。V03H 等小版本因固定开销占比高、绝对耗时小（<0.35ms），优化优先级低。

---

### 1. 数据基础（本文评估所依据的实测）

#### 1.1 层②边际成本与每模块成本（N 扫描 LSQ，R=5，串行；见 S9c 详细分析 §2）

| 基准点 | 模块数 | 边际 moon (ms/build) | 边际 fast (ms/build) | fast/moon | 每模块 moon (µs) | 每模块 fast (µs) |
|--------|-------:|---------------------:|---------------------:|----------:|-----------------:|-----------------:|
| V03H | 841 | 0.3041 | 0.0611 | **0.20×** | 0.362 | 0.0726 |
| V10H | 3249 | 1.1623 | 0.3352 | **0.29×** | 0.358 | 0.1032 |
| V40H | 31329 | 9.0074 | 3.1848 | **0.35×** | 0.287 | 0.1017 |

> 每模块成本已剔 run 级进程启动（moon 侧 a≈23–34ms/run，fast≈0），是「纯单次 build 摊到每格」的量级口径。
> **注意**：V03H 的每模块成本内含不可忽略的**每次 build 固定开销**（分配、容量选择、编码等），故不能简单
> 解释为 V03 单格比 V40 贵；纵向应看同侧趋势（moon 0.29–0.36µs 窄带、fast 0.07–0.10µs 窄带）+ 横向比值。

#### 1.2 内部差分模型（S9b §2，wasm-gc 单次 build；层②为其跨库外延）

| 基准点 | 单次 auto | 单次 fixed（无择优） | 择优管线开销 | 择优占 auto |
|--------|------:|------:|------:|------:|
| V03H | 0.39ms | 0.169ms | ≈0.22ms | ≈57% |
| V10H | 1.08ms | 0.233ms | ≈0.85ms | ≈73% |
| V40H | 7.99ms | 1.13ms | **≈6.86ms** | **≈86%** |

- **对齐关系**：层② V40H 边际 9.01ms（wasm 后端）与内部 auto 7.99ms（wasm-gc）量级一致；固定/择优比
  说明**版本越大、择优占比越高** → 优化择优主循环对 V40H 收益最大，与大版本是 QR 成本主体的直觉一致。
- **跨库含义**：fast_qr-wasm32 的 V40H **自动**路径只花 3.18ms 就完成了 MoonBit 需要 ~9ms 的同语义工作
  （fast 也要做 8 轮择优，见其 `placement.rs::place_on_matrix` 逐轮 `qr.clone()+mask+score`）——这证明
  **「8 轮择优」本身不是 3× 差距的理由，差距在于每轮实现的效率**（拷贝宽度、扫描趟数、判定方式）。

---

### 2. 热点代码核对（把「评估」钉在实码上）

> 本节逐段核对当前实码，标注每个成本项对应的行；与 S9b 路线互相印证并补充「表示宽度」「判定特化」两个维度。

#### 2.1 `create_auto_qr` —— 择优主循环（`lib/internal/matrix/placement.mbt:109-132`）

```
base = create_matrix(size)          // 1 次，size² 分配
place_on_matrix_data(base, ...)
for k in 0..8:
    masked = apply_mask(base, k)    // 每轮 1 次整矩阵 copy（8 次）
    s = score(masked, size)         // 每轮 ~4 趟全矩阵扫描（8 轮 ≈32 趟）
create_matrix_format_info(base, best)
masked_out = apply_mask(base, best) // 末尾再 1 次整矩阵 copy（第 9 次）
```

- **与 S9b 一致的结论**：9 次整矩阵 copy（V40 每次 31329 格 × 4B ≈ 125KB）+ 评分扫描是主体。
- **新增证据**：fast_qr 同路径（`placement.rs` 每轮 `let mut copy = qr.clone()`）但每格只 1B、且 clone 是
  u8 固定数组整块拷贝 → 同算法结构下 moon 每轮内存搬运 4×。⇒ **表示宽度是系数差的一部分，见 2.5。**

#### 2.2 `apply_mask` —— 掩码应用（`lib/internal/matrix/datamasking.mbt:38-53`）

- `let out = m.copy()`：**无论哪一轮都先整矩阵 copy**（S9b O1-a 靶点：toggle 是自逆操作，可 `就地翻转 →
  score → 还原`，免 copy）。
- 双重扫描成本：外层逐 (y,x)，每格调 `mask_at(x,y,mask_idx)`（含 `match mask_idx` 8 分支判别）+ 
  `is_data_byte`；fast 侧为 **8 个独立特化函数**（`mask_checkerboard/horizontal/…`），每格无分支判别，
  只按公式步进翻转 → **moon 每格多一次 match 分派**，V40H 8 轮 ×31329 格 ≈ 25 万次无谓 match。
  ⇒ **新候选优化：mask 判定特化/提升**（见 §4 T4）。

#### 2.3 `score` —— 4 规则评分（`lib/internal/matrix/score.mbt:32-192`）

- `score()` = `line_rows`（N1+N3 行，一次遍历同时结 run 与 pattern）+ `line_cols`（N1+N3 列，按
  `m[i*size+col]` 跳访）+ `score_dark`（全扫计数）+ `score_squares`（行对滑窗）≈ **4 趟全矩阵**/轮；
  列评分按 S5 铁律须在掩码后做（历史 bug），**趟序不可随意省**，但行/列 N1+N3 已在同趟合并（S9b 已记录）。
- 每行 `line_score(fn(i){ m[base+i] }, size)` 以**闭包**传入行的取数函数：wasm-gc 下闭包每行分配/调用
  有额外开销；fast 用**行切片引用 + 内联**（`&qr[row]`、行间同一函数体）。⇒ 系数级小优化（P2）。

#### 2.4 `wrap_packed` / `QRCode.data` —— 固定容量分配（`lib/qr_build.mbt:57-82`、`lib/qr.mbt:22-37`）

- `wrap_packed` 每 build 分配 `Array::make(QR_MAX_MODULES, …)`（**恒 31329 格**），再只填前 `size²` 格；
  小版本（V03 只需 841 格）**分配了 ~37× 于实际**。这是 S9b O3 靶点。
- `QRCode.data` 为公共固定容量容器（`pub(all)` 字段、测试断言 `length()==QR_MAX_MODULES`），改按 size²
  分配属**公共接口语义变更**（渲染/序列化可能依赖整表长度），需先评估再动（S9b O3 备注一致）。
- **层②旁证**：V03H 的固定开销（含此分配）占单次 build 比重高，导致小版本**差距最大**（fast/moon 比最小
  0.20×，即 MoonBit 慢 ~5×）。

#### 2.5 表示宽度与容器 —— 系数差的「底」

| 维度 | 本仓库 MoonBit | fast_qr Rust |
|------|----------------|--------------|
| 工作矩阵 | `Array[Int]`（**4B/格** + 托管/GC + 边界检查） | `[Module; 31329]` 固定数组，`Module(pub u8)` **1B/格** |
| copy 粒度 | `m.copy()` 按格（4B×size²） | `qr.clone()` u8 数组整块 memcpy |
| 访问 | 每格 `Int` 装载/改写 | u8 内联值语义 |
| 评分扫描 | 行闭包 + 列跳访 | 行切片内联 + 列跳访（同为 i*size+col） |

- 层②每模块成本 moon 0.29–0.36µs vs fast 0.07–0.10µs 的**窄带差（≈3–5×）**即由此类系数构成。
- ⚠️ **注意**：将工作矩阵从 `Array[Int]` 改 `Array[Byte]` 或位打包是**内部介质级重构**（涉及
  `internal/matrix` 全部文件 + `packed` 语义 + 评分/掩码/放置位运算），属「系数级、改面大」项，须单独
  实验验证（MoonBit Byte 运算是否真的省、wasm 后端收益多少）再决定（§4 T6）。

#### 2.6 后端口径注记（解释为什么不能用 wasm-gc 横向比 fast）

- 层②跨语言对比受宿主约束只能用 `wasm`（WASI）产物：`wasm-gc` 仅 `moon run` 宿主、无 Node 对等宿主可
  **同进程**直调 fast_qr。而本仓库内部层①（S9 记录）实测 wasm-gc 比 wasm **快约 1.2–1.4×**。
- 含义：层②表里 MoonBit 的数字是「wasm（较慢后端）」口径；若未来有 wasm-gc 的 Node/宿主通道，本仓库
  相对 fast_qr 的实测差距会再收窄 ~1.2–1.4×。**这属于口径说明，不改变优化方向**（两后端的择优主循环
  成本结构相同，优化对两端同效）。

---

### 3. 差距归因（为什么 fast/moon 随版本从 0.20× 升到 0.35×）

| 基准点 | 单次固定开销占比 | 择优占 auto | fast/moon | 主要成因 |
|--------|:---:|:---:|:---:|---------|
| V03H | **高**（矩阵小，固定项主导） | 57% | 0.20× | 每次 build 固定开销（容量选择、分配、wrap 整表 31329 格）摊到 841 格 → 占比大 → 差距最大 |
| V10H | 中 | 73% | 0.29× | 择优管线渐为主、矩阵增大，固定开销占比下降 |
| V40H | 低（31329 格摊薄） | **86%** | 0.35× | 择优管线（copy+扫描）主导；差距收敛到「每轮实现系数」（宽度 4× + match 分派 + 趟数）≈2.8× |

- **一句话**：版本小 → 固定开销主导（**优先治「分配/容器」**）；版本大 → 择优管线主导（**优先治
  「copy+扫描+判定」**）。QR 真实场景中 V10-V40 是主流（承载字节多），故**治大版本择优管线收益最高**。

---

### 4. 优化候选项评估（含预期量级/风险/影响面）

> 排序 = 预期收益 × 确定性 ÷（风险×影响面）。所有项**不得改变输出明暗/元数据语义**（快照逐位 diff + 109
> 测试 + 双后端 checksum 兜底，见 §6）。

#### T1（P1，S9b O1-a）：`apply_mask` 就地翻转，免 8 次整矩阵 copy
- **做法**：toggle 为自逆（`b ^ 1`，`lib/internal/matrix/module.mbt:73`）。每轮改为「就地 toggle 当前 mask → score →
  就地还原」，单 `base` 缓冲复用；末尾最优轮与还原合并，把 9 次 copy 中 **8 轮 copy** 消掉。
- **铁律**：列评分必须在掩码后做 → 就地形态下 score 仍在已掩码视图（逐格即时翻转）执行，勿提前取列。
- **预期**：V40H 择优 6.86ms → 望 **≈3–4.5ms**（S9b 估 3~4ms）；V40H 边际 9.01 → **≈5–6.5ms**。
- **实测（2026-09-06，见 本文件「O1 实施记录」部分）**：按原形落地后
  **V40H marginal +~8%（409 vs 384ms）——否决**：每轮多 1 趟真实判定扫描换掉 1 次 memcpy 净亏；
  copy 非大头、score 多趟扫描才是。改为开放项，主攻方向转 T3（O2 减趟）。
- **风险**：中（score 对已掩码视图的时序铁律易错）；影响面：`datamasking.mbt` + `placement.mbt` 局部。
- **自检**：快照零差异 + 双后端 checksum 不变即安全。

#### T2（P1，S9b O1-b）：复用最优轮矩阵，省末尾第 9 次 copy
- **做法**：择优循环记住最优轮**已掩码矩阵**，末尾 `masked_out=apply_mask(base,best)` 改为直接把真实
  Format 覆写到最优轮掩码矩阵上（Format 位非 Data、mask 不触及，逐位等价）。
- **预期**：−≈1/9 择优 copy（V40H ≈0.5–0.8ms）；风险低、改动极小。
- **实测（2026-09-06）**：**已落地**，V40H marginal 9.0074→8.8742ms（≈−1.5%）；sha256/快照/109 全保持
  （见 本文件「O1 实施记录」部分）。

#### T3（P1，S9b O2）：`score` 融合减趟
- **做法**：N4 dark 计数并入已有趟（如 `line_rows`/`line_cols` 顺带累加暗模块）；`score_squares` 是否可与
  行列趟共享局部窗口另实验。保留 4 规则分值逐位不变。
- **预期**：V40H 择优中扫描趟数 ~4 → ~3 趟，再削 **≈10–20%** 择优成本；风险中（评分是对齐敏感区）。

#### T4（P1，新补充）：mask 判定特化/提升（消除每格 `match mask_idx`）
- **做法**：仿 fast 8 特化函数，或把 `mask_at(x,y,idx)` 的外层 `match` 提升为「每轮一个闭包/一函数」，
  内层只做坐标公式；或将布尔判定预计算成只对命中格迭代。消除 8 轮×size² 次 match 分派。
- **预期**：V40H ≈25 万次无谓 match 消掉，望 **−5–10%** 择优成本；风险低；影响面 `datamasking.mbt`。
- **注意**：与 T1 就地翻转天然配套（翻转前判一次即可），建议与 T1 同批做、独立提交便于回归定位。

#### T5（P2，S9b O3）：`wrap_packed` 按 `size²` 分配（需先评估公共容器语义）
- **做法**：wrap 只分配 `size²` 的本地缓冲、完成后再铺入 `QRCode.data`（整表仍 31329 由公共契约决定），
  或先做**不改公共字段**的内部化分配。
- **预期**：小版本（V03-V10）单次 build 降固定开销，**改善 V03H 类小版本的比值**（0.20× → 望 0.3×+）；
  V40H 影响小（31KB/125KB 已被摊薄）。风险：公共 `data` 长度语义，需先确认序列化/渲染不依赖整表。

#### T6（P2/实验，新补充）：表示宽度 `Array[Int]` → 更窄介质
- **做法**：internal/matrix 工作矩阵改 `Array[Byte]`（或保持 Int 但**预分配复用**），验证 wasm 后端
  内存搬运 4× 收窄的实测收益。
- **预期**：系数级，V40H 或再 −10–25%；**但改动面大**（全部 internal 位运算/评分/放置/测试白盒断言），
  且 MoonBit Byte 运算/边界是否真的更快需**先做独立微基准**（放 /tmp，勿入库），确认正收益再动。
- **风险**：高（回归面大）；建议排 T1–T5 之后，作为第二阶段候选。

#### T7（P3/不推荐现阶段）：跨 build 复用/缓冲池
- QRBuilder 不可变式接口 + 多线程/并发场景下**全局池有状态风险**，现阶段不做；若未来做服务端高吞吐，
  可考虑 build 内部局部复用（如 `create_matrix` 缓冲），单列评估。

#### T8（口径项，非代码）：后端选择与对比通道
- 层②维持 `wasm` 口径不变（无 Node 对等宿主）；在文档中明示「MoonBit 另快 1.2–1.4× 的 wasm-gc 口径
  未参与跨库计时」。优化对两后端同效。

---

### 5. 实施顺序与预期（组合量级，不承诺）

| 批次 | 内容 | V40H 边际预期 | V40H fast/moon 预期 | 验收 |
|------|------|--------------:|--------------------:|------|
| 现状 | — | 9.01ms | 0.35×（2.8× 慢） | 层②表 |
| 批 1（部分落地） | T1（O1-a 就地翻转）+T2（O1-b 复用最优轮） | T1 **实测否决**（+~8%）；T2 已落地 −1.5%（9.007→8.874ms） | T2 后 0.35×→≈0.355× | 快照 diff + checksum + bench-layer2 |
| 批 2（主攻，见实施记录 §4） | T3（减趟）+T4（mask 特化） | ≈4–5ms | ≈0.65–0.8×（1.25–1.5× 慢） | 同上 |
| 批 3 | T5（小版本容器） | V03H 类改善 | V03H 0.20→0.3×+ | 同上 |
| 批 4（可选） | T6（表示宽度实验后定） | 再 −10–25%？ | 视实验 | 先微基准 |

> **2026-09-06 实测更新**：批 1 中 **T1（O1-a 就地翻转）落地后实测否决**——V40H marginal 反而 +~8%
> （409 vs 384ms），因 copy 是轻量 memcpy、score 多趟判定扫描才是大头，就地翻转用真实扫描换 memcpy
> 净亏；**T2（O1-b 复用最优轮）落地有效**（V40H marginal 9.0074→8.8742ms ≈ −1.5%，sha256/快照/109 全
> 保持）。**主攻方向据此转向批 2 的 T3（O2 score 减趟，score 4 趟→3 趟）**；实施细节与数字见
> 本文件「O1 实施记录」部分。
>
> **明确不承诺**：因表示/托管系数残留，把 V40H 拉平到 fast_qr 的 3.18ms（1.0×）在**不改内部介质**的
> 前提下不现实；roadmap S9 行本来就是「透明对比，无硬门槛」。

---

### 6. 验收口径（沿用 S9b §5 + S9c 同一把尺子）

每一步独立提交，须过：

1. **快照逐位 diff 零差异**（mask 择优结果与 S1-S7 参考一致；用既有快照测试）。
2. **109 测试全绿**：`moon fmt --check` / `moon check --deny-warn` / `moon test`（wasm-gc/wasm）。
3. **双后端 checksum 不变**：wasm-gc/wasm 各点 `cmd/bench` 的 `TOTAL_CHECKSUM`（82000/32400/9200）。
4. lib 公共 `.mbti` 零漂移（T1-T4 只动 internal/matrix，天然满足；T5 若动 `wrap_packed` 私有函数也满足；
   T6 若动内部介质，需确认 public 类型字段未变）。
5. **优化前后同一把尺子**：每批落地后用 `bash scripts/bench-layer2.sh` 复跑，对照 S9c 详细分析 §2 的
   N 扫描（R=5、逐点串行）记录边际/每模块/比值变化，回填本文 §5 表。

---

### 7. 明确不做 / 边界

- **不改择优语义**：mask 选择结果、评分 4 规则、与 fast_qr/参考快照的逐位一致性，全部不可变。
- **不做 native 对比**：层③仍需 C 工具链 + fast_qr native 环境，属可选量级注记，非本阶段。
- **不追平每模块 0.07–0.10µs**：那是 Rust `release`+u8 固定数组+LLVM 的系数下限；MoonBit wasm 在合理
  重构内只求把比值从 2.8× 收到 1.2–1.6×，不作不现实承诺。
- **本轮未改代码**：本文为评估文档；落地批次需另立实施任务并遵守 roadmap「S5 O1 主循环重构单列 P2」约束。

---

### 8. 参考

- 层②实测：[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
  （N 扫描边际/每模块/启动分解）、[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
- 优化路线底稿：本文件「评估与路线」部分（P1/O1、P2/O2/O3、验收口径）
- 层①/口径：[S9-性能基准.md](./S9-性能基准.md)（wasm-gc vs wasm 1.2–1.4×）
- 实码：`lib/internal/matrix/placement.mbt`（create_auto_qr）、`datamasking.mbt`（apply_mask/mask_at）、
  `score.mbt`（score 4 规则）、`lib/qr_build.mbt`（wrap_packed/build/build_fixed）、`lib/qr.mbt`
  （QR_MAX_MODULES 固定容器）
- 参考 fast_qr v0.14.0：`src/placement.rs`（8 轮 clone+mask+score）、`src/datamasking.rs`（8 个 mask 特化
  函数）、`src/score.rs`（u8 Module 行切片评分）、`src/qr.rs`（`[Module; QR_MAX_MODULES]` 固定数组）

---

## O1 实施记录

> 承接 本文件「评估与路线」部分（P1/P2 路线）与
> 本文件「再评估与实施建议」部分（T1–T6 实施批建议）。
> 本文记录第一批优化（P1 中 **T2 = S9b O1-b**）的落地与实测，并记录 **T1（S9b O1-a）实测否决**的
> 证据与结论——用「同一把尺子」（S9c 层② N 扫描 marginal）量化前后差异。
> 日期：2026-09-06　｜　范围：只改 `lib/internal/matrix/placement.mbt`（自动择优末段），
> **未动** score/datamasking/qr_build 与公共 API；快照/checksum/层② sha256 全保持。

---

### 0. 一句话结论

- **T2（O1-b）落地**：把「择优后在 base 上再 `apply_mask` 一次（第 9 次整矩阵 copy）」改为**复用最优轮
  已掩码矩阵**、把真实 Format 直接覆写其上 → 省 1 次整矩阵 copy（V40 = 31329 格 × 4B ≈ 125KB）。
  语义逐位不变（快照 + 层② sha256 + 双后端 checksum 全绿）。
- **T1（O1-a 就地翻转）实测否决**：按建议实现「就地 toggle → score → 再 toggle 还原」后，
  V40H marginal **变慢约 8%**（slope 9.007→9.77 ms，整程 384→409ms）——原因见 §3。
  已回退，T1 不再按原形落地（保留为「若改成**单缓冲 + 预判**再评估」的开放项）。
- 净效果（T2 一个点）：V40H marginal slope **9.0074 → 8.8742 ms（≈ −1.5%）**，V03H/V10H 同向略降；
  属小步、低风险、可复现的 O1-b 增量。

---

### 1. 落地内容（T2，`placement.mbt`）

#### 1.1 改动点

改前（`create_auto_qr` 末段）：
```
8 轮择优…选 best_mask
create_matrix_format_info(base, size, ecl, best)   // 真实 Format 写进 base
let out = apply_mask(base, size, best)             // 第 9 次整矩阵 copy（125KB@V40）
(out, best)
```
改后：
```
8 轮择优…选 best_mask，并记住 best_masked（该轮 apply_mask 的副本）
create_matrix_format_info(best_masked, size, ecl, best)  // Format 覆写到已掩码矩阵
(best_masked, best)
```

- **等价性依据**：`apply_mask` 只翻 **Data** 类模块；Format/功能图案位不是 Data、mask 不触及。
  故「真实 Format 覆写到**已掩码**矩阵」与「先写 base 再 apply（copy 保留 Format 位）」逐位等价——
  由既有 109 测试 + S6 快照 + 层② sha256（三矩阵与 fast_qr-wasm32 逐字一致）三重验证。
- **无回归面**：不改 score、不更 apply_mask 语义（`apply_mask` 仍返回新矩阵供固定 mask 路径与
  择优轮使用）、不改 `QRCode` 容器；`lib` 公共 `.mbti` 零漂移。

#### 1.2 为何收益「小」而非 S9b 预期的大

- S9b §2 内部模型（wasm-gc 单点）估 O1-a 削 8 轮 copy 可把 V40H 择优 6.86ms → 3–4ms；其隐含前提是
  **copy 是大头**。层② marginal 实测（wasm 后端）显示：真正大头是 **8 轮 × score 多趟扫描**（每轮
  ~4 趟全矩阵），copy 的绝对占比有限；去掉 1 次 copy 只带来 ~1.5%——**与 S9b 模型的方向一致但量级
  校正**（详见 §3、§4）。

---

### 2. 验收（全绿）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test            # 109 全绿
for t in wasm-gc wasm; do moon build lib --target $t --release; \
  moon build cmd/bench --target $t --release; moon test --target $t; done
# cmd/bench 默认输出逐字不变：
#   V03H 2000 builds checksum=82000 / V10H 400 →32400 / V40H 40 →9200；TOTAL_CHECKSUM=123600
# 层② 三矩阵 sha256 与 fast_qr-wasm32 逐字一致（V03H 4942f6aa… / V10H 91c85c94… / V40H c3c04930…）
```

---

### 3. T1（O1-a 就地翻转）实测否决：数据与结论

#### 3.1 尝试的实现

把每轮 `apply_mask(base,k)`（copy+翻）改为：`apply_mask_inplace(base,k) → score(base) → 再 inplace
还原`，意图免 8 次整矩阵 copy。

#### 3.2 实测（同一把尺子：层② N 扫描 R=5，moonrun 整程取最小）

| 形态 | V40H N=40 (ms) | V40H marginal slope (ms/build) | vs 基线 |
|------|---------------:|-------------------------------:|--------:|
| 基线（改前） | 384.02 | 9.0074 | — |
| T1 inplace 双翻转 | **409.43** | ~9.77 | **+~8% 更慢** |
| T2（O1-b，本文） | 381.04 | 8.8742 | −1.5% |

#### 3.3 为什么更慢（分析）

- **每轮成本构成**：`copy`（整块 memcpy，带宽型、常数小）远低于 `score` 的 **多趟带判定的全矩阵扫描**
  （每轮 ~4 趟 × 逐格类型/明暗/窗口判定）。
- T1 每轮 = 就地翻(1 趟) + score(4 趟) + 还原翻(1 趟) ≈ **5 趟扫描 + 无 copy**；
  基线每轮 = copy(≈0.3 趟带宽) + 翻(1 趟) + score(4 趟) ≈ **5 趟扫描 + 1 次轻量 copy**。
  即 T1 用「一次真实扫描」去换「一次 memcpy」，**净亏**；且 wasm 下 Array copy 编译器常做整块优化。
- **结论**：O1-a 的收益模型把 copy 高估了；本仓库 wasm 后端上「免 copy」必须**连 score 趟数一起降**
  才有正收益（即 O2/T3 方向），单纯就地翻转不划算。**本文保留 T1 开放但不按原形落地**。

---

### 4. 后续（未做/开放，按再评估建议排序）

- **T3（O2 score 融合减趟）**：`score()` 现 ~4 趟/轮；把 N4 dark 计数并入已有趟（如 `line_rows`/
  `line_cols` 顺带累计）→ 每轮 ~3 趟。这才是把「score 大头」打下来的路径；因 score 是对齐敏感区，
  需**逐步独立提交 + 快照逐位 diff + 层② sha256** 兜底（本文未越界）。
- **T4（mask 判定特化）**：消除每格 `match mask_idx`——可与 T3 同批或独立，先微基准验证收益。
- **T5（wrap_packed 按 size² 分配）**：涉公共 `QRCode.data` 固定容量容器语义，**需先评估接口影响**
  （S9b O3 备注一致），未动。
- 每步沿用 S9c 详细分析 §2 的 N 扫描同一把尺子（R=5、逐点串行、LSQ marginal）记录前后差异。

---

### 5. 汇总

1. **T2（O1-b）已落地**：复用最优轮掩码矩阵 + 真实 Format 覆写其上，省第 9 次整矩阵 copy；语义逐位
   不变，109 测试 + 快照 + 双后端 checksum + 层② sha256 全绿。
2. **实测量级**：V40H marginal 9.0074 → 8.8742ms（≈ −1.5%）；说明 copy 非大头，收益模型需校正
   （大头 = score 多趟扫描）。
3. **T1（O1-a 就地翻转）实测否决**：V40H marginal +~8%；「免 copy」在本后端不如直接优化 score 趟数。
4. 后续建议主攻 **T3（O2 减趟）**，独立提交并以快照逐位 diff + 层② sha256 兜底。

---

### 6. 参考

- 优化路线：本文件「评估与路线」部分
- 实施建议（T1–T6）：本文件「再评估与实施建议」部分
- 同一把尺子/基线：[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
- 实码：`lib/internal/matrix/placement.mbt`（create_auto_qr 末段；其余未动）

---
