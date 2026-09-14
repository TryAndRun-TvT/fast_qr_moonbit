#!/usr/bin/env bash
# S9p 宿主调用面基准入口：**JS 反复把参数传给 wasm**（真实宿主嵌入形态）。
#
# 【为什么需要这个口径 —— 承接 issue #50 的问题】
#   既有层②（scripts/bench-layer2.sh）的 MoonBit 侧是 `cmd/bench`（**命令形态**，导出面只有
#   `_start`，输入走 argv）。它只能给出两种口径：
#     A：每次迭代新建 Instance + `_start` → 把「模块实例化」成本算进每一次调用；
#     B：把迭代数也塞进 argv 让 wasm 内部紧循环 → 宿主传参成本被完全抹平。
#   两者都不是「宿主嵌入 wasm 库、反复带参调用」的真实形态。本脚本补这一口径：
#     MoonBit = `cmd/host-probe`（`foreign_library`，导出 `qr_generate(String, Int) -> Int`）
#     宿主     = 一次 compile + 一次 Instance，随后循环调用 N 次，每次都是真实带参调用。
#
# 【与层② 的关系】层② 保留（它给出 A/B 与跨宿主护栏）；本脚本是**对外引用的主口径**，
#   两者在 README/S9p 文档中并列呈现，且 `fast/ours` 应互相印证（差异即口径差异的直接度量）。
#
# 【前置】`cmd/host-probe` 的 JS String Builtins 需要 Node ≥ 22（V8 支持 `js-string` builtins）；
#   fast_qr 侧可选（不给 `--fast` 则只测 MoonBit 宿主面）。
#
# 用法:
#   bash scripts/bench-host.sh                  # MoonBit ↔ fast_qr（R=3）
#   R=5 bash scripts/bench-host.sh              # 更多轮次取最小
#   bash scripts/bench-host.sh --no-build       # 跳过构建（产物已就绪）
#   NO_FAST=1 bash scripts/bench-host.sh        # 只测 MoonBit 宿主面
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
export R="${R:-3}"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
PKG="$ROOT/pkg"
MOON_GC_HOST_PROBE_WASM="${MOON_GC_HOST_PROBE_WASM:-$PWD/_build/wasm-gc/release/build/cmd/host-probe/host-probe.wasm}"
MOON_GC_BENCH_WASM="${MOON_GC_BENCH_WASM:-$PWD/_build/wasm-gc/release/build/cmd/bench/bench.wasm}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== [1/2] MoonBit cmd/host-probe + cmd/bench（wasm-gc 默认后端，release）==="
  moon build cmd/host-probe --target wasm-gc --release
  moon build cmd/bench --target wasm-gc --release
  if [[ -z "${NO_FAST:-}" ]]; then
    echo "=== [2/2] fast_qr-wasm 参考侧（环境 + 产物）==="
    bash "$SCRIPT_DIR/setup-fast-qr-wasm-env.sh"
    bash "$SCRIPT_DIR/build-fast-qr-wasm.sh"
  fi
fi

ARGS=(--moon-gc "$MOON_GC_HOST_PROBE_WASM" --bench "$MOON_GC_BENCH_WASM" --reps "$R")
if [[ -z "${NO_FAST:-}" ]]; then
  ARGS+=(--fast "$PKG/fast_qr.js")
fi

echo ""
echo "=== S9p 宿主调用面基准（R=$R，单 Node 进程、单 Instance、反复带参调用）==="
node "$SCRIPT_DIR/host-bench.mjs" "${ARGS[@]}"
