#!/usr/bin/env bash
# 安装 Rust 工具链并校验可用性（用于与 Rust 参考实现 fast_qr 对比）。
#
# 背景：本仓库是 Rust 库 fast_qr v0.14.0 的 MoonBit 重写（见 README「移植参考」）。
# 需要本地 Rust 环境来对参考库做源码核对 / 黄金输出 / 体积与性能对比。
# 本脚本参考 tryandrun/rust_dev/rs-site-tools 的 scripts/rust_setup.sh 编写：
#   - 使用 rsproxy 国内镜像加速 rustup / crates.io 下载（与 CNB 云环境网络匹配）
#   - 生成 ~/.cargo/config.toml 走 sparse 镜像索引
#   - cargo fetch 预热依赖
#
# 注意：
#   - 仅供开发环境做 MoonBit↔Rust 对比用，不接入 push CI（本仓库核心 CI 走 MoonBit，
#     见 .cnb.yml / AGENTS.md「收尾检查」）。
#   - native 后端 / 参考库原生构建仍需系统 C 编译器，见 docs/moonbit-工具链与构建-setup-分析.md。
#
# 用法: bash scripts/setup-rust.sh
set -euo pipefail

echo ">>> Setting up Rust toolchain (rsproxy mirror) for fast_qr reference comparison..."

# 1) rsproxy 国内镜像（加速 rustup 自身下载）
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"

# 2) 安装 rustup + 默认 stable 工具链（非交互 -y）
curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh | sh -s -- -y

# 3) 生成 ~/.cargo/config.toml，crates.io 走 sparse 镜像索引
tee "$HOME/.cargo/config.toml" << 'RS_PROXY_EOF'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true
RS_PROXY_EOF

# 4) 载入 cargo 环境变量（rustup-init 生成 ~/.cargo/env）
# shellcheck disable=SC1090
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# 5) 校验
cargo --version
rustc --version

echo ">>> Rust toolchain ready for fast_qr reference comparison."
echo "    cargo : $(cargo --version)"
echo "    rustc : $(rustc --version)"
echo "    用法: 克隆 fast_qr v0.14.0 后可 cargo test / cargo bench 与 MoonBit 版做黄金输出与性能对比"
