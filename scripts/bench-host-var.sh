#!/usr/bin/env bash
# S9q 宿主调用面**统计稳定性**入口：量化「数字可信到几位」、「该不该多次取平均」。
#
# 【与 bench-host.sh 的分工】
#   bench-host.sh      → 「多快」（点估计）：一次 run，R 轮取最小/中位数，给出主表。
#   bench-host-var.sh  → 「这个点估计可信到几位」（区间估计）：同一进程内做轮次级重抽样，
#                        给出 CV、lag-1 自相关、单轮失稳率、轮內离散。
#   两者口径同源（同一产物、同一 INPUT、同 R 取最小），故区间能盖住点估计。
#
# 【结论摘要（详见 docs/S9q）】单次 build 越便宜，宿主抖动占比越高：
#   V40H 比值 CV ≈0.35%（R≥3 已足）≪ V10H ≈3.5% < V03H ≈6%（须 R≥7 + 跨进程重抽样）。
#   V03H 的轮次序列存在热/频漂移（lag-1 r1 ≈0.3–0.7），故「同一进程内多跑几轮」收益有限。
#
# 【前置】同 bench-host.sh：`cmd/host-probe` 的 JS String Builtins 需 Node ≥ 22
#   （**注意 Node v23.x 的 V8 未注入 js-string builtins，实测不可用，见 docs/S9q §3.4**）。
#
# 用法:
#   bash scripts/bench-host-var.sh                      # 全流程（构建 + fast_qr 参考侧）
#   bash scripts/bench-host-var.sh --no-build           # 产物就绪时只测
#   NO_FAST=1 bash scripts/bench-host-var.sh --no-build # 只测 MoonBit 宿主面
#   ROUNDS=25 REPS=7 bash scripts/bench-host-var.sh --no-build
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
export ROUNDS="${ROUNDS:-15}"
export REPS="${REPS:-5}"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
PKG="$ROOT/pkg"
MOON_GC_HOST_PROBE_WASM="${MOON_GC_HOST_PROBE_WASM:-$PWD/_build/wasm-gc/release/build/cmd/host-probe/host-probe.wasm}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== [1/2] MoonBit cmd/host-probe（wasm-gc 默认后端，release）==="
  moon build cmd/host-probe --target wasm-gc --release
  if [[ -z "${NO_FAST:-}" ]]; then
    echo "=== [2/2] fast_qr-wasm 参考侧（环境 + 产物）==="
    bash "$SCRIPT_DIR/setup-fast-qr-wasm-env.sh"
    bash "$SCRIPT_DIR/build-fast-qr-wasm.sh"
  fi
fi

ARGS=(--moon-gc "$MOON_GC_HOST_PROBE_WASM" --rounds "$ROUNDS" --reps "$REPS")
if [[ -z "${NO_FAST:-}" ]]; then
  ARGS+=(--fast "$PKG/fast_qr.js")
fi

echo ""
echo "=== S9q 宿主调用面统计稳定性（ROUNDS=$ROUNDS 轮 × REPS=$REPS 次取最小）==="
node "$SCRIPT_DIR/bench-host-var.mjs" "${ARGS[@]}"
