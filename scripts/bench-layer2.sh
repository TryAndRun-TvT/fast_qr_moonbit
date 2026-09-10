#!/usr/bin/env bash
# NOTE: 本脚本已纳入仓库并公开可审阅，供复现与评审。
# 目标：在**统一 Node 进程内**调用两侧 wasm，对比 MoonBit 与 fast_qr-wasm32 的真实性能（S9e）。
#
# 与 S9c 旧口径的区别（对齐 issue「并非统一通过 nodejs 调用」）：
#   旧：fast_qr 侧 Node 进程内直调 + MoonBit 侧 `moonrun` **子进程**整程（含进程启动，实测占 12–20%）。
#   新：两侧都在**同一 Node 进程**内调用——MoonBit 由 scripts/moonbit-wasm-runner.mjs 进程内实例化，
#       fast_qr 由 wasm-bindgen 胶水进程内直调；两侧共享同一进程、同一时钟、同一循环形态。
#
# 职责（对应 S9e 方案 + 实现记录）：
#   1) 确保环境（scripts/setup-fast-qr-wasm-env.sh：rust wasm32 target + wasm-bindgen-cli + gcc）；
#   2) 构建 fast_qr v0.14.0 qr_with nodejs 产物（scripts/build-fast-qr-wasm.sh，外部检出，不入库）；
#   3) moon build cmd/bench --target wasm --release；
#   4) 调 scripts/wasm-compare.mjs 跑三基准点「逐位对齐 + R 次取最小计时」并输出 markdown。
#
# 用法:
#   bash scripts/bench-layer2.sh                 # R=3 跑全部三点
#   R=5 bash scripts/bench-layer2.sh             # 自定义重复次数
#   bash scripts/bench-layer2.sh --no-build      # 跳过构建（已就绪，只跑对比）
#
# 可选回退（宿主协议变更时）：
#   MOON_HOST=moonrun bash scripts/bench-layer2.sh   # 用 moonrun 子进程计时（旧 S9c 口径量级）
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
echo "=== 层②对比（R=$R，Node 进程内统一调用）==="
node "$SCRIPT_DIR/wasm-compare.mjs" \
  --fast "$PKG/fast_qr.js" \
  --moon "$MOON_BENCH_WASM" \
  --reps "$R"
