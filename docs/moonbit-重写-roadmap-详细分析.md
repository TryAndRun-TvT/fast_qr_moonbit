# fast_qr → MoonBit 重写 roadmap · 详细分析

> 依据对参考库 **fast_qr v0.14.0** 源码（检出于 `/fast_qr`，commit `53e8c99`，master）的
> 逐项核对与架构分析，给出用 **MoonBit** 重写的评估结论与分阶段 roadmap。
> 本文承接 [项目基础框架-详细分析](./项目基础框架-详细分析.md)（目标结构/适配点/验证策略）
> 与 [跨语言重写评估](./移植参考/专有概念/跨语言重写评估.md)（通用重写策略），
> 叠加**源码级已核验**细节，供实现阶段直接执行。
>
> 日期：2026-09-05　｜　依据索引见 §6

---

## 0. 结论速览

| 项 | 结论 |
|----|------|
| 参考对象 | fast_qr v0.14.0（MIT），master `53e8c99`（chore: 0.14 release），源码已检出于 `/fast_qr` |
| 语料核对 | 既有 [移植参考语料](./移植参考/fast-qr-索引.md) 中的行号/规模/常量论断与源码**全部吻合，无需更正**（§1.2） |
| 重写策略 | 机械翻译 + 黄金数据/矩阵快照双层验证（详见语料与框架文档） |
| 本环境前提 | 有 `moon`（0.1.20260827），**无 cargo/rustc** → 快照/黄金数据生成需一次具备 Rust 的环境（§4.1） |
| 预估节奏 | 单包起步 → 全功能对齐 → 性能/分发；关键里程碑 M1=Byte 首码对齐、M2=全版本×ECL 快照对齐（§4.4） |

---

## 1. 参考源码与语料核对

### 1.1 克隆与源码树

```bash
git clone --depth 1 https://github.com/erwanvivien/fast_qr /fast_qr
# master @ 53e8c99 "chore: 0.14 release"；Cargo.toml version = "0.14.0"
```

源码树与语料描述一致：`src/` 下 14 个核心文件 + `convert/{mod,svg,image}.rs` + `wasm.rs`；
`src/tests/` 11 个测试模块；另有 `benches/qr.rs`、`examples/`、`wasm-pack.sh`、`pkg/`。

### 1.2 核对结论（抽检关键论断，全部命中）

| 语料论断 | 源码实测 |
|------|------|
| `version.rs` 819 行、const fn `get` 在 :96 | 819 行；`get(mode,ecl,len)` @ :96 |
| `hardcode.rs` 412 行；`ecc_to_groups` :14（u32 位打包）；`get_polynomial` :324 | 412 行；:14、:324 命中 |
| `module.rs` struct :42、`ModuleType` enum :4（判别值 `0<<1…7<<1`） | 命中（`Data = 0 << 1` … `Empty = 7 << 1`） |
| `qr.rs` `QRBuilder` :200、`QRCode` :25 | 命中 |
| `compact.rs` `KEEP_LAST` 65 项（:34）/ wasm32 33 项（:53）；`from_version` :100、`push_bits` :177、`push_u8` :146、`fill` :213 | 命中（`#[cfg(target_arch=…)]` 两分支） |
| `polynomials.rs` LOG :11 / ANTILOG :28、`division` :83→`[u8;255]`、`structure` :106→`[u8;5430]` | 命中 |
| `placement.rs` 141 行；`place_on_matrix` :85、总装 `create_matrix` :122 | 命中 |
| `score.rs` 201 行；N3 窗口 11 bit（`0b00001011101`/`0b10111010000`）、`line` :82、`score` :195 | 命中（quiet zone 注释属实） |
| 列评分必须在掩码后（placement 100-104 历史 bug 注释） | 命中 |
| `wasm.rs` 236 行；`qr` :18、`SvgOptions` :27、`qr_svg` :202 | 命中 |
| 测试：11 模块；`version` 3876、`polynomials` 1168、`structure` 489、`score` 415、`compact` 200 行 | 全部命中（wc 复核） |
| 规模：核心管线约 3280、convert+wasm 约 1170、测试约 7100；`encode`+`compact`=426、`module`+`qr`=470 | 命中 |
| 基准：V03H 82.2us/6.51x、V10H 269.3us/7.85x、V40H 2436.2us/7.40x；bench 输入 `https://example.com/`，V03/V10/V40 × ECL H | README/benches 命中 |
| Cargo：edition 2021、rust-version 1.59、MIT；feature `svg`/`image`(含 svg+resvg)/`wasm-bindgen`；release `opt-level='s'`+LTO+`codegen-units=1`+`panic='abort'` | 命中 |

> 结论：**移植参考语料可直接作为实现依据，无需勘误。** 本环境缺 Rust 工具链是后续执行（非分析）约束。

---

## 2. 架构分析要点（源码级）

### 2.1 模块与依赖

单向管线：`encode → compact → polynomials → placement/default → datamasking/score → qr`；
`convert/` 与 `wasm.rs` 只消费 `QRCode` 矩阵，属外围。

### 2.2 7 条性能决策的源码锚点（已核验）

1. 固定矩阵 `[Module; 31329]`：`qr.rs` `QRCode.data`
2. 单字节 Module 打包（bit0 明暗 + bit1-3 类型号，判别值 `<<1`）：`module.rs:4,42`
3. 预分配比特缓冲：`compact.rs:100`（`len*8` 一次分配）
4. 编译期常量表：`version.rs:96` 起 const fn、`hardcode.rs` 全 const、GF LOG/ANTILOG `polynomials.rs:11-42`
5. 掩码择优成本：`placement.rs:85-119`（基础矩阵一次构建、8 轮 clone+mask+score）
6. 无分支/查表热点：`compact.rs:177` `push_bits`、`polynomials.rs:83` 查表除法
7. 体积链：Cargo release profile + `wasm-pack.sh`（build-std/panic_immediate_abort/wasm-opt -Oz）

### 2.3 规范未明说、必须照抄的实现决策（源码注释实证）

| 决策 | 源码证据 |
|------|---------|
| 评分 quiet zone：行首/行尾补浅色模块，双侧浅命中计两次 | `score.rs:84-100` 注释 |
| 列评分必须在掩码后 | `placement.rs:100-104` 注释（历史 bug） |
| N3 11 位窗口按值扫描整行 | `score.rs` `PATTERN_LIGHT_BEFORE/AFTER/WINDOW` 常量 |
| 掩码 5/6 共用 6x6 网格 + OFFSETS（Fields 4 项 / Diamonds 12 项） | `datamasking.rs:94,126,133` |
| Format 区先占位、掩码择优后覆写 | `default.rs` 图案绘制与 `placement.rs` 时序 |
| GF 交织方向：数据区逐块跨字节、纠错区逐字节跨块 | `polynomials.rs` `structure` |
| 只翻转 Data 类模块 | `datamasking.rs` 各 mask 先判类型 |

---

## 3. 用 MoonBit 重写：思考 && 评估

### 3.1 保留什么（语义契约，不可改动）

1. 模块位布局与「只动 Data」规则（框架文档 §五.1-2）
2. 编码/纠错/交织/掩码/评分全部数值语义（框架文档 §五.3-10）
3. 黄金数据 + 快照验证体系（§4.1）

### 3.2 Rust 机制 → MoonBit 的替代/注意点

| Rust 侧机制 | MoonBit 重写注意（实现时验证） |
|------------|------------------------------|
| `const fn` 大容量表（version/hardcode） | 表量级大且含 40 版本×模式×ECL——用**提取脚本**从 `/fast_qr` 源码生成表数据与黄金断言，禁止手抄 |
| `[u8; 5430]`/`[Module; 31329]` 固定数组 | 明确用固定容量容器；关注大数组逃逸与初始化开销 |
| `usize` 位宽差异（KEEP_LAST 65/33） | `wasm`/`wasm-gc`/`js` 后端一致性实现时按 `compact.rs` cfg 两分支核对 |
| `u8` 回绕 / u32 位打包 | 位运算显式掩码（`& 0xFF`/`& 0xFFFF`），黄金测试覆盖 |
| `% 255` alpha 加法 | 无负数场景，仍加断言防越界 |
| `panic=abort`/LTO/opt-level 优化链 | MoonBit 骨架 wasm-gc 仅 440 B，天然小；体积/性能优化推迟到 P2 评估 |
| 枚举判别值 `<<1` | MoonBit 若无原始判别值枚举，用 Byte + 常量掩码方案替代（详见框架文档 §四/§五） |

### 3.3 不做的事

- 不按 ISO 规范“重新实现”（会重新踩上述全部决策点；已由源码注释证实其存在）。
- 不在功能对齐前做性能优化（正确性未收敛前优化会干扰定位）。
- 不在实现前空建子包目录（`moon.pkg` 未用依赖会触发 `unused_package`）。

---

## 4. Roadmap 详细规划

### 4.1 验证基座（任何编码前的第一步）

**前提**：本容器无 `cargo`/`rustc`。快照与黄金数据需在**具备 Rust 的环境**执行一次：

1. **矩阵快照**：在 `/fast_qr` 增加一个 ~30 行的小工具（或临时 example）：
   输入 (content, ECL, 可选 version/mask) 列表 → 输出每条含最终 version/ecl/mask 与
   31329 字节矩阵的 JSON。快照集建议约 60 条（4 ECL × 3 模式 × 低/中/高版本 + V7/V14/V26/V32
   版本信息触发点 + V1-L 最短 / V40-H 满容量边界 + 指定 mask/version 路径）。
2. **黄金数据**：从 `/fast_qr/src/tests/{version,polynomials,structure,compact,encode,score,datamasking}.rs`
   提取期望值表（3876/1168/489/200/233/415/238 行现成断言），转译成 MoonBit 测试常量。
3. 产出入库后常驻：`_wbtest.mbt` 单元级、`_test.mbt` 公共行为级。

> 验收标志：60 快照 JSON 生成；version/hardcode/polynomials 黄金单测在 MoonBit 侧转译后全绿。

### 4.2 实现顺序（按 internal 子包落地，出现信号再细分）

> 布局说明：仓库已采用**方案 3**（模块根无包），库包在 `lib/`，实现子包在
> `lib/internal/`（constants/bitstream/reedsolomon/data_encoding/matrix，见
> [moonbit-实现布局与文件职责](./moonbit-实现布局与文件职责.md)）。下表各步落点为对应子包
> （B 表目标文件名即其内文件）；原「S8 拆包」语义调整为：在既有 internal 包之上，
> 出现细分信号时再拆。

| 步 | 内容 | 参考源码（已核验锚点） | 对应黄金/快照 |
|----|------|------------------------|---------------|
| S1 | 数据结构：Module 打包、QRCode 固定数组、CompactQR、错误类型、公共枚举骨架 | `module.rs` / `qr.rs:25,200` / `compact.rs:61-224` / `version.rs` / `ecl.rs` | `tests/compact.rs` |
| S2 | 常量表提取 + GF(256)（division/structure） | `hardcode.rs` / `version.rs:96` / `polynomials.rs:11-106` | `tests/version.rs`、`tests/polynomials.rs`、`tests/structure.rs` |
| S3 ✅ | 三模式 encode + 容量选择（D2：一次全落三模式） | `encode.rs` / `version.rs` | `tests/encode.rs` |
| S4 ✅ | default 功能图案 + placement 之字形放置（固定 mask 首码）【D3 module helper + 8 掩码数学式 + **B9a 功能图案/Format 覆写 + B9b 之字形放置 + M1 lib 最小编排入口均已落**（对照 fast_qr v0.14.0 固定 mask 快照逐位对齐，测试 77）；固定 mask 首码闭环达成，见 [S4 实现记录](./S4-矩阵与放置-实现记录.md)】 | `default.rs` / `placement.rs:36` | 快照（固定 mask 路径） |
>
> - **S4 详细方案见 [S4-矩阵与放置-实现方案](./S4-矩阵与放置-实现方案.md)**：在 `internal/matrix` 落
>   `matrix.mbt`（功能图案）+ `placement.mbt`（之字形放置）+ 8 掩码实现，以**固定 mask** 串
>   encode→structure→放置→Format 闭环产出 M1 首码；含 D3 原始字节矩阵介质决策与快照验收策略。
| S5 ✅ | 8 掩码 + 4 评分 + 择优主循环（最难点） | `datamasking.rs` / `score.rs` / `placement.rs:85-119` | 全量快照对齐 |
>

> - **S5 已落地（据 [S5 实现记录](./S5-掩码评分与择优-实现记录.md)）**：8 掩码随 S4 落；S5 补齐
>   4 条评分（score.mbt N1/N2/N3/N4）+ 8 轮 clone+score 择优主循环（placement `create_auto_qr`）
>   + N4 表 `PERCENT_SCORE`（constants）+ lib 自动择优 `QRCode::build`（mask 可 None）。对照
>   fast_qr v0.14.0 自动择优快照（10 用例最优 mask + 全矩阵）逐位对齐，双后端全绿（测试 77→85）。

> - **S4/S5 掩码分批（据 S4 方案 §5）**：8 种掩码**数学式实现**随 S4 落（可独立快照验证）；
>   S5 只做 **4 条评分 + 8 轮 clone+score 择优主循环**（B10 后半）——降低 S5 耦合、避免 S4 只写
>   单掩码再返工补 7 种。
| S6 | 60 快照端到端对齐 + 公共 API 完善（三模式已在 S3 落地） | `lib.rs` 导出面 | 60 快照 100% |
| S7 | 输出层：`to_str` 终端画 + SVG（按需） | `helpers.rs` / `convert/svg.rs` | `tests/svg.rs` 快照 |
| S8 | 拆 `internal/` 子包（触发信号：文件过多/分层/私有类型需进 `.mbti` 之外） | 见框架文档 §三.2 | `.mbti` 对照 |
| S9 | 性能：移植三基准点 V03H/V10H/V40H（输入 `https://example.com/`） | `benches/qr.rs` | 透明对比（无硬门槛） |
> - **S6 已落地（据 [S6-端到端对齐与公共API-实现记录.md](./S6-端到端对齐与公共API-实现记录.md)、方案见
>   [S6-端到端对齐与公共API-实现方案.md](./S6-端到端对齐与公共API-实现方案.md)）**：承接 S5 锁定的自动择优
>   正确性，落地公共 `QRBuilder` 构造器（new/from_string + mode/ecl/version/mask 不可变链式 setter +
>   build，对齐 lib.rs 导出面）+ 快照收口（三模式×4ECL 矩阵级 + V01/V14/V26/V32 + V40-H 满容量 +
>   自动 mask 路径，约 20 条参考全矩阵逐位对齐 0 差异），收敛里程碑 **M2 功能对齐**
>   （测试 85→94 +9，双后端全绿）。roadmap §4.1 原 60 条中大量 Byte 固定 mask 用例已在 S4/S5 逐位对齐，
>   本阶段补的快照精确对准 S6 真实缺口即「60 快照全量对齐」的覆盖收口。
>   ⚠️ 已评审判定：此前的「全参数 None 纯自动 ×3 对参考逐位」表述失实——C 组实为 mode/ecl/version 冻结、
>   仅 mask 自动；真全 None 分支缺参考端到端快照，详见
>   [S6-实现评审与优化-记录.md](./S6-实现评审与优化-记录.md) §2.1。

> - **S7 详细方案见 [S7-输出层to_str与SVG-实现方案.md](./S7-输出层to_str与SVG-实现方案.md)**：输出层——
>   `helpers.mbt` 落地终端画 `print_matrix_with_margin`（含四态映射与边距）+ `QRCode::to_str`/`print`
>   （对齐 `helpers.rs`/`qr.rs:174-185`，补 M1「CLI 输出」欠账）；`lib/svg.mbt` 落地公共 `Shape`+
>   `SvgBuilder`（margin/shape/module_color/background_color + `to_str(qr)`）纯字符串 SVG 输出（对齐
>   `convert/svg.rs` 不依赖 resvg/file IO 的子集）；含参考**全串快照**逐字节对齐验收（比 tests/svg.rs 更严）。
>   S7 不做 PNG/image.rs 与 wasm 嵌图子集（无 resvg/无 wasm-bindgen 对应物，按需/二期）。
> - **S7 方案评估见 [S7-输出层to_str与SVG-实现评估与优化-记录.md](./S7-输出层to_str与SVG-实现评估与优化-记录.md)**：独立检出
>   fast_qr v0.14.0 参考源码逐行复核方案，方向正确无致命漏洞；补 circle 形状特例 / `<svg>` 的 `xmlns` /
>   多 shape → 多 `<path>` / 坐标已含 margin 等 4 处精确核对点 + Shape↔字符串映射等优化建议。


> - **S7 已落地（据 [S7-输出层to_str与SVG-实现记录.md](./S7-输出层to_str与SVG-实现记录.md)、方案见
>   [S7-输出层to_str与SVG-实现方案.md](./S7-输出层to_str与SVG-实现方案.md)）**：输出面补齐达成——`helpers.mbt`
>   落地终端画 `print_matrix_with_margin`（四态映射/上边距两行合一/末行，逐字符对齐 `helpers.rs`）+
>   `QRCode::to_str`/`print`（委托，对齐 `qr.rs:174-185`）；`lib/shape.mbt` 公共 `Shape` 枚举 + 名字↔枚举映射、
>   `lib/svg.mbt` 公共 `SvgBuilder`（margin/shape/module_color/background_color 值语义 + `to_str`）纯字符串 SVG
>   （6 形状 path 片段集中常量、rounded 描边特判、多 shape→多 `<path>`、坐标含 margin，对齐
>   `convert/{mod,svg}.rs` 子集）；参考**全串字节对齐**快照（受控矩阵 ×6 形状 + 多 shape + 真实 V01/V05 终端画
>   + 真实 V01 SVG）比 tests/svg.rs 的 contains 更严；`cmd/main` 落地真码终端画+SVG 输出（补 M1 CLI 欠账）；
>   roadmap §4.4 输出面补齐完成，测试 94→109，双后端全绿。下一步为 S8（internal 拆包）/S9（性能）。

### 4.3 代码迁移路线图（文件级）

把 §4.2 的步骤落到**逐个 Rust 文件**的迁移上。顺序 = 源码依赖方向；每一层完成即可独立验证，
保持 `moon fmt/check/test` 常绿：

```
[数据/常量层]  ecl → version → hardcode → polynomials(LOG/ANTILOG/除法/交织)
                     ↓
[结构层]      module → compact → qr(QRCode/错误/QRBuilder 骨架)
                     ↓
[算法层]      encode → default(图案) → placement(放置) → datamasking → score
                     ↓
[组装/输出层]  lib 导出面 → helpers(to_str) → convert/svg（按需）
```

| 迁移批次 | 源文件（/fast_qr → 目标 .mbt） | 关键交付 | 自检（本批即绿） |
|---------|------------------------------|---------|-----------------|
| B1 | `ecl.rs` → `ecl.mbt` | ECL 枚举与判别 | 白盒断言判别值 |
| B2 | `version.rs` → `version.mbt` | 容量/元数据表（**脚本从源码提取**，禁止手抄） | 抄自 `tests/version.rs` 的黄金单测 |
| B3 | `hardcode.rs` → `hardcode.mbt` | 分组（u32 打包）/格式信息/生成多项式表 | 表值抽测 |
| B4 | `polynomials.rs` → `reedsolomon.mbt` | LOG/ANTILOG + `division` + `structure` | `tests/polynomials.rs` + `tests/structure.rs` 全绿 |
| B5 | `module.rs` → `module.mbt` | Module 位打包 + 类型/明暗读写 | 位级断言（含「只动 Data」） |
| B6 | `compact.rs` → `bitbuffer.mbt` | CompactQR（大端序、KEEP_LAST、fill） | `tests/compact.rs` 全绿 |
| B7 | `encode.rs` → `encode.mbt` | 三模式编码 + 容量选择（S3 已落地，D2） | `tests/encode.rs` |
| B8 | `qr.rs` → 根包入口 | QRCode 组装 + 公共 API/错误面 | 黑盒行为用例 |
| B9 | `default.rs` / `placement.rs` → 放置层 | 图案绘制 + 之字形放置（跳第 6 列） | 固定 mask 首码与快照一致（M1） |
| B10 | `datamasking.rs` / `score.rs` → 择优层 | 8 掩码 + 4 评分 + 择优主循环 | 全量快照对齐（M2） |
| B11 | `helpers.rs` / `convert/svg.rs` → 输出层 | `to_str` / SVG（按需） | `tests/svg.rs` 风格快照 |

**提交切分建议**：每个批次一个提交，消息形如 `feat(qr): 迁移 <模块>（参照 <Rust 文件>）`；
表数据/黄金数据用「生成脚本」产出、结果入库，脚本本身不入库（或放独立 `tools/`，避免进入产物）。
迁移原则：**先数据表、后算法、最后组装**；任何批次不允许把未迁移文件里的符号提前声明
（`unused_package`/`missing_doc` 会挡门禁）。

### 4.4 里程碑

| 里程碑 | 含义 | 验收 |
|--------|------|------|
| M0 ✅ | 验证基座 + 数据结构全绿 | S1-S2 完成；单测与黄金数据通过 |
| M1 ✅ | 编码 + 放置最小路径跑通 | 固定参数首码与参考快照逐位一致（S4 达成，测试 77）；CLI 已 import 库并输出 |
| M2 | **功能对齐** | 60 快照 100% 逐位一致；API 面与 `lib.rs` 导出对齐（待 S5 评分择优 + S6 全量快照） |
| M3 | 性能与分发基线 | 三基准点可跑并给出对比数字；后端/产物分发结论记录在案 |

### 4.5 收尾门禁（沿用 AGENTS.md）

```bash
moon fmt && moon info && moon check --deny-warn && moon test
for t in wasm-gc wasm js; do moon build --target $t --release; moon test --target $t; done
```

---

## 5. 汇总

1. **分析已完成**：fast_qr v0.14.0 源码与既有参考语料逐项核对**零出入**，语料可直接作为实现依据。
2. **评估**：MoonBit 重写采用「机械翻译 + 双层验证」；需替换的是 Rust 编译器机制
   （const fn 大表、固定数组、位宽、优化链），需照抄的是全部算法语义与工程 bug 决策。
3. **Roadmap**：先建验证基座（需一次 Rust 环境）→ S1-S9 顺序实现 → M2 全量快照对齐为功能完成
   标志 → M3 性能透明。当前仓库代码仍为骨架，此 roadmap 即实现阶段蓝图。

**下一步（首个可执行动作）**：在具备 Rust 的环境运行 §4.1 快照/黄金数据生成，产物入库后启动 S1。

---

## 6. 参考

- 参考源码：`/fast_qr`（fast_qr v0.14.0，master `53e8c99`）；<https://github.com/erwanvivien/fast_qr>
- 语料入口：[fast-qr-索引.md](./移植参考/fast-qr-索引.md)（架构/接口/概念/模块，已核对）
- MoonBit 汇总：[项目基础框架-详细分析.md](./项目基础框架-详细分析.md)
- 通用重写策略：[跨语言重写评估.md](./移植参考/专有概念/跨语言重写评估.md)
- 仓库文档索引见 [README.md](../README.md)「文档」
