# fast_qr 文档

本套文档覆盖 fast_qr（Rust 高性能 QR 码生成库，v0.14.0）的架构、接口、开发流程，以及"用其他语言重写"的完整评估。目标读者：想深入理解该库的工程师、评估移植/重写方案的技术决策者。

> **本套文档在本仓库的定位**：fast_qr_moonbit 以 fast_qr 为参考实现，本套文档是其**移植参考**
> （分析对象为 Rust 参考库，源码不在本仓库）。MoonBit 侧的汇总与落地路线见
> [项目基础框架-详细分析.md](../项目基础框架-详细分析.md)。

**快速链接**: [架构](./fast-qr-架构.md) | [接口](./fast-qr-接口.md) | [开发者指南](./fast-qr-开发者指南.md)

---

## 核心文档

### [架构](./fast-qr-架构.md)
系统设计、技术栈、六大子系统、数据流图，以及 7 条核心性能设计决策的代码级解析。从这里开始。

### [接口](./fast-qr-接口.md)
Rust 公开 API（QRBuilder/QRCode/convert）、JavaScript/WASM API（qr/qr_svg/SvgOptions）、示例与基准、性能契约数据。

### [开发者指南](./fast-qr-开发者指南.md)
环境搭建、feature 矩阵构建、CI 约定、release 优化配置、编码规范、常见任务操作步骤。

---

## 核心概念

理解这些概念即可读懂全部核心代码：

| 概念 | 描述 |
|------|------|
| [Module](./专有概念/module.md) | 单字节打包的矩阵单元（bit0 明暗 + bit1-3 类型），性能设计的基石 |
| [CompactQR](./专有概念/compact-qr.md) | 位级缓冲区，承载编码器到矩阵放置之间的比特流 |
| [GF256纠错与交织](./专有概念/gf256-纠错与交织.md) | 查表完成的 Reed-Solomon 纠错与码字交织算法 |
| [掩码与评分](./专有概念/掩码与评分.md) | 8 种掩码图案与 4 条评分规则，含 6 条规范未明说的实现决策 |
| [跨语言重写评估](./专有概念/跨语言重写评估.md) | 重写价值判定、候选语言对比、最快可用落地排期（保留原 API/架构，含验证策略与翻译陷阱清单） |

---

## 模块

| 模块 | 描述 | README |
|------|------|--------|
| `src/` | 核心编码管线（约 3280 行，零依赖） | [核心编码管线](./模块/核心编码管线.md) |
| `src/convert/` | SVG/PNG 输出转换 | [convert输出转换](./模块/convert-输出转换.md) |
| `src/wasm.rs` | WASM/JS 绑定与构建链 | [wasm绑定](./模块/wasm-绑定.md) |

---

## 入门路径

### 想理解它为什么快？

1. **[架构 - 核心设计决策](./fast-qr-架构.md)** — 7 条性能决策逐条对应代码行号
2. **[Module](./专有概念/module.md)** 与 **[CompactQR](./专有概念/compact-qr.md)** — 两个核心数据结构
3. **[掩码与评分](./专有概念/掩码与评分.md)** — 最精巧的算法部分

### 想重写成其他语言？

1. **[跨语言重写评估](./专有概念/跨语言重写评估.md)** — 直接读，含完整路线图
2. **[架构](./fast-qr-架构.md)** — 补充数据流全景
3. **[GF256纠错与交织](./专有概念/gf256-纠错与交织.md)** — 移植中最容易出错的模块

### 想贡献代码？

1. **[开发者指南](./fast-qr-开发者指南.md)** — 环境与 CI 约定
2. **[接口](./fast-qr-接口.md)** — API 契约

---

## 快速参考

### 命令

```bash
cargo test                          # 全部测试
cargo bench                         # 性能基准
cargo run --example simple          # 终端 QR 示例
cargo run --example svg -F svg      # SVG 示例
cargo run --example image -F image  # PNG 示例
./wasm-pack.sh                      # 构建 WASM 产物
```

### 重要文件

| 文件 | 目的 |
|------|------|
| `src/qr.rs` | API 入口（QRBuilder） |
| `src/placement.rs` | 管线总装（create_matrix） |
| `src/hardcode.rs` | 全部常量表 |
| `Cargo.toml` | feature flags 与 release 优化 |
| `wasm-pack.sh` | WASM 发布构建 |

---

## 文档版本

- 生成日期：2026-09-04
- 基于 fast_qr v0.14.0（commit 级别分析；参考库源码检出于分析环境 `/fast_qr`，**不在本仓库内**）
- 本次同时产出重写评估：见 [跨语言重写评估](./专有概念/跨语言重写评估.md)
