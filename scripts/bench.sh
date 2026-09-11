#!/usr/bin/env bash
# S9 性能三基准点 **层① 跨后端选型自比**脚本（wasm-gc vs wasm）+ 跨后端 checksum 互证。
#
# 【后端角色约定】（S9j 起全局统一，避免「比的是哪个后端」歧义）：
#   - wasm-gc = 主推/默认后端（moon.mod 的 preferred_target，实际分发形态）→ **对外对比口径**；
#   - wasm(WASI) = 兼容兜底后端，仅作历史记录 → **不参与对外对比**。
#   本脚本是**自比**（回答「为什么默认 wasm-gc」的选型依据），**不是** vs fast_qr 对比：
#   层②「vs fast_qr-wasm32」见 scripts/bench-layer2.sh（默认 wasm-gc；MOON_TARGET=wasm 走历史口径），
#   见 docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md。
#
# 对齐 docs/wasm §5.2 的「宿主多次取最小」计时口径（D15，主口径在宿主而非命令内）：
#   对同一点 `moon run cmd/bench --release --target <后端> <点> <N>` 整程重复 R 次，取最小耗时，
#   剔除冷启动抖动；同时记录各点 TOTAL_CHECKSUM 做跨后端结果互证（同源码语义一致则相同）。
#   每个基准点单独一次进程（V03H/V10H/V40H 各配独立迭代数），产出 per-point × per-backend 表。
#
# 用法:
#   bash scripts/bench.sh                # 跑 wasm-gc + wasm 双后端 × 三基准点，默认 R=3
#   R=5 bash scripts/bench.sh            # 指定重复次数
#   bash scripts/bench.sh --no-wasm      # 只跑主推后端 wasm-gc（快速/调试）
#
# 交叉引用：层②（vs fast_qr，默认 gc）scripts/bench-layer2.sh + docs/S9j-…；
#   体积（默认 gc）scripts/bench-size.sh + docs/S9i-…。
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
echo "### 层②（vs fast_qr-wasm32）已独立实现，不在本脚本内"
echo "本脚本只做层① 跨后端自比；层② 见 bash scripts/bench-layer2.sh（默认后端 wasm-gc；"
echo "MOON_TARGET=wasm 走 S9e 的 wasm/WASI 历史口径），详见 docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md。"
