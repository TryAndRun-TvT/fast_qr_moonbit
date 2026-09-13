#!/usr/bin/env bash
# coverage.sh —— T5 覆盖率报告（S10 §6 T5-a）
#
# 目的：把 `moon coverage analyze` 的**逐文件未覆盖行数**固化为可复跑报告，
# 并给出「分模块已覆盖 / 未覆盖」摘要，供 S10 文档与 README 引用。
#
# 口径说明（重要，与 S10 §6 T5-a/T5-b 一致）：
#   - T5-a：本脚本产出报告；
#   - T5-b（v5 新增）：`--floor` 模式做**「不下降」门禁**——把 `lib/**` 未覆盖行数
#     与 `docs/S10b-测试覆盖率报告.md` 中登记的上限比较，超过即失败。
#     **不设「绝对覆盖率百分比」**（S10 §6 明确先「不下降」再逐步抬升）：
#     行覆盖率是 T4 变异检测的补充，绝对数字容易诱发「造无信息量用例」（铁律 6）。
#   - 覆盖率是 T4（变异检测）的**补充而非替代**：100% 行覆盖下仍可能全是 `actual == actual`，
#     故本报告的解读必须以 S10 §5 铁律 3 为前提。
#   - 覆盖率数字含 `cmd/*` 三个探针包（仅审计/演示，不属库分发面），解释时须区分。
#
# 用法:
#   bash scripts/coverage.sh                 # 打印报告（T5-a）
#   bash scripts/coverage.sh --floor         # 不下降门禁：lib/** 未覆盖行数 <= 登记上限（T5-b）
#   COVERAGE_OUT=docs/xxx.md bash scripts/coverage.sh   # 同时写入文件
#
# T5-b 登记上限的**唯一权威来源**是 `docs/S10b-测试覆盖率报告.md` 里的机器可读行：
#   `<!-- coverage-floor: lib_uncovered=N -->`
# 改这个数必须同时更新报告正文并说明理由（评审可见），禁止只改数字。
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

# ---- T5-b：不下降门禁 ------------------------------------------------------
FLOOR_FILE="docs/S10b-测试覆盖率报告.md"
floor_check() {
  local limit
  limit="$(sed -n 's/.*<!-- coverage-floor: lib_uncovered=\([0-9]*\) -->.*/\1/p' "$FLOOR_FILE" | head -1)"
  if [[ -z "$limit" ]]; then
    echo "!! T5-b：$FLOOR_FILE 未登记 \`<!-- coverage-floor: lib_uncovered=N -->\`，跳过门禁。" >&2
    return 0
  fi
  echo "--- T5-b 不下降门禁 ---"
  echo "  登记上限（lib/** 未覆盖行）: $limit"
  echo "  实测（lib/** 未覆盖行）    : $lib_total"
  if (( lib_total > limit )); then
    echo "  ❌ 覆盖率**下降**（未覆盖行 $lib_total > 上限 $limit）。" >&2
    echo "     处置：补测或说明理由后，同步更新 $FLOOR_FILE 的 coverage-floor 标记。" >&2
    return 1
  fi
  echo "  ✅ 未下降（$lib_total <= $limit）"
  return 0
}

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

if [[ "${1:-}" == "--floor" ]]; then
  echo
  floor_check
fi
