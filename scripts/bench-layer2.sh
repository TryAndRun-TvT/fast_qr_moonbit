#!/usr/bin/env bash
# 层② 一键驱动：Node.js 调用 wasm 对比（MoonBit wasm vs fast_qr-wasm32，S9c）。
#
# 职责（对应 S9c 方案 §4 #4 + 实现记录）：
#   1) 确保环境（scripts/setup-fast-qr-wasm-env.sh：rust wasm32 target + wasm-bindgen-cli）；
#   2) 构建 fast_qr v0.14.0 qr_with nodejs 产物（scripts/build-fast-qr-wasm.sh，外部检出，不入库）；
#   3) moon build cmd/bench --target wasm --release；
#   4) 调 scripts/wasm-compare.mjs 跑三基准点「逐位对齐 + R 次取最小计时」并输出 markdown。
#
# 用法:
#   bash scripts/bench-layer2.sh                 # R=3 跑全部三点
#   R=5 bash scripts/bench-layer2.sh             # 自定义重复次数
#   bash scripts/bench-layer2.sh --no-build      # 跳过构建（已就绪，只跑对比）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
export R="${R:-3}"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
PKG="$ROOT/pkg"
MOON_BENCH_WASM="${MOON_BENCH_WASM:-$PWD/_build/wasm/release/build/cmd/bench/bench.wasm}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== [1/3] fast_qr-wasm 环境 ==="
  bash "$SCRIPT_DIR/setup-fast-qr-wasm-env.sh"
  echo "=== [2/3] 构建 fast_qr qr_with nodejs 产物 ==="
  bash "$SCRIPT_DIR/build-fast-qr-wasm.sh"
fi

echo "=== [3/3] MoonBit cmd/bench (--target wasm --release) ==="
moon build cmd/bench --target wasm --release

echo ""
echo "=== 层②对比（R=$R，Node.js 调用 wasm）==="
node "$SCRIPT_DIR/wasm-compare.mjs" \
  --fast "$PKG/fast_qr.js" \
  --moon "$MOON_BENCH_WASM" \
  --reps "$R"
