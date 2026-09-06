# S6 · 全量快照端到端对齐 + 公共 API 收口 · 详细实现方案

> 承接 [moonbit-重写-roadmap-详细分析](./moonbit-重写-roadmap-详细分析.md) §4.2/§4.3/§4.4 的 **S6 / B8 收口 +
> 里程碑 M2**：在 S5 已锁自动择优正确性（mask 选择）的前提下，把 S1-S5 已落地的完整管线
> （`select_capacity → encode → structure → 放置 → 8 掩码 → 4 评分 → 择优`）做 **60 快照全量端到端
> 逐位对齐**，并补齐 fast_qr `lib.rs:75-80` 导出面上的 **`QRBuilder` 同名构造器 + 链式方法**公共 API，
> 收敛 roadmap §4.4 里程碑 **M2（功能对齐）**。
>
> 日期：2026-09-06　｜　前置：S5 已合入 main（PR #29，85 测试绿，`create_auto_qr` 择优 + `QRCode::build`
> 自动 mask 已落地，见 [S5 实现记录](./S5-掩码评分与择优-实现记录.md)）；三模式 encode 已随 S3 落地。
> ⚠️ 本阶段为**方案评估文档**：不写实现代码，只做「读代码/文档 + roadmap 核验 + 逐文件落地清单 +
> 关键架构决策与验收策略」，供 S6 实现阶段直接执行。

---

## 0. 一句话结论

S6 有两块交付，均属 **M2「功能对齐」收口**（roadmap §4.4）：

1. **全量 60 快照端到端对齐**：把 S5 现有「仅 Byte 模式 & V≤10 & 固定 mode/ecl/version」的择优子集快照，
   扩展为 roadmap §4.1 设计的约 60 条全参数端到端快照（补 **Numeric/Alnum 模式 + V40 满容量/边界 +
   版本信息区触发点 V7/V14/V26/V32 + 全参数 None 纯自动路径**），逐位比对 MoonBit `QRCode::build` /
   `QRBuilder` 输出与参考 fast_qr v0.14.0 全矩阵。对应 S5 复核 §4 的 **O2 建议**（端到端覆盖补
   Numeric/Alnum + V40）。
2. **公共 API 收口**：在 lib 公共层新增 **`QRBuilder` 构造器**（同名 + `mode/ecl/version/mask` 4 个链式
   setter + `build`），对齐 fast_qr `lib.rs:75-80` 导出面（`pub use crate::qr::{QRBuilder, QRCode}`），
   让既有底层 `QRCode::build`/`build_fixed` 收敛为一个对外惯用的 builder 入口。

S6 **不含**输出层（`to_str` 终端画 / SVG → **S7/B11**），**不含** wasm 绑定导出面收口（当前 `moon.mod`
  仅 `+wasm+wasm-gc`、无 `wasm-bindgen` 对应物，wasm 导出面是否随 S6 或单列需在实现时按 `.cnb.yml`/
  AGENTS 决策确认——本方案默认将 wasm 导出面列为 S6 尾部的可选项，见 §7）。

---

## 1. S6 范围界定（对照 roadmap §4.2/§4.4 / S5 遗留）

来自 roadmap §4.2：

> **S6** | 60 快照端到端对齐 + 公共 API 完善（三模式已在 S3 落地）| `lib.rs` 导出面 | 60 快照 100%

对应 §4.4 里程碑：

> **M2** | **功能对齐** | 60 快照 100% 逐位一致；API 面与 `lib.rs` 导出对齐（待 S5 评分择优 + S6 全量快照）

并承接 S5 实现记录 §4「遗留」：

> **S6**：60 快照全量端到端逐位对齐 + 公共 `QRBuilder` builder 壳 / wasm 导出面（M2 收口）。S5 已锁自动
>   择优（mask 选择）正确性，为 S6 全量对齐提供唯一前置。

### 1.1 S6 分两块，逐条对照

| 子项 | 内容 | 参考锚点 | 对应快照/API |
|:---:|------|---------|-------------|
| S6-1 | 60 快照全量端到端对齐（三模式已在 S3 落地）| `lib.rs` 导出面 + 全链路 | roadmap §4.1 的 60 快照集 100% |
| S6-2 | 公共 `QRBuilder` 构造器 + 链式方法 | `qr.rs` `QRBuilder`（:200）| API 面与 `lib.rs:75-80` 导出对齐 |

### 1.2 不属于 S6（由后续阶段承接）
- **`to_str` 终端画 / `print`**（helpers.mbt）→ **S7（B11 输出层）**；当前 helpers.mbt 仍是注释骨架。
- **SVG / image convert**（`SvgBuilder`/`ImageBuilder`）→ **S7+**（需 feature 语义，本仓库为纯库无 Cargo
  feature，是否按需实现以 roadmap S7 为准）。
- **性能微优化**（8 轮 clone 开销、评分逐格分配）→ **S9**（roadmap §3.3 先正确后优化）。

---

## 2. 现状盘点（动手前已核验）

### 2.1 已就绪、S6 将直接消费的完整管线（S1-S5 全绿，85 测试）
| 层 | 位置 | S6 将消费的 API | 状态 |
|------|------|---------------|:---:|
| 容量/版本选择 | lib `qr.mbt` | `QRCode::select_capacity(input, mode, ecl, version) -> Result[(Int,Int,Int), QRCodeError]` | ✅ S3 |
| 三模式编码 | `internal/data_encoding/encode.mbt` | `encode` / `best_encoding`（Numeric/Alnum/Byte）| ✅ S3 |
| 纠错交织 | `internal/reedsolomon/reedsolomon.mbt` | `structure` | ✅ S2 |
| 功能图案/放置/掩码 | `internal/matrix` | `create_fixed_qr` / `create_auto_qr` | ✅ S4/S5 |
| 公共入口（底层）| lib `qr.mbt` | `QRCode::build(input, mode, ecl, version, mask)`（mask 可 None 自动择优）+ `build_fixed` | ✅ S5 |
| 黑盒快照 | lib `m1_snapshot_test.mbt` | 8 固定 mask + 10 自动择优快照 | ✅ S4/S5 |

### 2.2 S6 独有的缺口（本次要补/对齐）
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

## 3. 关键架构决策与逐文件落地清单

### 3.1 决策 D6：60 快照集用「脚本在具备 Rust 环境一次生成 JSON + 入库常量表」而非手工手抄
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

### 3.2 决策 D7：`QRBuilder` 用 MoonBit 不可变链式（值语义），每 setter 返回新 `QRBuilder`
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

### 3.3 逐文件落地清单

| 文件 | 改动 | 目的 |
|------|------|------|
| `lib/qr.mbt` | 新增 `QRBuilder` struct + `new`/`from_string` + 4 链式 setter + `build`（委托 `QRCode::build`）| 补齐 `lib.rs` 导出面公共构造器 |
| `lib/m1_snapshot_test.mbt` | 追加 S6 全量 60 快照常量表 + 端到端比对 test | 端到端逐位对齐（含 Numeric/Alnum/V40/全自动）|
| `README.md` | 文档索引表 + S6 方案链接 | 收口文档索引 |
| （可选）`lib/fast_qr_moonbit.mbt` | 若需顶层 re-export 便捷函数（如 `build_qr(input)`），随 QRBuilder 面一并确认 | API 同构 |

- **不改动**任何 internal 层逻辑（S6 是验证 + API 壳层，管线正确性已在 S1-S5 锁定）。
- `QRBuilder` 放 lib 公共层，只用 `pub` 暴露；内部字段可 `pub(all)` 供白盒测试，或仅 `pub` struct + 构造/
  setter 让字段私有（对齐 S1 `QRCode` 已用 `pub(all)` 的惯例，具体实现时定）。

### 3.4 错误面
- `QRCodeError`（`EncodedData` / `SpecifiedVersion`）已在 lib 定义（S3），QRBuilder::build 直接透传
  `Result[QRCode, QRCodeError]`，无需新增错误变体。

---

## 4. 关键实现语义核对清单（写代码前须对照参考源码核验）

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

## 5. 测试与验收

### 5.1 前提：一次具备 Rust 环境生成 60 全量快照（复用 S4/S5 工具链）
- `scripts/setup-rust.sh` 已在仓库（供开发环境做 MoonBit↔Rust 对比，不入 push CI）。
- 在 `/fast_qr` 新增/扩展生成器：输入 = 约 60 条（content, mode?, ecl?, version?, mask?）→ 输出每条含
  （最终 mode/ecl/version/mask + 全矩阵 hex）的常量表。
- 产出入库为 `lib/m1_snapshot_test.mbt`（或新 `lib/s6_snapshot_test.mbt`）常量 + 比对 test。

### 5.2 端到端快照对齐 test
对每条快照：
- **固定参数路径**：`QRBuilder::new(input).mode(m).ecl(e).version(v).mask(mask).build()` → 逐格比对全矩阵；
- **全自动路径**：`QRBuilder::new(input).build()`（全 None）→ 断言返回 `meta()` 的 (version, ecl, mask, mode)
  与参考一致 + 逐格比对全矩阵。

### 5.3 QRBuilder 黑盒用例
- 链式各 setter 的组合结果 == `QRCode::build` 同参结果（等值护栏）；
- 默认缺省：全 None → Q + 最小版本 + 自动 mask + best_encoding；
- 错误面：数据超 V40 → `Err(EncodedData)`；指定 version < 最小 → `Err(SpecifiedVersion)`（沿用
  `public_select_capacity_*` 既有语义，QRBuilder 层透传验证）。

### 5.4 门禁（沿用 AGENTS §二.4）
```bash
moon fmt && moon info && moon check --deny-warn && moon test   # 预期 85 → 更多（随 60 快照条数增加）
for t in wasm-gc wasm; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done
```
- `.mbti` 护栏：QRBuilder 新增公共 API 属预期变更；internal 层零改动则 internal 各 `.mbti` 不变。
- 不得入库构建产物（`_build/`、`*.wasm`、`*.mbti` 已 gitignore）。

### 5.5 验收 = M2 功能对齐达成
60 快照全量逐位 + API 面与 `lib.rs:75-80` 导出对齐（`QRCode` + `QRBuilder` + 6 公共枚举）+
门禁全绿 = S6 达成，即 M2（功能对齐）收口，S7 输出层可据此继续。

---

## 6. 提交切分（每批一提交，消息 `feat(qr): …`）
1. **生成器 + 快照常量**：在具备 Rust 环境生成 60 全量快照 JSON → 转成 MoonBit 常量表 + 端到端比对 test
   （提交：`feat(qr): S6 全量 60 快照端到端对齐（含 Numeric/Alnum/V40/版本信息区/全自动）`）。
2. **QRBuilder 公共构造器**：`lib/qr.mbt` 加 `QRBuilder`（new/from_string + mode/ecl/version/mask + build）
   + 黑盒用例（提交：`feat(qr): S6 公共 QRBuilder 构造器（对齐 lib.rs 导出面）`）。
3. **收尾**：README / roadmap 状态更新（S6 记为完成、M2 收口、S7 下一步）、文档索引。

---

## 7. 风险与评估

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

## 8. 参考
- [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) — roadmap S6、B8、M2、§4.1 60 快照集
- [跨语言重写评估.md](./移植参考/专有概念/跨语言重写评估.md) §5.1/5.2 — 验收门槛 1（60 快照 100%）/ 2（API
  同构，`lib.rs:75-108` 导出清单）
- [fast-qr-接口.md](./移植参考/fast-qr-接口.md) §1.1 — QRBuilder `new/mode/ecl/version/mask/build` 签名与缺省
- [S5-实现记录](./S5-掩码评分与择优-实现记录.md) §4 遗留 — S6 交接（60 快照 + QRBuilder/wasm 导出面）
- [S5-实现评审与优化-记录.md](./S5-实现评审与优化-记录.md) §4 O2 — S6 端到端覆盖补 Numeric/Alnum + V40
- [S3-数据编码-实现记录.md](./S3-数据编码-实现记录.md) — 三模式 encode 已在 S3 落地（S6 前置就绪）
- 参考源码 fast_qr v0.14.0：`src/qr.rs:200`（QRBuilder）、`src/lib.rs:75-80`（导出面）、`src/encode.rs`
