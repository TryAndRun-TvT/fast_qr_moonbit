# Rust 环境配置脚本 · 与 fast_qr 参考对比 Setup

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §7

> 本文记录本次「增加 Rust 环境配置脚本便于对比」的完整过程：阅读现状、clone 参考仓库
> `rs-site-tools`、抽取其 `rust_setup.sh` 思路、落地本仓库 `scripts/setup-rust.sh`，
> 并给出脚本用途、与 CI 的关系与后续使用方式。
>
> 关联：ISSUE #9（在 `moonbit-工具链与构建-setup-分析.md` §演进记录 与 README 中同步）
> 参考实现：Rust 库 fast_qr v0.14.0（见 README「移植参考」）

---

## 一、背景与动机

本仓库 `TryAndRun-TvT/fast_qr_moonbit` 是 **Rust 库 `fast_qr` v0.14.0 的 MoonBit 重写**。
移植过程中反复需要对参考库做三类比对：

| 对比场景 | 需要什么 |
|---------|---------|
| 源码核对 | 逐文件对照 Rust 源码（`/fast_qr`），还原常量表 / 算法语义 |
| 黄金输出验证 | 跑 `fast_qr` 的测试 / 示例产出期望矩阵，与 MoonBit 版逐字节对齐 |
| 体积与性能对比 | 对比 wasm / native 产物体积与微基准（见 `docs/wasm-编译与运行-结果分析.md`） |

前两类在现有 MoonBit 工具链之外还需要一套可用的 **Rust 工具链**。
因此需要一份「环境配置脚本」把 Rust 工具链装好并可用。

`rs-site-tools` 仓库（`tryandrun/rust_dev/rs-site-tools`）正好是一套**以 Rust 为主的平台**，
其 `scripts/rust_setup.sh` 是一份成熟的 Rust 国内镜像环境配置脚本，可作为本仓库参考范本。

---

## 二、执行过程

### 1. 阅读本仓库代码与文档

- `.cnb.yml`：`push`/`vscode` 阶段命令已抽离到 `scripts/`（setup-moonbit / fmt-check / check / test / build-and-run）。
- `AGENTS.md`：核心约束 —— 本仓库是 MoonBit 项目，CI 不收 native（需系统 C 编译器）阶段；
  密钥/私人配置不入库；构建产物 gitignore。
- `docs/moonbit-工具链与构建-setup-分析.md`：MoonBit 工具链安装、后端矩阵与 CI 集成说明。
- `docs/wasm-编译与运行-结果分析.md`：wasm 产物体积与多后端对比数据（与 Rust 对比的切入点）。

结论：MoonBit 侧 CI 已完备，缺的是**可选的 Rust 参考对比环境**。

### 2. clone 参考仓库 rs-site-tools

```bash
git clone https://cnb.cool/tryandrun/rust_dev/rs-site-tools
```

该仓库脚本目录 `scripts/` 提供：
- `rust_setup.sh` —— 用 rsproxy 国内镜像安装 Rust + 生成 `~/.cargo/config.toml`（sparse 索引）+ `cargo fetch` 预热。
- `apt_setup.sh` / `nvm_setup.sh` —— 分别装系统依赖与 Node/bun（与本仓库无关，不采用）。
- `vercel-*` —— Vercel 部署构建（与 fast_qr 对比无关，不采用）。

### 3. 参考其 rust_setup.sh，落地 `scripts/setup-rust.sh`

抽取的要点（对齐本仓库脚本风格与命名）：

| 要点 | 参考仓库做法 | 本仓库落地 |
|------|------------|-----------|
| rustup 国内加速 | `RUSTUP_DIST_SERVER` / `RUSTUP_UPDATE_ROOT` 指向 `https://rsproxy.cn` | 保留相同变量 |
| 安装 rustup | `curl ... https://rsproxy.cn/rustup-init.sh \| sh -s -- -y`（非交互） | 保留 |
| crates.io 走 sparse 镜像 | 生成 `~/.cargo/config.toml`：`rsproxy-sparse` | 保留 |
| 载入环境 | `source $HOME/.cargo/env` | 改为兼容写法：`[ -f ... ] && . ...` |
| 校验 | 参考仓库装 `cargo-zigbuild`（Vercel 专用） | **不采用**（本仓库无 Vercel 需求） |
| `cargo fetch` 预热 | 参考仓库执行 | 改为**注释提示**（本仓库未锁依赖，无需预热） |

差异取舍：
- 参考仓库 `rust_setup.sh` 面向 Vercel Rust Function 部署，额外装了 `cargo-zigbuild`。
  本仓库仅做 **fast_qr 参考对比**，只需 stable 工具链 + 镜像配置即可，故裁剪掉 zigbuild/zig。
- 命名对齐本仓库既有脚本：`setup-` 前缀 + `bash scripts/<name>.sh` 用法（同 setup-moonbit.sh）。
- 头部注释写明用途、背景、来源与差异，避免误以为其接入主 CI。

### 4. 是否接入 `.cnb.yml` CI

**不接入 `push` / `vscode` 必选阶段**，理由：
- 本仓库核心 CI 是 MoonBit（`moon fmt/check/test/build`），Rust 只是**可选对比依赖**；
  每次都装 Rust 会显著拖慢云开发环境与 CI。
- `AGENTS.md` 明确禁止把 native（需 C 编译器）阶段写入 CI 必选流程 —— Rust 原生参考构建同理。
- 该脚本按需手动执行：`bash scripts/setup-rust.sh`。

---

## 三、落地产物

| 文件 | 说明 |
|------|------|
| `scripts/setup-rust.sh` | 用 rsproxy 镜像安装 Rust 工具链 + 生成 cargo sparse 镜像配置 + 校验 |

脚本内容要点：

```bash
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh | sh -s -- -y
# 生成 ~/.cargo/config.toml（rsproxy-sparse）
# 载入 ~/.cargo/env 并校验 cargo / rustc 版本
```

用法：`bash scripts/setup-rust.sh` → `cargo --version` / `rustc --version` 输出即成功。

---

## 四、文档更新

- `README.md`：`项目结构` 的 `scripts/` 下补 `setup-rust.sh` 条目；文档索引补本文。
- `docs/moonbit-工具链与构建-setup-分析.md`：演进记录补 ISSUE #9 本次记录。

---

## 五、后续使用建议

装好 Rust 后做 fast_qr 参考对比的推荐路径：

```bash
# 1. 装 Rust（一次性）
bash scripts/setup-rust.sh
export PATH="$HOME/.cargo/bin:$PATH"

# 2. 检参考库并核对/产黄金输出
git clone https://github.com/erwanvivien/fast_qr.git  # 或检出到 /fast_qr
cd fast_qr && git checkout v0.14.0
cargo test && cargo run --example simple

# 3. 与 MoonBit 版逐字节对比 / 体积性能对比
#    见 docs/wasm-编译与运行-结果分析.md（wasm 体积）与各 S 实现记录的黄金测试说明
```

> 注意：fast_qr 原生构建 / `cargo bench` 可能需系统 C 编译器（当前云镜像未装），
> 若需可另行 apt 安装 gcc，不影响本脚本的 rustup 安装步骤。
