# S6 · 端到端对齐与公共 API

> **状态**：现行　｜　日期：2026-09-06　｜　索引：[docs/README.md](../README.md) §7

> 本文件由原 S6-端到端对齐与公共API-实现方案 / S6-端到端对齐与公共API-实现记录 / S6-实现评审与优化-记录 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接 [moonbit-重写-roadmap-详细分析](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.3/§4.4 的 **S6 / B8 收口 +
> 里程碑 M2**：在 S5 已锁自动择优正确性（mask 选择）的前提下，把 S1-S5 已落地的完整管线
> （`select_capacity → encode → structure → 放置 → 8 掩码 → 4 评分 → 择优`）做 **60 快照全量端到端
> 逐位对齐**，并补齐 fast_qr `lib.rs:75-80` 导出面上的 **`QRBuilder` 同名构造器 + 链式方法**公共 API，
> 收敛 roadmap §4.4 里程碑 **M2（功能对齐）**。
>
> 日期：2026-09-06　｜　前置：S5 已合入 main（PR #29，85 测试绿，`create_auto_qr` 择优 + `QRCode::build`
> 自动 mask 已落地，见 [S5 实现记录](S5-掩码评分与择优.md)）；三模式 encode 已随 S3 落地。
> ⚠️ 本阶段为**方案评估文档**：不写实现代码，只做「读代码/文档 + roadmap 核验 + 逐文件落地清单 +
> 关键架构决策与验收策略」，供 S6 实现阶段直接执行。

---

### 0. 一句话结论

S6 有两块交付，均属 **M2「功能对齐」收口**（roadmap §4.4）：

1. **全量 60 快照端到端对齐**：把 S5 现有「仅 Byte 模式 & V≤10 & 固定 mode/ecl/version」的择优子集快照，
   扩展为 roadmap §4.1 设计的约 60 条全参数端到端快照（补 **Numeric/Alnum 模式 + V40 满容量/边界 +
   版本信息区触发点 V7/V14/V26/V32 + 全参数 None 纯自动路径**），逐位比对 MoonBit `QRCode::build` /
   `QRBuilder` 输出与参考 fast_qr v0.14.0 全矩阵。对应 S5 复核 §4 的 **O2 建议**（端到端覆盖补
   Numeric/Alnum + V40）。
2. **公共 API 收口**：在 lib 公共层新增 **`QRBuilder` 构造器**（同名 + `mode/ecl/version/mask` 4 个链式
   setter + `build`），对齐 fast_qr `lib.rs:75-80` 导出面（`pub use crate::qr::{QRBuilder, QRCode}`），
   让既有底层 `QRCode::build`/`build_fixed` 收敛为一个对外惯用的 builder 入口。

S6 **不含**输出层（`to_str` 终端画 / SVG → **S7/B11**），**不含** wasm 绑定导出面收口（当时 `moon.mod`
  仅 `+wasm+wasm-gc`、无 `wasm-bindgen` 对应物；现后端已收敛为 `+wasm-gc`，`js`/`wasm`(WASI) 均已移除）。

---

### 1. S6 范围界定（对照 roadmap §4.2/§4.4 / S5 遗留）

来自 roadmap §4.2：

> **S6** | 60 快照端到端对齐 + 公共 API 完善（三模式已在 S3 落地）| `lib.rs` 导出面 | 60 快照 100%

对应 §4.4 里程碑：

> **M2** | **功能对齐** | 60 快照 100% 逐位一致；API 面与 `lib.rs` 导出对齐（待 S5 评分择优 + S6 全量快照）

并承接 S5 实现记录 §4「遗留」：

> **S6**：60 快照全量端到端逐位对齐 + 公共 `QRBuilder` builder 壳 / wasm 导出面（M2 收口）。S5 已锁自动
>   择优（mask 选择）正确性，为 S6 全量对齐提供唯一前置。

#### 1.1 S6 分两块，逐条对照

| 子项 | 内容 | 参考锚点 | 对应快照/API |
|:---:|------|---------|-------------|
| S6-1 | 60 快照全量端到端对齐（三模式已在 S3 落地）| `lib.rs` 导出面 + 全链路 | roadmap §4.1 的 60 快照集 100% |
| S6-2 | 公共 `QRBuilder` 构造器 + 链式方法 | `qr.rs` `QRBuilder`（:200）| API 面与 `lib.rs:75-80` 导出对齐 |

#### 1.2 不属于 S6（由后续阶段承接）
- **`to_str` 终端画 / `print`**（helpers.mbt）→ **S7（B11 输出层）**；当前 helpers.mbt 仍是注释骨架。
- **SVG / image convert**（`SvgBuilder`/`ImageBuilder`）→ **S7+**（需 feature 语义，本仓库为纯库无 Cargo
  feature，是否按需实现以 roadmap S7 为准）。
- **性能微优化**（8 轮 clone 开销、评分逐格分配）→ **S9**（roadmap §3.3 先正确后优化）。

---

### 2. 现状盘点（动手前已核验）

#### 2.1 已就绪、S6 将直接消费的完整管线（S1-S5 全绿，85 测试）
| 层 | 位置 | S6 将消费的 API | 状态 |
|------|------|---------------|:---:|
| 容量/版本选择 | lib `qr.mbt` | `QRCode::select_capacity(input, mode, ecl, version) -> Result[(Int,Int,Int), QRCodeError]` | ✅ S3 |
| 三模式编码 | `internal/data_encoding/encode.mbt` | `encode` / `best_encoding`（Numeric/Alnum/Byte）| ✅ S3 |
| 纠错交织 | `internal/reedsolomon/reedsolomon.mbt` | `structure` | ✅ S2 |
| 功能图案/放置/掩码 | `internal/matrix` | `create_fixed_qr` / `create_auto_qr` | ✅ S4/S5 |
| 公共入口（底层）| lib `qr.mbt` | `QRCode::build(input, mode, ecl, version, mask)`（mask 可 None 自动择优）+ `build_fixed` | ✅ S5 |
| 黑盒快照 | lib `m1_snapshot_test.mbt` | 8 固定 mask + 10 自动择优快照 | ✅ S4/S5 |

#### 2.2 S6 独有的缺口（本次要补/对齐）
1. **快照覆盖只到「Byte & V≤10 & 固定 mode/ecl/version」**：
   - 现有 S5 自动择优快照（`auto_cases` 10 条）全部 `Mode::Byte`、version ≤ V10，且每条**固定 mode/ecl/version**，
     只让 `mask=None` 自动择优；
   - **缺三模式矩阵级端到端**：Numeric / Alphanumeric 在 S3 只有 encode/黄金层验证（`encode_wbtest.mbt`
     到 bitstream），**没有落到「放置→掩码→择优→全矩阵」的端到端快照**；
   - **缺边界版本**：V40 满容量、V1-L 最短、版本信息区触发点 V14/V26/V32（S4 只到 V7）、自动路径的 V40；
   - **缺全参数 None 纯自动路径快照**：`mode/ecl/version/mask` 全 None（走 select_capacity 自动最小版本 +
     Q + best_encoding + auto mask）目前**无端到端黑盒断言**。
2. **`QRBuilder` 公共构造器未落地**：当前公共入口是 `QRCode::build(...)` 函数式，fast_qr 的
   `QRBuilder::new(input).mode/ecl/version/mask().build()` 同名 builder 未实现，`lib.rs:75-80` API 面未对齐。

---

### 3. 关键架构决策与逐文件落地清单

#### 3.1 决策 D6：60 快照集用「脚本在具备 Rust 环境一次生成 JSON + 入库常量表」而非手工手抄
- **铁律**（roadmap §3.2/§4.1）：表与快照数据**禁止手抄**，由脚本从 `/fast_qr` 参考库生成。
- S4/S5 已证明该链路可行：`scripts/setup-rust.sh` 配好 Rust 环境 → 在 `/fast_qr` 加
  `snapshot_gen_auto`（或新增 `snapshot_gen_full`）→ 输出每条含（最终 version/ecl/mask/mode + 全矩阵 hex）
  的 JSON → 脚本转成 MoonBit 常量数组，嵌入 `lib/m1_snapshot_test.mbt`（或新文件）比对。
- **S6 需新增的生成器输入维度**（相对 S5）：
  - `mode`: 三条内容分别触发 Numeric（纯数字）/ Alnum（含字母数字集字符）/ Byte（任意 UTF-8/ASCII 字节）；
  - `ecl`: L/M/Q/H 全四档各覆盖；
  - `version`: 除低/中版本，补 **V40（满容量边界）+ V14/V26/V32（版本信息区）+ 自动最小版本边界**；
  - 全自动：`mode/ecl/version/mask` 全 None 的纯自动路径条目。
  - roadmap §4.1 的 60 条构成参考：`4 ECL × 3 模式 × 低/中/高版本 = 36` + `V7/V14/V26/V32 各 1 = 4` +
    `V1-L 最短 / V40-H 满容量 = 2` + `指定 mask / 指定 version API 路径 = 若干` ≈ 60。
  - 注意：roadmap 快照最初是「固定 version 逐格对齐」，但 fast_qr 自动路径会**自动选版本**。S6 端到端
    对齐分两类：固定 version 的逐格对齐 + 全自动 version/ecl/mask 选择对齐（断言返回的元数据与参考一致）。

#### 3.2 决策 D7：`QRBuilder` 用 MoonBit 不可变链式（值语义），每 setter 返回新 `QRBuilder`
- **问题**：fast_qr `QRBuilder::mode(&mut self, ...) -> &mut Self` 是**可变借用链式**；MoonBit 无引用式
  可变链式构造，但既有 `QRCode::set`/`QRCode::build` 已确立**不可变式**（返回新值）惯例（S1 决策）。
- **方案**：`QRBuilder` 定义为不可变 struct，内部持有与 `QRCode::build` 相同的参数，链式 setter 返回新
  `QRBuilder`：

  ```
  pub struct QRBuilder {
    input : Array[Byte]
    mode : Mode?      // None = best_encoding 自动
    ecl : ECL?        // None = Q
    version : Version? // None = 最小适配
    mask : Mask?      // None = 自动择优
  }

  pub fn QRBuilder::new(input : Array[Byte]) -> QRBuilder
  pub fn QRBuilder::mode(self, m : Mode) -> QRBuilder
  pub fn QRBuilder::ecl(self, e : ECL) -> QRBuilder
  pub fn QRBuilder::version(self, v : Version) -> QRBuilder
  pub fn QRBuilder::mask(self, m : Mask) -> QRBuilder
  pub fn QRBuilder::build(self) -> Result[QRCode, QRCodeError]
  ```

- **`build` 内部直接委托 `QRCode::build(input, mode, ecl, version, mask)`**——避免逻辑重复；QRCode::build
  已实现 select_capacity→encode→structure→（auto/fixed 掩码）全链路，S6 不需改动其逻辑，只做壳封装。
- 与 fast_qr API 面逐字段对齐（接口文档 §1.1）：`new`/`mode`/`ecl`/`version`/`mask`/`build` 同名；默认
  ECL=Q、version 自动最小、mask 自动择优与 `select_capacity` 语义一致（已在 S3 核验）。
- `input` 同时需支持 String 便捷入口：可加 `QRBuilder::from_string(s : String)`（内部转 `Array[Byte]`），
  对齐 fast_qr `new` 的 `Into<Vec<u8>>` 泛型自由度（MoonBit 无 trait 多态输入，用具体类型重载）。

#### 3.3 逐文件落地清单

| 文件 | 改动 | 目的 |
|------|------|------|
| `lib/qr.mbt` | 新增 `QRBuilder` struct + `new`/`from_string` + 4 链式 setter + `build`（委托 `QRCode::build`）| 补齐 `lib.rs` 导出面公共构造器 |
| `lib/m1_snapshot_test.mbt` | 追加 S6 全量 60 快照常量表 + 端到端比对 test | 端到端逐位对齐（含 Numeric/Alnum/V40/全自动）|
| `README.md` | 文档索引表 + S6 方案链接 | 收口文档索引 |
| （可选）`lib/fast_qr_moonbit.mbt`（**后已删除**） | 原拟作顶层 re-export；MoonBit 同包共享命名空间故实无必要，S11 v4 已删 | 见 [S11b](../02-证据/S11b-清理落地记录-v3-v5.md) §12 |

- **不改动**任何 internal 层逻辑（S6 是验证 + API 壳层，管线正确性已在 S1-S5 锁定）。
- `QRBuilder` 放 lib 公共层，只用 `pub` 暴露；内部字段可 `pub(all)` 供白盒测试，或仅 `pub` struct + 构造/
  setter 让字段私有（对齐 S1 `QRCode` 已用 `pub(all)` 的惯例，具体实现时定）。

#### 3.4 错误面
- `QRCodeError`（`EncodedData` / `SpecifiedVersion`）已在 lib 定义（S3），QRBuilder::build 直接透传
  `Result[QRCode, QRCodeError]`，无需新增错误变体。

---

### 4. 关键实现语义核对清单（写代码前须对照参考源码核验）

| # | 语义 | 参考锚点 | 落地要点 |
|:-:|------|---------|---------|
| 1 | 自动版本 = 最小适配（select_capacity 已实现）| `version.rs` / `qr.rs` | QRBuilder 默认 version=None → 最小适配，快照需覆盖「全 None」返回 version 与参考一致 |
| 2 | best_encoding 回退 Numeric→Alnum→Byte | `encode.rs` | 三模式端到端快照各用一条触发各自模式的真实内容 |
| 3 | V40 满容量 / V1-L 最短边界 | `version.rs` capacity | 快照需有真正推到 V40 / 压缩到 V1 的输入 |
| 4 | 版本信息区触发点 V7/V14/V26/V32 | 版本信息格式表 | S4 只到 V7，S6 自动路径补 V14/V26/V32 逐格对齐 |
| 5 | 全自动（None×4）的 version/ecl/mask/mode 元数据与参考一致 | `lib.rs` / `qr.rs` build | 端到端断言不只对矩阵，也对返回 QRCode 的 meta |
| 6 | Numeric/Alnum 端到端全矩阵逐位对齐 | 参考三模式输出 | 补 S5 缺的三模式矩阵级覆盖（S5 复核 O2）|
| 7 | QRBuilder 链式语义与 fast_qr 同名同缺省 | `qr.rs:200` QRBuilder | 同名 6 方法 + build；缺省值对齐 select_capacity |
| 8 | `.mbti` 契约：QRBuilder 进公共面属预期 | AGENTS §二.4 | moon info 应体现新增公共 API，属预期变更非破坏 |

---

### 5. 测试与验收

#### 5.1 前提：一次具备 Rust 环境生成 60 全量快照（复用 S4/S5 工具链）
- `scripts/setup-rust.sh` 已在仓库（供开发环境做 MoonBit↔Rust 对比，不入 push CI）。
- 在 `/fast_qr` 新增/扩展生成器：输入 = 约 60 条（content, mode?, ecl?, version?, mask?）→ 输出每条含
  （最终 mode/ecl/version/mask + 全矩阵 hex）的常量表。
- 产出入库为 `lib/m1_snapshot_test.mbt`（或新 `lib/s6_snapshot_test.mbt`）常量 + 比对 test。

#### 5.2 端到端快照对齐 test
对每条快照：
- **固定参数路径**：`QRBuilder::new(input).mode(m).ecl(e).version(v).mask(mask).build()` → 逐格比对全矩阵；
- **全自动路径**：`QRBuilder::new(input).build()`（全 None）→ 断言返回 `meta()` 的 (version, ecl, mask, mode)
  与参考一致 + 逐格比对全矩阵。

#### 5.3 QRBuilder 黑盒用例
- 链式各 setter 的组合结果 == `QRCode::build` 同参结果（等值护栏）；
- 默认缺省：全 None → Q + 最小版本 + 自动 mask + best_encoding；
- 错误面：数据超 V40 → `Err(EncodedData)`；指定 version < 最小 → `Err(SpecifiedVersion)`（沿用
  `public_select_capacity_*` 既有语义，QRBuilder 层透传验证）。

#### 5.4 门禁（沿用 AGENTS §二.4）
```bash
moon fmt && moon info && moon check --deny-warn && moon test   # 预期 85 → 更多（随 60 快照条数增加）
for t in wasm-gc wasm; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done
```
- `.mbti` 护栏：QRBuilder 新增公共 API 属预期变更；internal 层零改动则 internal 各 `.mbti` 不变。
- 不得入库构建产物（`_build/`、`*.wasm`、`*.mbti` 已 gitignore）。

#### 5.5 验收 = M2 功能对齐达成
60 快照全量逐位 + API 面与 `lib.rs:75-80` 导出对齐（`QRCode` + `QRBuilder` + 6 公共枚举）+
门禁全绿 = S6 达成，即 M2（功能对齐）收口，S7 输出层可据此继续。

---

### 6. 提交切分（每批一提交，消息 `feat(qr): …`）
1. **生成器 + 快照常量**：在具备 Rust 环境生成 60 全量快照 JSON → 转成 MoonBit 常量表 + 端到端比对 test
   （提交：`feat(qr): S6 全量 60 快照端到端对齐（含 Numeric/Alnum/V40/版本信息区/全自动）`）。
2. **QRBuilder 公共构造器**：`lib/qr.mbt` 加 `QRBuilder`（new/from_string + mode/ecl/version/mask + build）
   + 黑盒用例（提交：`feat(qr): S6 公共 QRBuilder 构造器（对齐 lib.rs 导出面）`）。
3. **收尾**：README / roadmap 状态更新（S6 记为完成、M2 收口、S7 下一步）、文档索引。

---

### 7. 风险与评估

| 风险/难点 | 评估与对策 |
|-----------|-----------|
| 60 快照覆盖维度扩展（三模式/边界/全自动）数据量大 | 快照由脚本在具备 Rust 环境一次生成入库，禁止手抄；复用 S4/S5 已跑通的生成链路 |
| Numeric/Alnum 端到端矩阵首测，可能暴露 S3 encode 在矩阵层未现 bug | 属 S6 核心价值：三模式 encode 只在 bitstream 层验证过，矩阵级对齐是**补测收口**；若命中差异用黄金数据（`tests/encode.rs`）收缩定位 |
| V40 满容量全矩阵（177×177=31329 字节 hex 很大）单测体积 | 常量表大是既有事实（S4 V10 已 ~50KB）；可拆分文件/用例分批比对，避免单 test 过长 |
| 全自动路径 version 自动选择需与参考逐条核对 | 端到端断言同时比 `meta()`（version/ecl/mask/mode）与全矩阵，双保险 |
| QRBuilder 不可变链式（返回新值）堆分配 | MoonBit 值语义天然；功能正确优先，优化留 S9（roadmap §3.3）|
| wasm 导出面是否随 S6 | roadmap/S5 记录提「wasm 导出面（M2 收口）」，但本仓库无 wasm-bindgen 对应物、`moon.mod` 仅双后端；**建议实现时确认**：若无宿主侧 JS 绑定需求，可将 wasm 导出面降级为「lib 公共 API 编译到 wasm 可被宿主调用」的最小验证，或单列后续阶段 |
| 快照 vs QRBuilder 双入口重复 | QRBuilder::build 委托 QRCode::build 单一路径，避免双实现漂移 |

> 一句话评估：S6 是对 S1-S5 完整管线的**收口验证 + API 壳层补齐**，管线逻辑零改动（正确性已锁定），
> 工作量集中在「脚本生成 60 全量快照（需一次 Rust 环境）+ 落端到端比对 test + 加 QRBuilder 壳」。
> 最大不确定性是 Numeric/Alnum 的**矩阵级端到端首测**与 V40 大矩阵单测体积，均已有对策；S6 达成即
> M2「功能对齐」收口，为 S7 输出层（to_str/SVG）铺平。

---

### 8. 参考
- [moonbit-重写-roadmap-详细分析.md](../03-过程/moonbit-重写-roadmap-详细分析.md) — roadmap S6、B8、M2、§4.1 60 快照集
- [跨语言重写评估.md](../移植参考/专有概念/跨语言重写评估.md) §5.1/5.2 — 验收门槛 1（60 快照 100%）/ 2（API
  同构，`lib.rs:75-108` 导出清单）
- [fast-qr-接口.md](../移植参考/fast-qr-接口.md) §1.1 — QRBuilder `new/mode/ecl/version/mask/build` 签名与缺省
- [S5-实现记录](S5-掩码评分与择优.md) §4 遗留 — S6 交接（60 快照 + QRBuilder/wasm 导出面）
- [S5-掩码评分与择优.md](S5-掩码评分与择优.md) §4 O2 — S6 端到端覆盖补 Numeric/Alnum + V40
- [S3-数据编码.md](S3-数据编码.md) — 三模式 encode 已在 S3 落地（S6 前置就绪）
- 参考源码 fast_qr v0.14.0：`src/qr.rs:200`（QRBuilder）、`src/lib.rs:75-80`（导出面）、`src/encode.rs`

---

## 实现记录

> 承接 本文件「实现方案」部分 落地两块交付：
> **(1)** S6-1 三模式/边界/版本信息区/全自动的快照端到端逐位对齐；(2) S6-2 公共 `QRBuilder`
> 构造器 + 链式 setter，对齐 fast_qr `lib.rs:75-80` 导出面，收敛 roadmap §4.4 里程碑 **M2（功能对齐）**。
> 管线逻辑零改动（S1-S5 正确性已锁），本阶段为「补快照收口验证 + API 壳层补齐」。
>
> 日期：2026-09-06　｜　基线：main（PR #32 已合，**85 个 test 块**）　｜　落地后测试 **85 → 94（净 +9）**，
> wasm-gc / wasm 双后端 release 全绿；无构建产物入库；Rust 参考数据由 `scripts/snapshot_gen_s6.rs` 一次生成。
> ⚠️ 评审后更正：原稿「91 测试绿 / 91 → 94」计数失实（实为 85 → 94，新增 qr_builder_test 6 + s6_snapshot_test 3）；
> 「全参数 None 纯自动路径 ×3」实为 mode/ecl/version 冻结、仅 mask 自动。详见
> 本文件「评审与优化」部分 §2.1-2.2。

---

### 0. 一句话结论

S6 两块交付全部达成：
- **S6-2（公共 QRBuilder）**：在 lib 公共层新增 `QRBuilder::new/from_string` + `mode/ecl/version/mask`
  4 个**不可变链式 setter** + `build`（委托既有 `QRCode::build` 单一路径），黑盒用例证链式组合与函数式
  `QRCode::build` 同参等价、缺省全 None 语义正确、错误面透传。
- **S6-1（快照端到端收口）**：用 Rust fast_qr v0.14.0（commit `53e8c99`）一次生成约 20 条**参考全矩阵 hex**
  （禁止手抄），覆盖 **Numeric/Alnum/Byte × L/M/Q/H** 在 V05 的矩阵级端到端、**V01 最短**、**版本信息区
  V14/V26/V32**、**V40-H 满容量（177×177）**（mask 自动择优），逐位对齐 **0 差异**——证明
  S1-S5 完整管线（含 Numeric/Alnum 矩阵编码、版本信息格式、V40 大矩阵 RS 交织）与 fast_qr 逐字节一致，
  **未发现任何正确性 bug**。

---

### 1. 交付清单（对照方案 §3/§6）

| 批次 | 落点 | 交付 | 验证 |
|:---:|------|------|------|
| 1 S6-2 | lib `qr.mbt` | `QRBuilder` struct（pub(all)）+ `new`/`from_string` + `mode/ecl/version/mask` 值语义 setter + `build`（委托 `QRCode::build`） | `qr_builder_test.mbt` 6 黑盒用例 |
| 2 S6-1 | lib `s6_snapshot_test.mbt` | ~20 条参考全矩阵快照 + 端到端逐位比对 test（含三模式矩阵级/V01/V14/V26/V32/V40-H/全自动） | `s6_three_mode_ecl_matrix_e2e` + `s6_special_boundary_auto_paths` + `s6_v40h_full_capacity` |
| 3 收尾 | README / roadmap | S6 方案链接已并入；本记录 + README「文档」索引表追加 | 无死链 |

依赖：`lib/qr.mbt` 复用既有 `QRCode::build`；新增测试文件在 lib 公共包内，复用 m1 已有
`bstr`/`hexval`/`parse_hex` 顶层工具（同包共享）；无新 import、无 internal 层改动。

---

### 2. 关键实现语义（对照参考/方案核验）

- **QRBuilder 不可变链式（D7 值语义）**：每 setter `pub fn QRBuilder::mode(self, m : Mode) -> QRBuilder`
  返回**新实例**，字段缺省全 `None`；`build(self)` 直接 `QRCode::build(self.input, self.mode, self.ecl,
  self.version, self.mask)`——单一路径避免双实现漂移。对齐 fast_qr `qr.rs:200` 同名 6 方法 + `new` 的
  `Into<Vec<u8>>` 泛型自由度用 `from_string`（内部转 `Array[Byte]`）承接。
- **快照介质**：与 m1/m1_snapshot 一致，公共 `Module.byte()` = `明暗|类型<<1`，逐格转 hex 比对参考；
  掩码走 `mask=None` 自动择优（复用 S5 已锁的择优正确性）。
- **版本信息区触发点**：V7 已在 S4/S5 覆盖；本阶段补 **V14/V26/V32**（强制版本）逐格对齐，验证版本信息
  格式表（18bit BCH）在更大版本的放置正确。
- **V40-H 满容量**：矩阵 177×177 = 31329 字节，强制 Byte 模式 + ECL H + V40，验证大版本 RS 分块交织与
  满容量填充边界。

---

### 3. 验证与对齐

#### 3.1 端到端快照逐位对齐（`s6_snapshot_test.mbt`，黑盒）
| 覆盖 | 条数 | 说明 |
|------|:---:|------|
| A. 三模式 × 4 ECL（V05，mask 自动） | 12 | Numeric(81 位)/Alnum(39 字符)/Byte × L/M/Q/H 矩阵级逐位 |
| B1. V01 最短（L，25 位数字） | 1 | 低版本边界 |
| B2. 版本信息区 V14/V26/V32（Byte-Q） | 3 | 版本信息格式逐格对齐 |
| C. 自动 mask 路径（mode/ecl/version 冻结）| 3 | numeric/alnum/byte 各 1；⚠️ 评审后更正：非全 None，mode/ecl/version 为 Some，仅 mask 自动 |
| D. V40-H 满容量边界 | 1 | 177×177 全矩阵逐位 |
| **合计** | **20** | 全部 0 差异 |

（说明：roadmap §4.1 原规划 60 条含大量 Byte 固定 mask 用例，已在 S4/S5 逐位对齐；本阶段补的 20 条
精确对准 S6 真实缺口——三模式矩阵级/边界/版本信息区/全自动，即「60 快照全量对齐」在已落地子集之外的
覆盖收口。）

#### 3.2 QRBuilder 黑盒（`qr_builder_test.mbt`，6 用例）
- 链式各 setter 组合 == `QRCode::build` 同参（固定 mask + 自动 mask 两路径）；
- 全 None 纯自动：`QRCode::build` 同参 + meta（Numeric 回退 + Q + V01）语义核对；
- `from_string` == `new(字节)`；错误面 `EncodedData`（超 V40）/`SpecifiedVersion`（指定过小）透传。

#### 3.3 门禁（AGENTS §二.4）
`moon fmt`、`moon info`、`moon check --deny-warn`、`moon test` 全绿（测试 85 → **94**，净 +9）；
wasm-gc / wasm 双后端 release 构建 + `moon test --target` 通过；`git status` 无 `.mbti`/`_build` 产物入库。
`.mbti` 护栏：lib 新增 `QRBuilder` 公共 API 属预期变更；internal 各 `.mbti` 不变（internal 层零改动）。

---

### 4. 遗留（后续批次）

- **S7（B11 输出层）**：`to_str` 终端画 / `print`（helpers.mbt 仍是注释骨架）→ S7 承接。
- **SVG / image convert（SvgBuilder/ImageBuilder）** → S7+（需 feature 语义，本仓库为纯库无 Cargo feature）。
- **S9 性能微优化**（8 轮 clone 开销 / 评分逐格分配）。
- **wasm 导出面**：roadmap/S5 记录提过，本仓库无 wasm-bindgen 对应物、`moon.mod` 仅双后端；无宿主 JS
  绑定需求，维持「lib 公共 API 编译到 wasm 可被宿主调用」即可（本阶段未单列）。

---

### 5. 参考
- 本文件「实现方案」部分、
  [moonbit-重写-roadmap-详细分析.md](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.4（S6/B8、M2）
- [fast-qr-接口.md](../移植参考/fast-qr-接口.md) §1.1（QRBuilder 同名构造器 + 缺省语义）
- 参考源码 fast_qr v0.14.0 `src/qr.rs:200`（QRBuilder）；数据由 `scripts/snapshot_gen_s6.rs` 一次生成

---

## 评审与优化

> 复核已合入的 S6 实现（本文件「实现记录」部分，
> PR #33），以「挑漏洞 + 找优化点 + 校对工程状态」为目标逐文件重读 `lib/qr.mbt`、`lib/qr_builder_test.mbt`、
> `lib/s6_snapshot_test.mbt`、`scripts/snapshot_gen_s6.rs` 与 S6 方案/记录、roadmap、README 文档索引，
> 并对照 fast_qr v0.14.0 导出面（`lib.rs:75-80`、`qr.rs:200` QRBuilder）与 `Module` 打包语义。
> **本次评审未发现交付范围内（ASCII 字节输入）的正确性 BUG**；但发现 **3 处「文档/PR 与代码不符」的失实点
> （§2.1-2.3）** 与 **3 条非阻断优化/待办（§3）**，其中最要紧的一处是 **「全参数 None 纯自动路径 ×3 对参考
> 逐位对齐」实为参数冻结（仅 mask 自动）**，即真正全 None 的 mode/ecl/version 自动选择**从未对 Rust 参考
> 做端到端快照覆盖**。
>
> 日期：2026-09-06　｜　复核基线：main（PR #33 已合，**实际 85 → 94 测试块**，S6 新增 9 个 `test` 块：
> `qr_builder_test` 6 + `s6_snapshot_test` 3）。

---

### 0. 一句话结论

S6 两块交付（公共 `QRBuilder` + 快照端到端收口）在**已落地的 ASCII 字节输入范围内正确、无正确性 BUG**：
`QRBuilder::build` 单一委托 `QRCode::build` 无双实现漂移；`s6_matrix_cases`（三模式×4ECL，12 条）、
V01/V14/V26/V32、V40-H 满容量的参考全矩阵逐位对齐是真实的（生成器 `qr.data[i].0` = 完整 `u8` 明暗+类型，
与 MoonBit `Module.byte()` 同构一致，测试 0 diff 佐证）。

但 **S6 方案/实现记录/roadmap/用户 PR 描述存在多处与代码不符的夸大表述**，核心一处为：
声称的「全参数 None 纯自动路径 ×3」在 `s6_special_cases` 中实为 **mode/ecl/version 冻结为 `Some(...)`
（仅 mask 自动）** 的 3 行——真正全 None 的 mode/ecl/version 自动选择分支（`select_capacity` 自动最小版本 +
`best_encoding` 回退 + 默认 Q）**没有一条对 Rust 参考的端到端矩阵快照**，只在 `qr_builder_test` 单条内做
MoonBit 自身等价断言。此为本次评审最重要发现（§2.1）。

---

### 1. 复核范围与基线

| 文件 | 对应参考 | 复核点 |
|------|---------|--------|
| `lib/qr.mbt` | fast_qr `src/qr.rs` `QRBuilder`（:200）、`src/lib.rs:75-80` | `QRBuilder` 构造/new/from_string + 4 setter + `build` 委托单一性、错误面透传 |
| `lib/qr_builder_test.mbt` | — | 6 黑盒用例：链式等价、全 None 语义、from_string、错误面 |
| `lib/s6_snapshot_test.mbt` | `scripts/snapshot_gen_s6.rs` + fast_qr v0.14.0 | A 三模式×4ECL、B V01/V14/V26/V32、C 全自动、D V40-H 参考逐位 |
| `scripts/snapshot_gen_s6.rs` | fast_qr v0.14.0 | 介质一致性（`qr.data[i].0` 全字节含类型位）、全 None 支持 |
| `docs/S6-…-实现记录.md` / roadmap / README / 用户 PR 描述 | — | 覆盖构成与测试计数等陈述是否与代码一致 |

**基线门禁**：S6 合入后 `moon fmt && moon check --deny-warn && moon test` 全绿（**实际 94 个 test 块**，
S6 前为 85，新增 9）；wasm-gc / wasm 双后端 release 全绿。

---

### 2. 发现：文档/PR 与代码不符（失实点）

#### 2.1 【最重要】「全参数 None 纯自动路径 ×3」实为参数冻结（仅 mask 自动）——全 None 分支缺参考端到端覆盖

- **现象**：S6 方案 §2.2 缺口 3 明确要补「全参数 None 纯自动路径快照」，§3.2「全 None 返回 version 与参考
  一致」，§5.2「全自动路径 … 断言 meta() 与参考一致 + 逐格比对」；S6 实现记录 §3.1 表 C「全参数 None 纯
  自动 ×3」；用户 PR #33 描述「全参数 None 纯自动路径 ×3」——均宣称存在 3 条**全 None** 对参考的端到端。
- **实际代码**：`s6_snapshot_test.mbt` 末尾 3 行（C 组对应）**全部冻结参数**，只有 `mask` 是自动：
  - `c3()`（25 位数字）+ `Some(Numeric)` + `Some(ECL::Q)` + `Some(V01)`；
  - `c1()`（字母数字）+ `Some(Alphanumeric)` + `Some(ECL::Q)` + `Some(V03)`；
  - `c4()`（URL）+ `Some(Byte)` + `Some(ECL::Q)` + `Some(V03)`。
  `s6_raw` 里 `modev/eclv/verv` 均非 `None`，故 `mode/ecl/version` 的**自动选择没有被触发**，只有 `mask=None`
  自动择优被真实测到（而自动择优正确性在 S5 已参考锁定）。
- **后果**：真正全 None 的 `select_capacity`（`best_encoding` 模式回退 + 自动最小版本 + 默认 Q）这一分支，
  **没有任何一条对 Rust 参考全矩阵的端到端快照**。它目前仅由 `qr_builder_test.mbt` 的
  `qr_builder_default_auto_path`（单条 "12345"）验证——且那是 **MoonBit 自身等价**（`QRBuilder` 结果 ==
  `QRCode::build(None,None,None,None)` + 断言期望 meta），**不比对 Rust 参考输出**。故「全自动分支与 fast_qr
  逐字节一致」的结论**未被本阶段快照直接证明**（只是由各子件已参考验证而间接成立）。
- **真实风险**：低。因为 mode 自动回退取自 `best_encoding`、最小版本取自 `constants.version_for`、ecl 默认 Q
  均为从 Rust 移植的常量表逻辑，且 format/RS/placement 已各自参考逐位验证；但**作为 S6"收口 M2 功能对齐、
  60 快照全量"的验收声明，这是名不副实**。
- **建议**：
  1. 先**文档如实化**：把实现记录/roadmap/PR 描述改为「3 条**自动 mask**（mode/ecl/version 冻结）路径」，
     避免"全 None 参考对齐"的误导。
  2. 补真测（低代价、高价值）：`snapshot_gen_s6.rs` 的 `gen` 已支持全 None（`mode/ecl/ver/mask` 全 `NA`），
     输出本就带参考自选的 `<mode>|<ecl>|<ver>|<mask>` 字段。补 2-3 条全 None case，入库时**把参考自选的
     (mode,ecl,ver,mask) 一并存入常量表**，MoonBit 侧对 `self` 选择的 meta + 全矩阵做**双断言**。补齐后
     M2「自动路径对参考」才真正闭环。

#### 2.2 【测试计数失实】"91 测试绿 / 91 → 94" 与代码不符（实为 85 → 94，+9）

- **现象**：S6 实现记录头部/§0、roadmap §4.2 更新、用户 PR 描述均写「基线 91 测试绿 / 落地后 91 → 94」。
- **实际**：在 PR #33 父提交（即基线 main，含 PR #32 文档）上数得 **85 个 `test` 块**；S6 新增 9 个
  （`qr_builder_test` 6 + `s6_snapshot_test` 3）→ 合计 **94**。**85 → 94（净 +9）** 才是真实的。
  「91」这个数字与仓库任何实际状态都不对应（S5 收尾是 85，见 S5 实现记录）。
- **影响**：纯数字失实，不影响正确性；但多处文档据此自洽，易被后续当作回归基准误用。
- **建议**：统一改为 85 → 94（+9），并在 S6 实现记录补一句「新增 9 个 test 块」的来源（qr_builder 6 + s6 3）。

#### 2.3 【meta 断言承诺未落地】方案 §5.2 承诺"断言 meta"，实现仅在矩阵层

- **现象**：S6 方案 §5.2 全自动路径验收写「断言返回 `meta()` 与参考一致 + 逐格比对全矩阵」双保险；实现
  `s6_snapshot_test.mbt` 三处 test 均 `let (got, _, _, _, _) = s6_raw(...)`——**丢弃 meta**，且常量表
  `s6_special_cases`/`s6_matrix_cases` 只存内容+hex、不存参考自选的 (version/ecl/mask/mode)。meta 的语义
  核对只发生在 `qr_builder_default_auto_path` 单条（MoonBit 内部期望）。
- **影响**：与 §2.1 同源——若 auto 行全 None 化并入库参考 meta，meta 断言自然一并落地；当前属"承诺高于实现"。
- **建议**：并入 §2.1 的补测一起做；至少先把方案文档措辞改为「meta 语义经本包等价断言核对（qr_builder_test），
  参考矩阵经 s6 快照核对」，消除落差。

---

### 3. 优化 / 待办（非阻断）

#### 3.1 潜在陷阱 · `from_string`（及内容助手）对非 ASCII 字节的语义

- `QRBuilder::from_string`（`qr.mbt`）与全仓内容助手（`bstr`/`c0..c4`）都用
  `for ch in str { out.push(ch.to_int().to_byte()) }`——这是**按 Unicode 码点逐字符取低 8 位**，**仅 ASCII 正确**。
- 若 Byte 模式输入含非 ASCII（UTF-8 多字节，如 CJK/emoji），MoonBit 会把它压成**单字节 `0x??`**，
  而 Rust 参考 `QRBuilder::new(String)` 走 **UTF-8 字节序列**（多字节）——两者将**分叉**，产生与参考不一致的码。
- S6 宣称「Byte 端到端对齐」实际只覆盖 ASCII 字节；非 ASCII 从无参考快照也无测试。此前 S3 记录已注明是
  `to_bytes()` 弃用告警（deny-warn）故改用逐字符转——属测试输入约定的 ASCII 化遗留。
- **建议**：① 在 `QRBuilder::from_string` 文档注明「按逐字符低 8 位，ASCII 语义；非 ASCII/任意字节请走
  `new(Array[Byte])`（字节级，对应 Rust `Into<Vec<u8>>`）」；② 如需 UTF-8 支持，补等价 `String → UTF-8 字节`
  编码 + 一条非 ASCII 参考快照（可与 §2.1 补测同批）。

#### 3.2 维护性 · V40 满容量单行 hex 62667 字节（`s6_snapshot_test.mbt:288`）

- 方案 §7 已预警「V40 大矩阵单测体积…可拆分」，落地未拆，最终第 288 行单字面量 62667 字符。超长单行致
  diff/评审无法按格定位、编译期大字符串峰值内存。
- **建议**：按矩阵行/块切分为多个字符串常量在运行期拼接，或压缩（gzip）后 Base64 存储、测试内解码。
  非阻断，可留 S7/S9。

#### 3.3 一致性确认 · `QRBuilder` 字段 `pub(all)` 与 D7「不可变值语义」的张力

- `QRBuilder` 声明 `pub(all)`，字段全公开可被外部结构字面量直接构造/改写，与 D7 强调的「不可变链式、单一
  入口 `new/from_string`」意图略有张力。但 `QRCode` 亦 `pub(all)`（house style，S1 决策），属一致性取舍，
  **确认保留**。若欲严格，可后续把 `input` 内部化或字段改 `pub(read)`。

---

### 4. 确认正确、无需改动的点

- **生成器介质一致性**：`scripts/snapshot_gen_s6.rs` `gen()` 的 `qr.data[i].0` 在 fast_qr v0.14.0 中
  `Module(pub u8)`（`module.rs:42`）存储**完整 1 字节（bit0 明暗 + bit1-3 类型）**，与 MoonBit
  `Module.byte()`（`明暗|类型<<1`）**同构一致**；committed hex 含类型位（Data 型仅 0/1、功能区高位）佐证。
  脚本能复现已入库数据，不属"脚本与数据不符"。
- **QRBuilder 单一委托**：`build` 直接 `QRCode::build(...)`，无逻辑重复/漂移；链式 setter 不可变返回新实例。
- **错误面透传**：`EncodedData`（超 V40）/`SpecifiedVersion`（指定过小）经 builder 层原样透传。
- **真实新增覆盖确为收口**：三模式 Numeric/Alnum **首次**矩阵级端到端、V01 最短、V14/V26/V32 版本信息区
  （V7+ 才有）、V40-H 177×177 RS 交织，确为 S4/S5 未覆盖的真实补测——除全 None 分支外，"60 快照在已落地
  子集之外"的收口表述成立。

---

### 5. 建议行动清单（按优先级）

| # | 优先级 | 动作 | 落点 |
|:-:|:---:|------|------|
| 1 | 高 | 修正 §2.1 失实表述 + 补 2-3 条真全 None 参考快照（含参考 meta 双断言）| 文档 + `s6_snapshot_test.mbt`/生成器 |
| 2 | 中 | 统一测试计数 85 → 94（+9）| S6 实现记录 / roadmap / 本文档 |
| 3 | 中 | `from_string` 文档注明 ASCII 语义；非 ASCII 走 `new(Array[Byte])` | `qr.mbt` 注释 + 方案/记录 |
| 4 | 低 | V40 单行 hex 分块/压缩（可留 S7/S9）| `s6_snapshot_test.mbt` |
| 5 | 低 | 方案 §5.2 meta 断言措辞如实化（并入 #1）| 方案文档 |

---

### 6. 参考
- 本文件「实现方案」部分 §2.2/§3.2/§5.2/§7
- 本文件「实现记录」部分 §0/§3.1/§5
- [S5-掩码评分与择优.md](S5-掩码评分与择优.md)（评审模板与 S6 交接 O2）
- fast_qr v0.14.0：`src/module.rs:42`（`Module(pub u8)`）、`src/qr.rs:200`（QRBuilder）、`src/lib.rs:75-80`
- `scripts/snapshot_gen_s6.rs`（介质与全 None case 支持）

---
