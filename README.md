# tryandrun/fast_qr_moonbit

基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。

## 功能特性

- 纯 MoonBit 实现，无外部依赖
- 支持 `wasm-gc` / `wasm` 双后端（`js` 已按需移除，`native` 需系统 C 编译器）
- 快速生成符合 ISO/IEC 18004 标准的二维码

## 快速开始

### 安装 MoonBit 工具链

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

### 构建

模块根不设包（core 式布局）：库包在 `lib/`，CLI 在 `cmd/main/`，构建需显式给包名。

```bash
moon build lib          # 编译库包
moon build cmd/main     # 编译 CLI
```

### 运行 CLI

```bash
moon run cmd/main
```

### 测试

```bash
moon test
```

## 编译为 Wasm

`supported_targets = "+wasm+wasm-gc"`，默认后端 `preferred_target = "wasm-gc"`。

```bash
# 默认后端 wasm-gc（体积最小、性能最优，宿主只需提供 spectest.print_char）
moon build cmd/main --release
moon run   cmd/main

# 兼容后端 wasm（WASI preview1，可被 node / wasmtime 等标准宿主加载）
moon build cmd/main --target wasm --release
moon run   cmd/main --target wasm
```

产物位置：

| 后端 | 产物 | 骨架体积（release） | 特点 |
|------|------|--------------------:|------|
| **`wasm-gc`**（默认） | `_build/wasm-gc/release/build/cmd/main/main.wasm` | **440 B** | 仅 1 个 `spectest.print_char` 导入，不导出 memory，宿主集成成本最低 |
| `wasm` | `_build/wasm/release/build/cmd/main/main.wasm` | 2598 B | 符合 WASI preview1，可被 node / wasmtime 等标准宿主加载 |

默认选 `wasm-gc` 的依据：体积比 `wasm` 小 83%，计算微基准快约 33%。
`native` 后端需系统 C 编译器（`cc` / `gcc` / `clang`），当前未安装，不可用。

详见 [docs/wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md)。

## 文档

| 文档 | 说明 |
|------|------|
| [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md) | 目录/包/测试设置的官方依据 + 实证验证 + 落地清单 |
| [代码布局检查与整理.md](./docs/代码布局检查与整理.md) | 代码放置位置检查、MoonBit 文件/测试约定与整理记录 |
| [wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md) | wasm 编译/运行全过程、产物结构、多后端对比与选型 |
| [moonbit-工具链与构建-setup-分析.md](./docs/moonbit-工具链与构建-setup-分析.md) | 工具链安装、构建系统与 CI 集成 |
| [rust-环境配置脚本与fast_qr对比-setup.md](./docs/rust-环境配置脚本与fast_qr对比-setup.md) | Rust 参考环境配置（`scripts/setup-rust.sh`，rsproxy 镜像）+ fast_qr 对比用法 |
| [repo-初始化配置说明.md](./docs/repo-初始化配置说明.md) | 仓库初始化与云原生构建配置 |
| [core-仓库布局参考与目标架构.md](./docs/core-仓库布局参考与目标架构.md) | 参考 `moonbitlang/core` 布局得出的目标包架构与分阶段落地路线 |
| [项目基础框架-详细分析.md](./docs/项目基础框架-详细分析.md) | **项目基础框架**：资产盘点、参考模块→MoonBit 映射、移植语义、验证策略与 P0-P2 路线（实现 QR 前先读） |
| [moonbit-重写-roadmap-详细分析.md](./docs/moonbit-重写-roadmap-详细分析.md) | **MoonBit 重写路线图**：基于 `/fast_qr` 源码核验的架构要点、S1-S9 实现顺序、里程碑 M0-M3 与验证基座 |
| [S1-数据结构-实现方案.md](./docs/S1-数据结构-实现方案.md) | **S1 详细方案**：数据结构层（Module/QRCode/CompactQR/错误/公共枚举骨架）的文件级实现清单、Module 归属与依赖边界决策（D1/D2）、待实测项与 M0 验收 |
| [S1-数据结构-实现记录.md](./docs/S1-数据结构-实现记录.md) | **S1 落地记录**：S1 数据结构（ECL/Version/Mode/Mask/Module/QRCode/CompactQR）的真实实现、实测拍板决策（pub(all)/Array 矩阵/KEEP_LAST 32 位/错误推迟）与三后端全绿测试 |
| [S1-实现评审与优化-记录.md](./docs/S1-实现评审与优化-记录.md) | **S1 复核记录**：逐文件挑漏洞/找优化点，发现并修复 `QRCode::set` 别名写穿（共享数组破坏不可变语义）、补回归测试，其余设计点确认方向正确 |
| [S2-常量表与GF256-实现方案.md](./docs/S2-常量表与GF256-实现方案.md) | **S2 详细方案**：容量表 + 分组/格式信息/生成多项式硬编码表（internal/constants）+ GF(256) division/structure（internal/reedsolomon）的文件级落地、脚本生成表、黄金测试与 S1 衔接 |
| [S2-实现评估与源码核对-记录.md](./docs/S2-实现评估与源码核对-记录.md) | **S2 评估记录**：动手前阅读代码/文档并恢复 fast_qr 源码核对，修正方案 2 处与源码不一致点（`get_polynomial(v,ecl)` 31 条、capacity=Version::get 分段阈值）+ 补 `data_codewords` 等 3 张旁路表，给出修订后文件级落地清单 |
| [S2-实现记录.md](./docs/S2-实现记录.md) | **S2 落地记录**：constants 容量表/分组/多项式硬编码表 + reedsolomon division/structure 真实实现（大表脚本提取）、回填 CompactQR::from_version、tests/structure.rs 黄金逐字节对齐，三后端全绿（测试 32→42） |
| [S2-实现评审与优化-记录.md](./docs/S2-实现评审与优化-记录.md) | **S2 复核记录**：逐文件复核 S2 实现并校对工程状态，落地「移除 js 后端（收敛为 wasm-gc/wasm 双后端）」「表间不变量交叉一致性测试（42→43）」「max_bytes 注释语义修正」，其余无阻断 bug、方向确认正确 |
| [S3-数据编码-实现方案.md](./docs/S3-数据编码-实现方案.md) | **S3 详细方案**：落地 `internal/data_encoding` 三模式编码 + best_encoding 自动回退 + terminator/8 位对齐，补 `cci_bits` 依赖，并覆盖 B8（QRCode 容量选择 / QRCodeError），含测试/验收与 S3 直接做三模式的取舍论证 |
| [S3-数据编码-实现记录.md](./docs/S3-数据编码-实现记录.md) | **S3 落地记录**：data_encoding 三模式编码 + best_encoding 自动回退 + terminator/pad，补 `cci_bits`（capacity），B8 容量选择与 QRCodeError（lib 首次 import internal），黄金/Python 逐字节核对，三后端全绿（测试 43→63） |
| [S3-实现评审与优化-记录.md](./docs/S3-实现评审与优化-记录.md) | **S3 复核记录**：发现并修复 `is_qr_alphanumeric` 字符映射 bug（`&`/`*` 混淆，与 S3 已修 ascii 映射 bug 同源）、README 表格格式、roadmap 范围同步；其余设计点方向正确 |
| [S4-矩阵与放置-实现方案.md](./docs/S4-矩阵与放置-实现方案.md) | **S4 详细方案**：落地 `internal/matrix` 功能图案绘制（matrix.mbt）+ 之字形数据放置（placement.mbt）+ 8 掩码实现，配**固定 mask** 打通 encode→structure→放置→Format 最小闭环产出 M1 固定参数首码，含 D3 原始字节矩阵介质决策与快照验收策略 |
| [S4-矩阵与放置-实现记录.md](./docs/S4-矩阵与放置-实现记录.md) | **S4 落地记录**：B9b 之字形放置（place_on_matrix_data/create_fixed_qr）+ M1 lib 最小编排入口（QRCode::build_fixed），对照 fast_qr 固定 mask 快照逐位对齐（测试 73→77），双后端全绿 |
| [S5-掩码评分与择优-实现方案.md](./docs/S5-掩码评分与择优-实现方案.md) | **S5 详细方案**：落地 `internal/matrix/score.mbt` 4 条评分（N1/N2/N3/N4）+ `placement` 8 轮 clone+score 择优主循环（自动 mask），补 N4 的 `PERCENT_SCORE` 表，lib 自动择优入口；含 score 语义铁律核对清单与择优快照验收策略 |
| [S5-掩码评分与择优-实现记录.md](./docs/S5-掩码评分与择优-实现记录.md) | **S5 落地记录**：score.mbt 4 条评分（N1/N2/N3/N4）+ placement `create_auto_qr` 8 轮择优 + constants N4 表 + lib `QRCode::build` 自动择优入口，对照 fast_qr 自动择优快照（10 用例最优 mask+全矩阵）逐位对齐（测试 77→85），双后端全绿 |
| [S5-实现评审与优化-记录.md](./docs/S5-实现评审与优化-记录.md) | **S5 复核记录**：对照 fast_qr v0.14.0 `score.rs`/`placement.rs:85-119` 逐行比对，确认无正确性 BUG、与参考逐字等价；落地固定 mask 路径注释口径修正（实际跳过 8 轮评分），补参考概念澄清注记；列 S6/S9 两条非阻断优化建议 |
| [S6-端到端对齐与公共API-实现方案.md](./docs/S6-端到端对齐与公共API-实现方案.md) | **S6 详细方案**：60 快照全量端到端逐位对齐（补 Numeric/Alnum 三模式矩阵级 + V40 满容量/边界 + V14/V26/V32 版本信息区 + 全参数 None 纯自动路径，roadmap §4.1 集 100%）+ 公共 `QRBuilder` 构造器（`new` + mode/ecl/version/mask 链式 setter + `build`，对齐 fast_qr `lib.rs:75-80` 导出面），收敛 M2 功能对齐；含 60 快照脚本生成策略、D6/D7 决策、逐文件落地清单与验收 |
| [S6-端到端对齐与公共API-实现记录.md](./docs/S6-端到端对齐与公共API-实现记录.md) | **S6 落地记录**：新增公共 `QRBuilder` 构造器（`new`/`from_string` + mode/ecl/version/mask 不可变链式 setter + `build` 委托 `QRCode::build`，对齐 `lib.rs:75-80`）+ S6-1 快照收口（三模式×4ECL 矩阵级 + V01/V14/V26/V32/V40-H 满容量 + 自动 mask 路径，约 20 条参考全矩阵逐位对齐 0 差异），验证 S1-S5 完整管线与 fast_qr 逐字节一致（测试 85→94 净 +9），双后端全绿；⚠️ 评审后已更正计数与原「全 None」表述 |
| [S6-实现评审与优化-记录.md](./docs/S6-实现评审与优化-记录.md) | **S6 复核记录**：确认交付范围内（ASCII 字节）无正确性 BUG、QRBuilder 单一委托与生成器介质一致；发现 3 处文档/PR 与代码失实——「全参数 None 纯自动 ×3 对参考逐位」实为参数冻结（仅 mask 自动，全 None 分支缺参考端到端快照）、测试计数实为 85→94（+9）而非 91→94、auto 路径 meta 断言承诺未落地；列 from_string 非 ASCII 字节语义与 V40 单行 hex 两条优化建议 |
| [S7-输出层to_str与SVG-实现方案.md](./docs/S7-输出层to_str与SVG-实现方案.md) | **S7 详细方案**：输出层——终端画 `to_str`/`print`（对齐 `helpers.rs`，补 M1「CLI 输出」欠账）+ 公共 `SvgBuilder`/`Shape` SVG 字符串输出（对齐 `convert/svg.rs` 纯字符串子集，无 resvg/无 file IO），含 D8/D9 决策、四态映射/边距/形状 path 语义核对清单、参考全串快照验收策略 |
| [S7-输出层to_str与SVG-实现评估与优化-记录.md](./docs/S7-输出层to_str与SVG-实现评估与优化-记录.md) | **S7 方案评估记录**：独立检出 fast_qr v0.14.0 参考源码逐行复核 S7 方案，方向正确无致命漏洞；补 4 处精确核对点（circle 形状特例 / `<svg>` 的 `xmlns` 与单行无分隔 / 多 shape → 多 `<path>` / 坐标已含 margin）+ Shape↔字符串映射等优化建议 |
| [S8-内部结构归位与分层-实现方案.md](./docs/S8-内部结构归位与分层-实现方案.md) | **S8 详细方案**：拆包判据（框架 §三.2）核对后判定 roadmap 原义「拆 internal」已被 S1-S5 达成、internal 无再拆信号；真命中项为 lib 公共层失效入口 `fast_qr_moonbit.mbt`（仍自称骨架）+ `qr.mbt`（401 行）职责混杂；方案 = 公共层文件级职责归位（qr.mbt→qr_build/qr_builder/qr_output，不改 `.mbti`/不加包/无逻辑改动）+ 入口刷新，回归 109 全绿即验收 |
| [S9-性能基准-实现方案.md](./docs/S9-性能基准-实现方案.md) | **S9 详细方案**：性能三基准点移植（roadmap §4.2 S9 / 收敛 M3）——本仓库 MoonBit `Int` 32 位、`KEEP_LAST` 取 Rust wasm32 分支（33 项、全后端生效），是 wasm 形态移植；故「透明对比」三层分层：① wasm-gc/wasm 跨后端选型、② **MoonBit-wasm vs fast_qr-wasm32**（同执行模型、不依赖 C 工具链、当前环境可落地，主口径：逐位对齐+计时双验证）、③ native vs fast_qr native（可选量级注记，需 C 工具链）；参考 82.2/269.3/2436.2 us 标注「64 位 native」；定方案 = 新增 `cmd/bench` + `scripts/bench.sh` 宿主计时（D14/D15，口径同时喂层①②），三基准点 `QRBuilder::from_string(input).ecl(H).version(V03/V10/V40).build()`，只测基线、不并入 S5 O1 主循环重构（单列 P2）；回归 109 全绿 + 快照零差异即安全 |
| [S9-性能基准-实现评估与优化-记录.md](./docs/S9-性能基准-实现评估与优化-记录.md) | **S9 方案评估记录**：独立重读实码 + roadmap 复核 S9 方案，方向正确无致命漏洞；更正输入 `https://example.com/` 实为 **20 字节**（非 19，V03H 最小适配结论不变）、bench 循环须消费 build 结果防空循环（死代码消除）、补「KEEP_LAST 33 vs 65 对真实 QR 语义无差别」论证——把层②逐位对齐重新定位为对既有 S1-S7 快照对齐的跨宿主重确认（增量价值在计时可比性）；供 S9 实现直接执行前兜底 |
| [S9-性能基准-实现记录.md](./docs/S9-性能基准-实现记录.md) | **S9 实现记录**：落地基准载体 `cmd/bench`（三基准点 V03H/V10H/V40H，输入 `https://example.com/`=20 字节、ECL=H、强制版本、mask 自动择优，循环累加消费 build 结果防死代码消除）+ `scripts/bench.sh`（宿主多次取最小计时，主口径在宿主，预留层② `FAST_QR_WASM` 入口）；跑出层①跨后端数字——wasm-gc 全程更快（约 1.2–1.4×，V03H 0.695/0.854s、V10H 0.451/0.621s、V40H 0.369/0.484s @ N=2000/400/40），两后端各点 TOTAL_CHECKSUM 一致 → 同源码跨后端结果互证成立；层②对 fast_qr-wasm32 / 层③ native 需外部环境，预留驱动入口；回归 109 全绿 + lib `.mbti` 零漂移 |
| [S9b-性能优化-评估与路线.md](./docs/S9b-性能优化-评估与路线.md) | **S9 后续优化评估路线**：对 S9 之后的性能优化做逐热点评估（纯文档）——进程级差分实测建成本模型（V40H auto 7.99ms vs fixed 1.13ms，8 轮择优开销 ≈6.86ms、占 auto **≈86%**，随版本超线性放大）；定位头号靶点 `create_auto_qr` 8 轮择优主循环（S5 O1），给分优先级路线——P1 O1-a 就地翻转免每轮全量 copy / O1-b 复用最优轮矩阵省末尾一次 copy；P2 O2 score 融合减趟 / O3 wrap_packed 按 size*size 分配；含测量坑（argv 探针被编译器折叠须编译期常量+消费结果）与统一验收口径（快照零差异 + 109 测试 + 双后端 checksum）；未越界做性能改写 |
| [S7-输出层to_str与SVG-实现记录.md](./docs/S7-输出层to_str与SVG-实现记录.md) | **S7 落地记录**：`helpers.mbt` 终端画 `print_matrix_with_margin`（四态映射/边距两行合一/末行，对齐 `helpers.rs`）+ `QRCode::to_str`/`print`（委托）+ 公共 `Shape`/`SvgBuilder`/`to_str` SVG 纯字符串输出（6 形状 path 常量集中、rounded 描边特判、多 shape→多 `<path>`、坐标含 margin，对齐 `convert/{mod,svg}.rs` 子集），参考全串字节对齐快照 + CLI 真码输出（测试 94→109）；双后端全绿
| [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md) | **实现布局（方案 3 库机制）**：`lib/` 公共包 + `lib/internal/` 子包的文件职责、无环依赖规则（B1-B11 落地）、测试规划与注释骨架状态 |

### 移植参考：fast_qr（Rust v0.14.0）分析

本仓库以 Rust 库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 为参考实现。
以下文档是对该参考库源码的深度分析（分析时检出于环境 `/fast_qr`，不在本仓库内），
作为移植输入与设计依据：

| 文档 | 说明 |
|------|------|
| [fast-qr-索引.md](docs/移植参考/fast-qr-索引.md) | 参考库文档集入口：架构 / 接口 / 开发者指南 / 核心概念 / 模块 / 跨语言重写评估 |
| [fast-qr-架构.md](docs/移植参考/fast-qr-架构.md) | 六大子系统、数据流与 7 条核心性能设计决策 |
| [fast-qr-接口.md](docs/移植参考/fast-qr-接口.md) | Rust 与 JS/WASM 公开 API、示例与性能契约数据 |
| [fast-qr-开发者指南.md](docs/移植参考/fast-qr-开发者指南.md) | 参考库环境、feature 矩阵、CI 与已知注意事项 |
| [跨语言重写评估.md](docs/移植参考/专有概念/跨语言重写评估.md) | 重写价值判定、候选语言对比与机械翻译+黄金测试路线图 |

## 代码放置约定（方案 3：模块根无包，库包在 `lib/`）

本仓库模块根只放元数据（对齐 `moonbitlang/core` 形态），按下列约定放置代码：

| 文件 / 目录 | 放置位置 | 约定 |
|-------------|---------|------|
| 模块配置 | 根目录 `moon.mod` | 声明 `name` / `preferred_target` / `supported_targets`；**根目录不建包**（无 `moon.pkg`） |
| 库包 | `lib/` + `lib/moon.pkg` | 库源码全部在 `lib/`；公共类型/入口在 `lib/` 根文件，实现子包在 `lib/internal/` |
| 库入口 | `lib/fast_qr_moonbit.mbt` | 文件名沿用模块名便于识别（目录内可自由命名） |
| 黑盒测试 | `lib/<模块名>_test.mbt` | **包外**运行，只能访问 `pub` API；用 `@lib` 别名引用本包（别名 = 目录名 `lib`） |
| 白盒测试 | `lib/<模块名>_wbtest.mbt` | **包内**运行，可直接访问私有实现 |
| CLI 入口 | `cmd/main/` | `moon.pkg` 需写 `pkgtype(kind: "executable")` |
| 跨包依赖 | 使用方的 `moon.pkg` | `import { "tryandrun/fast_qr_moonbit/lib" @lib }`；**声明后必须使用**，否则触发 `unused_package` 告警 |

> **不要建 `src/`**：MoonBit 无 `src/` 约定；本仓库用 `lib/` 承载库包、`lib/internal/`
> 承载实现细节（与 core 的 feature 包 + internal 形态一致）。
> 每个子包目录各带一个 `moon.pkg`；**包名由目录名决定且不可配置**，目录内 `.mbt` 的文件名则可自由命名。
> 详见 [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md)
> 与 [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md)。
> 弃用代码统一放各目录的 `deprecated.mbt`。

## 项目结构

```
├── moon.mod                    # MoonBit 模块配置（模块根不建包）
├── lib/                        # 库包（公共 API，lib/moon.pkg）
│   ├── fast_qr_moonbit.mbt     #   库入口 / 公共 API 总览（真实实现见下列各文件）
│   ├── ecl/version/mode/mask.mbt  # 公共枚举（ECL/Version/Mode/Mask，.mbti 对外契约）
│   ├── module.mbt              #   公共 Module / ModuleType（呈现层，位打包语义）
│   ├── qr.mbt                  #   QRCode 结果容器 + QRCodeError + 访问器（S8 拆后收敛）
│   ├── qr_build.mbt             #   编排/构造：select_capacity + build_fixed/build（S8 拆出）
│   ├── qr_builder.mbt           #   公共 QRBuilder 构造器（S8 拆出）
│   ├── qr_output.mbt            #   QRCode 输出便捷 to_str/print（S8 拆出）
│   ├── helpers.mbt / svg.mbt / shape.mbt  # 输出层：终端画 + SVG + Shape 枚举
│   ├── fast_qr_moonbit_test.mbt  # 黑盒测试（包外，@lib）
│   ├── fast_qr_moonbit_wbtest.mbt # 白盒测试（包内）
│   └── internal/               #   实现子包（各带 moon.pkg；不反向依赖 lib）
│       ├── constants/          #     常量表 hardcode + 容量/元数据表 capacity
│       ├── bitstream/          #     位流缓冲 bitbuffer（CompactQR）
│       ├── reedsolomon/        #     GF(256) 除法 division 与交织 structure
│       ├── data_encoding/      #     三模式编码 encode + 自动回退
│       └── matrix/             #     module/matrix/placement/datamasking/score
│       # 职责与 roadmap 批次（B1-B11）见 docs/moonbit-实现布局与文件职责.md
├── cmd/main/                   # CLI 可执行入口（import { ".../lib" @lib }）
│   ├── main.mbt
│   └── moon.pkg
├── docs/                       # 项目文档（工程/布局 + 移植参考/fast_qr 语料）
├── AGENTS.md                   # AI 协作代理指南（单一真实文件）
├── scripts/                    # 构建与开发辅助脚本
│   ├── setup-moonbit.sh        #   安装 MoonBit 工具链并校验（.cnb.yml 各阶段调用）
│   ├── setup-rust.sh           #   安装 Rust 工具链（rsproxy 镜像，供 fast_qr 参考对比，可选）
│   ├── fmt-check.sh            #   格式门禁（moon fmt --check）
│   ├── check.sh                #   静态检查门禁（moon check --deny-warn）
│   ├── test.sh                 #   单元测试
│   └── build-and-run.sh        #   多后端(wasm-gc/wasm)构建回归
├── .githooks/                  # 可选 Git 钩子（需自行启用，见其 README）
├── .cnb.yml                    # 云原生构建配置
├── .codebuddy/                 # CodeBuddy 自定义命令
├── README.md                   # 本文件（项目说明；moon.mod 的 readme）
└── LICENSE                     # Apache-2.0
```
