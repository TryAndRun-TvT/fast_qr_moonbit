# tryandrun/fast_qr_moonbit

基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。

## 功能特性

- 纯 MoonBit 实现，无外部依赖
- 支持 `wasm` / `wasm-gc` / `js` 后端（`native` 需系统 C 编译器）
- 快速生成符合 ISO/IEC 18004 标准的二维码

## 快速开始

### 安装 MoonBit 工具链

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

### 构建

```bash
moon build
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

`supported_targets = "+wasm+wasm-gc+js"`，默认后端 `preferred_target = "wasm-gc"`。

```bash
# 默认后端 wasm-gc（体积最小、性能最优，宿主只需提供 spectest.print_char）
moon build --release
moon run   cmd/main

# 兼容后端 wasm（WASI preview1，可被 node / wasmtime 等标准宿主加载）
moon build --target wasm --release
moon run   cmd/main --target wasm

# js
moon run cmd/main --target js
```

产物位置：

| 后端 | 产物 | 骨架体积（release） | 特点 |
|------|------|--------------------:|------|
| **`wasm-gc`**（默认） | `_build/wasm-gc/release/build/cmd/main/main.wasm` | **440 B** | 仅 1 个 `spectest.print_char` 导入，不导出 memory，宿主集成成本最低 |
| `wasm` | `_build/wasm/release/build/cmd/main/main.wasm` | 2598 B | 符合 WASI preview1，可被 node / wasmtime 等标准宿主加载 |
| `js` | `_build/js/debug/build/cmd/main/main.js` | 293 B | 可直接用于 npm / 浏览器 |

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

## 代码放置约定

本仓库布局与 `moon new` 生成的官方布局一致，按下列约定放置代码：

| 文件 / 目录 | 放置位置 | 约定 |
|-------------|---------|------|
| 模块配置 | 根目录 `moon.mod` | 声明 `name` / `preferred_target` / `supported_targets` |
| 包描述 | 每个包目录一个 `moon.pkg` | 根包可为空；依赖在使用方声明 |
| 库主文件 | 根目录 `<模块名>.mbt` | 文件名与 `moon.mod` 的 `name` 末段同名 |
| 黑盒测试 | 根目录 `<模块名>_test.mbt` | **包外**运行，只能访问 `pub` API；用 `@fast_qr_moonbit` 别名引用本包 |
| 白盒测试 | 根目录 `<模块名>_wbtest.mbt` | **包内**运行，可直接访问私有实现 |
| CLI 入口 | `cmd/main/` | `moon.pkg` 需写 `pkgtype(kind: "executable")` |
| 跨包依赖 | 使用方的 `moon.pkg` | `import { "tryandrun/fast_qr_moonbit" @lib }`；**声明后必须使用**，否则触发 `unused_package` 告警 |

> **不要建 `src/`**：MoonBit 无 `src/` 约定（官方教程的标准目录树中不含 `src/`）。
> 库源码直接放模块根目录，CLI 放 `cmd/main/`。
> 拆分多个子包时按功能建目录（如 `reedsolomon/`），每个目录各带一个 `moon.pkg`；
> **包名由目录名决定且不可配置**，目录内 `.mbt` 的文件名则可自由命名。
> 注意 `src/` 并非被禁止：在其中放 `.mbt` + `moon.pkg` 技术上可编译（实测通过），
> 只是**不合官方惯例**。
> 详见 [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md)。
> 弃用代码统一放各目录的 `deprecated.mbt`。

## 项目结构

```
├── moon.mod                    # MoonBit 模块配置
├── moon.pkg                    # 根包描述（暂无依赖，留空）
├── fast_qr_moonbit.mbt         # 库主文件（公共 API）
├── fast_qr_moonbit_test.mbt    # 黑盒测试（包外，仅 pub API）
├── fast_qr_moonbit_wbtest.mbt  # 白盒测试（包内，可访问私有实现）
├── cmd/main/                   # CLI 可执行入口
│   ├── main.mbt
│   └── moon.pkg
├── docs/                       # 项目文档
├── AGENTS.md                   # AI 协作代理指南（对齐官方命名）
├── agents.md -> AGENTS.md      # 符号链接，兼容读取小写名的工具
├── .githooks/                  # 可选 Git 钩子（需自行启用，见其 README）
├── .cnb.yml                    # 云原生构建配置
├── .codebuddy/                 # CodeBuddy 自定义命令
├── README.mbt.md               # 本文件（含 mbt check 代码块）
├── README.md -> README.mbt.md  # 符号链接（官方布局）
└── LICENSE                     # Apache-2.0
```
