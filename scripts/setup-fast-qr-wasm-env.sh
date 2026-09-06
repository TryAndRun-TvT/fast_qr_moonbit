#!/usr/bin/env bash
# 层② fast_qr-wasm 参考侧环境配置（S9c 方案 §4 #3 / D17）：装 Rust wasm32 目标 + wasm-bindgen-cli。
#
# 背景：层② = Node.js 调用 wasm 对比（MoonBit wasm vs fast_qr-wasm）。fast_qr v0.14.0 的 wasm 侧
#   patch（qr_with 导出）需 cargo 以 wasm32-unknown-unknown 目标编译 + wasm-bindgen CLI 生成 Node 胶水。
#   本脚本幂等准备工具链；产物构建见 scripts/build-fast-qr-wasm.sh。
#
# 要点：
#   - Rust 工具链走既有 scripts/setup-rust.sh（rsproxy stable + sparse 镜像，不入 push CI）。
#   - wasm-bindgen CLI 版本钉 Cargo.lock 的 wasm-bindgen=0.2.100（ABI 匹配）；用官方 GitHub release
#     预编译 x86_64-linux-musl 二进制，免 C 编译器 / 免 cargo install。
#   - 全程不接入 .cnb.yml push CI（同 setup-rust.sh：外部参考构建，拖慢 CI）。
#
# 用法: bash scripts/setup-fast-qr-wasm-env.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WB_VERSION="${WB_VERSION:-0.2.100}"
WB_BIN_DIR="${WB_BIN_DIR:-$HOME/.cargo/bin}"

# 1) Rust 工具链（缺失时才装）
if ! command -v cargo >/dev/null 2>&1; then
  echo ">>> cargo not found; running setup-rust.sh (rsproxy stable) ..."
  bash "$SCRIPT_DIR/setup-rust.sh"
fi
export PATH="$HOME/.cargo/bin:$PATH"

# 2) wasm32-unknown-unknown 目标（幂等）
rustup target add wasm32-unknown-unknown

# 3) wasm-bindgen CLI（幂等，版本须 = Cargo.lock 的 wasm-bindgen）
if command -v wasm-bindgen >/dev/null 2>&1 &&
  [[ "$(wasm-bindgen --version 2>/dev/null || true)" == *"$WB_VERSION"* ]]; then
  echo ">>> wasm-bindgen $(wasm-bindgen --version) already on PATH."
else
  echo ">>> Downloading wasm-bindgen-cli $WB_VERSION (prebuilt, GitHub release) ..."
  url="https://github.com/rustwasm/wasm-bindgen/releases/download/${WB_VERSION}/wasm-bindgen-${WB_VERSION}-x86_64-unknown-linux-musl.tar.gz"
  tmp="$(mktemp -d)"
  curl -fL --retry 3 -o "$tmp/wb.tar.gz" "$url"
  tar -xzf "$tmp/wb.tar.gz" -C "$tmp"
  mkdir -p "$WB_BIN_DIR"
  cp "$tmp"/wasm-bindgen-*/wasm-bindgen "$WB_BIN_DIR/"
  rm -rf "$tmp"
  export PATH="$WB_BIN_DIR:$PATH"
  echo ">>> installed: $(wasm-bindgen --version)"
fi

echo ">>> rustc : $(rustc --version)"
echo ">>> target: $(rustup target list --installed | tr '\n' ' ')"
echo ">>> wasm-bindgen env ready (layer2 fast_qr-wasm)."
