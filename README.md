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
| [S3-数据编码-实现方案.md](./docs/S3-数据编码-实现方案.md) |
| [S3-数据编码-实现记录.md](./docs/S3-数据编码-实现记录.md) | **S3 落地记录**：data_encoding 三模式编码 + best_encoding 自动回退 + terminator/pad，补 `cci_bits`（capacity），B8 容量选择与 QRCodeError（lib 首次 import internal），黄金/Python 逐字节核对，三后端全绿（测试 43→63） | **S3 详细方案**：落地 `internal/data_encoding` 三模式编码 + best_encoding 自动回退 + terminator/8 位对齐，补 `cci_bits` 依赖，并覆盖 B8（QRCode 容量选择 / QRCodeError），含测试/验收与 S3 直接做三模式的取舍论证 |
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
│   ├── fast_qr_moonbit.mbt     #   库入口 / 公共 API 组装（当前为职责注释）
│   ├── ecl/version/mode/mask.mbt  # 公共枚举（.mbti 对外契约）
│   ├── qr.mbt / helpers.mbt    #   QRCode 容器与错误 / 终端输出
│   ├── fast_qr_moonbit_test.mbt  # 黑盒测试（包外，@lib）
│   ├── fast_qr_moonbit_wbtest.mbt # 白盒测试（包内）
│   └── internal/               #   实现子包（各带 moon.pkg；不反向依赖 lib；注释骨架）
│       ├── constants/          #     常量表 + 容量/元数据表
│       ├── bitstream/          #     位流缓冲（CompactQR）
│       ├── reedsolomon/        #     GF(256) 除法与交织
│       ├── data_encoding/      #     三模式编码
│       └── matrix/             #     module/matrix/placement/datamasking/score
│       # 职责与 roadmap 批次（B1-B11）见 docs/moonbit-实现布局与文件职责.md
├── cmd/main/                   # CLI 可执行入口（import { ".../lib" @lib }）
│   ├── main.mbt
│   └── moon.pkg
├── docs/                       # 项目文档（工程/布局 + 移植参考/fast_qr 语料）
├── AGENTS.md                   # AI 协作代理指南（单一真实文件）
├── scripts/                    # 云原生构建脚本（.cnb.yml 各阶段命令）
│   ├── setup-moonbit.sh        #   安装 MoonBit 工具链并校验
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
