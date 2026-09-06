#!/usr/bin/env bash
# S9 性能三基准点宿主计时脚本（层① 跨后端选型 + 层② fast_qr-wasm32 对比预留入口）
#
# 对齐 docs/wasm §5.2 的「宿主多次取最小」计时口径（D15，主口径在宿主而非命令内）：
#   对同一点 `moon run cmd/bench --release --target <后端> <点> <N>` 整程重复 R 次，取最小耗时，
#   剔除冷启动抖动；同时记录各点 TOTAL_CHECKSUM 做跨后端结果互证（同源码语义一致则相同）。
#   每个基准点单独一次进程（V03H/V10H/V40H 各配独立迭代数），产出 per-point × per-backend 表，
#   便于对参考 fast_qr 三基准点逐点比照（参考：V03H/V10H/V40H）。
#
# 用法:
#   bash scripts/bench.sh                # 跑 wasm-gc + wasm 双后端 × 三基准点，默认 R=3
#   R=5 bash scripts/bench.sh            # 指定重复次数
#   bash scripts/bench.sh --no-wasm      # 只跑主推后端 wasm-gc（快速/调试）
#
# 层②（对 fast_qr-wasm32，主口径）预留入口：
#   需先检出 fast_qr 并跑 wasm-pack.sh 产出 fast_qr_bg.wasm，再以同一宿主计时口径驱动其 JS/npm
#   宿主跑三基准点做逐位对齐 + 计时（见 docs/S9-性能基准-实现方案.md §3.2/§4 #3）。本脚本预留
#   FAST_QR_WASM 环境位：设置后打印提示，实际 JS 驱动由实现期另行落地（本脚本先固化层①）。
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

R="${R:-3}"
include_wasm=1
if [[ "${1:-}" == "--no-wasm" ]]; then include_wasm=0; fi

# 三基准点：点标签 + 各自迭代数（对齐 cmd/bench default_iters；版本越大单次越贵、迭代越少）。
declare -a points=(V03 V10 V40)
declare -A iters=( [V03]=2000 [V10]=400 [V40]=40 )

# 对 (target, point) 跑 R 次整程，取最小 real 秒；输出 "<min_s> <checksum>"。
# bash 内建 time（TIMEFORMAT='%R'）输出纯秒到 stderr，合并捕获；awk 做浮点比较（不依赖 bc）。
run_min() {
  local t="$1" pt="$2" n="${iters[$pt]}"
  local best="" best_cs=""
  for ((i=0;i<R;i++)); do
    local out
    out="$( { TIMEFORMAT='%R'; time moon run cmd/bench --release --target "$t" -- "$pt" "$n" ; } 2>&1 )"
    local sec cs
    sec="$(echo "$out" | grep -E '^[0-9]+\.[0-9]+$' | tail -1)"
    cs="$(echo "$out" | grep -E 'TOTAL_CHECKSUM=' | sed 's/.*=//')"
    if [[ -z "$best" ]] || [[ "$(awk -v a="$best" -v b="$sec" 'BEGIN{print (b<a)?1:0}')" == "1" ]]; then
      best="$sec"; best_cs="$cs"
    fi
  done
  echo "$best $best_cs"
}

targets=(wasm-gc)
[[ "$include_wasm" == 1 ]] && targets+=(wasm)

echo "# S9 三基准点基准（input=https://example.com/, ecl=H, auto-mask）"
echo "> 宿主计时口径：每点 × 每后端整程跑 R=$R 次取最小（剔冷启动）；数字为整程 wall time（含启动），量级供选型/对比。"
echo "> TOTAL_CHECKSUM 相同 = 跨后端/跨版本结果互证（同源码语义一致）。"
echo ""
echo "### 层① 跨后端选型（wasm-gc vs wasm）"
echo "| 基准点 | 迭代 N | wasm-gc 最小(s) | wasm 最小(s) | TOTAL_CHECKSUM |"
echo "|--------|-------:|----------------:|-------------:|----------------|"
for pt in "${points[@]}"; do
  local_gc="" local_w="" cs_gc="" cs_w=""
  read -r local_gc cs_gc <<< "$(run_min wasm-gc "$pt")"
  if [[ "$include_wasm" == 1 ]]; then
    read -r local_w cs_w <<< "$(run_min wasm "$pt")"
  fi
  echo "| ${pt}H | ${iters[$pt]} | ${local_gc:-N/A} | ${local_w:-N/A} | ${cs_gc:-N/A} |"
done
echo ""
echo "### 层③ native 注记（可选，需具 C 工具链 + fast_qr 环境）"
echo "MoonBit native 与 fast_qr native 对比仅为方法学/量级参考（注明 32 位 wasm 形态 vs 64 位 native 差异），非主口径。"
echo ""
if [[ -n "${FAST_QR_WASM:-}" ]]; then
  echo "### 层② fast_qr-wasm32 对比（主口径）预留"
  echo "FAST_QR_WASM=$FAST_QR_WASM 已设置；需以 JS/npm 宿主跑 fast_qr_bg.wasm 三基准点，"
  echo "与上方 MoonBit wasm 逐位对齐 + 同口径计时（实现期落地，见实现记录）。"
else
  echo "（未设置 FAST_QR_WASM，跳过层② fast_qr-wasm32 对比 —— 那是 S9 主口径，需检出 fast_qr 产物后在具宿主环境执行。）"
fi
