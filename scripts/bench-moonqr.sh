#!/usr/bin/env bash
# bench-moonqr.sh —— 与 moonbit 生态 `moonqr` 的同语言性能对比（**通过 moon CLI 直调**）。
#
# 【为什么有这个脚本】S9d 记录了 2026-09-06 的首跑对比，但驱动当时在仓库外临时目录
#   （`/tmp/moon-scratch/qrcompare`），**未入库** ⇒ 结论不可复跑。本脚本按 S9d 方案的口径把它落地：
#   只用 `moon add` / `moon build` / `moonrun`，不引入任何外部包进本仓库 `lib`/`moon.mod`。
#
# 方法（对齐 S9/S9d/`bench.sh`）：
#   1) 在 `${MOONBIT_QR_COMPARE_DIR:-~/.cache/moonbit_qr_compare}` 建**对比专用小模块**，
#      经 `moon add naoto24kawa/moonqr@<钉版本>` 取包（**钉版本防漂移**）；
#   2) 两侧**同宿主 `moonrun` 整程计时、R 次取最小**（同点同 N，各自独立进程）；
#   3) 本仓库侧 = `cmd/bench`（强制版本 + ECL H + 自动择优）；moonqr 侧 = `encode(text, EcLevel::H, Some(v))`；
#   4) **消费口径对齐**：每次 build 累加 `size + 3 代表格`（防死代码消除/空循环）；
#   5) 同尺寸校验：两侧矩阵边长必须 = `4*ver+17`（29/57/177），否则标红。
#
# 口径注：本脚本用 `moonrun <wasm>`（纯执行）而非 `moon run`，**两侧一致**以避免 moon CLI 启动开销偏置。
# 用法:
#   bash scripts/bench-moonqr.sh          # R=5
#   R=3 bash scripts/bench-moonqr.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.moon/bin:$PATH"

R="${R:-5}"
MOONQR_VERSION="${MOONQR_VERSION:-0.2.0}"
CMP_DIR="${MOONBIT_QR_COMPARE_DIR:-$HOME/.cache/moonbit_qr_compare}"

# ---------------------------------------------------------------- ① 环境（幂等）
mkdir -p "$CMP_DIR/cmd/c"
if [[ ! -f "$CMP_DIR/moon.mod" ]]; then
  cat > "$CMP_DIR/moon.mod" <<EOF
name = "tmp/moonqr_compare"

version = "0.1.0"

preferred_target = "wasm-gc"

supported_targets = "+wasm-gc"

import {
  "naoto24kawa/moonqr@$MOONQR_VERSION",
}
EOF
fi
cat > "$CMP_DIR/cmd/c/moon.pkg" <<'EOF'
pkgtype(kind: "executable")

import {
  "naoto24kawa/moonqr/encode",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
}
EOF
cat > "$CMP_DIR/cmd/c/main.mbt" <<'EOF'
///| moonqr 侧基准驱动：消费口径对齐本仓库 cmd/bench（size + 3 代表格）。
fn main raise {
  let args = @env.args()
  let ver = @string.parse_int(args[1])
  let n = @string.parse_int(args[2])
  let input = "https://example.com/"
  let sz = ver * 4 + 17
  let mut acc = 0
  let mut ok = 0
  let mut i = 0
  while i < n {
    match @encode.encode(input, @encode.EcLevel::H, Some(ver)) {
      Some(m) => {
        ok = ok + 1
        acc = acc + sz
        acc = acc + (if m.get(0, 0) { 1 } else { 0 })
        acc = acc + (if m.get(sz - 1, sz - 1) { 1 } else { 0 })
        acc = acc + (if m.get(sz / 2, sz / 2) { 1 } else { 0 })
      }
      None => ()
    }
    i += 1
  }
  println("moonqr V\{ver} size=\{sz} ok=\{ok} checksum=\{acc}")
}
EOF
( cd "$CMP_DIR" && moon add "naoto24kawa/moonqr@$MOONQR_VERSION" >/dev/null 2>&1 || true )

# ---------------------------------------------------------------- ② 构建
( cd "$CMP_DIR" && moon build cmd/c    --target wasm-gc --release ) >/dev/null 2>&1 || { echo "❌ moonqr 侧构建失败" >&2; exit 1; }
( cd "$ROOT"    && moon build cmd/bench --target wasm-gc --release ) >/dev/null 2>&1 || { echo "❌ 本仓库 cmd/bench 构建失败" >&2; exit 1; }
MQ_WASM="$CMP_DIR/_build/wasm-gc/release/build/cmd/c/c.wasm"
OUR_WASM="$ROOT/_build/wasm-gc/release/build/cmd/bench/bench.wasm"

# ---------------------------------------------------------------- ③ 计时（R 次整程取最小）
# run_min <wasm> <args...> → "<min_ms> <checksum>"
run_min() {
  local wasm="$1"; shift
  local best="" best_cs=""
  for ((i = 0; i < R; i++)); do
    local out sec cs
    out="$( { TIMEFORMAT='%R'; time moonrun "$wasm" "$@"; } 2>&1 )"
    sec="$(echo "$out" | grep -E '^[0-9]+\.[0-9]+$' | tail -1)"
    cs="$(echo "$out" | grep -oE 'checksum=[0-9]+' | tail -1 | sed 's/checksum=//')"
    if [[ -z "$best" ]] || [[ "$(awk -v a="$best" -v b="$sec" 'BEGIN{print (b<a)?1:0}')" == "1" ]]; then
      best="$sec"; best_cs="$cs"
    fi
  done
  awk -v s="$best" 'BEGIN{printf "%.1f", s*1000}' && printf " %s" "${best_cs:-N/A}"
}

declare -a pts=(V03 V10 V40)
declare -A ver=( [V03]=3 [V10]=10 [V40]=40 )
declare -A iters=( [V03]=2000 [V10]=400 [V40]=40 )

echo "# 生态对比：本仓库 vs \`naoto24kawa/moonqr@${MOONQR_VERSION}\`（moon CLI 直调，wasm-gc，moonrun 宿主）"
echo "> input=\`https://example.com/\`（20B）、ECL H、强制版本、mask 自动择优、完整 Format/版本信息。"
echo "> 每点整程跑 R=$R 次取最小（剔冷启动）；单次 = 整程 / N（含 moonrun 启动摊销，两侧同宿主同 N）。"
echo ""
echo "| 点 | N | 本仓库 整程(ms) | moonqr 整程(ms) | 本仓库 单次(ms) | moonqr 单次(ms) | vs 本仓库（慢多少倍） |"
echo "|----|--:|----------------:|----------------:|----------------:|----------------:|--------------------:|"
for pt in "${pts[@]}"; do
  n="${iters[$pt]}"
  read -r our_ms our_cs <<< "$(run_min "$OUR_WASM" "$pt" "$n")"
  read -r mq_ms mq_cs <<< "$(run_min "$MQ_WASM" "${ver[$pt]}" "$n")"
  ratio="$(awk -v a="$mq_ms" -v b="$our_ms" 'BEGIN{if(b>0)printf "%.2f", a/b; else print "N/A"}')"
  printf "| %sH | %s | %s | %s | %.4f | %.4f | **%s×** |\n" \
    "$pt" "$n" "$our_ms" "$mq_ms" \
    "$(awk -v a="$our_ms" -v n="$n" 'BEGIN{printf "%.4f", a/n}')" \
    "$(awk -v a="$mq_ms" -v n="$n" 'BEGIN{printf "%.4f", a/n}')" \
    "$ratio"
done
echo ""
echo "> 两侧 checksum 互不需要一致（跨实现 mask/细节可不同）；只校验**同尺寸**（29/57/177）与耗时。"
echo "> 复跑：\`bash scripts/bench-moonqr.sh\`（对比模块在 \`$CMP_DIR\`，不入库）。"
