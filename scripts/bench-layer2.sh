#!/usr/bin/env bash
# NOTE: 本脚本已纳入仓库并公开可审阅，供复现与评审。
# 目标：在**统一 Node 进程内**调用两侧 wasm，对比 **MoonBit wasm-gc（默认后端）** 与 fast_qr-wasm32 的真实性能。
#
# 口径收敛（S9j，2026-09-11）：
#   层② 对外引用的 MoonBit 侧统一为 **`wasm-gc`（`moon.mod` 的 `preferred_target`，实际分发形态）**。
#   S9e 的 `wasm`(WASI) 兼容后端对比作为**历史口径保留**，仅在显式指定 `MOON_TARGET=wasm` 时运行，
#   目的是消除「MoonBit 是哪个后端」的歧义（详见 docs/S9j-…）。
#
# 与 S9c 旧口径的区别（对齐 issue「并非统一通过 nodejs 调用」）：
#   旧：fast_qr 侧 Node 进程内直调 + MoonBit 侧 `moonrun` **子进程**整程（含进程启动，实测占 12–20%）。
#   新：两侧都在**同一 Node 进程**内调用；两侧共享同一进程、同一时钟、同一循环形态。
#
# 职责：
#   1) 确保环境（scripts/setup-fast-qr-wasm-env.sh：rust wasm32 target + wasm-bindgen-cli + gcc）；
#   2) 构建 fast_qr v0.14.0 qr_with nodejs 产物（scripts/build-fast-qr-wasm.sh，外部检出，不入库）；
#   3) moon build cmd/bench --target wasm-gc --release；
#   4) 调 scripts/gc-compare.mjs 跑三基准点「逐位对齐 + Node/moonrun 跨宿主护栏 + R 次取最小计时」。
#
# 用法:
#   bash scripts/bench-layer2.sh                 # 【默认 S9j】wasm-gc vs fast_qr，R=3
#   R=5 bash scripts/bench-layer2.sh             # 自定义重复次数
#   bash scripts/bench-layer2.sh --no-build      # 跳过构建（已就绪，只跑对比）
#
# 历史回退口径（S9e，wasm/WASI 后端；不再作为对外引用口径）：
#   MOON_TARGET=wasm bash scripts/bench-layer2.sh
#
# ⚠️ 环境敏感性（S9h，2026-09-11 受控 A/B 证实）：绝对毫秒数强依赖 **Node 大版本与宿主机**
#   （node v24 比 v22 使 MoonBit 侧单次快 18–41%、两侧再受宿主漂移 ±20–40%）；跨环境请只比
#   「同一次 run 内的成对比值」。详见 docs/S9h-层②性能复测异常归因-Node版本与宿主漂移.md。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
export R="${R:-3}"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
PKG="$ROOT/pkg"
MOON_TARGET="${MOON_TARGET:-wasm-gc}"
MOON_GC_BENCH_WASM="${MOON_GC_BENCH_WASM:-$PWD/_build/wasm-gc/release/build/cmd/bench/bench.wasm}"
MOON_BENCH_WASM="${MOON_BENCH_WASM:-$PWD/_build/wasm/release/build/cmd/bench/bench.wasm}"
MOONRUN="${MOONRUN:-moonrun}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== [1/3] fast_qr-wasm 环境 ==="
  bash "$SCRIPT_DIR/setup-fast-qr-wasm-env.sh"
  echo "=== [2/3] 构建 fast_qr qr_with nodejs 产物 ==="
  bash "$SCRIPT_DIR/build-fast-qr-wasm.sh"
fi

if [[ "$MOON_TARGET" == "wasm" ]]; then
  echo "=== [3/3] MoonBit cmd/bench (--target wasm --release，S9e 历史口径) ==="
  moon build cmd/bench --target wasm --release
  echo ""
  echo "=== 层②对比（R=$R，Node 进程内统一调用，wasm/WASI 历史口径）==="
  node "$SCRIPT_DIR/wasm-compare.mjs" \
    --fast "$PKG/fast_qr.js" \
    --moon "$MOON_BENCH_WASM" \
    --reps "$R"
  exit 0
fi

# 默认：wasm-gc（本仓库实际分发形态）
echo "=== [3/3] MoonBit cmd/bench (--target wasm-gc --release，默认后端) ==="
moon build cmd/bench --target wasm-gc --release

echo ""
echo "=== 层②对比（R=$R，Node 进程内统一调用，wasm-gc vs fast_qr）==="
node "$SCRIPT_DIR/gc-compare.mjs" \
  --fast "$PKG/fast_qr.js" \
  --moon-gc "$MOON_GC_BENCH_WASM" \
  ${MOON_BENCH_WASM:+--moon-wasm "$MOON_BENCH_WASM"} \
  --moonrun "$MOONRUN" \
  --reps "$R"

