#!/usr/bin/env bash
# coverage.sh —— T5 覆盖率报告（S10 §6 T5-a）
#
# 目的：把 `moon coverage analyze` 的**逐文件未覆盖行数**固化为可复跑报告，
# 并给出「分模块已覆盖 / 未覆盖」摘要，供 S10 文档与 README 引用。
#
# 口径说明（重要，与 S10 §6 T5-a 一致）：
#   - **先不承诺阈值**（T5-b 才谈「不下降」锁定）；本脚本只产出报告，不做门禁判定；
#   - 覆盖率是 T4（变异检测）的**补充而非替代**：100% 行覆盖下仍可能全是 `actual == actual`，
#     故本报告的解读必须以 S10 §5 铁律 3 为前提。
#   - 覆盖率数字含 `cmd/*` 三个探针包（仅审计/演示，不属库分发面），解释时须区分。
#
# 用法: bash scripts/coverage.sh            # 打印报告
#   COVERAGE_OUT=docs/xxx.md bash scripts/coverage.sh   # 同时写入文件
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

RAW="$(mktemp)"
moon coverage analyze >"$RAW" 2>&1 || true

echo "=== T5-a 覆盖率报告（moon coverage analyze，行级）==="
grep -E '^[0-9]+ uncovered line\(s\) in ' "$RAW" | sed 's/^/  /'
echo
grep -E '^Total: ' "$RAW" | sed 's/^/  /'
echo
echo "--- 库分发面（lib/**，排除 cmd/* 探针）---"
lib_total=0
while IFS= read -r line; do
  n="${line%% uncovered*}"
  f="${line#* in }"; f="${f%%:*}"
  case "$f" in
    lib/*) lib_total=$((lib_total + n)); printf '  %-52s %4d\n' "$f" "$n" ;;
  esac
done < <(grep -E '^[0-9]+ uncovered line\(s\) in ' "$RAW")
echo "  ---- lib/** 合计未覆盖 $lib_total 行"
echo
echo "注：覆盖率是 T4（变异检测，bash scripts/test-audit.sh mutation）的补充而非替代——"
echo "    行覆盖率高 ≠ 断言有效（S10 §5 铁律 3：禁止 actual == actual）。"

if [[ -n "${COVERAGE_OUT:-}" ]]; then
  {
    echo "# T5-a 覆盖率报告（行级）"
    echo
    echo "> 由 \`bash scripts/coverage.sh\` 生成（\`moon coverage analyze\`）；**仅报告，不设阈值**。"
    echo "> 覆盖率是 T4 变异检测的补充而非替代（S10 §5 铁律 3）。"
    echo
    echo '```'
    grep -E '^[0-9]+ uncovered line\(s\) in |^Total: ' "$RAW"
    echo "---- lib/** 合计未覆盖 $lib_total 行"
    echo '```'
  } >"$COVERAGE_OUT"
  echo ">> 已写入 $COVERAGE_OUT"
fi
rm -f "$RAW"
