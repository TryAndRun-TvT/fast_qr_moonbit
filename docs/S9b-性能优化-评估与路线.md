# S9b · S9 之后性能优化 · 评估与路线

> 承接已合入的 S9 性能三基准点实现（PR #45，见 [S9-性能基准-实现记录.md](./S9-性能基准-实现记录.md)），
> 本文档对 S9 之后的性能优化做**逐热点评估**：建立进程级差分成本模型、定位头号优化靶点、
> 给分优先级落地路线（P1/P2）与统一验收口径。
> 范围：**纯评估文档、未越界做性能改写**——改写仍遵循 roadmap「S5 O1 主循环重构单列 P2」约束，
> 留给后续专项在前置（本路线）下推进。
> 日期：2026-09-06　｜　前置：S9 基准载体已合入 main（测试 109 基线）。

---

## 0. 一句话结论

**头号优化靶点 = 自动择优 8 轮掩码评分主循环**（`lib/internal/matrix/placement.mbt` 的
`create_auto_qr`，即 S5 评审 §4 O1 所指）。用**进程级差分实测**建立成本模型后确认：8 轮择优开销
随版本**超线性放大**——V40H 时占单次 auto 构建成本约 **86%**（≈6.86ms / 单次 7.99ms）。
非择优管线（encode→structure→matrix→放置→wrap）已相对紧凑、非优先。分优先级给出
P1（O1-a 就地翻转、O1-b 复用最优轮矩阵）与 P2（O2/O3）路线，验收统一走快照逐位 diff +
109 测试 + 双后端 checksum。

---

## 1. 背景与范围

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

## 2. 成本模型（进程级差分实测）

### 2.1 差分口径与可信性

- 环境：容器内自装 MoonBit 工具链，wasm-gc 后端 release 计时（主口径同 S9 层①）。
- 差分：同点同输入，仅差自动择优（`build` mask=None）vs 固定 mask（`build_fixed`，选 S5 实测最优掩码）。
- 可信性交叉验证：
  - CMD 层 `cmd/bench` 数字与 PR #45 入库记录**完全吻合**（V40H N=40 ≈0.45s、`TOTAL_CHECKSUM`=9200）。
  - 常量探针 V40H auto n=100 → 0.78s / n=200 → 1.58s，**线性缩放**，排除死代码折叠。

### 2.2 实测数字

| 基准点 | 单次 auto | 单次 fixed(无择优) | **8 轮择优开销** | 择优占 auto |
|--------|------:|------:|------:|------:|
| V03H | 0.39ms | 0.169ms | ≈0.22ms | ≈57% |
| V10H | 1.08ms | 0.233ms | ≈0.85ms | ≈73% |
| V40H | 7.99ms | 1.13ms | **≈6.86ms** | **≈86%** |

### 2.3 测量坑记录（供后续复测/性能专项避坑）

> **argv 驱动探针会被编译器整段折叠**：若用 `argv` 传入迭代次数驱动循环且结果不消费，MoonBit 编译器
> 会因纯函数/常折叠把整段循环裁掉，得到「0ms」假象。必须用**编译期常量**（如 `let N = 100` 内联）+ 把
> 每轮 `build` 的 `Result` **累加消费**（size+代表性模块字节进 checksum）防空循环。S9 实现记录的
> `cmd/bench` 已按此口径落地，本评估探针同口径。

---

## 3. 逐热点分析（按成本贡献排序）

### 3.1 热点①：`create_auto_qr` 8 轮择优主循环（`placement.mbt:109-134`）——头号靶点

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

### 3.2 热点②：`score` 评分趟数偏多（`score.mbt`）——次要靶点

`score` 现拆 4 趟（N1 行/N3 行、N1 列/N3 列、N2、N4）。其中 N1 与 N3 在 `line_rows`/`line_cols`
内**已同行合并**返回 `(run, patt)`（`line_score` 一趟同时结算 N1 run + N3 pattern 窗口），故「减趟」
空间主要在：能否把 N1 行扫与 N1 列扫合并（现行列分离、列靠 `m[i*size+col]` 跳跃访问）；N4 dark 计数
能否在已有趟顺带累加。属常数系数级优化（P2），收益 < 热点①。

### 3.3 热点③：`wrap_packed` 恒量整表分配（`qr_build.mbt`）

`wrap_packed` 内 `Array::make(QR_MAX_MODULES, ...)` 对**任何版本**都分配整张 `QR_MAX_MODULES`（V40 上限）
容量，再只填前 `size*size` 格——小版本（V01-V10）浪费可观。但该分配每 `build` 只做一次、不随 8 轮放大，
且 `QRCode.data` 为固定容量容器设计（公共类型字段），改按 `size*size` 分配属**接口/容器语义权衡**，非纯
局部改动（见 P2 O3 备注）。

---

## 4. 优化路线（分优先级）

> 全部路线**不得改变输出明暗/元数据语义**；验收统一见 §5。O1/O2 逐步独立提交以缩小回归面兜底。
> 代码改写阶段仍遵循 roadmap「S5 O1 单列 P2」约束——本文档只给路线，不越界落地改写。

### P1 —— 首选落地

- **O1-a 就地翻转（自逆 toggle）免每轮全量 copy**：`apply_mask` 改为**就地** toggle（toggle 为自逆操作：
  `toggle→score→还原` 无净副作用），单 base 缓冲复用，免 8 次全量 copy。但**列评分必须在掩码后做**
  （S5 历史 bug 铁律），故可行形态 = 对当前轮 mask 做 `toggle → score → 还原` 三连，score 仍在已掩码副本
  视角下做（逐格即时翻转），无全量 clone。预期：V40H 择优 6.86ms → ≈3~4ms（削掉 ~4ms copy 大头）。
- **O1-b 复用最优轮矩阵省末尾一次 copy**：择优循环中记下**最优轮已 apply_mask 的矩阵**（O1-a 就地形态下
  即还原前最优点留用），末尾 `masked_out = apply_mask(base, best_mask)`（第 9 次 copy）可直接复用。
  低风险、−≈1/9 择优 copy。

### P2 —— 常数系数级

- **O2 score 融合减趟**：在保持 4 规则分值逐位不变前提下，合并可并行的趟（如 N4 dark 顺带在已有趟计数、
  N1 行列扫的内存布局权衡）；收益为常数系数、风险中等（评分是对齐敏感区）。
- **O3 wrap_packed 按 size*size 分配**：省小版本恒量浪费。⚠️ 需先评估 `QRCode.data` 固定容量容器语义
  （公共字段、快照/API 是否依赖整表），属接口权衡项、非纯局部改动，单列审慎。

### 层②/③ 对比收尾（非性能改写）

- 层②（MoonBit-wasm vs fast_qr-wasm32 逐位对齐 + 同口径计时）与层③（native 注记）仍**待外部环境**
  （具 fast_qr 检出 / C 工具链），达成即收敛 roadmap M3；与本优化路线正交、可并行推进。

---

## 5. 验收口径（统一）

无论 O1/O2/O3 落地与否，性能专项的每步独立提交须过：

1. **快照逐位 diff 零差异**：自动择优输出矩阵对既有 S1-S7 参考快照逐位一致（mask 择优结果不变）。
2. **109 测试全绿**：`moon fmt --check` / `moon check --deny-warn` / `moon test`。
3. **双后端 checksum 一致**：wasm-gc/wasm 各点 `TOTAL_CHECKSUM` 不变（复用 S9 `cmd/bench`）。
4. lib 公共 `.mbti` 零漂移（O1/O2 若只改 internal/matrix 内实现，公共接口不变，天然满足）。

> 目标量级（参考，非承诺）：V40H 单次 auto 由 ≈7.99ms 通过 O1-a 削 8 轮 copy 后望向 ≈3~4ms。

---

## 6. 参考

- 前置：S9 [实现方案](./S9-性能基准-实现方案.md)（PR #42）、[评估记录](./S9-性能基准-实现评估与优化-记录.md)
  （PR #44）、[实现记录](./S9-性能基准-实现记录.md)（PR #45）；roadmap §4.2 S9 / §4.4 M3。
- S5 评审 §4 O1：见 [S5-实现评审与优化-记录.md](./S5-实现评审与优化-记录.md)。
- 实码：`lib/qr_build.mbt`（build/build_fixed/wrap_packed）、`lib/internal/matrix/placement.mbt`
  （create_auto_qr/create_fixed_qr）、`datamasking.mbt`（apply_mask）、`score.mbt`（score 4 规则）。
