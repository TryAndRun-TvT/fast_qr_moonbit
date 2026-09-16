# fast_qr 开发者指南

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README-导航与索引.md](../../README-导航与索引.md) §7

## 项目目的

fast_qr 是一个 QR 码生成库，以"比现有实现快数倍"为核心目标。它在生态中担任底层生成引擎角色：Rust 侧作为 crate 直接使用，JS 侧编译为 WASM 发 npm。

**核心职责**:
- 将字节流编码为符合 ISO/IEC 18004 的 QR 码矩阵（版本 1-40、4 种纠错级别、3 种编码模式、8 种掩码）
- 将矩阵渲染为 SVG / PNG / 终端字符画
- 通过 wasm-bindgen 向 JavaScript 暴露同一能力

**相关系统**:
- `qrcode` crate — dev-dependency，仅用于基准对照与纠错输出交叉验证
- npm registry — WASM 产物的分发渠道（包名 `fast_qr`）

## 环境搭建

### 前置条件

- Rust >= 1.59（`rustup` 安装）
- 构建 WASM 产物额外需要：nightly 工具链、`wasm32-unknown-unknown` target、`wasm-bindgen-cli`、`wasm-opt`（binaryen）
- 基准测试需要 criterion（cargo 自动拉取）

### 安装与验证

```bash
# 克隆仓库
git clone https://github.com/erwanvivien/fast_qr.git
cd fast_qr

# 运行测试（无需任何 feature）
cargo test

# 运行示例
cargo run --example simple
cargo run --example svg -F svg
cargo run --example image -F image
```

### 构建 WASM

```bash
./wasm-pack.sh
# 产物位于 pkg/，包含 fast_qr_bg.wasm 与 JS 胶水
# 脚本内部流程：nightly -Z build-std=std,panic_abort + panic_immediate_abort
#              -> wasm-bindgen --web -> wasm-opt -Oz
```

## 开发工作流

### 常用命令

| 命令 | 目的 |
|------|------|
| `cargo build` | 默认构建（无 feature） |
| `cargo build -F svg` / `-F image` / `-F wasm-bindgen` | feature 组合构建 |
| `cargo test` | 全部单元测试 |
| `cargo bench` | criterion 基准（V03H/V10H/V40H 对比 qrcode crate） |
| `cargo clippy` | lint（CI 以 `--deny warnings` 运行） |

### CI 矩阵（.github/workflows/rust.yml）

CI 对以下组合逐一构建并测试，本地提交前建议至少覆盖：

1. 无 feature、`svg`、`image`、`wasm-bindgen`
2. 三个 target：原生、`wasm32-unknown-unknown`、wasm32+wasm-bindgen
3. benches 编译检查
4. `RUSTFLAGS="--deny warnings"`（警告即失败）

### release 构建配置（Cargo.toml）

```toml
[profile.release]
lto = true
codegen-units = 1
opt-level = 's'      # 体积优先
panic = 'abort'
strip = "debuginfo"
```

修改性能相关代码后，务必用 `cargo bench` 验证退化情况。

## 代码结构约定

### 模块分层

核心管线单向依赖，方向固定：

```
encode -> compact
version/hardcode -> （被 encode/polynomials/placement 查表使用）
polynomials -> hardcode
default/placement -> module/hardcode/polynomials
score -> module/hardcode
qr -> encode/placement（组装入口）
```

新增代码禁止引入反向依赖或让核心模块依赖 `convert`。

### 编码规范（从现有代码提炼）

| 项 | 约定 | 依据 |
|------|------|------|
| unsafe | 核心模块全部 `#![deny(unsafe_code)]` | encode.rs、compact.rs 等 |
| 文档 | 公开项 `#![warn(missing_docs)]` | lib.rs:2 |
| 常量表 | `#[rustfmt::skip]` + 注释说明来源 | compact.rs:32 |
| 性能注释 | 解释"为什么这样做"与被否决的替代方案 | qr.rs:26-31、score.rs:40 |
| 覆盖点 | 每个 magic number 标注规范章节（如 8.4.2） | encode.rs:66 |

### 测试约定

- 测试位于 `src/tests/`，按主题分 11 个模块（mod.rs 声明清单）
- 黄金数据测试为主：容量表逐值断言（version.rs 3876 行）、多项式除法期望值表（polynomials.rs 1168 行）
- 纠错输出与 `qrcode` crate 交叉验证（error_correction.rs）
- 内部函数通过 `#[cfg(test)]` 的 `test_*` 包装函数暴露（score.rs:11-34、placement.rs:30）

## 常见任务

### 修改容量表或新增常量

**需修改的文件**:
1. `src/hardcode.rs` 或 `src/version.rs` — 修改表
2. `src/tests/version.rs` / `src/tests/polynomials.rs` — 同步黄金数据
3. `src/convert/` 无需改动

**步骤**:
1. 按 ISO/IEC 18004 附录表核对数值
2. 保持 u32 位打包格式（`(count << 24) | (size << 16) | ...`）
3. 更新对应测试期望值

### 新增一种输出形状（Shape）

**需修改的文件**:
1. `src/convert/mod.rs` — Shape 枚举加变体（WASM 与非 WASM 两处）
2. `src/convert/svg.rs` — 实现 ModuleFunction 分支
3. `src/wasm.rs` — 导出（如需 JS 侧可见）
4. `src/tests/svg.rs` — 增加快照断言

### 新增 WASM 配置项

**需修改的文件**:
1. `src/wasm.rs` — SvgOptions 字段 + 链式方法
2. `src/convert/svg.rs` 或 `image.rs` — 消费该配置
3. `pkg/` 需重新构建发布

### 修复 Bug

1. 先在 `src/tests/` 写复现用例（倾向黄金数据风格而非模糊断言）
2. 定位根因，保持单向依赖
3. `cargo test && cargo clippy -- -D warnings` 通过
4. 若涉及性能路径，`cargo bench` 确认无退化

## 已知注意事项

- `CompactQR::push_bits` 的 `KEEP_LAST` 表在 wasm32 下仅 33 项（usize 位宽差异），跨平台修改时注意 `#[cfg]` 分支
- 掩码择优循环中列评分必须在掩码后进行（placement.rs:100-104 注释记录了此 bug 的历史）
- WASM 构建必须用 nightly 的 `-Z build-std`，否则 panic 字符串会显著增大产物
- 版本选择 `Version::get` 是穷举 match，若 Rust 编译器升级导致常量折叠失效，性能会明显退化（基准测试可发现）
