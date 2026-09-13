#!/usr/bin/env bash
# diff-gate.sh —— T4-c 差分门禁（S10 §6 T4-c / 缺口 G11）
#
# 目的：把 `scripts/gc-compare.mjs` 的「逐位对齐 sha256」从**仅打印**升级为
# **可选的、有明确跳过语义的 CI 门禁**：
#   - 有参考 wasm 制品（fast_qr.js）时：三基准点 sha256 零差异 → 退出 0；
#   - 无制品 / 无 node / 无 `moon` 时：明确打印 `skipped` 并**退出 0**（不阻塞 CI）。
#
# 为什么「无制品时跳过而非失败」：参考 wasm 制品需 Rust + wasm-bindgen + 网络构建，
# 属本地/审计资产（同 `bench*.sh` 角色），不应让主门禁依赖网络与额外工具链。
# 但**跳过必须显式可见**（打印 skipped + 原因），避免「静默假绿」。
#
# 用法: bash scripts/diff-gate.sh
#   环境变量：FAST_QR_PKG（fast_qr.js 所在目录）、MOON_GC_BENCH_WASM（MoonBit 侧 bench.wasm）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

fast_pkg="${FAST_QR_PKG:-$HOME/.cache/fast_qr_wasm/pkg}"
fast_js="$fast_pkg/fast_qr.js"

if ! command -v node >/dev/null 2>&1; then
  echo ">> diff-gate: skipped（未找到 node）"
  exit 0
fi
if [[ ! -f "$fast_js" ]]; then
  echo ">> diff-gate: skipped（未找到参考 wasm 制品 $fast_js；"
  echo "   本地复现：bash scripts/setup-rust.sh && bash scripts/setup-fast-qr-wasm-env.sh && bash scripts/build-fast-qr-wasm.sh）"
  exit 0
fi
if ! command -v moon >/dev/null 2>&1; then
  echo ">> diff-gate: skipped（未找到 moon 工具链）"
  exit 0
fi

moon build cmd/bench --target wasm-gc --release >/dev/null
moon_wasm="$ROOT/_build/wasm-gc/release/build/cmd/bench/bench.wasm"
if [[ ! -f "$moon_wasm" ]]; then
  echo ">> diff-gate: skipped（未产出 $moon_wasm）"
  exit 0
fi

echo "=== diff-gate: 逐位对齐 sha256（V03/V10/V40，S9j 口径）==="
node "$SCRIPT_DIR/gc-compare.mjs" \
  --fast "$fast_js" \
  --moon-gc "$moon_wasm" \
  --moonrun "$(command -v moonrun || echo moonrun)" \
  --reps 1 --points V03,V10,V40 --iters 10,10,10
