#!/usr/bin/env bash
# 测试审计脚本（S10 附录 D/E 的可复跑入口）——**仅本地/审计，不进 push CI**。
#
# 回答两个「覆盖率答不出」的问题：
#   E) 强负向对照（变异检测）：把已知缺陷就地植入实现，跑 `moon test`，看**是否有测试变红**。
#      「0 个测试变红」= 该缺陷类型当前**无保护**（S10 附录 E 的 M11/M12 就是这样发现的）。
#   D) 独立解码回读：用第三方纯 JS 解码器（jsqr）解码我方矩阵，断言读回原文。
#      这是「与参考逐位一致」之外唯一的**独立语义证据**（口径见 S10 附录 D）。
#
# 前置（缺则对应检查自动跳过并打印原因）：
#   - 变异检测：只需 MoonBit 工具链（`bash scripts/setup-moonbit.sh`）。
#   - 解码回读：需 node + `jsqr`，以及 `moon build cmd/bench --target wasm-gc --release`。
#
# 用法:
#   bash scripts/test-audit.sh                # 全部（能跑多少跑多少）
#   bash scripts/test-audit.sh mutation       # 只跑变异检测
#   bash scripts/test-audit.sh decode         # 只跑解码回读
#   bash scripts/test-audit.sh list           # 只列出变异清单（不执行）
#
# 安全：变异检测会**就地改动 `lib/` 下源码**（每条用 `git checkout -- lib/` 还原）。
#       故要求 `lib/` 工作区干净，否则拒绝运行；结束时再校验一次还原干净。
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-all}"

# --- 变异清单：编号|描述|文件|锚点原文|替换文本 -------------------------------
# 锚点用 `\n` 表示换行（由 scripts/apply-mutation.py 还原）。
mutations() {
  cat <<'MUT'
M1|掩码 2/3 公式互换|lib/internal/matrix/datamasking.mbt|2 => x % 3 == 0\n    3 => (x + y) % 3 == 0|2 => (x + y) % 3 == 0\n    3 => x % 3 == 0
M2|Format 表 L-mask1 错 1 位|lib/internal/constants/hardcode.mbt|30660, 29427, 32170, 30877|30660, 29426, 32170, 30877
M4|N2 每 2x2 计 4 分（应 3）|lib/internal/matrix/score.mbt|square = square + 3|square = square + 4
M5|division 余数截断 1 字节|lib/internal/reedsolomon/reedsolomon.mbt|let rem_len = by.length() - 1|let rem_len = by.length() - 2
M6|容量表 Numeric-L-V01 41->42|lib/internal/constants/capacity.mbt|41, 77, 127, 187, 255, 322, 370, 461|42, 77, 127, 187, 255, 322, 370, 461
M7|cci_bits Numeric 分段 9->8|lib/internal/constants/capacity.mbt|if v >= 26 {\n        14\n      } else if v >= 9 {\n        12|if v >= 26 {\n        14\n      } else if v >= 8 {\n        12
M8|QRCode::set 改回共享数组|lib/qr.mbt|let data = self.data.copy()|let data = self.data
M9|is_data_byte 类型位放宽|lib/internal/matrix/module.mbt|((b >> 1) & 7) == 0|((b >> 1) & 3) == 0
M11|容量表 Numeric-L 中间项 +1|lib/internal/constants/capacity.mbt|1022, 1101, 1250,|1022, 1101, 1251,
M12|Format 表 M-mask3 值 -1|lib/internal/constants/hardcode.mbt|21522, 20773, 24188, 23371|21522, 20773, 24188, 23370
MUT
}

run_mutation() {
  if ! git diff --quiet -- lib/; then
    echo "!! lib/ 有未提交改动；本脚本会就地改写并 `git checkout -- lib/` 还原。"
    echo "   请先 git stash 或提交后再运行。"
    exit 1
  fi
  echo "=== E) 强负向对照（变异检测，S10 附录 E）==="
  echo "基线：$(moon test </dev/null 2>&1 | tail -1)"
  echo
  printf '%-4s %-30s %-8s %s\n' "编号" "植入缺陷" "失败数" "判定"
  printf '%-4s %-30s %-8s %s\n' "----" "------------------------------" "------" "----"
  # 变异表落盘，循环用专用 fd 3 读：`moon test` 会**消费 stdin**，
  # 若用 `<<<"$table"` 直接喂 stdin，第一条之后剩余行会被吃掉、循环提前结束（实测踩过）。
  local table; table="$(mktemp)"; mutations >"$table"
  local id desc file from to out failed verdict
  while IFS='|' read -r id desc file from to <&3; do
    [ -z "$id" ] && continue
    if ! python3 scripts/apply-mutation.py "$file" "$from" "$to" 2>/dev/null; then
      printf '%-4s %-30s %-8s %s\n' "$id" "$desc" "-" "⚠️ 锚点失效（实现已变，需同步更新清单）"
      git checkout -- lib/; continue
    fi
    out="$(moon test </dev/null 2>&1 | tail -1)"
    failed="$(sed -n 's/.*failed: \([0-9]*\)\..*/\1/p' <<<"$out")"
    verdict="✅ 已检出"; [ "${failed:-0}" = "0" ] && verdict="❌ 漏检"
    printf '%-4s %-30s %-8s %s\n' "$id" "$desc" "${failed:-?}" "$verdict"
    git checkout -- lib/
  done 3<"$table"
  rm -f "$table"
  if ! git diff --quiet -- lib/; then
    echo "!! 警告：lib/ 未能完全还原，请手动 git checkout -- lib/" >&2; exit 1
  fi
  echo
  echo "注：❌ 项即当前「无保护」的缺陷类型（修改实现不会被任何测试发现），"
  echo "    需按 S10 §6 补测后重跑本检查，直到全部 ✅。"
}

run_decode() {
  echo "=== D) 独立解码回读（jsqr，S10 附录 D）==="
  if ! command -v node >/dev/null 2>&1; then echo ">> 跳过：未找到 node"; return 0; fi
  if ! node -e 'require.resolve("jsqr")' >/dev/null 2>&1; then
    echo ">> 跳过：未安装 jsqr（本地审计用依赖：npm i jsqr，不入库、不入 CI）"; return 0
  fi
  moon build cmd/bench --target wasm-gc --release >/dev/null
  node scripts/qr-decode-check.mjs \
    --moon-gc "_build/wasm-gc/release/build/cmd/bench/bench.wasm" \
    --moonrun "$(command -v moonrun)" \
    --expr "https://example.com/" --points V03,V10,V40
}

case "$MODE" in
  mutation) run_mutation ;;
  decode)   run_decode ;;
  list)     mutations ;;
  all)      run_mutation; echo; run_decode ;;
  *) echo "用法: bash scripts/test-audit.sh [all|mutation|decode|list]"; exit 2 ;;
esac
