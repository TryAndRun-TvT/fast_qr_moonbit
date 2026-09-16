# S9m · ReadOnlyArray 适用性评估（修订）

> **状态**：历史　｜　日期：2026-09-12　｜　索引：[docs/README.md](../README.md) §7　｜　并入：结论已并入 [S9n](S9n-优化方案复评与wasm-gc收敛审计.md)（已否决项）

> 承接 [S9k（成本分解）](S9k-性能瓶颈与理论上限评估.md) 与
> [S9l（fast_qr 参考）](S9l-参考fast_qr高性能实现分析.md)：回答
> **「MoonBit core 的 `ReadOnlyArray[T]` 对本项目是不是合适/最优的选择？能不能用来提速？」**
> 并对早期结论做一次**自审式修订**（找漏洞、纠量级、收敛到 `wasm-gc` 单一口径）。
>
> 方法 = ① core 源码级事实；② 官方月报/文档与编译器 lint 既有结论；③ 本项目数组盘点；
> ④ **真实代码 A/B 受控实验**（临时把 `reedsolomon` 的真实模块级表换 `ReadOnlyArray` 后实测，
> 再还原）+ 工作区复用对照；⑤ lint 命中审计。
>
> 日期：2026-09-11　｜　环境：`moon 0.1.20260904`、**仅 `wasm-gc` release**（`moonrun` 边际斜率）
> ｜　范围：**分析 + 临时探针实验；未保留任何入库代码改动**（表替换测毕 `git checkout` 还原，探针测毕即删）。
>
> > 项目决策：`wasm`(WASI)、`js` 后端均已移除，**现仅支持 `wasm-gc`**。本文所有结论只针对 `wasm-gc`。

---

## 0. 结论先行

1. **类型选择：对「纯读查找表」`ReadOnlyArray` 是最佳**——它是 `FixedArray` 的**零成本类型封装**
   （core 用 `%identity` reinterpret，`readonlyarray.mbt:16-23`），读路径与 `FixedArray` 逐指令相同，
   但**没有 set 方法**（不可变由类型系统保证），且是**官方指定的查找表容器**、被官方 lint 推荐。
   对只读表，它同时满足「语义正确 + 零开销 + 官方优化/lint 认可」三者，优于 `Array`（多一层间接）
   与 `FixedArray`（可变、语义不精确）。
2. **但它不是本项目的性能杠杆**。真实代码 A/B（wasm-gc，真实 V40H 的 15B 块）：
   RS `division` 表 `Array[Byte]` → `ReadOnlyArray[Byte]`，**division 实测 ≈1.25–1.29×**；
   外推到 V40H 整 build 仅 **≈0.4–0.5%**。原因：RS 全链只占 V40 单次 auto 的 **≈2.5%**（S9k），
   即使把 RS 做得再快，整 build 收益仍是百分位级。
3. **它救不了两大瓶颈**（机制层，见 §4）：V40 `score`（68%）需要**就地写**且读成本不变；
   V03 `wrap`（44%）是**逐格对象装箱税**，与容器可变性无关。
4. **官方「静态初始化」红利在 `wasm-gc` 上不适用**：官方明确保证只写在 **C/LLVM/Wasmlinear** 后端；
   `wasm-gc` 上 `ReadOnlyArray` 的收益只剩**消除 `Array[T]` 的 `{buf,len}` 二层间接**（即上面的 ≈1.25×）。
5. **真正更该优化的是 RS 的分配，而不是表容器**：`division` 每次 `Array::make(255)`（+ 余数分配）
   在 15B 短块下占可观比例；改**复用工作区**实测 ≈1.13×（与表容器改动**相互独立**）。
   但其上限同样受「RS ≈2.5%」约束 → RS 两项合计最好也就 ≈0.6–0.7%。**主攻方向仍是 S9l 的 P0–P3。**
6. **修订要点（自审发现的问题，见 §3.4）**：早期稿用**运行时构造的局部表**做代理、并把
   `wasm`(WASI) 后端一并讨论，均已被本稿替换为**真实模块级字面量表的直接 A/B**与 **wasm-gc 单口径**。

**一句话**：把 `ReadOnlyArray` 用于**只读字面量表**（T-R1/T-R2）是**用对类型**，值得做，但请按
**≈0.5% 的语义/体积对齐**预期，不要当性能杠杆；要把 RS 再压一点，优先做**分配消除**，但两者都受
「RS 仅占 2.5%」封顶。

> **复评修订（2026-09-12，见 [S9n](S9n-优化方案复评与wasm-gc收敛审计.md)）**：口径微调——上文的
> 「RS 占 2.5%」精确应为 **`pipe`(encode+RS) 占 2.5%，RS 单项更低**（结论更保守）；且 T-R1 的容器收益
> 与 P3 介质窄化同属「表示层」，落地前须做 `Array[Int]`/`FixedArray[Byte]`/`Bytes` 三向微基准，避免重复计数。

---

## 1. 表示与官方定位（wasm-gc）

### 1.1 core 源码级事实

```moon
// readonlyarray.mbt:16-23（core builtin）
fn[T] ReadOnlyArray::unsafe_reinterpret_to_fixed_array(self) -> FixedArray[T] = "%identity"
fn[T] unsafe_reinterpret_from_fixed_array(arr : FixedArray[T]) -> ReadOnlyArray[T] = "%identity"
```

- 所有方法都是**先 identity 转回 `FixedArray` 再转发**；`%identity` 是 no-op → **读路径与
  `FixedArray` 逐指令相同**，零运行时开销。
- **无任何 set/swap/fill**；不可变性由类型系统在编译期保证。
- `ReadOnlyArray::from_array(view)` = `FixedArray::from_array` = **逐元素拷贝**（`fixedarray.mbt:644`）
  ——「从可变 `Array` 转只读」**不是零成本视图**；常量表应直接用 `ReadOnlyArray` 字面量。

### 1.2 官方文档/月报既有结论

| 来源 | 结论 |
|------|------|
| 月报 Vol.05（2025-11-03） | 新增 `ReadOnlyArray` 内建类型，**"mainly used as lookup tables"**；**全字面量表在 C/LLVM/Wasmlinear 后端保证静态初始化** |
| 月报 Vol.06（2025-12-02） | 功能完善；**"编译器会针对 ReadOnlyArray 做更多的性能优化"** |
| 月报 Vol.07（2026-01-12） | 新增 lint：只读数组字面量提示改用 `ReadOnlyArray`/`FixedArray`；**默认关闭** |
| 编译器 lint `E0065` | *"Consider using ReadOnlyArray[T] for better performance and smaller code size."*（本仓库实测触发） |

> **`wasm-gc` 边界**：静态初始化的官方保证**不含 `wasm-gc`**。因此在本项目唯一目标后端上，
> `ReadOnlyArray` 的收益只能是**布局收益**（§3 实测），不应计入「启动/静态表」红利。

### 1.3 容器表示对比（wasm-gc）

| 容器 | 表示 | 每次访问 | 可变 | 适用 |
|------|------|---------|------|------|
| `Array[T]` | `{ buf : UninitializedArray[T], len : Int }`（`arraycore_nonjs.mbt:16-19`） | 载入 buf + 越界检查 + 索引（**两层**） | ✅ | 需增长/追加 |
| `FixedArray[T]` | 定长连续数组 | 越界检查 + 索引（**一层**） | ✅ | 定长可写 |
| `ReadOnlyArray[T]` | = `FixedArray[T]`（identity） | 同 FixedArray（**一层**） | ❌ | **只读查找表** |
| `Bytes` | 定长字节 | 一层 | 无公开 setter | 无 |

---

## 2. 本项目数组使用盘点

| 数据 | 容器 | 热/冷 | 占比 | 写需求 | ReadOnlyArray |
|------|------|-------|------|--------|----------------|
| 工作矩阵 `m : Array[Int]`（internal/matrix） | `Array[Int]` | **热** | score 68% / mask 11% | **就地写** | ❌ 不适用 |
| RS 表 `log/antilog`（`reedsolomon.mbt:17,280`） | `Array[Byte]` | 热（division 内层） | pipe 2.5% 的大头 | ❌ 纯读 | ✅ **适用** |
| 其余常量表（capacity/generator/format/groups） | `Array[Byte]`/嵌套 | 冷 | 可忽略 | ❌ 纯读 | ✅ 适用（语义/体积） |
| `CompactQR.data`（bitbuffer） | `Array[Byte]` | 中 | pipe 内微小 | 追加写 | ❌ |
| `QRCode.data`（`qr.mbt:26`） | `Array[Module]` | 构建期写、此后读 | **V03 44% 载体** | 构建期逐格写 | ⚠️ 类型可换，装箱税不变 |
| `structure` 输出（reedsolomon） | `Array[Byte]`（5430） | 冷-中 | pipe | 逐字节写 | ❌ |

---

## 3. 受控实验（真实代码 A/B + 工作区复用）

### 3.1 方法（消除早期「代理」漏洞）

- **A/B 直测真实代码**：临时把 `lib/internal/reedsolomon/reedsolomon.mbt` 的两个**真实模块级
  字面量表**类型标注 `Array[Byte]` → `ReadOnlyArray[Byte]`，编译后测**真实 `@reedsolomon.division`**，
  测毕 `git checkout` 还原（无入库改动）。这样测的就是**真实字面量表 + 真实访问路径**，非代理。
- 探针（临时包，测毕删）：以真实 **V40-H `get_polynomial(39,3)`**（31 taps）为除式；数据块两档
  **15B（真实 V40H 每块规格）**与 **220B（上限，220+31≤256）**；逐位对拍余数校验和；
  N / N÷2 整程**边际斜率**、`R=5` 取最小（bash `TIMEFORMAT='%R'`）。
- 对照组 `reuse`：副本用**预分配并复用**的 255B 工作区替代每次 `Array::make(255)`，
  与 `arr`（每次分配）同表同数据，隔离「分配税」。

### 3.2 结果（wasm-gc，µs/division，边际斜率）

**真实代码 A/B（改真实表）**

| 表容器 | 15B（真实 V40H） | 220B |
|--------|-----------------:|-----:|
| `Array[Byte]`（基线，两次复测） | 1.64 / 1.69 | 23.2 / 25.6 |
| `ReadOnlyArray[Byte]` | **1.31** | **19.4** |
| 比值 | **≈1.25–1.29×** | 1.20–1.32× |

**分配税对照（副本，15B）**

| 变体 | µs/division | 比值 |
|------|------------:|-----:|
| 每次 `Array::make(255)`（`arr`） | 1.58 | 1.00× |
| 复用工作区（`reuse`） | **1.40** | **≈1.13×** |

> - 结论一：**表容器改动 ≈1.25×**，且来自**布局**（省一层 `{buf,len}` 间接），与官方静态初始化无关。
> - 结论二：**分配消除 ≈1.13×**，是**独立**于表容器的另一项；两者可叠加。
> - 噪声提示：220B 档基线两次为 23.2 / 25.6 µs（≈10% 抖动），故 220B 比值区间偏宽；
>   真实块长（15B）的两档复测更稳定，取 **≈1.25×** 为对外口径。

### 3.3 外推到整 build（量级估算）

- V40H = **81 个块**（20×15B + 61×16B；`data_codewords(3,39)=1276`，81×30 ECC，合计 3706 ✓）。
- 表容器：`Array` ≈81×1.68 = **136 µs** → `ReadOnlyArray` ≈81×1.31 = **106 µs**，省 **≈30 µs**；
  相对 S9k V40 auto **5.90 ms** ≈ **0.5%**（按 1.64 基线则 ≈0.45%）。
- 叠加分配消除（≈1.13×）：再省 ≈12–20 µs，合计 ≈**0.6–0.7%**。
- 硬上限：S9k `pipe`(encode+RS) V40 = **0.1475 ms = 2.5%**——**RS 再怎么优化，整 build 收益 <2.5%**。

### 3.4 早期方案的漏洞与修订（自审）

| # | 漏洞 | 影响 | 修订 |
|:-:|------|------|------|
| F1 | 用**运行时构造的局部表**做代理，未测真实**模块级字面量**表 | 结论可能不可迁移 | 本稿改为**直接改真实表 A/B**，比值由 1.22× 修正为 **≈1.25×**（方向一致，量级确认） |
| F2 | 并列讨论 `wasm`(WASI) 后端，引入无关变量 | 分散口径、易误读 | 按项目决策**移除 wasm**，本稿**仅 wasm-gc** |
| F3 | 把「静态初始化/更小体积」隐含为收益 | `wasm-gc` 无此保证，夸大 | 明确**静态初始化只在 C/LLVM/Wasmlinear**；wasm-gc 只算布局收益 |
| F4 | 外推假设 division 占 pipe 大头、整函数比值可平移 | 0.5% 属估算，非直测 | 标注为**量级估算**；真实整 build 增量 ≈0.03 ms 低于 `bench.sh` 分辨率，无法直接观测 |
| F5 | 把 T-R1 作为「性能项」与 S9l P0 同批「捎带」 | 高估其价值 | 降级为**语义/类型对齐**（收益 ≈0.5%），不当作性能里程碑 |
| F6 | 未量化分配税 | 漏掉同量级、更本质的杠杆 | 新增 `reuse` 对照：**≈1.13×**，并指明受 `pipe=2.5%` 封顶 |
| F7 | 官方 lint 覆盖面未说明 | 可能误以为「开 lint 就能管住表」 | 实测 lint **只命中函数局部字面量**，**不覆盖模块级表**（见 §5） |

---

## 4. 为什么它救不了两大瓶颈（机制层）

1. **score（V40 68%）**：评分前矩阵已被 `apply_mask` **就地翻转**（S9b 已否决「免写」换拷贝）；
   评分是**读+算**型，读成本 = `FixedArray`（S9l 实测介质换字节也仅 1.26×）。
   `ReadOnlyArray` 既不能用于写阶段，也不改变读成本。
2. **wrap（V03 44%）**：成本 = 固定 31329 槽 + 逐格 `Module` **对象分配**（`Array[Module]` 填格比
   `Array[Int]` 慢 ≈10×，S9k §3.3）。`ReadOnlyArray[Module]` 仍是**引用数组、逐格托管对象**，
   装箱税与可变性无关。
3. **防御性拷贝非热点**：`CompactQR::data()` 每 build 拷 ≈1.3KB、`QRCode::data()` 无生产调用方，
   量级为 µs。

---

## 5. 可落地项（修订后）

| 编号 | 项 | 做法 | 预期 | 风险 |
|------|----|------|------|------|
| **T-R1** | RS 表只读化 | `reedsolomon.mbt:17,280` 两表标注 `ReadOnlyArray[Byte]` | division **≈1.25×**；整 build **≈0.5%** | 极低（internal，`.mbti` 不变；余数逐位不变由 109 测试兜底） |
| **T-R2** | 常量表 + 局部字面量 | `internal/constants` 纯读表、生产局部 `offsets`（`matrix.mbt:59`）、`pad`（`bitbuffer.mbt:129`）改只读 | 语义/体积；无可测 per-build 收益 | 极低 |
| **T-R3** | `QRCode.data` 只读化 | `Array[Module]` → `ReadOnlyArray[Module]`，`data()` 免拷贝 | 性能≈0；语义收益 | **中**：`pub(all)` 类型变更，单独评审 |
| **T-R5** | **RS 分配消除**（独立杠杆） | `division`/`slice`/`structure` 复用预分配工作区（对照 fast_qr 栈数组） | division **≈1.13×**；整 build ≈0.2%；**受 pipe 2.5% 封顶** | 中（须逐位对拍 + 复用正确性论证） |
| **T-R4** | 启用 lint（可选） | `moon.pkg` 加 `+prefer_readonly_array` | 防回归；**只覆盖函数局部字面量** | 低 |

**lint 审计（`moon check --warn-list "+prefer_readonly_array"`）**：命中 4 处——生产 `offsets`、`pad`；
测试 `mods`、`bits`。**模块级表（`log_table`/`antilog_table` 等）不被 lint 覆盖**，故 T-R1 必须人工做。

> **建议**：T-R1/T-R2 **作为类型对齐**低优先落地（不单列为性能里程碑）；T-R5 是 RS 侧更本质的杠杆，
> 但两者都**不应占据优化主线**——主线仍是 S9l **P0 掩码特化 / P1 容器 / P2 评分**。

> **落地记录（2026-09-12，见 [S9n §6.5–6.6](S9n-优化方案复评与wasm-gc收敛审计.md)）**：**T-R1/T-R2/T-R4 已实施**——
> RS 两表、全部常量表与局部只读字面量（`offsets`/`pad`/测试 `mods`/`bits`/`sizes`）改为 `ReadOnlyArray`；
> `get_polynomial`/`alignment_grid` 改**零拷贝只读视图**（免 `.copy()` 分配）；`moon.mod` 启用
> `prefer_readonly_array` lint（实测生效、当前零命中）。验证：111 测试 + `TOTAL_CHECKSUM` 三点一致 +
> `QR_MIN_CHECKSUM=283` + lib 公共 `.mbti` 零漂移。
>
> **性能复验（同日受控探针 ABAB，详见 [S9n §6.6](S9n-优化方案复评与wasm-gc收敛审计.md)）**：
> 真实块长（15B）`division` **≈1.30–1.34×**（本文历史口径 ≈1.25×，同向确认）、220B 档 ≈1.6–1.9×；
> 整 build V40 实测 Δ≈40µs/build ≈ **0.9%**（分母由 5.90ms 缩至 4.42ms，故高于本文按旧基线外推的
> ≈0.5%）——定性不变：**类型对齐为主、有限性能为辅，非性能杠杆**。T-R3 维持不做；T-R5 待做。

### 明确不做

- **不**用 `ReadOnlyArray` 重构工作矩阵/评分/掩码（与 S9l 实测方向相悖）；
- **不**把 `ReadOnlyArray::from_array` 当零成本视图（它是拷贝）；
- **不**计入 `wasm-gc` 的「静态初始化/启动」红利（官方保证不含该后端）；
- **不**为这 ≈0.5% 单独跑长周期 bench 立项（低于 `bench.sh` 分辨率）。

---

## 6. 验收与复现

- 门禁：快照逐位 diff、全量单测全绿、`TOTAL_CHECKSUM`、层② sha256（见 [S9b §5/§6](S9b-性能优化.md)）。
- 复现（**不出库**；探针 `lib/probe/`，`pkgtype(executable)`，import `internal/{constants,reedsolomon}`）：
  1. A/B：先测基线 `moon run lib/probe --release --target wasm-gc -- real 400000 15`；再把
     `reedsolomon.mbt` 两表标注改 `ReadOnlyArray[Byte]` 重测；测毕 `git checkout` 还原。
  2. `reuse`：副本用预分配 255B 工作区，隔离分配税。
  3. 计时：宿主对 N 与 N/2 整程取最小算斜率（`R=5`，bash `TIMEFORMAT='%R'`；zsh 不生效）。
  - **坑**：`division` 前置 `data.length()+by.length() <= 256`；表替换后余数必须逐位不变。

---

## 7. 参考

- core 源码：`builtin/readonlyarray.mbt`（identity、`from_array` 拷贝、无 set）、
  `builtin/arraycore_nonjs.mbt:16-19`、`builtin/fixedarray.mbt:644`
- 官方文档/月报：[Vol.05](https://www.moonbitlang.com/updates/2025/11/03/index) ·
  [Vol.06](https://www.moonbitlang.cn/updates/2025/12/02/index) ·
  [Vol.07](https://www.moonbitlang.cn/updates/2026/01/12/index) ·
  [E0065](https://docs.moonbitlang.com/en/stable/language/error_codes/E0065.html)
- 本项目实码：`lib/internal/reedsolomon/reedsolomon.mbt`、`lib/qr.mbt`、
  `lib/internal/bitstream/bitbuffer.mbt:129`、`lib/internal/matrix/matrix.mbt:59`
- 成本依据：[S9k](S9k-性能瓶颈与理论上限评估.md)（五段分解）、
  [S9l](S9l-参考fast_qr高性能实现分析.md)（P0–P4）
- 对外基线：[S9j](S9j-层②统一Node对比-wasm-gc与fast_qr.md) · 门禁 [S9b](S9b-性能优化.md)
