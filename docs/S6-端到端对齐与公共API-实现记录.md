# S6 · 全量快照端到端对齐 + 公共 API 收口 · 实现记录

> 承接 [S6-端到端对齐与公共API-实现方案](./S6-端到端对齐与公共API-实现方案.md) 落地两块交付：
> **(1)** S6-1 三模式/边界/版本信息区/全自动的快照端到端逐位对齐；(2) S6-2 公共 `QRBuilder`
> 构造器 + 链式 setter，对齐 fast_qr `lib.rs:75-80` 导出面，收敛 roadmap §4.4 里程碑 **M2（功能对齐）**。
> 管线逻辑零改动（S1-S5 正确性已锁），本阶段为「补快照收口验证 + API 壳层补齐」。
>
> 日期：2026-09-06　｜　基线：main（PR #32 已合，**85 个 test 块**）　｜　落地后测试 **85 → 94（净 +9）**，
> wasm-gc / wasm 双后端 release 全绿；无构建产物入库；Rust 参考数据由 `scripts/snapshot_gen_s6.rs` 一次生成。
> ⚠️ 评审后更正：原稿「91 测试绿 / 91 → 94」计数失实（实为 85 → 94，新增 qr_builder_test 6 + s6_snapshot_test 3）；
> 「全参数 None 纯自动路径 ×3」实为 mode/ecl/version 冻结、仅 mask 自动。详见
> [S6-实现评审与优化-记录.md](./S6-实现评审与优化-记录.md) §2.1-2.2。

---

## 0. 一句话结论

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

## 1. 交付清单（对照方案 §3/§6）

| 批次 | 落点 | 交付 | 验证 |
|:---:|------|------|------|
| 1 S6-2 | lib `qr.mbt` | `QRBuilder` struct（pub(all)）+ `new`/`from_string` + `mode/ecl/version/mask` 值语义 setter + `build`（委托 `QRCode::build`） | `qr_builder_test.mbt` 6 黑盒用例 |
| 2 S6-1 | lib `s6_snapshot_test.mbt` | ~20 条参考全矩阵快照 + 端到端逐位比对 test（含三模式矩阵级/V01/V14/V26/V32/V40-H/全自动） | `s6_three_mode_ecl_matrix_e2e` + `s6_special_boundary_auto_paths` + `s6_v40h_full_capacity` |
| 3 收尾 | README / roadmap | S6 方案链接已并入；本记录 + README「文档」索引表追加 | 无死链 |

依赖：`lib/qr.mbt` 复用既有 `QRCode::build`；新增测试文件在 lib 公共包内，复用 m1 已有
`bstr`/`hexval`/`parse_hex` 顶层工具（同包共享）；无新 import、无 internal 层改动。

---

## 2. 关键实现语义（对照参考/方案核验）

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

## 3. 验证与对齐

### 3.1 端到端快照逐位对齐（`s6_snapshot_test.mbt`，黑盒）
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

### 3.2 QRBuilder 黑盒（`qr_builder_test.mbt`，6 用例）
- 链式各 setter 组合 == `QRCode::build` 同参（固定 mask + 自动 mask 两路径）；
- 全 None 纯自动：`QRCode::build` 同参 + meta（Numeric 回退 + Q + V01）语义核对；
- `from_string` == `new(字节)`；错误面 `EncodedData`（超 V40）/`SpecifiedVersion`（指定过小）透传。

### 3.3 门禁（AGENTS §二.4）
`moon fmt`、`moon info`、`moon check --deny-warn`、`moon test` 全绿（测试 85 → **94**，净 +9）；
wasm-gc / wasm 双后端 release 构建 + `moon test --target` 通过；`git status` 无 `.mbti`/`_build` 产物入库。
`.mbti` 护栏：lib 新增 `QRBuilder` 公共 API 属预期变更；internal 各 `.mbti` 不变（internal 层零改动）。

---

## 4. 遗留（后续批次）

- **S7（B11 输出层）**：`to_str` 终端画 / `print`（helpers.mbt 仍是注释骨架）→ S7 承接。
- **SVG / image convert（SvgBuilder/ImageBuilder）** → S7+（需 feature 语义，本仓库为纯库无 Cargo feature）。
- **S9 性能微优化**（8 轮 clone 开销 / 评分逐格分配）。
- **wasm 导出面**：roadmap/S5 记录提过，本仓库无 wasm-bindgen 对应物、`moon.mod` 仅双后端；无宿主 JS
  绑定需求，维持「lib 公共 API 编译到 wasm 可被宿主调用」即可（本阶段未单列）。

---

## 5. 参考
- [S6-端到端对齐与公共API-实现方案.md](./S6-端到端对齐与公共API-实现方案.md)、
  [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) §4.2/§4.4（S6/B8、M2）
- [fast-qr-接口.md](./移植参考/fast-qr-接口.md) §1.1（QRBuilder 同名构造器 + 缺省语义）
- 参考源码 fast_qr v0.14.0 `src/qr.rs:200`（QRBuilder）；数据由 `scripts/snapshot_gen_s6.rs` 一次生成
