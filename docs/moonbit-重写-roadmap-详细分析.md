# fast_qr → MoonBit 重写 roadmap · 详细分析

> **状态**：历史　｜　日期：2026-09-06　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §7　｜　并入：路线已全部落地，结论并入 [项目基础框架-详细分析](项目基础框架-详细分析.md) / [moonbit-实现布局与文件职责](moonbit-实现布局与文件职责.md)

> ⚠️ **历史记录**：MoonBit `wasm`(WASI) 后端已按项目决策移除，本项目现仅支持 `wasm-gc`；本文涉及的 `wasm` 后端数字与口径仅作历史留存，不再作为对外口径。

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
| S4 ✅ | default 功能图案 + placement 之字形放置（固定 mask 首码）【D3 module helper + 8 掩码数学式 + **B9a 功能图案/Format 覆写 + B9b 之字形放置 + M1 lib 最小编排入口均已落**（对照 fast_qr v0.14.0 固定 mask 快照逐位对齐，测试 77）；固定 mask 首码闭环达成，见 [S4 实现记录](./S4-矩阵与放置.md)】 | `default.rs` / `placement.rs:36` | 快照（固定 mask 路径） |
>
> - **S4 详细方案见 [S4-矩阵与放置-实现方案](./S4-矩阵与放置.md)**：在 `internal/matrix` 落
>   `matrix.mbt`（功能图案）+ `placement.mbt`（之字形放置）+ 8 掩码实现，以**固定 mask** 串
>   encode→structure→放置→Format 闭环产出 M1 首码；含 D3 原始字节矩阵介质决策与快照验收策略。
| S5 ✅ | 8 掩码 + 4 评分 + 择优主循环（最难点） | `datamasking.rs` / `score.rs` / `placement.rs:85-119` | 全量快照对齐 |
>

> - **S5 已落地（据 [S5 实现记录](./S5-掩码评分与择优.md)）**：8 掩码随 S4 落；S5 补齐
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
> - **S6 已落地（据 [S6-端到端对齐与公共API.md](./S6-端到端对齐与公共API.md)、方案见
>   [S6-端到端对齐与公共API.md](./S6-端到端对齐与公共API.md)）**：承接 S5 锁定的自动择优
>   正确性，落地公共 `QRBuilder` 构造器（new/from_string + mode/ecl/version/mask 不可变链式 setter +
>   build，对齐 lib.rs 导出面）+ 快照收口（三模式×4ECL 矩阵级 + V01/V14/V26/V32 + V40-H 满容量 +
>   自动 mask 路径，约 20 条参考全矩阵逐位对齐 0 差异），收敛里程碑 **M2 功能对齐**
>   （测试 85→94 +9，双后端全绿）。roadmap §4.1 原 60 条中大量 Byte 固定 mask 用例已在 S4/S5 逐位对齐，
>   本阶段补的快照精确对准 S6 真实缺口即「60 快照全量对齐」的覆盖收口。
>   ⚠️ 已评审判定：此前的「全参数 None 纯自动 ×3 对参考逐位」表述失实——C 组实为 mode/ecl/version 冻结、
>   仅 mask 自动；真全 None 分支缺参考端到端快照，详见
>   [S6-端到端对齐与公共API.md](./S6-端到端对齐与公共API.md) §2.1。

> - **S7 详细方案见 [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md)**：输出层——
>   `helpers.mbt` 落地终端画 `print_matrix_with_margin`（含四态映射与边距）+ `QRCode::to_str`/`print`
>   （对齐 `helpers.rs`/`qr.rs:174-185`，补 M1「CLI 输出」欠账）；`lib/svg.mbt` 落地公共 `Shape`+
>   `SvgBuilder`（margin/shape/module_color/background_color + `to_str(qr)`）纯字符串 SVG 输出（对齐
>   `convert/svg.rs` 不依赖 resvg/file IO 的子集）；含参考**全串快照**逐字节对齐验收（比 tests/svg.rs 更严）。
>   S7 不做 PNG/image.rs 与 wasm 嵌图子集（无 resvg/无 wasm-bindgen 对应物，按需/二期）。
> - **S7 方案评估见 [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md)**：独立检出
>   fast_qr v0.14.0 参考源码逐行复核方案，方向正确无致命漏洞；补 circle 形状特例 / `<svg>` 的 `xmlns` /
>   多 shape → 多 `<path>` / 坐标已含 margin 等 4 处精确核对点 + Shape↔字符串映射等优化建议。


> - **S7 已落地（据 [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md)、方案见
>   [S7-输出层to_str与SVG.md](./S7-输出层to_str与SVG.md)）**：输出面补齐达成——`helpers.mbt`
>   落地终端画 `print_matrix_with_margin`（四态映射/上边距两行合一/末行，逐字符对齐 `helpers.rs`）+
>   `QRCode::to_str`/`print`（委托，对齐 `qr.rs:174-185`）；`lib/shape.mbt` 公共 `Shape` 枚举 + 名字↔枚举映射、
>   `lib/svg.mbt` 公共 `SvgBuilder`（margin/shape/module_color/background_color 值语义 + `to_str`）纯字符串 SVG
>   （6 形状 path 片段集中常量、rounded 描边特判、多 shape→多 `<path>`、坐标含 margin，对齐
>   `convert/{mod,svg}.rs` 子集）；参考**全串字节对齐**快照（受控矩阵 ×6 形状 + 多 shape + 真实 V01/V05 终端画
>   + 真实 V01 SVG）比 tests/svg.rs 的 contains 更严；`cmd/main` 落地真码终端画+SVG 输出（补 M1 CLI 欠账）；
>   roadmap §4.4 输出面补齐完成，测试 94→109，双后端全绿。下一步为 S8（internal 拆包）/S9（性能）。
> - **S8 详细方案见 [S8-内部结构归位与分层.md](./S8-内部结构归位与分层.md)**：按 §三.2
>   拆包判据对 post-S7 代码库逐条核对后判定——roadmap 原义「拆 internal 子包」已被 S1-S5 实质达成，
>   internal 五子包单一职责/测试齐备、**无再拆信号**；真正命中判据的是 **lib 公共层的失效入口
>   `fast_qr_moonbit.mbt`（仍自称骨架、实已实现）+ `qr.mbt`（401 行）混容器/编排/builder/output 三类子关注**。
>   S8 定方案 = 公共层**文件级职责归位**（拆 qr.mbt → qr_build/qr_builder/qr_output，不改 `.mbti`、不加 internal
>   包、无逻辑改动）+ 入口文档刷新，低风险收口、回归 109 全绿即验收。
>   **S8 拆改已落地（2026-09-06，据本方案 §4 清单执行）**：qr.mbt → qr_build/qr_builder/qr_output 同包文件级
>   拆分完成、`fast_qr_moonbit.mbt` 刷新为真实库入口文档头、README 项目结构树补 qr_build/qr_builder/qr_output；公共
>   `lib` 包 `.mbti` 拆前拆后 **零漂移**（接口集不变）、测试维持 **109 全绿**（纯搬移未增减行为测试）。roadmap 原义
>   「拆 internal」经核对**不拆**（internal 无再拆信号）。

> - **S9 详细方案见 [S9-性能基准.md](./S9-性能基准.md)**（2026-09-06 按「本项目与
>   fast_qr 主比较 wasm 产物性能」修订对比分层）：承接 S8 合入（测试 109）后性能三基准点移植（roadmap §4.2
>   S9，收敛 M3）。核心架构事实——MoonBit `Int` 32 位，`bitbuffer.mbt` 的 `KEEP_LAST` 取 Rust **wasm32 分支**
>   （33 项、对全部后端生效），本仓库是 **wasm 形态**移植，故与其语义最贴近的 fast_qr 参照物是 **wasm32
>   build**（`wasm-pack.sh` 产物 `fast_qr_bg.wasm`），而非 64 位 native（KEEP_LAST=65）。故「透明对比」三层
>   分层：① wasm-gc/wasm 跨后端选型（同源码、host 计时）；② **MoonBit-wasm-gc/wasm vs fast_qr-wasm32**
>   （同执行模型、**不依赖 C 工具链、当前环境可落地，主口径**：逐位对齐 + 计时双验证）；③ native MoonBit vs
>   fast_qr native（可选方法学量级注记、需 C 工具链环境、注明内存模型差异，非主口径）。参考 82.2/269.3/
>   2436.2 us 标注为「64 位 native」并提示口径。S9 定方案 = 新增 `cmd/bench` 基准命令 + `scripts/bench.sh`
>   宿主计时（D14/D15），计时口径同时喂层①与层②；三基准点 = `QRBuilder::from_string(input).ecl(H).
>   version(V03/V10/V40).build()`，强制版本语义待实现时对 `benches/qr.rs` 核对（V03H 恰为 20 字节 Byte-H
>   最小适配版本，V10/V40 强制升版；fast_qr wasm 侧自动择优需对参考核对）；只测基线、**不并入** S5 O1
>   （8 轮 clone→就地翻转）等正确性敏感主循环重构（单列 P2）。回归 109 全绿 + 快照零差异即安全。
> - **S9 方案评估见 [S9-性能基准.md](./S9-性能基准.md)**（2026-09-06）：独立重读实码 + roadmap 复核 S9 方案，方向正确无致命漏洞；更正输入 `https://example.com/` 为 **20 字节**（roadmap 本行「19 字节」同步更正为 20，V03H 最小适配结论不变）、bench 循环须消费 build 结果防空循环（死代码消除）、补「KEEP_LAST 33 vs 65 对真实 QR 语义无差别」论证（真实路径 push≤16 位、index>16 不触达）→ 把层②逐位对齐重新定位为对既有 S1-S7 快照对齐的跨宿主重确认，增量价值在计时可比性。供 S9 实现阶段直接执行前兜底。
> - **S9 实现落地（层①基准载体 + 跨后端数字）见 [S9-性能基准.md](./S9-性能基准.md)**（2026-09-06）：落地 `cmd/bench`（三基准点 V03H/V10H/V40H，输入 `https://example.com/`=20 字节、ECL=H、强制版本、mask 自动择优，循环**累加消费 build 结果**防空循环，argv 可选指定点/迭代数）+ `scripts/bench.sh`（宿主 bash `time` 多次取最小，主口径在宿主，预留层② `FAST_QR_WASM` 驱动入口）。已跑出**层①跨后端选型**数字：wasm-gc 全程更快（约 1.2–1.4×；V03H 0.695/0.854s、V10H 0.451/0.621s、V40H 0.369/0.484s，@ N=2000/400/40），两后端各点 `TOTAL_CHECKSUM` 完全一致 → **同源码跨后端结果互证**成立；把 wasm §5.2 的朴素微基准升级为真实 QR 路径、入库存量可复跑。层②（对 fast_qr-wasm32，主口径：逐位对齐 + 同口径计时）与层③（native 注记）需具 fast_qr 检出 / C 工具链环境，已在实现记录 §4 预留驱动与口径说明，达成即收敛 M3。回归维持 **109 全绿** + 快照零差异 + lib `.mbti` 零漂移。
> - **S9 后续优化评估（2026-09-06，纯文档）见 [S9b-性能优化.md](./S9b-性能优化.md)**：对 S9 之后的性能优化做逐热点评估（未改代码）。进程级差分实测建成本模型（同点同输入只差「自动择优 vs 固定 mask」）——V40H 单次 auto 7.99ms vs fixed 1.13ms，8 轮择优开销 ≈6.86ms、**占 auto ≈86%**（V03H ≈57% / V10H ≈73%，随版本超线性放大，面积 ∝ size²）；头号靶点 = `create_auto_qr` 8 轮择优主循环（S5 评审 §4 O1），每轮 `apply_mask` 全量 copy（共 9 次）+ `score` 多趟全矩阵扫描（8 轮 ≈32 趟）；非择优管线（encode→structure→matrix→放置→wrap）单趟、相对紧凑、非优先。给**分优先级路线**：P1 O1-a 就地翻转（toggle 自逆 apply→score→还原，单 base 缓冲免 8 次全量 copy → V40H 择优 6.86ms 望 → ≈3~4ms）/ O1-b 复用最优轮矩阵省末尾 一次 copy（−≈1/9）；P2 O2 score 融合减趟 / O3 wrap_packed 按 size*size 分配（需先评估 QRCode.data 固定容量 容器语义）；层②/③ 对比收尾仍待外部环境。记录测量坑：**argv 驱动探针会被编译器整段折叠**，须编译期常量 + 消费结果。验收统一：快照逐位 diff 零差异 + 109 测试 + 双后端 checksum（O1/O2 逐步独立提交兜底）。
> - **S9 优化再评估（2026-09-06，纯文档）见 [S9b-性能优化.md](./S9b-性能优化.md)**：在层② fast_qr-wasm 实测（见下 S9c bullet 详细分析）后，用边际/每模块成本 + 逐热点实码核对把差距归因两层——算法冗余（9 次整矩阵 copy + 8 轮 ~4 趟扫描 ≈32 趟 + 每格 `mask_at` match，可消）与表示/实现系数（`Array[Int]` 4B/格 vs fast `Module(u8)` 1B 固定数组，难消）；给实施批序 T1（O1-a）→T2（O1-b）→T3（减趟）+T4（mask 特化）→T5（wrap 容器）→T6（宽度实验）与组合预期（V40H 边际 9.01ms → 批 1≈5–6.5ms → 批 2≈4–5ms，fast 3.18ms 的 1.25–1.6×）；验收沿用快照 diff + 109 测试 + checksum + bench-layer2 同一把尺子；明确不承诺拉平到 fast 系数。
> - **S9 优化首批实施（2026-09-06）见 [S9b-性能优化.md](./S9b-性能优化.md)**：落地 **T2（O1-b）**（复用最优轮掩码矩阵 + 真实 Format 覆写，省第 9 次整矩阵 copy；V40H marginal 9.0074→8.8742ms ≈−1.5%，sha256/快照/109 全保持）；**T1（O1-a 就地翻转）实测否决**（V40H marginal +~8%：409 vs 384ms）——copy 非大头、score 多趟扫描才是，单纯就地翻转用真实扫描换 memcpy 净亏；结论：主攻方向转向 **T3（O2 score 减趟）**（score 4 趟→3 趟，把大头打下来），O1-a 保留为开放项不按原形落地。
> - **S9 层②（与 fast_qr wasm 对比）方案见 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)**（2026-09-06）：把 S9 记录 §4 预留的层②落成**同一 Node.js 调用 wasm**、可复跑的性能测试代码（D17/D18/D19）。fast_qr v0.14.0（`53e8c99`）patch `wasm.rs` 加 **`qr_with(content,ecl,version)`** + `wasm-bindgen --target nodejs` 产物（Node 直调 0/1 矩阵；env = rustup stable + wasm32 target + 预编译 cli 0.2.100 + **系统 gcc**——wasm-bindgen 宿主宏/构建脚本需 cc）；MoonBit `cmd/bench --target wasm` 产物由同一 Node 脚本经 **`moonrun` 子进程**驱动（Node 内 `_start` 同进程 spike 否决）；补 `cmd/bench --dump` 值全集矩阵（现校验和含类型位不可跨库互比）；新增 `原 wasm/WASI 对比驱动脚本` + `bench-layer2.sh`；npm 现成包停在 0.13.0 → 排除主口径。**实现落地见 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)**。
> - **S9 同语言生态对比方案（2026-09-06，纯文档）见 [S9d-与moonbit生态QR包性能对比.md](./S9d-与moonbit生态QR包性能对比.md)**：把对比视野扩到 **moonbit 生态现有 QR 包**——`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、`PaiGack/moonbitqrcode@0.1.0`（三包实测 `moon add` 可装、wasm-gc/wasm 可编译）。方案 = 仓库外独立对比模块 import 四方（本仓库 lib + 三包）→ 单一 wasm；复用 `cmd/bench` 口径（同输入 `https://example.com/`、ECL H、V03/V10/V40 强制版本或自动、N 次 build 消费 + R 取最小 + moonrun/Node 计时）；仓库仅加 scripts（setup/build/bench-moonbit-qr.sh 等），lib 零依赖零漂移。标注语义差异：moonbitqrcode lib 层固定 mask0/仅自动版本（择优/强制版本需走其 `src/coding`，可见性待落地核）、qrc/moonqr 支持强制版本+择优。不要求逐位对齐（跨实现细节不同），只做尺寸烟测 + 计时。属 roadmap M3 之后的可选对比延伸，非 M3 门槛。
> - **S9 同语言生态对比首跑（2026-09-06）见 [S9d-与moonbit生态QR包性能对比.md](./S9d-与moonbit生态QR包性能对比.md)**：三包 `moon add` 引入仓库外对比模块、同一 `moonrun` R=5 取最小实测。**同尺寸同语义可比子集 = 本仓库 vs moonqr**：本仓库 **2.5–4.1× 更快**（V40H 9.46 vs 38.29ms、V03H 0.318 vs 0.805ms 单次，V03→V40 全程）。**qrc/moonbitqrcode 无法同口径对齐**（实测核实：qrc 强制版本 API 无 mask/Format、自动 H 落 V2(25)<理论 V3；moonbitqrcode lib 仅 L/M/Q 固定 mask0、H 外部不可构造），仅作参考口径；附生态包可比性硬约束表，与 S9c 层② 同尺子衔接（S9b T3 落地后可复跑观察差距收窄）。
> - **S9 同语言生态全库详细分析（2026-09-06）见 [S9d-与moonbit生态QR包性能对比.md](./S9d-与moonbit生态QR包性能对比.md)**：4 方全库总表 + 容量/语义核验。自动最小版本尺寸：本仓库/moonqr H→V3 ✅、qrc H→V2 ⚠️（`get_data_capacity` 返回字节数 vs `calculate_required_length` 返回位数，bytes/bits 混比疑似容量 bug）、moonbitqrcode Q→V2 ✅（Q 档恰容 20B）。可比子集排名 = 本仓库快 moonqr 2.5–4.1×；逐库归因：qrc 强制路径只 place_data（无择优/Format）故 0.166ms 低值不代表完整成本、moonbitqrcode 固定 mask0+无 H 是「跳过择优的小版本下限」（0.074µs/模块）不能与择优方排名；生态启示 = 完整「自动择优+可强制 ECL+多版本」实现尚少，本仓库完整性与性能有生态价值。
> - **S9 生态专项：moonbitqrcode 快速归因 + 产物对比（2026-09-06）见 [S9d-与moonbit生态QR包性能对比.md](./S9d-与moonbit生态QR包性能对比.md)**：源码级结论——moonbitqrcode lib 固定 `Mask::of_int(0)`（不跑 8 轮择优）+ 只做自动最小版本（20B@Q→V2/625 格）；择优是择优库自动路径主要成本（S9b：V40H ≈86%）→ 免择优即快一个量级，其余管线（RS/放置/Format）并不省。产物交叉验证（矩阵→RGBA→moonqr decode 读回）：本仓库 V03H / moonqr auto-H / moonbitqrcode auto-Q **均可解码读回输入**；qrc auto-H（V2<最小 V3，容量单位 bug）与 qrc forced V3H（缺 Format/mask）**均解码失败** → moonbitqrcode「快≠算法更优」、qrc 0.1.1 暂不产出可用完整 QR。
> - **S9 生态专项：固定 mask0 缺陷 + 主流为何择优（2026-09-06）见 [S9d-与moonbit生态QR包性能对比.md](./S9d-与moonbit生态QR包性能对比.md)**：源码核实固定 mask0 = 忠实移植 rsc.io/qr 的**未完成择优**（Go `qr.go` `NewPlan(v,l,0)` + `// TODO: Pick appropriate mask.`；README 自称 Basic encoder，测试却对照有择优的 C libqrencode）——非移植丢功能。缺陷 = 放弃 ISO 18004 N1–N4 8 掩码评分择优的最坏情况解码鲁棒性（低对比/畸变/小尺寸更易扫失败；产物仍可解码，与上篇不矛盾）。主流（fast_qr/本仓库/moonqr/zxing/qrcodegen/libqrencode）默认择优，因择优是「小成本大保险」的默认质量机制。

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
| M2 ✅ | **功能对齐** | 三模式×4ECL 全矩阵逐位对齐 + 公共 QRBuilder/API 面对齐（S6 达成，测试 94→109）；60 快照覆盖收口 |
| M3 ✅ | 性能与分发基线 | 三基准点可跑并给出对比数字；后端/产物分发结论记录在案（S9 方案见 [S9-性能基准.md](./S9-性能基准.md)，评估见 [S9-性能基准.md](./S9-性能基准.md)，实现记录见 [S9-性能基准.md](./S9-性能基准.md)，优化评估见 [S9b-性能优化.md](./S9b-性能优化.md)。**层①已落地**：`cmd/bench` + `scripts/bench.sh`，wasm-gc 全程快约 1.2–1.4×、跨后端 checksum 互证。**层②已落地（2026-09-06）**：见 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md) 与复测/成本分解 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)——fast_qr `qr_with` wasm-bindgen nodejs 产物（Node 进程内直调）vs MoonBit `cmd/bench --target wasm`（moonrun 子进程）三基准点**逐位对齐零差异**（sha256 一致），计时 646.70/493.60/386.43ms vs 124.07/132.38/126.15ms（@N=2000/400/40）→ fast_qr-wasm32 快约 3.1–5.2×（整程）；详细分析剔启动后**边际单次 build** 0.304/1.162/9.01ms vs 0.061/0.335/3.18ms → fast_qr 快约 2.8–5.0×、每模块成本 0.29–0.36µs vs 0.07–0.10µs（基线，供 S9b P1/P2 优化前后对比）。层③ native 对比仍为可选量级注记（需 C 工具链 + fast_qr native 环境），非 M3 门槛） |

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
