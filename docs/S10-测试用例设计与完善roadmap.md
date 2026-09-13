# S10 — 测试用例设计与完善 roadmap（参考 fast_qr 测试体系）

> 目标：以 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 的测试代码/用例为基准，
> 盘点本仓库现有测试资产，定位覆盖缺口，给出**分阶段、可验收**的测试完善路线。
>
> 日期：2026-09-13　｜　基线：本仓库 `main @ a1aba3a`（111 单测全绿）
> ｜　参考检出：`fast_qr` HEAD（`Cargo.toml` version `0.14.0`，`--depth 1`）
> 复跑：`bash scripts/test.sh`（= `moon test`），后端回归 `moon test --target wasm-gc`。
>
> 说明：本文只输出**路线与盘点**，不落测试代码；实施按 §6 阶段逐批提 PR。

---

## 1. 结论摘要（TL;DR）

| 维度 | fast_qr（Rust） | 本仓库（MoonBit） | 判断 |
|------|-----------------|-------------------|------|
| 测试用例数 | `src/tests/*.rs` 167 个 `#[test]` + 11 个源码内联 `#[cfg(test)]` ≈ **178** | **111** 个 `test "…"` | 数量同量级 |
| 测试组织 | 集中式 `src/tests/` 11 文件 + 内联 `mod test` | 就近式：包内 `*_test.mbt`(黑盒)/`*_wbtest.mbt`(白盒) | 本仓库更贴合 MoonBit 约定 |
| 端到端快照 | `default.rs` 3 个手工矩阵（V1/V3/V7） | `m1`+`s6` 共 **21 个**全矩阵 hex 快照（V1/V5/V7/V10/V14/V26/V32/V40） | **本仓库更强** |
| 单算法黄金值 | ✅ 丰富（division/structure/compact/encode/score） | ✅ 大部分已转译（bitbuffer/reedsolomon/encode/score） | 基本对齐 |
| 格式信息逐位 | ✅ `version.rs` 64 用例（4 ECL × 8 mask × 版本/版本信息区） | ⚠️ 仅 `constants_wbtest` 表级 + 快照间接覆盖 | **缺口** |
| 生成多项式全表 | ✅ `generators` 子模块 40 用例（V01–V40 × L/M/Q/H 映射） | ⚠️ 仅 2 个表级抽查 | **缺口** |
| 打分（N1–N4）逐行/逐列 | ✅ `score.rs` 含逐行/逐列分数数组 | ⚠️ 仅合成矩阵 8 用例 | **缺口** |
| 掩码公式面 | ✅ 8/8 | ✅ 8/8（前 4 + 5/6/7 网格 + 等价性） | 对齐 |
| 边界/错误面 | ⚠️ 弱（仅 1 个容差用例） | ✅ 强（V40 边界、too big/too small、V01 最短） | **本仓库更强** |
| 解码回读（第三方解码器） | ⚠️ 未做（`it_can_output_to_bytes_from_image` 已注释） | ❌ 未做 | 两边都缺，**P1 补** |
| 属性/模糊测试 | ❌ 无 | ❌ 无 | 两边都缺，**P2 补** |

**一句话**：本仓库测试在「矩阵级逐位对齐 + 边界错误面」上**已优于参考**，
但参考在「**小函数黄金值密度**（`version.rs` 64 例、`polynomials.rs` 40 例）与
「**逐行/逐列打分明细**」上更细。测试完善路线的主轴是：**补齐参考已有而我们缺的细粒度黄金值
→ 补参考也没有的现代测试手段（解码回读 / 属性测试 / 差分测试）→ 把测试变成 CI 门禁的一部分**。

---

## 2. 基线：本项目测试资产盘点

### 2.1 载体与分工（对齐 AGENTS.md §二.1）

| 载体 | 运行位置 | 可访问范围 | 本仓库使用 |
|------|---------|-----------|-----------|
| `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` API | 公共面：枚举序号、`QRCode`/`QRBuilder`、SVG、终端画、快照 |
| `*_wbtest.mbt` | 包**内**（白盒） | 私有实现 | internal 各子包：位流、常量表、编码、打分、掩码、放置 |
| 源码内联 `test {}` | 包内 | 私有 | 目前**未使用**（见 §4.4 缺口 G7） |

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

### 2.3 快照资产（本仓库的强项）

- `m1_snapshot_test.mbt`：**8** 个固定 mask 用例（V01/V05/V07/V10 × L/M/Q/H）+ **10** 个自动择优
  用例（含期望 mask 号），参考值由 `scripts/snapshot_gen_s6.rs` 在 fast_qr 侧生成。
- `s6_snapshot_test.mbt`：**12** 个三模式 × ECL 矩阵级端到端 + **7** 个特殊边界
  （V01 最短 / V14·V26·V32 版本信息区触发点 / 全自动路径）+ V40H 满容量。
- 覆盖版本：V01 / V05 / V07 / V10 / V14 / V26 / V32 / V40；覆盖 mask：0/1/2/3/5/6/7 + 自动。
- 快照介质：公共 `Module::byte()` = `明暗 | 类型<<1`，与参考 `Module(u8)` 同构。

### 2.4 参考 fast_qr 测试资产盘点

| 文件 | 用例 | 行数 | 覆盖 | 本项目对位 |
|------|-----:|-----:|------|-----------|
| `src/tests/version.rs` | 64 | 3876 | 4 ECL × 8 mask 的 **Format 信息 15 位逐位** + 版本信息区 18 位（V≥7） | ⚠️ 部分（表级 + 快照） |
| `src/tests/polynomials.rs` | 41 | 1168 | `generators` 子模块 V01–V40 × L/M/Q/H → 生成多项式索引 40 例 + 多项式可读串 + `GENERATOR_POLYNOMIALS[31]` 全表 | ⚠️ 2 例抽查 |
| `src/tests/encode.rs` | 13 | 233 | `best_encoding` 7 例 + 三模式位级编码（Numeric 4 / Alnum 1 / Byte 1）+ header 解析 | ✅ 已对齐 |
| `src/tests/compact.rs` | 10 | 200 | `CompactQR` push 系列位级黄金值 | ✅ 已对齐 |
| `src/tests/score.rs` | 8 | 415 | N1–N4 合成 + **逐行/逐列分数数组**（`line_by_line_*`, `col_by_col_*`）+ mask 择优关注列（issue #77 回归） | ⚠️ 缺逐行/列明细 |
| `src/tests/structure.rs` | 8 | 489 | `structure` 交织黄金值 ×5（V05-Q/V10-Q/V07-H/V16-M/V03-Q）+ 二进制串 + 放置逐格手工核对 | ⚠️ 仅 V05-Q 1 例 |
| `src/tests/error_correction.rs` | 8 | 131 | `division` 余数黄金值（含 struct 分块随机用例） | ⚠️ 仅长度校验 |
| `src/tests/datamasking.rs` | 8 | 238 | 8 种掩码 10×10 逐格布尔图案 | ✅ 已对齐 |
| `src/tests/default.rs` | 3 | 262 | `create_mat_from_bool`（bool 矩阵 → Module 类型还原）V1/V3/V7 | ✅ 快照更强 |
| `src/tests/svg.rs` | 2 | 51 | SVG 不反转 + image data-uri 嵌入（本仓库明确不做 image） | ✅ 已对齐（不含 image） |
| `src/tests/bytes.rs` | 2 | 57 | PNG 字节级比对（**已注释**——参考自己也不再稳定维护） | — 不做 |
| `src/module.rs` 内联 | 11 | — | `Module` 全 API（含 `size_of::<Module>()==1`） | ✅ 已对齐（无 sizeof 对位） |
| `src/lib.rs` 文档测试 | 3 | — | `to_str` / `to_file(svg)` / `to_file(png)` doctest | ❌ 缺（MoonBit 无 doctest） |
| `benches/qr.rs` + `benches/README.md` | — | — | Criterion 与 `qrcode` crate 对比（V03H/V10H/V40H） | ✅ 已有等价（`scripts/bench-layer2.sh`） |

> 参考测试的**方法论特征**（值得借鉴）：
> 1. **`#[cfg(test)]` 白盒钩子**：把私有函数（`line`/`place_on_matrix_data`/`generated_to_string`）
>    在测试配置下 `pub` 化后再测；2. **表与快照禁止手抄**（生成器产出）；
> 3. **逐行/逐列分解断言**，而不是只看总分；
> 4. **issue 回归用例带注释**（如 `mask_selection_considers_columns` 对应 issue #77）。

---

## 3. 覆盖差距矩阵（按模块 × 测试手段）

| 模块（本项目） | 对位参考 | 单算法黄金值 | 端到端快照 | 边界/错误 | 逐行明细 | 缺口评级 |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `constants/hardcode` 生成多项式表 | `polynomials.rs::generators` | ⚠️ 2/40 | — | — | — | **P0** |
| `constants/hardcode` 格式信息 | `version.rs` | ⚠️ 表级 | ✅ 间接 | — | — | **P0** |
| `reedsolomon::division` | `error_correction.rs` | ❌ 仅长度 | ✅ 间接 | — | — | **P0** |
| `reedsolomon::structure` | `structure.rs` | ⚠️ 1/5 | ✅ 间接 | — | — | **P1** |
| `matrix::score` N1–N4 | `score.rs` | ⚠️ 合成 | — | — | ❌ | **P1** |
| `matrix::placement` | `structure.rs::placement` | ⚠️ 读回 | ✅ 间接 | — | — | **P1** |
| `constants/capacity` 容量表 | —（参考无独立） | ✅ 交叉一致性 | — | ⚠️ 边界少 | — | P2 |
| `data_encoding` | `encode.rs` | ✅ 对齐 | ✅ 间接 | ⚠️ 单字节 | — | P2 |
| `matrix::datamasking` | `datamasking.rs` | ✅ 对齐 | ✅ 间接 | — | — | ✅ |
| `bitstream` | `compact.rs` | ✅ 对齐 | — | ⚠️ 越界未测 | — | P2 |
| `Module` / 枚举 | `module.rs` 内联 | ✅ | — | — | — | ✅ |
| `QRCode` / `QRBuilder` | `lib.rs` doctest | ✅ 等价护栏 | ✅ | ✅ | — | ✅ |
| `SvgBuilder` / `Shape` | `svg.rs` | ✅ 全串 | ✅ | ⚠️ `from_name` 未测 | — | P2 |
| 终端输出 | `helpers.rs` 无测试 | ✅ 全串 | ✅ | — | — | ✅ |
| **解码回读**（第三方） | ❌ 参考也无 | — | — | — | — | **P1** |
| **属性/模糊测试** | ❌ | — | — | — | — | **P2** |
| **差分测试**（vs 参考实现） | ❌ | — | — | — | — | **P2** |

### 缺口明细（G 编号，供 roadmap 引用）

- **G1 生成多项式全表未逐版本断言**：`hardcode.get_polynomial(v, ecl)` 的 V01–V40 × L/M/Q/H
  → `GENERATOR_POLYNOMIALS[idx]` 映射只抽查了 2 例。参考用 40 个用例显式枚举。
  漏测后果：多项式索引表错位只在特定版本触发，快照覆盖不到全部 160 组。
- **G2 格式信息 15 位未逐 (ECL,mask) 断言**：`format_information(ecl, mask)` 仅表级/交叉一致性，
  参考对 4 ECL × 8 mask 直接断言 15 位序列（且含两个副本的物理布局）。
- **G3 `division`（GF(256) 除法）无黄金余数**：现仅断言余数**长度**。参考有 8 个余数值用例
  （含 V05-Q 分块与随机 struct）。漏测后果：RS 算法本身错误可能被 `structure` 快照掩盖或反之。
- **G4 `structure` 交织仅 1 组黄金值**：参考 5 组（覆盖单块/多块、不同 ECL、含 `< max_bytes` 补齐）。
- **G5 打分无逐行/逐列明细**：参考把某矩阵的每行/每列分数写成数组逐一断言
  （`line_by_line_xiaojiba` / `col_by_col_xiaojiba`），可精确定位「哪一行算错」；
  本项目只有合成矩阵。
- **G6 `placement` 无逐格坐标断言**：参考 `structure.rs::placement` 手工枚举 V02 的
  约 30 段坐标序列；本项目只做「位序读回一致」。
- **G7 无源码内联 `test {}`**：AGENTS.md §二.1 允许，且适合「贴近实现的单行不变量」
  （如 `pack` 位布局、查表边界）。当前全部集中在外部文件，小改动要跨文件跳转。
- **G8 `Shape::from_name` / `Mask::from_int` 等「名字/序号 ↔ 枚举」回环未测**（含未知值回退）。
- **G9 `CompactQR` 越界/容量写满行为未测**（参考 `increase_len` 有动态扩容，本项目为固定容量）。
- **G10 无解码回读**：所有断言都是「与参考实现的输出逐位一致」；
  一旦两侧同时理解错规范（如掩码公式、Format BCH）就同时错且测不出来。需要**独立第三方解码器**
  做终局正确性验证。
- **G11 CI 门禁未含覆盖率/差分**：`.cnb.yml` 只跑 `fmt/check/test/wasm-gc`。

---

## 4. 参考测试的「方法论」提炼（可直接移植）

| 参考做法 | 本项目对应做法 | 落地建议 |
|---------|--------------|---------|
| `#[cfg(test)] pub fn test_*` 白盒钩子 | MoonBit `*_wbtest.mbt` 天然可访问私有 | 直接使用，无需钩子（更干净） |
| 表/快照由生成器产出，禁止手抄 | `scripts/snapshot_gen_s6.rs` 已建立 | **扩充**：为 G1/G2 增加 `snapshot_gen_poly.rs` + `snapshot_gen_format.rs` |
| 逐行/逐列分解断言 | 无 | P1 增加（G5） |
| issue 回归用例带 issue 号注释 | 部分有（`qr_code_set_immutable_no_alias`） | 统一格式：`/// 回归：issue #NN …` |
| doctest（`lib.rs` 顶部示例即测试） | 无 MoonBit 等价物 | 以 `docs`+`cmd/main` 演示 + 在 `cmd/main` 内加断言替代 |
| `size_of::<Module>() == 1` | 无 | MoonBit 无 `size_of`；以位布局断言替代（已做） |
| 与 `qrcode` crate 交叉比对 | `scripts/bench-layer2.sh` 仅比性能 | P2：把「与参考逐位一致」升级为「**与第三方解码器语义一致**」 |

---

## 5. 设计原则（本项目测试的四条铁律）

1. **黄金值必须有出处**：参考值一律由脚本在 fast_qr 侧生成（`scripts/snapshot_gen_*.rs`），
   禁止手抄、禁止「跑一遍写下自己的输出」。
2. **黑盒锁契约、白盒锁实现**：公共 API 语义变化必须先在 `*_test.mbt` 里体现；
   私有实现的重构只允许动 `*_wbtest.mbt`。
3. **快照与单算法值并用**：快照保证端到端不漂移，单算法值保证失败时能定位到函数。
4. **每个缺口配一条「可验收断言」**：路线里的每一项都要写明「怎么判定做完了」。

---

## 6. 分阶段 roadmap

> 阶段沿项目既有 S 编号继续（S1–S9 为实现/性能，S10 为测试）。
> 每阶段一独立 PR，沿用 AGENTS.md §二.4 收尾检查：
> `moon fmt && moon info && moon check --deny-warn && moon test` + wasm-gc 回归。

### 阶段 T1 — 补齐「参考已有、我们缺」的细粒度黄金值（P0）

| 项 | 内容 | 载体 | 来源 | 验收 |
|----|------|------|------|------|
| T1-a (G1) | 生成多项式索引映射 V01–V40 × L/M/Q/H 全 160 组断言，并对 `GENERATOR_POLYNOMIALS` 全 31 表项做长度/首元素校验 | `constants_wbtest.mbt` | 新 `scripts/snapshot_gen_poly.rs`（参考侧打印 `get_polynomial` 的 `len-1`） | 160 组断言全绿；`moon test` 计数 +≥1 |
| T1-b (G2) | `format_information(ecl, mask)` 4×8=32 组 **15 位**序列逐位断言 | `constants_wbtest.mbt` | 新 `scripts/snapshot_gen_format.rs`（参考侧读 `mat[l-1..][8]` 序列） | 32 组 × 2 副本布局逐位一致 |
| T1-c (G3) | `division` 8 组黄金余数（V05-Q 4 组 + struct 分块 2 组 + 小用例） | `reedsolomon_wbtest.mbt` | 直接转译 `src/tests/error_correction.rs` | 余数值逐字节一致 |
| T1-d (G4) | `structure` 补 V10-Q / V07-H / V16-M / V03-Q 4 组交织黄金值（消息区 + 纠错区） | `reedsolomon_wbtest.mbt` | 直接转译 `src/tests/structure.rs` | 5 组（含现有 V05-Q）全绿 |

**工作量估计**：1 个 PR；新增生成器 2 个 + 测试 ~400 行。
**风险**：低——纯追加断言，不改实现。

### 阶段 T2 — 打分与放置的「可定位」测试（P1）

| 项 | 内容 | 载体 | 来源 | 验收 |
|----|------|------|------|------|
| T2-a (G5) | 选一个真实矩阵（V03），断言其**每一行** N1 分数数组与 `test_score_pattern` 明细 | `score_wbtest.mbt` | `src/tests/score.rs::line_by_line_xiaojiba` 方法迁移 | 逐行/逐列数组全等 |
| T2-b (G5) | 矩阵级四规则分量与参考 `example_com`/`fast_qr_com` 同名断言（dark/square/line+col/pattern） | `score_wbtest.mbt` | `src/tests/score.rs` 前三用例 | 4 个分量值一致（需先补参考侧生成器） |
| T2-c (G6) | V02 放置路径**逐格坐标**断言（分段枚举 `mat[r][c] == expected_bit`） | `placement_wbtest.mbt` | `src/tests/structure.rs::placement` | 分段序列全等 |
| T2-d | 择优「列参与评分」回归用例（对 `https://fast-qr.com/` + ECL H，断言期望 mask 号） | `score_wbtest.mbt` / 黑盒 | 参考 issue #77 方法迁移（**注意**：本项目掩码序号语义需先核对） | 断言 mask 号稳定 |

**工作量估计**：1 个 PR；~350 行。
**风险**：中——T2-d 涉及掩码评分口径，需先做一次「参考 ↔ 本项目」mask 号语义核对
（若语义一致则直接可用；若不一致则改为「断言与参考矩阵逐位一致」而非断号）。

### 阶段 T3 — 独立正确性验证：解码回读（P1，本项目新增能力）

> 这是**两边都缺**、但对 QR 库最有价值的一类测试：把生成的矩阵交给**独立解码器**，
> 断言读回原文等于输入。它把「与某实现逐位一致」升级为「符合 QR 规范语义」。

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T3-a | 用 Node 侧成熟解码库（如 `jsQR`/`zxing` 的 JS 移植）解码 `cmd/qr-min` 导出的矩阵，覆盖 三模式 × 4 ECL × {V01,V05,V10,V40} | `scripts/qr-decode-check.mjs`（本地/审计脚本，不进 push CI） | 全部用例解码原文 == 输入 |
| T3-b | 终端画/SVG 产物 OCR/图像化解码路径（可选，依赖重型依赖） | 同上，标记 `optional` | 至少 SVG 路径可被解码器读回 |
| T3-c | 把 T3-a 收敛为**固定向量 + 期望原文**的快照（避免 CI 依赖 npm 安装） | `lib/s6_decode_vectors_test.mbt`（黑盒，只断言我们自己的矩阵自洽 + 解码器结论已固化） | 不引入新依赖即可回归 |

**工作量估计**：1–2 个 PR；主要成本在解码器接入与依赖治理（`scripts/` 为主，入库为向量）。
**风险**：中高——npm 依赖与 CI 环境；建议**解码脚本只做审计**，仓库内固化向量。

### 阶段 T4 — 属性测试与差分测试（P2）

| 项 | 内容 | 载体 | 验收 |
|----|------|------|------|
| T4-a | **属性 1**：任意内容/ECL/版本 → size 恒为 `version*4+17`，功能图案区类型号恒定 | `lib/internal/matrix/*_wbtest.mbt`（伪随机 LCG 循环 N 次） | 1000 次随机抽样全绿 |
| T4-b | **属性 2**：`build_fixed(mask)` 矩阵经 8 种掩码 → 恰好 8 个互不相同的矩阵（同输入） | 黑盒 | 8 个互异 |
| T4-c | **属性 3**：`QRBuilder` 链式与 `QRCode::build` 在随机参数下恒等（现有等价护栏的随机化扩展） | `qr_builder_test.mbt` | 500 组随机参数全等 |
| T4-d | **差分**：`cmd/bench --dump` 输出与参考实现的 hash 对比（已在性能脚本内做 sha256，**升级为独立门禁**） | `scripts/gc-compare.mjs` 提炼 | 3 点 × 全 mask hash 零差异 |
| T4-e | **属性 4**：不可变式 API（`QRCode::set`/`SvgBuilder::*`）无别名副作用（扩展现有单例为随机化） | `*_test.mbt` | 随机 100 次源对象不变 |

**工作量估计**：1 个 PR；~300 行（伪随机用确定性 LCG，避免引入 `rand`）。

### 阶段 T5 — 覆盖率与门禁（P2）

| 项 | 内容 | 验收 |
|----|------|------|
| T5-a | 跑 `moon test --enable-coverage`，产出包级覆盖率报告并存 `docs/` 摘要 | 报告入库（不承诺阈值） |
| T5-b | 设定**分模块覆盖率下限**（先设「不下降」锁定，再逐步抬升） | CI 中 `scripts/test.sh` 附加比较 |
| T5-c | `.cnb.yml` 增加可选 job：`t4-d` 差分校验（需先备好参考 wasm 制品） | CI 绿 |
| T5-d | 死代码/未覆盖 `pub` 清单（用 `moon info` 的 `.mbti` 对比测试引用面） | 产出「无测试引用的 pub 符号」清单为 0（或明确豁免） |

### 阶段 T6 — 测试文档化与维护约定（P2，收口）

| 项 | 内容 | 验收 |
|----|------|------|
| T6-a | 在 `AGENTS.md` 增加「测试三载体分工 + 黄金值出处铁律」小节 | 文案入库 |
| T6-b | 生成器脚本统一入口 `scripts/gen-goldens.sh`（一键重建全部 golden） | 脚本可跑通 |
| T6-c | 本文（S10）与 README 文档索引互链 | 死链检查通过 |

---

## 7. 里程碑与优先级排序

```
T1 (P0 黄金值补齐)  ──►  T2 (P1 打分/放置可定位)  ──►  T3 (P1 解码回读)
                                                     │
                                                     └──►  T4 (P2 属性/差分)
                                                                │
                                                                └──►  T5 (P2 覆盖率门禁)
                                                                          │
                                                                          └──►  T6 (P2 收口)
```

| 优先级 | 阶段 | 理由 |
|:---:|------|------|
| **P0** | T1 | 参考已有、成本低（转译 + 生成器）、直接堵住「表错位/位序错」这类难查缺陷 |
| **P1** | T2 / T3 | T2 让失败可定位；T3 提供**独立**正确性证据（当前最大方法论缺口） |
| **P2** | T4 / T5 / T6 | 属性/差分/覆盖率提升置信度与长期可维护性，但需先有稳定的行为基线 |

**建议节奏**：T1 → T2 各 1 个 PR；T3 先出审计脚本（不入 CI）再固化向量；
T4/T5 待 S9 性能优化收敛后再做（避免测试与实现同时大改）。

---

## 8. 验收标准（Definition of Done）

- [ ] 每个 G 编号缺口在 §6 中都有对应项与验收断言（本文已覆盖 G1–G11）。
- [ ] 每阶段 PR 满足：`moon fmt --check` / `moon check --deny-warn` / `moon test` / `moon test --target wasm-gc` 全绿。
- [ ] 黄金值来源可复现：`scripts/` 内脚本 + 文档命令，第三方可重跑得到同值。
- [ ] 测试命名可定位：失败输出能直接指出「哪个模块/哪一行」。
- [ ] 测试文件行数受控：单文件 ≤800 行（超长拆分，对齐 AGENTS.md §三）。
- [ ] 文档无死链，README 索引已更新。

---

## 9. 与现有文档的关系

| 文档 | 关系 |
|------|------|
| [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) | **上游**：§5「测试规划」定义了三载体分工；本文细化到用例级 |
| [S6-端到端对齐与公共API.md](./S6-端到端对齐与公共API.md) | 提供 `m1`/`s6` 快照的生成方法（本文 §6 T1 沿用同一生成器模式） |
| [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md) | 输出层测试（`s7_*`）的语义基准 |
| [S9-性能基准.md](./S9-性能基准.md) / [性能测试脚本-公开评审说明.md](./性能测试脚本-公开评审说明.md) | 性能/体积基准；本文 §6 T4-d 与其 sha256 护栏对接 |
| [AGENTS.md](../AGENTS.md) | 测试放置与收尾检查的硬性约定 |
| [移植参考/fast-qr-索引.md](./移植参考/fast-qr-索引.md) | 参考库语料入口；本文 §2.4 是其测试面盘点 |

---

## 附录 A：参考 fast_qr 测试清单（逐文件 ↔ 本项目对位）

| 参考文件 | 用例 | 本项目对位文件 | 状态 |
|---------|-----:|---------------|------|
| `src/tests/version.rs` | 64 | `constants_wbtest.mbt` + `m1/s6` 快照 | ⚠️ T1-b |
| `src/tests/polynomials.rs` | 41 | `constants_wbtest.mbt` + `reedsolomon_wbtest.mbt` | ⚠️ T1-a |
| `src/tests/encode.rs` | 13 | `encode_wbtest.mbt` | ✅ |
| `src/tests/compact.rs` | 10 | `bitbuffer_wbtest.mbt` | ✅ |
| `src/tests/score.rs` | 8 | `score_wbtest.mbt` | ⚠️ T2-a/b |
| `src/tests/structure.rs` | 8 | `reedsolomon_wbtest.mbt` + `placement_wbtest.mbt` | ⚠️ T1-d/T2-c |
| `src/tests/error_correction.rs` | 8 | `reedsolomon_wbtest.mbt` | ⚠️ T1-c |
| `src/tests/datamasking.rs` | 8 | `datamasking_wbtest.mbt` | ✅ |
| `src/tests/default.rs` | 3 | `m1_snapshot_test.mbt` / `matrix_pattern_wbtest.mbt` | ✅（更强） |
| `src/tests/svg.rs` | 2 | `s7_svg_test.mbt` | ✅（不含 image） |
| `src/tests/bytes.rs` | 2 | —（PNG 子集不做） | N/A |
| `src/module.rs` 内联 | 11 | `fast_qr_moonbit_wbtest.mbt` | ✅ |
| `src/lib.rs` doctest | 3 | `cmd/main` + README 示例 | ⚠️ T6 |
| `benches/qr.rs` | — | `scripts/bench*.sh` | ✅ |

## 附录 B：黄金值生成器规划

| 脚本 | 用途 | 输出 | 引用方 |
|------|------|------|--------|
| `scripts/snapshot_gen_s6.rs`（已有） | 端到端全矩阵 hex | `CASE\|…\|hex` | `m1`/`s6` 快照 |
| `scripts/snapshot_gen_poly.rs`（T1-a 新增） | `get_polynomial(v,ecl)` 的 `(len-1, first, last)` | TSV | `constants_wbtest.mbt` |
| `scripts/snapshot_gen_format.rs`（T1-b 新增） | 4×8 的 Format 15 位 | TSV | `constants_wbtest.mbt` |
| `scripts/snapshot_gen_division.rs`（T1-c 新增） | `division` 余数向量 | TSV | `reedsolomon_wbtest.mbt` |
| `scripts/snapshot_gen_score.rs`（T2-a/b 新增） | 某矩阵逐行/逐列分数 | TSV | `score_wbtest.mbt` |

> 全脚本须支持「一条命令重建」（T6-b），并在文件头注释里写明：
> **参考值禁止手抄，一律由本脚本产出**。

## 附录 C：逐步落地清单（可勾选执行序）

1. [ ] 写 `scripts/snapshot_gen_poly.rs`，产出 160 组多项式映射 → 落 `constants_wbtest.mbt`（T1-a）
2. [ ] 写 `scripts/snapshot_gen_format.rs`，产出 32 组 Format 位串 → 落 `constants_wbtest.mbt`（T1-b）
3. [ ] 转译 `error_correction.rs` 8 个余数用例 → `reedsolomon_wbtest.mbt`（T1-c）
4. [ ] 转译 `structure.rs` 4 组交织用例 → `reedsolomon_wbtest.mbt`（T1-d）
5. [ ] 写 `scripts/snapshot_gen_score.rs` → 落逐行/逐列分数（T2-a/b）
6. [ ] 转译 `structure.rs::placement` 坐标序列 → `placement_wbtest.mbt`（T2-c）
7. [ ] 择优 mask 号核对与回归用例（T2-d）
8. [ ] 解码回读审计脚本 + 向量固化（T3）
9. [ ] 属性测试四则（随机化 + 不可变式）（T4）
10. [ ] 覆盖率报告与门禁（T5）
11. [ ] `AGENTS.md` 测试约定小节 + `scripts/gen-goldens.sh` + 索引互链（T6）
