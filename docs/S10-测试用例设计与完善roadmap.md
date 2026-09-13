# S10 — 测试用例设计与完善 roadmap v2（参考 fast_qr 测试体系 + 独立正确性验证）

> 目标：以 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 的测试代码为基准，
> 盘点本仓库测试资产，定位覆盖缺口，给出**分阶段、可验收、可定位失败**的测试完善路线；
> 并回答一个更根本的问题：**当前所有断言都是「与参考实现逐位一致」，谁保证参考本身对？**
>
> 日期：2026-09-13（v2 修订）　｜　基线：本仓库 `main @ 060c0ac`（**111 单测全绿**）
> ｜　参考检出：`fast_qr` commit `53e8c99`（`Cargo.toml` version `0.14.0`，`--depth 1`）
> 复跑：`bash scripts/test.sh`（= `moon test`），后端回归 `moon test --target wasm-gc`。
>
> **v2 修订说明**（相对初版 PR #58）：① 修正 fast_qr 测试证据等级口径（用例数与「表展开」重复度）；
> ② 补 `default.rs` 这一**带独立真值来源**的隐藏强项；③ 新增阶段 **T0 语料保护** 与 **T7 可定位性/规模护栏**；
> ④ 把 T3 从「设想」升级为**已实测落地的可开工口径**（附录 D 给出实跑证据与前置依赖）；
> ⑤ 补「测试自身有效性」原则（负向/变异/唯一性）与阶段依赖关系（§6.0）。
> 本文只输出**路线与盘点**，不落测试代码；实施按 §6 阶段逐批提 PR。

---

## 1. 结论摘要（TL;DR）

| 维度 | fast_qr（Rust） | 本仓库（MoonBit） | 判断 |
|------|-----------------|-------------------|------|
| 测试用例数 | `src/tests/*.rs` **167** 个 `#[test]` + `src/module.rs` 内联 **11** = **178** | **111** 个 `test "…"` | 数量同量级（但证据等级不同，见下） |
| 夹具/语料体积 | `version.rs`+`default.rs`+`polynomials.rs` ≈ **209 KB 机械展开** | 21 个全矩阵 hex 快照（≈2700 行测试码） | 机械展开 ≠ 独立信息量 |
| 测试组织 | 集中式 `src/tests/` 11 文件 + 1 处内联 | 就近式：包内 `*_test.mbt`(黑盒)/`*_wbtest.mbt`(白盒) | 本仓库更贴合 MoonBit 约定 |
| 端到端快照 | `default.rs` 3 个手工矩阵（V1/V3/V7） | `m1`+`s6` **21 个**全矩阵 hex 快照（V1/V5/V7/V10/V14/V26/V32/V40） | **本仓库更强** |
| **独立真值来源** | `default.rs` 2 例 `[[u8;25];25]` 数字矩阵 + **已禁用的 PNG/`qrcode` crate 交叉** | ❌ 无（`gc-compare` 层②亦为同项目两侧） | **两边都弱** → T3/T0 补 |
| 单算法黄金值 | ✅ 密度高（version/structure/error_correction/compact/encode） | ✅ 大部分已转译（bitbuffer/reedsolomon/encode/score） | **本仓库基本对齐**（非此前估计的「大缺口」） |
| 格式信息逐位 | ✅ 32 个「固定 ECL+mask + 强制版本」+ 32 个「版本信息区」用例（**同 32 组 15 位真值重复 2 遍**） | ✅ 表级 `format_information` + 快照间接 | ⚠️ 真值集合等价；缺「双副本物理布局」显式断言 |
| 生成多项式全表 | ✅ 40 个版本索引用例（**指向同一张 `GENERATOR_POLYNOMIALS`**） | ⚠️ 2 例抽查 + 160 组**度自洽**交叉不变量 | 本质是「版本→索引」映射；可用 4×1 例 + 表级校验等效覆盖 |
| 打分（N1–N4）逐行/逐列 | ✅ `score.rs` 含逐行/逐列分数数组 | ⚠️ 仅合成矩阵 + 分解不变量 | **缺口（真实）** |
| 放置 | ✅ `structure.rs::placement` V02 约 30 段逐格坐标序列 | ⚠️ 仅「位序读回一致」 | **缺口（真实）** |
| **强负向对照**（人为植入缺陷能否被测出） | ❌ 无 | ❌ 无 | **两边都缺，最大盲区** → T4 |
| 解码回读（第三方解码器） | ⚠️ `bytes.rs` 内 `qrcode` crate 交叉已删除；本仓库已有**层② vs fast_qr-wasm 逐位 sha256** | ❌ 无独立第三方解码 | **T3 已实测可落地**（附录 D） |
| 属性/变异测试 | ❌ 无 | ❌ 无 | 两边都缺，**T4 补** |
| 覆盖率门禁 | ❌ 无 | ❌ 无 | 两边都缺，T5 |

**一句话**：本仓库在「**端到端矩阵逐位对齐 + 边界/错误面 + 三载体就近分层**」上已优于参考；
参考的优势集中在「**逐行/逐列打分明细**」与「**放置逐格坐标**」两处**可定位性**用例（机械展开的大文件并非额外信息）。
方法论缺口**双方共有**：**无独立第三方解码回读**、**无属性/差分门禁**、**无数值型常量表值级校验**、
**无规模/时长护栏**。其中「测试是否有检出能力」一项本文**已实跑验证**（附录 E，10 项变异 9 项检出），
实测把两条初版判断**改写**了：`division` 长度断言与容量表**首项**校验**都有效**（各降级/维持），
而真正的漏检是**常量表的「非抽查点」**——改一个中间项/非抽查 `(ECL,mask)` 无任何测试变红（催生 P0 的 T1-f）。

---

## 2. 基线：本项目测试资产盘点

### 2.1 载体与分工（对齐 AGENTS.md §二.1）

| 载体 | 运行位置 | 可访问范围 | 本仓库使用 |
|------|---------|-----------|-----------|
| `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` API | 公共面：枚举序号、`QRCode`/`QRBuilder`、SVG、终端画、快照 |
| `*_wbtest.mbt` | 包**内**（白盒） | 私有实现 | internal 各子包：位流、常量表、编码、打分、掩码、放置 |
| 源码内联 `test {}` | 包内 | 私有 | 目前**未使用**（见 §3 缺口 G7） |

### 2.2 现有 111 用例分布

| 文件 | 用例 | 行数 | 层 | 说明 |
|------|-----:|-----:|---|------|
| `lib/internal/data_encoding/encode_wbtest.mbt` | 16 | 235 | 白盒 | 三模式编码 / 自动回退 / header 字符数 / 管线 |
| `lib/fast_qr_moonbit_wbtest.mbt` | 14 | 142 | 白盒 | Module 位打包、枚举序号、`QRCode` 容器 |
| `lib/fast_qr_moonbit_test.mbt` | 11 | 121 | 黑盒 | 公共枚举 + `select_capacity` 四态 |
| `lib/s7_svg_test.mbt` | 11 | 150 | 黑盒 | 6 形状全串 + 默认退化 + 自定义参数 + 真实 V01 |
| `lib/internal/bitstream/bitbuffer_wbtest.mbt` | 11 | 145 | 白盒 | `CompactQR` push/fill 黄金值（参考 `compact.rs` 转译） |
| `lib/internal/constants/constants_wbtest.mbt` | 9 | 195 | 白盒 | 容量查表 / ecc 分组 / 格式信息 / 160 行交叉一致性 |
| `lib/internal/matrix/score_wbtest.mbt` | 8 | 135 | 白盒 | N1–N4 合成用例 + 分解不变量 + 择优护栏 |
| `lib/qr_builder_test.mbt` | 6 | 121 | 黑盒 | 链式 == 过程式等价 + 错误面 |
| `lib/s7_terminal_test.mbt` | 4 | 126 | 黑盒 | 终端画全串（T1/T2/受控 mini） |
| `lib/internal/matrix/datamasking_wbtest.mbt` | 4 | 113 | 白盒 | 掩码公式 + 只翻 Data + 特化与参考等价 |
| `lib/s6_snapshot_test.mbt` | 3 | 292 | 黑盒 | **12 矩阵 + 7 特殊路径** 端到端 hex 快照（循环断言） |
| `lib/internal/matrix/matrix_pattern_wbtest.mbt` | 3 | 123 | 白盒 | V1/V7 功能图案 + Format 覆写几何 |
| `lib/internal/matrix/matrix_wbtest.mbt` | 3 | 65 | 白盒 | pack/类型号/位操作 |
| `lib/internal/matrix/placement_wbtest.mbt` | 3 | 137 | 白盒 | 放置填满 / 位序读回 / 掩码不动功能格 |
| `lib/internal/reedsolomon/reedsolomon_wbtest.mbt` | 3 | 101 | 白盒 | V05-Q 交织 消息区/纠错区 + division 余数长度 |
| `lib/m1_snapshot_test.mbt` | 2 | 329 | 黑盒 | **8 固定 mask + 10 自动 mask** 快照（循环断言） |
| **合计** | **111** | **~2700** | | 黑盒 37 / 白盒 74 |

≥95% 的断言形态是 `assert_eq(got, expected)` 且 `expected` 来自参考实现或本项目自身派生
（`actual == actual` 型护栏占少数）。这正是 T0/T3/T4 要处理的**证据同源**问题。

### 2.3 快照资产（本仓库的强项）

- `m1_snapshot_test.mbt`：**8** 个固定 mask 用例（V01/V05/V07/V10 × L/M/Q/H）+ **10** 个自动择优
  用例（含期望 mask 号），参考值由 `scripts/snapshot_gen_s6.rs` 在 fast_qr 侧生成。
- `s6_snapshot_test.mbt`：**12** 个三模式 × ECL 矩阵级端到端 + **7** 个特殊边界
  （V01 最短 / V14·V26·V32 版本信息区触发点 / 全自动路径）+ V40H 满容量。
- 覆盖版本：V01 / V05 / V07 / V10 / V14 / V26 / V32 / V40；覆盖 mask：0/1/2/3/5/6/7 + 自动。
- 快照介质：公共 `Module.byte()` = `明暗 | 类型<<1`，与参考 `Module(u8)` 同构。

> **重要提示（v2 新增）**：快照的强大以「生成器可信」为前提。`snapshot_gen_s6.rs` 是仓库内脚本，
> 但产物直接粘进 `.mbt` 文件——**没有记录「哪个 commit 重跑得到同一结果」**，
> 没有 `--verify` 自校验，也没有 CI 可执行的复现路径。这是 T0 的核心动因。

### 2.4 参考 fast_qr 测试资产盘点（含证据等级）

| 参考文件 | 用例 | 行数 | 覆盖 | 证据等级 | 本项目对位 |
|---------|-----:|-----:|------|---------|-----------|
| `src/tests/version.rs` | 64 | 3876 | 64 = 32（固定 ECL+mask 的 Format 15 位，**强制版本只为让 ref 可构建**）+ 32（版本信息区 18 位）；**真值仅 32 组、物理布局 2 遍** | 中（真值源自参考自身构建结果） | ⚠️ 缺双副本物理布局断言（T2-e） |
| `src/tests/polynomials.rs` | 41 | 1168 | 40 例「版本 → `generators` 表索引」+ 1 例全表；**40 例断言的是同一张表** | 中（同一表自我一致性） | ⚠️ 2 例抽查 + 160 组度自洽（T1-a 降级为抽查） |
| `src/tests/encode.rs` | 13 | 233 | `best_encoding` 7 例 + 三模式位级编码 + header 解析 | 中 | ✅ 已对齐 |
| `src/tests/compact.rs` | 10 | 200 | `CompactQR` push 系列位级黄金值 | 中 | ✅ 已对齐 |
| `src/tests/score.rs` | 8 | 415 | N1–N4 合成 + **逐行/逐列分数数组**（`line_by_line_*`/`col_by_col_*`）+ 列参与择优回归（issue #77） | 中 | ⚠️ 缺逐行/列明细（T2-a） |
| `src/tests/structure.rs` | 8 | 489 | `structure` 交织黄金值 ×5（V05-Q/V10-Q/V07-H/V16-M/V03-Q）+ 二进制串 + V02 放置**逐格坐标** | 中 | ⚠️ 交织仅 V05-Q 1 例（T1-d）；放置缺坐标（T2-c） |
| `src/tests/error_correction.rs` | 8 | 131 | `division` 余数黄金值 8 例（4×V05-Q + 2×struct + 小例） | 中 | ⚠️ 仅长度校验（T1-c） |
| `src/tests/datamasking.rs` | 8 | 238 | 8 种掩码 10×10 逐格布尔图案 | 中 | ✅ 已对齐 |
| `src/tests/default.rs` | 3 | 55133 B | V1/V3/V7 **数字真值矩阵**（`[[u8; 25]; 25]` 等）；`create_mat_from_bool` 还原 Module 类型 | **高**（唯一独立真值来源，源自 Python `qrcode` 库产物） | ❌ 缺（T0-c） |
| `src/tests/svg.rs` | 2 | 51 | SVG 不反转 + image data-uri 嵌入 | 中 | ✅ 已对齐（不含 image） |
| `src/tests/bytes.rs` | 2 | 57 | PNG 字节级比对 ×1（**已注释**）+ `dontInvert` 回归 ×1 | 低（1 例） | — 不做 |
| `src/module.rs` 内联 | 11 | — | `Module` 全 API（含 `size_of::<Module>()==1`） | 中 | ✅ 已对齐（无 sizeof 对位） |
| `src/lib.rs` doctest | 3 | — | `to_str` / `to_file(svg)` / `to_file(png)` doctest | 中（**doc 不删除文件**） | ❌ 缺（MoonBit 无 doctest，T6/T7 对位） |
| `benches/qr.rs` + `benches/README.md` | — | — | Criterion 与 `qrcode` crate 对比（V03H/V10H/V40H）**（仅打印，不断言）** | 低 | ✅ 已有等价（`scripts/bench-layer2.sh`） |

**关键教训（v2 新增，必须逐条吸收）**：

1. **参考自己的回归门禁也被禁用了**：`benches/qr.rs` 的 `qrcode` crate 对比「只打印不断言」；
   `bytes.rs` 的 PNG 字节断言**已删除**，只剩 1 个 `dontInvert` 用例。→ 说明**跨实现/跨表示回归极易腐化**，
   T3 必须一开始就设计成「**少数固定向量 + 明确复跑路径**」，不要指望「跑通一次就长期有效」。
2. **规模 ≠ 信息量**：`version.rs`（3876 行）真值仅 32 组；`polynomials.rs`（1168 行）断言同一张表。
   本仓库 160 行表级不变量已达到同等级保护。**测试评审应看「真值集合大小」而非用例数**。
3. **参考最值得抄的是 `default.rs` 的数字真值**：它来自**另一个实现**（Python `qrcode` 库），
   是参考测试体系里唯一的独立真值来源。T0-c 把它转译过来，成本低、收益是**独立证据**。
4. **参考的 doctest 会删自己写的文件**（`lib.rs` 的 `remove_file`），而 `bytes.rs` 的 `#[cfg(feature="image")]`
   段落更把**运行时字符串拼接结果当断言**，且该 feature 不在 `[dev-dependencies]` 里 → 永远不会执行。
   反面教材：**测试里禁止「把运行结果拼成断言」与「自删除副作用」**，本文 §5 铁律 5。

---

## 3. 覆盖差距矩阵（按模块 × 测试手段）

| 模块（本项目） | 对位参考 | 单算法黄金值 | 端到端快照 | 边界/错误 | 逐行/逐格明细 | 独立证据 | 缺口评级 |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| 快照/表生成器可信度 | `snapshot_gen_*.rs` | — | ✅ | — | — | ❌ | **P0（T0-a）** |
| 独立数字真值（V1/V3/V7） | `default.rs` | ❌ | ✅ | ✅ | — | ❌ | **P0（T0-c）** |
| `constants/hardcode` 生成多项式 | `polynomials.rs` | ✅（度自洽 160 组） | — | — | — | ❌ | P2（抽查 T1-a） |
| `constants/hardcode` 格式信息 | `version.rs` | ⚠️ 2 点抽查 + 160 组结构不变量（**非抽查点漏检**，附录 E M12） | ✅ 间接 | — | ⚠️ 双副本布局 | ❌ | **P1（T2-e）** |
| `reedsolomon::division` | `error_correction.rs` | ⚠️ 长度（已能捕获截断） | ✅ 间接 | — | — | — | **P1（T1-c，实测降级）** |
| `reedsolomon::structure` | `structure.rs` | ⚠️ 1/5 | ✅ 间接 | — | — | — | **P1（T1-d）** |
| `matrix::score` N1–N4 | `score.rs` | ⚠️ 合成 | — | — | ❌ | — | **P1（T2-a/b）** |
| `matrix::placement` | `structure.rs::placement` | ⚠️ 读回 | ✅ 间接 | — | ❌ | — | **P1（T2-c）** |
| `constants/capacity` 容量表 | —（参考无独立） | ⚠️ 抽查 + **结构**不变量（**非抽查点漏检**，附录 E M11） | — | ⚠️ | — | — | **P0（T1-f 全表值校验）** |
| `data_encoding` | `encode.rs` | ✅ 对齐 | ✅ 间接 | ⚠️ 单字节 | — | — | P2 |
| `matrix::datamasking` | `datamasking.rs` | ✅ 对齐 | ✅ 间接 | — | — | — | ✅ |
| `bitstream` | `compact.rs` | ✅ 对齐 | — | ⚠️ 越界未测 | — | — | P2 |
| `Module` / 枚举 | `module.rs` 内联 | ✅ | — | — | — | — | ✅ |
| `QRCode` / `QRBuilder` | `lib.rs` doctest | ✅ 等价护栏 | ✅ | ✅ | — | — | ✅ |
| `SvgBuilder` / `Shape` | `svg.rs` | ✅ 全串 | ✅ | ⚠️ `from_name` 未测 | — | — | P2 |
| 终端输出 | `helpers.rs` 无测试 | ✅ 全串 | ✅ | — | — | — | ✅ |
| **注入强负向（变异检测能力）** | ❌ 两边都无 | — | — | — | — | — | **P0（T4-b）** |
| **解码回读（第三方）** | ❌ 参考已删，本仓库有层② | — | — | — | — | ❌ | **P1（T3）** |
| **属性/模糊测试** | ❌ | — | — | — | — | — | P2（T4-a） |
| **差分门禁（vs 参考 wasm）** | — | — | — | — | — | ⚠️ 同源 | P2（T6-c） |
| **规模/时长护栏** | ❌ | — | — | — | — | — | **P1（T7-b）** |
| **覆盖率** | ❌ | — | — | — | — | — | P2（T5） |

### 缺口明细（G 编号，供 roadmap 引用）

- **G1 生成多项式「版本→索引」未逐版本断言**：`get_polynomial(v, ecl)` 只抽查 2 例；
  已有 160 组**度自洽**不变量（`degree == total_ec / groups` 且 `== len-1`）作为强替代。
  漏测后果：仅「某版本指向了长度相同但内容不同的表项」这一种错位能逃过（可能性低）。
  **v2 处置：降级为 P2 抽查（T1-a），不再列为 P0。**
- **G2 Format 信息 15 位未逐 (ECL,mask) 显式断言**：现为表级 `format_information(0,0)/(3,7)` + 160 行交叉不变量
  + 端到端快照间接覆盖；参考对 32 组做逐位断言，但**未断言双副本的物理坐标序列**。
  **v2 处置：保留 T2-e（双副本物理布局），真值集合与参考等价，不重复造。**
- **G3 `division`（GF(256) 除法）无黄金余数**：现仅断言余数**长度**。参考 8 例。
  **v2 实测修正**：附录 E 的 M5 表明「余数截断」类缺陷**已被长度断言捕获**（10 条测试变红），
  故本条降级为 **P1**——仍需补「值级」黄金余数（长度对而值错的情形无法捕获），但已不是最紧急项。
- **G4 `structure` 交织仅 1 组黄金值**：参考 5 组（单块/多块、不同 ECL、`< max_bytes` 补齐）。
- **G5 打分无逐行/逐列明细**：参考把某矩阵的每行/每列分数写成数组逐一断言，可定位「哪一行算错」。
- **G6 `placement` 无逐格坐标断言**：参考手工枚举 V02 约 30 段坐标序列；本项目只做「位序读回一致」
  （该读回由**与实现相同的遍历序**推出 → `actual == actual`，见 §5 铁律 3）。
- **G7 无源码内联 `test {}`**：AGENTS.md §二.1 允许，适合「贴近实现的单行不变量」。
- **G8 `Shape::from_name` / `Mask::from_int` / `Version::from_int` 等回环与未知值回退未测**。
- **G9 `CompactQR` 越界/容量写满行为未测**（本项目固定容量，参考为动态扩容——语义不同，勿照抄参考断言）。
- **G10 无强负向对照**：**没有一条测试能证明「实现被破坏时测试会红」**。
  这是比「缺解码回读」更靠前的缺口——**先证明测试有效，再谈覆盖率**。
- **G11 CI 门禁未含覆盖率 / 差分 / 规模护栏**：`.cnb.yml` 只跑 `fmt / check / test / wasm-gc`。
- **G12 快照生成器不可复现校验**：无 commit 钉版、无 `--verify`、无复跑记录（T0-a）。
- **G13 无独立数字真值语料**：`default.rs` 的 V1/V3/V7 数字矩阵未转译（T0-c）。
- **G14 测试规模与时长无护栏**：单文件行数、`moon test` 壁钟时间、断言总量无监控（T7-b）。
- **G15 数值型常量表在「非抽查点」无保护（附录 E M11/M12 实测仅有的两条漏检）**：
  容量表只有表首项抽查（改首项会被捕获，见 M6），其余 119 项由结构不变量兜底——
  但结构不变量**只约束分组/度/最小性，不约束数值**，故改一个**中间项**全程无感（M11）；
  Format 表同理：只有 `(0,0)`/`(3,7)` 两个抽查点，改其它 `(ECL,mask)` 值和布局都测不出（M12）。
  → **稀疏抽查 = 稀疏保护**。处置：T1-f（全表值指纹）+ T2-e（Format 32 组 + 双副本逐位）。

---

## 4. 参考测试的「方法论」提炼（可直接移植 / 需摒弃）

| 参考做法 | 本项目对应做法 | 落地建议 |
|---------|--------------|---------|
| `#[cfg(test)] pub fn test_*` 白盒钩子 | MoonBit `*_wbtest.mbt` 天然可访问私有 | 直接使用，无需钩子（更干净） |
| 表/快照由生成器产出 | `scripts/snapshot_gen_s6.rs` 已建立 | **补可复现校验 + commit 钉版**（T0-a），并建 `gen-goldens.sh`（T6-b） |
| 逐行/逐列分解断言 | 无 | P1 增加（T2-a） |
| 手工坐标序列核对放置 | 无 | P1 增加（T2-c） |
| issue 回归用例带 issue 号注释 | 部分有（`qr_code_set_immutable_no_alias`） | 统一格式：`/// 回归：issue #NN …` |
| **数字真值矩阵（`default.rs`）** | 无 | **P0 转译（T0-c）——参考中最值得抄的部分** |
| doctest（`lib.rs` 顶部示例即测试） | 无 MoonBit 等价物 | 以 `cmd/main` 演示 + 断言替代（T7-a）；**禁止 doctest 式自删除副作用** |
| ~~PNG 字节比对 / `qrcode` crate 交叉~~ | — | **明确不抄**：参考已删除（不可长期维护）。改走 T3 的 jsQR 少量向量 |
| ~~40 例表索引断言~~ | 160 组度自洽 | **不照抄**：改为抽查 4 例 + 表级校验（避免 4000 行机械展开） |

---

## 5. 设计原则（本项目测试的铁律，v2 扩至七条）

1. **黄金值必须有出处**：参考值一律由脚本在 fast_qr 侧生成（`scripts/snapshot_gen_*.rs`），
   禁止手抄、禁止「跑一遍写下自己的输出」。
2. **黑盒锁契约、白盒锁实现**：公共 API 语义变化必须先在 `*_test.mbt` 里体现；
   私有实现的重构只允许动 `*_wbtest.mbt`。
3. **禁止 `actual == actual`**：断言两端不得来自**同一段实现逻辑**（不同函数但同一算法亦不允许）。
   典型反例：`placement_wbtest.mbt` 的「逆序读回」用的是与 `place_on_matrix_data` 相同的遍历序 →
   它只锁「实现与自身一致」，不提供任何正确性证据（**保留其回归价值，但不得计入正确性覆盖**）。
4. **每个断言可定位**：失败信息必须能指出**模块 + 函数 + 行/列/格坐标/版本/ECL**，
   而不是「case 7 length mismatch」。新用例强制 `fail("{模块}.{函数} … got=… want=…")`。
5. **负向优先于正向**：新增/修改实现时先写「能红」的用例（T4-b 的变异清单可作模板），
   再写正向快照。禁止把运行结果拼成断言字符串（参考 `bytes.rs` 的反面教材）。
6. **真值集合而非用例数**：评审看「独立真值点数 / 覆盖的参数叉积」，不看文件行数；机械展开的重复断言一律拒绝。
7. **测试不得有破坏性副作用**：不写临时文件（或写入后必删且可并发）、不改全局状态、不依赖执行顺序。

---

## 6. 分阶段 roadmap

> 阶段沿项目既有 S 编号继续（S1–S9 为实现/性能，S10 为测试）。
> 每阶段独立 PR，沿用 AGENTS.md §二.4 收尾检查：
> `moon fmt && moon info && moon check --deny-warn && moon test` + wasm-gc 回归。

### 6.0 依赖关系（v2 新增）

```
T0 (语料保护: 钉版+校验+独立数字真值)  ──►  T1 (细粒度黄金值)  ──►  T2 (可定位性: 打分/放置/Format)
        │                                                              │
        └──────────────────────────────►  T4 (负向/变异/属性/差分) ◄────┘
                                                   │
                                                   ├──►  T3 (独立解码回读，已实测可落地)
                                                   ├──►  T5 (覆盖率门禁)
                                                   └──►  T7 (可定位性/规模护栏)
                                                                │
                                                                └──►  T6 (文档/约定收口)
```

**唯一强制序**：`T0 → (T1 ∥ T2 ∥ T4) → (T3 ∥ T5 ∥ T7) → T6`。
T0 必须先行：**语料未钉版前，后续所有「与参考一致」的断言都建立在浮动沙地上**。

### 阶段 T0 — 语料与生成器保护（P0，v2 新增，前置一切）

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T0-a (G12) | `snapshot_gen_*.rs` 头注释写明**参考 commit `53e8c99`**；新增 `scripts/gen-goldens.sh` 一键重建 + `--verify`（与入库常量比对，仅报差异不改文件） | `scripts/` | 一条命令可复现 21 个快照；`--verify` 在未漂移时零输出 |
| T0-b | 每个快照 `.mbt` 顶部登记「生成器脚本 + 参考 commit + 生成日期」，作为入库元数据（**注释，不是断言**） | `m1/s6_snapshot_test.mbt` | 元数据齐全，可审计溯源 |
| T0-c (G13) | 转译 `src/tests/default.rs` 的 V1/V3/V7 **数字真值矩阵**（`[[u8;25];25]` 等），覆盖 `QRCode::get` 逐格 | `lib/internal/matrix/*_wbtest.mbt` + `lib/*_test.mbt` | 3 组真值逐格一致；**首次引入独立于本项目与 fast_qr 输出的真值** |

**不可行方案已排除**：曾在初版考虑的「`gc-compare.mjs --dump` 反解参考矩阵」——实测发现
`--dump` 输出 `0/1` 明暗值，而 **`Module` 类型位（bit1-3）不可从明暗恢复**，无法还原完整矩阵快照；
且该路径输出为 JS 生成、无人工审阅 → 判定「形式合规、实质手抄」，**不做**。

**工作量**：1 个 PR，~250 行 + 脚本改造。**风险**：低（纯追加 + 脚本）。

### 阶段 T1 — 补齐「参考已有、我们缺」的细粒度黄金值（P0/P1）

| 项 | 内容 | 载体 | 来源 | 验收 |
|----|------|------|------|------|
| T1-a (G1，降级) | `get_polynomial(v,ecl)` **4 例抽查**（覆盖 4 个 ECL 与 V01/V07/V40 边界，比对 `(len-1, first, mid, last)` 四元组）+ 沿用现有 160 组度自洽不变量 | `constants_wbtest.mbt` | 新 `scripts/snapshot_gen_poly.rs` | 4 例 × 4 元组一致；不新增 >100 行 |
| T1-b | **（并入 T2-e）** Format 15 位真值集合与参考等价，不再单列 | — | — | 见 T2-e |
| T1-c (G3) | `division` **8 组黄金余数**（4×V05-Q + 2×struct + 小例） | `reedsolomon_wbtest.mbt` | 直接转译 `src/tests/error_correction.rs` | 余数逐字节一致；**失败信息含 `data[0..4]` 指纹** |
| T1-d (G4) | `structure` 补 **V10-Q / V07-H / V16-M / V03-Q** 4 组交织黄金值（消息区 + 纠错区） | `reedsolomon_wbtest.mbt` | 转译 `src/tests/structure.rs` | 5 组（含现有 V05-Q）全绿；每组断言 `message.len()`/`errors.len()` |
| T1-e | `division` 与 `structure` **互为独立证据**：直接用 `structure` 的纠错区反推 `division` 输入输出（同项目内两算法交叉） | `reedsolomon_wbtest.mbt` | 由 T1-d 语料派生 | 交叉一致的组数 ≥5 |
| T1-f (G15，**P0，实测最高价值**） | **数值型常量表全表值级校验**：对 `capacity_bytes`（3×4×40）、`max_bytes`、`data_codewords`、`ecc_to_groups`、`information`、`alignment_grid` 由脚本导出**全表指纹**（逐行 hex / 整表 sha256）并断言 | `constants_wbtest.mbt` + 新 `scripts/snapshot_gen_tables.rs` | 参考侧（fast_qr 常量表） | 全表指纹一致；**附录 E M11 型「中间项改值」被捕获** |

**工作量**：1 个 PR，~350 行。**风险**：低。

> **为什么 T1-c/T1-d 要单独做**：`division` 是 GF(256) 算术，出错时**端到端快照仍可能全绿**
> （RS 纠错在 Format 区/功能区之外的错误会被解码器容忍）。快照给不出「哪个函数错了」的证据。

### 阶段 T2 — 打分 / 放置 / Format 的「可定位」测试（P1）

| 项 | 内容 | 载体 | 来源 | 验收 |
|----|------|------|------|------|
| T2-a (G5) | 选一个真实矩阵（V03），断言**每一行** N1 运行分数数组 + 每列数组 | `score_wbtest.mbt` | `src/tests/score.rs::line_by_line_xiaojiba` 方法迁移 | 逐行/逐列数组全等；失败输出到具体行号 |
| T2-b (G5) | 矩阵级四规则分量（dark/square/line+col/pattern）与参考同名断言（`example_com`/`fast_qr_com`） | `score_wbtest.mbt` | `src/tests/score.rs` 前三用例 | 4 个分量值一致（需先补参考侧生成器 `snapshot_gen_score.rs`） |
| T2-c (G6) | V02 放置路径**逐格坐标**断言（分段枚举，覆盖约 20 段/50 点，含跳第 6 列与行向交替） | `placement_wbtest.mbt` | 转译 `src/tests/structure.rs::placement` | 分段序列全等；**失败输出 `(段号, 格坐标)`** |
| T2-d | 择优「列参与评分」回归用例（对 `https://fast-qr.com/` + ECL H，断言期望 mask 号） | `score_wbtest.mbt` 或黑盒 | 参考 issue #77 方法迁移（**须先核对两边 mask 号语义**） | 断言 mask 号稳定；若语义不一致则改为「断言与参考矩阵逐位一致」 |
| T2-e (G2) | Format 信息**双副本物理布局**逐位断言：① `mat[l-1-k][8]`/`mat[8][l-k]` 序列；② `mat[8][0..8]`/`mat[7..0][8]` 折返序列 | `matrix_pattern_wbtest.mbt` | 转译 `src/tests/version.rs` 的两段取址逻辑（真值复用现有表级/不变量） | 2 段坐标序列 × 32 组 (ECL,mask) 逐位一致 |

**工作量**：1 个 PR，~400 行。**风险**：中（T2-d 的 mask 号语义需先核对；T2-a/b 需新增参考侧生成器）。

### 阶段 T3 — 独立正确性验证：解码回读（P1，**已实测可落地**）

> 这是**两边都缺**、对 QR 库最有价值的一类测试：把生成的矩阵交给**独立第三方解码器**，
> 断言读回原文等于输入。它把「与某实现逐位一致」升级为「符合 QR 规范语义」。
> **详细实测证据（本环境实跑）见附录 D；此处只给落地口径。**

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T3-a ✅ | `scripts/qr-decode-check.mjs`：用 `jsqr`（纯 JS，零原生依赖）解码 **MoonBit 侧**矩阵（`cmd/bench --dump`），断言读回原文 == 输入；包装入口 `scripts/test-audit.sh decode` | `scripts/`（本地/审计脚本，**不进 push CI**） | **已达成**：3 基准点读回原文一致，退出码 0 |
| T3-b ✅ | 反向证据：脚本 `--mutate` 破坏左上 finder 内环，断言解码失败 | 同上 `--mutate` | **已达成**：3 点全部解码 NULL，退出码 0（脚本判定「已检出」） |
| T3-c | 收敛为**固定向量**（避免 CI 依赖 npm）：把 T3-a 的矩阵 sha256 + 期望原文写进 `lib/s6_decode_vectors_test.mbt`（黑盒，只断言「我方矩阵自洽 + 已固化解码器结论」） | `lib/` | 不引入新依赖即可回归；向量 ≤10 组 |
| T3-d ⏳ | 多内容/多 ECL 扩样（现 `cmd/bench` 仅支持固定输入 `https://example.com/`）——**前置改动**：给 `cmd/bench` 增加只读 `--dump-case index` 或新增 `cmd/qr-dump` 探针（无 argv 副作用），覆盖三模式 × 4 ECL × {V01,V05,V10,V40} | `cmd/` + `scripts/` | 审计脚本覆盖 ≥12 组；矩阵与 `s6` 快照口径一致 |

**前置依赖（实测得到，务必先办）**：jsQR 是**纯 JS 像素域**解码器，须把模块渲染成像素且要有静默区。
实测标定（`scale` = 每模块像素数，`q` = 静默区模块数）：

| 配置 | V03（29 模块） | V10（57） | V40（177） |
|------|:---:|:---:|:---:|
| scale=1, q=0 | ❌ NULL | ✅ | ✅ |
| scale=1, q=1 | ❌ NULL | ✅ | ✅ |
| scale=1, q≥2 | ✅ | ✅ | ✅ |
| scale≥2 | ✅ | ✅ | ✅ |

即**小版本（模块少）对「总像素数」敏感，大版本对静默区不敏感**（模块多、采样点足够）。
统一用 `scale=4, q=4`（当前 `gc-compare.mjs`/试点即此配置，三点全绿）最稳；
不要用 `scale=1`，否则 V01–V03 会出「明明正确却解不出」的假红灯。

**工作量**：1–2 个 PR（脚本 + `cmd` 探针 + 向量）。**风险**：中——npm 依赖与 CI 环境；
**解码脚本只做审计，仓库内固化向量**（与参考 `bytes.rs` 已被删除的教训一致）。

### 阶段 T4 — 强负向对照 + 属性测试 + 差分（P0/P2）

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T4-b (G10，**最高优先**） | **注入强负向清单**：对 8 类实现改动（掩码公式换号、Format BCH 少一位、`structure` 交织方向反转、N2 计 4 分/块、`division` 余数截断、版本容量表错一行、`cci_bits` 分段偏移、`QRCode::set` 改回共享数组）逐一**临时植入**，断言**至少一条现有测试变红** | 手工执行 + 结果记入本文附录 E | 8/8 全部被检出；未检出项立即补用例 |
| T4-a | **属性 1**：任意内容/ECL/版本 → size 恒为 `version*4+17`，功能图案区类型号恒定 | `lib/internal/matrix/*_wbtest.mbt`（确定性 LCG，不引入 `rand`） | 1000 次随机抽样全绿 |
| T4-a2 | **属性 2**：同输入 8 种固定掩码 → 恰好 8 个互不相同的矩阵 | 黑盒 | 8 个互异（本次审计**尚未覆盖**） |
| T4-a3 | **属性 3**：`QRBuilder` 链式与 `QRCode::build` 在随机参数下恒等 | `qr_builder_test.mbt` | 500 组随机参数全等 |
| T4-a4 | **属性 4**：不可变式 API（`QRCode::set`/`SvgBuilder::*`）无别名副作用 | `*_test.mbt` | 随机 100 次源对象不变 |
| T4-c (G11) | **差分门禁**：把 `scripts/gc-compare.mjs` 的「逐位对齐 sha256」从「打印」升级为**独立 CI 可选项**（需参考 wasm 制品；无制品时跳过并标注 `skipped`） | `.cnb.yml` + 脚本 | 有制品时 3 点 sha256 零差异；无制品时明确 skipped |

**工作量**：1 个 PR，~350 行 + 手工变异记录。**风险**：低（T4-b 纯手工，产出是「信心」与补测清单）。

### 阶段 T5 — 覆盖率与门禁（P2）

| 项 | 内容 | 验收 |
|----|------|------|
| T5-a | 跑 `moon test --enable-coverage`，产出包级覆盖率报告并存 `docs/` 摘要 | 报告入库（**先不承诺阈值**） |
| T5-b | 设定**分模块覆盖率下限**（先「不下降」锁定，再逐步抬升） | CI 中 `scripts/test.sh` 附加比较 |
| T5-c | 死代码/未覆盖 `pub` 清单（用 `moon info` 的 `.mbti` 对比测试引用面） | 「无测试引用的 pub 符号」清单为 0（或明确豁免并记录理由） |

> **覆盖率是 T4 的补充而非替代**：100% 行覆盖下仍可能全部断言都是 `actual == actual`（§5 铁律 3）。

### 阶段 T6 — 测试文档化与维护约定（P2，收口）

| 项 | 内容 | 验收 |
|----|------|------|
| T6-a | `AGENTS.md` 增加「测试三载体分工 + 七条铁律 + 黄金值出处」小节 | 文案入库 |
| T6-b | `scripts/gen-goldens.sh` 一键重建全部 golden（含 `--verify`），文件头写明参考 commit | 脚本可跑通；`--verify` 零差异 |
| T6-c | 本文（S10）与 README 文档索引互链 | 死链检查通过 |

### 阶段 T7 — 可定位性与规模护栏（P1/P2，v2 新增）

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T7-a | **失败可定位性标准化**：新用例统一 `fail("{模块}.{函数} {上下文} got=… want=…")`；为现有 `m1/s6` 快照循环补「参数指纹（version/ecl/mask/mode）」到 fail 信息 | `lib/**/*_test.mbt` | 断言失败输出含模块+参数；人工评审 10 条示例 |
| T7-b (G14) | **规模与时长护栏**：① 单测试文件 ≤800 行（AGENTS.md §三已定，改为脚本校验）；② 记录 `moon test` 壁钟基准（本机 ~1 s 量级），新增用例后 >3× 需说明；③ 断言总数与真值点数纳入本文附录维护 | `scripts/` + 本文 | `scripts/test-scale.sh` 可跑；README 无需改动 |
| T7-c | **反向可复现**：`cmd/qr-min` 的 `QR_MIN_CHECKSUM` 与 `cmd/bench` 的 `TOTAL_CHECKSUM` 作为「跨优化档语义等价」的廉价护栏，纳入 `scripts/build-and-run.sh` 输出核对（已有值，改为**断言**） | `scripts/build-and-run.sh` | 输出不匹配即失败 |

**工作量**：1 个 PR，~200 行。**风险**：低。

---

## 7. 里程碑与优先级排序（v2 重排）

| 优先级 | 阶段 | 理由 |
|:---:|------|------|
| **P0** | **T0**（语料保护 + 独立数字真值） | 前置一切：语料浮动则所有「一致」断言失效；`default.rs` 是**唯一非自证真值** |
| **P0** | **T4-b**（注入强负向清单） | 成本最低、信息量最大：**先证明测试能红**。无此步，覆盖率与快照数量都是自我安慰 |
| **P0** | **T1-f**（常量表全表值级校验） | 附录 E 实测漏检 M11（中间项）的**唯一**解法；成本极低、堵住数值型常量表的系统性盲区 |
| **P1** | T1-c（`division` 余数**值**） | M5 已证明长度断言有效；剩余缺口是「长度对而值错」，可定位到函数 |
| **P1** | T2（打分/放置/Format 可定位） | 让失败能指到「哪一行/哪一格」 |
| **P1** | T3（独立解码回读） | **已实测可落地**（附录 D）：提供跨实现的语义证据 |
| **P1** | T1-d / T7 | 交织多组黄金值 + 失败信息/规模护栏 |
| **P2** | T4-a（属性）/ T5（覆盖率）/ T6（收口）/ 其余 P2 项 | 建立在稳定行为基线之上 |

**建议节奏**：`T0` → `T4-b`（**已完成，见附录 E**）→ `T1-f/T1-c/T1-d` → `T2` → `T3`（先审计脚本，再固化向量）→ `T5/T7` → `T6`。
T4-a 待 S9 性能优化收敛后再做（避免测试与实现同时大改）。

---

## 8. 验收标准（Definition of Done）

- [ ] 每个 G 编号缺口在 §6 中都有对应项与验收断言（本文覆盖 G1–G14）。
- [ ] 每阶段 PR：`moon fmt --check` / `moon check --deny-warn` / `moon test` / `moon test --target wasm-gc` 全绿。
- [ ] 黄金值来源可复现：`bash scripts/gen-goldens.sh --verify` 零差异，且脚本头写明参考 commit。
- [ ] 失败可定位：断言失败输出含「模块 + 函数 + 参数（版本/ECL/mask/行号/坐标）」。
- [ ] 测试文件行数受控：单文件 ≤800 行（脚本校验，T7-b）。
- [ ] 文档无死链，README 索引已更新。
- [ ] **新增（v2）**：任何「与参考逐位一致」的新用例，其真值必须能指回生成脚本 + commit；
      否则不予合入（§5 铁律 1）。
- [ ] **新增（v2）**：至少一条 T4-b 变异被检出，才认为该模块「有有效测试」。
- [ ] **新增（v2）**：附录 E 表中所有 ❌ 漏检项（M11→T1-f、M12→T2-e）必须有对应补测项，且重跑 `scripts/test-audit.sh mutation` 后转为 ✅。

---

## 9. 与现有文档的关系

| 文档 | 关系 |
|------|------|
| [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) | **上游**：§5「测试规划」定义三载体分工；本文细化到用例级 |
| [S6-端到端对齐与公共API.md](./S6-端到端对齐与公共API.md) | 提供 `m1`/`s6` 快照的生成方法（本文 T0/T1 沿用同一生成器模式） |
| [S9j-层②统一Node对比-wasm-gc与fast_qr.md](./S9j-层②统一Node对比-wasm-gc与fast_qr.md) | 层② 逐位对齐 + sha256 门禁脚本 `scripts/gc-compare.mjs`（本文 T3/T4-c 复用其矩阵导出与宿主 shim） |
| [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md) | 输出层测试（`s7_*`）的语义基准 |
| [S9-性能基准.md](./S9-性能基准.md) · [性能测试脚本-公开评审说明.md](./性能测试脚本-公开评审说明.md) | 性能/体积基准；本文 T4-c/T7-c 与其 checksum 护栏对接 |
| [AGENTS.md](../AGENTS.md) | 测试放置与收尾检查的硬性约定 |
| [移植参考/fast-qr-索引.md](./移植参考/fast-qr-索引.md) | 参考库语料入口；本文 §2.4 是其测试面盘点 |

---

## 附录 A：参考 fast_qr 测试清单（逐文件 ↔ 本项目对位）

| 参考文件 | 用例 | 行数 | 本项目对位文件 | 状态 |
|---------|-----:|-----:|---------------|------|
| `src/tests/version.rs` | 64 | 3876 | `constants_wbtest.mbt` + `matrix_pattern_wbtest.mbt` + `m1/s6` 快照 | ⚠️ T2-e（布局）/ T1-b（真值已等价） |
| `src/tests/polynomials.rs` | 41 | 1168 | `constants_wbtest.mbt`（160 组度自洽） | ✅ 等效（T1-a 仅补 4 例抽查） |
| `src/tests/encode.rs` | 13 | 233 | `encode_wbtest.mbt` | ✅ |
| `src/tests/compact.rs` | 10 | 200 | `bitbuffer_wbtest.mbt` | ✅ |
| `src/tests/score.rs` | 8 | 415 | `score_wbtest.mbt` | ⚠️ T2-a/T2-b |
| `src/tests/structure.rs` | 8 | 489 | `reedsolomon_wbtest.mbt` + `placement_wbtest.mbt` | ⚠️ T1-d / T2-c |
| `src/tests/error_correction.rs` | 8 | 131 | `reedsolomon_wbtest.mbt` | ⚠️ T1-c |
| `src/tests/datamasking.rs` | 8 | 238 | `datamasking_wbtest.mbt` | ✅ |
| `src/tests/default.rs` | 3 | 55133 B | —（**待转译**） | ❌ T0-c（**独立真值**） |
| `src/tests/svg.rs` | 2 | 51 | `s7_svg_test.mbt` | ✅（不含 image） |
| `src/tests/bytes.rs` | 2 | 57 | —（PNG 子集不做；1 例已注释 + 1 例 `dontInvert`） | N/A |
| `src/module.rs` 内联 | 11 | — | `fast_qr_moonbit_wbtest.mbt` | ✅ |
| `src/lib.rs` doctest | 3 | — | `cmd/main` + README 示例 | ⚠️ T7-a |
| `benches/qr.rs` | — | — | `scripts/bench-layer2.sh`（**只打印不断言**，与参考同病） | ⚠️ T4-c 升级为断言 |

## 附录 B：黄金值生成器规划

| 脚本 | 用途 | 输出 | 引用方 | 状态 |
|------|------|------|--------|------|
| `scripts/snapshot_gen_s6.rs` | 端到端全矩阵 hex | `CASE\|…\|hex` | `m1`/`s6` 快照 | 已有（待补 commit 元数据 + `--verify`，T0-a） |
| `scripts/snapshot_gen_poly.rs` | `get_polynomial(v,ecl)` → `(len-1, first, mid, last)` | TSV | `constants_wbtest.mbt`（T1-a） | 待建 |
| `scripts/snapshot_gen_division.rs` | `division` 余数向量（8 组） | TSV | `reedsolomon_wbtest.mbt`（T1-c） | 待建 |
| `scripts/snapshot_gen_score.rs` | 某矩阵逐行/逐列分数 | TSV | `score_wbtest.mbt`（T2-a/b） | 待建 |
| `scripts/gen-goldens.sh` | **一键重建全部 golden**（含 `--verify`） | — | 全部 | 待建（T0-a/T6-b） |
| `scripts/qr-decode-check.mjs` | 第三方解码回读审计（jsQR，含 `--mutate` 负向） | 报告 + 退出码 | 审计（T3-a/b） | **已建**（`scripts/test-audit.sh decode` 包装） |

> 全脚本须在文件头写明：**参考 commit `53e8c99`（fast_qr v0.14.0）**；**参考值禁止手抄，一律由本脚本产出**。

## 附录 C：逐步落地清单（可勾选执行序，v2 重排）

1. [ ] `snapshot_gen_*.rs` 补参考 commit 元数据；新增 `gen-goldens.sh`（重建 + `--verify`）（T0-a/T6-b）
2. [ ] 转译 `default.rs` V1/V3/V7 数字真值矩阵 → 逐格断言（T0-c，**独立真值**）
3. [x] **注入强负向清单**（掩码/Format/N2/division/容量表首项与中间项/cci_bits/set 别名/is_data_byte），记录哪条测试变红（T4-b，**已完成，见附录 E**；入口 `scripts/test-audit.sh mutation`）
3b. [ ] 补 `capacity_bytes` 等常量表**全表值级**校验（T1-f，修掉附录 E 漏检 M11）
4. [ ] 转译 `error_correction.rs` 8 个余数用例（T1-c）
5. [ ] 转译 `structure.rs` 4 组交织用例 + `division`↔`structure` 交叉（T1-d/T1-e）
6. [ ] 抽查 4 例多项式映射 + 表级校验（T1-a）
7. [ ] 写 `scripts/snapshot_gen_score.rs` → 逐行/逐列分数（T2-a/T2-b）
8. [ ] 转译 `structure.rs::placement` 坐标序列（T2-c）
9. [ ] 转译 `version.rs` 两段 Format 双副本取址逻辑（T2-e）
10. [ ] 择优 mask 号核对与回归用例（T2-d）
11. [ ] `snapshot_gen_poly.rs`（若 T1-a 需脚本侧真值）
12. [x] `qr-decode-check.mjs` 审计脚本（jsQR；含 `--mutate` 反向证据）+ `scripts/test-audit.sh` 包装（T3-a/T3-b，**已入库实跑**）
12b. [ ] `cmd` 多内容探针（覆盖三模式 × 4 ECL × 4 版本）（T3-d）
13. [ ] 固化解码向量 `s6_decode_vectors_test.mbt`（T3-c）
14. [ ] 属性测试四则（随机化 + 不可变式 + 掩码互异）（T4-a）
15. [ ] `gc-compare.mjs` 升级为 CI 可选差分门禁（T4-c）
16. [ ] 覆盖率报告与分模块下限（T5）
17. [ ] 失败信息标准化 + 规模/时长护栏 + checksum 断言化（T7）
18. [ ] `AGENTS.md` 测试小节（三载体 + 七铁律）+ README 索引互链（T6）

## 附录 D：T3 解码回读「已实测」结论（2026-09-13，本环境实跑）

> 初版 T3 只有设想；本版把可行性验完并给出可直接照抄的口径。**原始产物不入库**（临时脚本在 `/tmp`）。

| 验证项 | 做法 | 实测结果 |
|--------|------|---------|
| 环境可达性 | `bash scripts/setup-rust.sh` + `bash scripts/build-fast-qr-wasm.sh` | ✅ 参考 wasm 侧产出 `$HOME/.cache/fast_qr_wasm/pkg`（`qr_with` V40H = 31329 B 自检通过） |
| 层② 基线仍在 | `node scripts/gc-compare.mjs --fast … --moon-gc _build/wasm-gc/release/build/cmd/bench/bench.wasm --moonrun moonrun` | ✅ 三点 **sha256 零差异**（V03/V10/V40）且与 `moonrun` 跨宿主一致 |
| MoonBit 侧矩阵导出 | 复用 `gc-compare.mjs` 的宿主 shim + `moonrun` 调 `cmd/bench --dump V03/V10/V40` | ✅ 可直接拿到 0/1 规范矩阵 |
| **第三方解码（MoonBit 侧）** | `jsqr` 解码 `--dump` 矩阵（RGBA 像素化，quiet zone = 4 模块） | ✅ V03/V10/V40 **三点全部读回 `https://example.com/`** |
| **第三方解码（fast_qr 侧）** | `jsqr` 解码 `qr_with` 矩阵 | ✅ 三点同样读回原文（**跨实现语义一致**） |
| 像素标定（重要） | V03（29 模块）`scale=1,q=0/1` 解码 **失败**，`q≥2` 或 `scale≥2` 起 **成功**；V10/V40 全配置成功 | ⚠️ 统一 `scale=4, q=4`；`scale=1` 会让小版本出假红灯（标定表见 T3 前置依赖） |
| 负向对照 | 翻转 1~数个数据模块 | ⚠️ 仍解出原文——**被 RS 纠错完全掩盖**（实测多处翻转亦无效） |
| 负向对照（有效版） | 翻转左上 finder **内环 (1..3,1..3) 共 9 格** | ✅ 三点全部 `NULL`（解码失败）——**T3-b 采用此植入**；脚本 `--mutate` 已实装 |
| 脚本化落地 | `scripts/qr-decode-check.mjs`（正向 + `--mutate` 负向一体） | ✅ 正向 3/3 读回原文；负向 3/3 解码失败（本环境实跑，退出码符合预期） |

**结论**：T3 已从「P1 设想」落为「**P1 已开工**」——审计脚本 `scripts/qr-decode-check.mjs`
与 `scripts/test-audit.sh decode`（可复跑入口）**已入库并实跑通过**；口径、像素标定与负向植入参数如上。
唯一剩余前置是 T3-d 的 `cmd` 多内容探针（现 `cmd/bench` 输入固定为 `https://example.com/`）。

## 附录 E：强负向对照实测（T4-b 已执行，2026-09-13）

> 本节为**实跑结果**：在本仓库 `main` 上就地植入单点缺陷 → `moon test` → 记录 `failed` 数 → `git checkout -- lib/` 还原。
> 可复跑入口：**`bash scripts/test-audit.sh mutation`**（清单与锚点都在脚本里，禁止手抄漂移）。

| # | 植入缺陷（单点最小改动） | 失败数 | 判定 |
|:-:|------------------------|:---:|:---:|
| M1 | `datamasking::mask_at` 掩码 2/3 公式互换 | **2** | ✅ 已检出 |
| M2 | Format 表 L-mask1 的 15 位字错 1 位（29427→29426） | **2** | ✅ 已检出 |
| M4 | `score_squares` 每 2×2 计 4 分（应 3） | **3** | ✅ 已检出 |
| M5 | `division` 余数截断 1 字节 | **10** | ✅ 已检出 |
| M6 | 容量表 `Numeric-L-V01` 41→42（**表首项**） | **3** | ✅ 已检出 |
| M7 | `cci_bits` Numeric 分段 9→8 | **1** | ✅ 已检出 |
| M8 | `QRCode::set` 改回共享数组（破坏不可变） | **1** | ✅ 已检出 |
| M9 | `is_data_byte` 类型位判定放宽（`&7`→`&3`） | **13** | ✅ 已检出 |
| **M11** | 容量表 `Numeric-L` **中间项** 1250→1251 | **0** | ❌ **漏检** |
| **M12** | Format 表 **M-mask3** 值 23371→23370 | **0** | ❌ **漏检** |

**8/10 已检出，2/10 漏检。** 两条漏检的成因**同源且极具体**：

| 漏检项 | 为什么测不出 | 补测方案 |
|--------|-------------|---------|
| M11（容量表中间项改值） | `capacity_bytes` 只有「**表首项**抽查」+「**结构**交叉不变量（分组覆盖/度自洽/`version_for` 最小性）」。**中间项**既不在抽查点、也不被结构约束——改一个值全程无感 | **T1-f**：由参考侧脚本导出**全表值指纹**（逐行 hex 或整表 sha256）并断言 |
| M12（Format 表非抽查项改值） | `format_information` 只有 `(0,0)` 与 `(3,7)` **两个**抽查点；快照只覆盖 V01–V40 中少数 `(ECL,mask)` 组合，恰好没踩到 M-mask3 | **T2-e**：32 组 `(ECL,mask)` 全表逐位断言 + **双副本物理布局** |

### 实测结论（比表格更重要）

1. **初版的两条「预计漏检」被实测推翻**（这是本次审计最大的价值）：
   - `division` 长度断言**有效**（M5 触发 10 条失败）→ **G3 由 P0 降为 P1**，
     剩余缺口收窄为「长度对而值错」这一窄类。
   - 容量表**首项**改值也能被捕获（M6 触发 3 条）→ 说明既有抽查 + 最小性不变量**有效**，
     只是**覆盖不到表的中间项**。
2. **真正的漏检是「常量表的非抽查点」**：数值型常量表（`capacity_bytes`、`format_information`
   等）的保护率取决于**抽查点的数量**，而不是表的正确性——**稀疏抽查 = 稀疏保护**。
   这直接催生 **T1-f（全表值指纹，P0）** 与 **T2-e（Format 32 组 + 双副本，P1）**。
3. **检出密度差异极大**：M9 一处类型位判定触发 **13** 条，M7/M8 只触发 **1** 条。
   说明「单算法黄金值」是失败定位的第一现场，端到端快照是第二道网——**两者不可互相替代**
   （快照能兜住 M4/M5，但兜不住 M11/M12）。
4. **过程中踩到的坑（已固化进脚本）**：`moon test` 会**消费 stdin**。若在 `while read`.
   循环里直接用 `<<<"$table"` 喂 stdin，第一条之后剩余行会被 `moon` 吃掉、**循环静默提前结束**，
   于是早期一版脚本"跑出"了 M6 漏检的**假结论**。现脚本改为「清单落盘 + `read -u 3` + `moon test </dev/null`」。
   **教训：测试基础设施本身也会骗人，审计工具必须先自证（本例用 `bash -x` 逐条核对）。**
5. **元教训**：不做这一步，就无从知道「111 个用例 / 21 个快照」是否真的等于保护力。
   建议把本表固化为「**每新增一个模块的测试后重跑**」的例行检查（入口即 `test-audit.sh mutation`）。

> 执行方式：`bash scripts/test-audit.sh mutation`（自动备份要求 `lib/` 干净、逐条还原并校验）。
> 全过程 ≤15 分钟，**不需要任何额外工具链**。
