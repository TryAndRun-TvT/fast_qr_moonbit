#!/usr/bin/env bash
# publish-check.sh —— 发布前门禁（mooncakes 归档面 + 元数据 + 质量基线）
#
# 目的：把「发布不可逆」这件事变成**可执行、可在 CI 跑**的门禁。
#   官方文档未给出 `yank`/撤回命令（实测 `moon publish --help` 无相关选项），
#   故必须假设「已发布版本不可撤回」——发布前门禁必须先可执行、再谈发布。
#
# 本门禁做四件事（全部只读、零网络、秒级）：
#   ① 质量基线：fmt --check / check --deny-warn / test；
#   ② 归档面基线：把 `moon package --list` 的条目数钉在**登记值**上，防「归档悄悄膨胀」；
#   ③ 归档内容白名单：断言分发面只含 lib/** + cmd/main + 三件套，且**不含** scripts/docs/测试；
#   ④ 元数据自检：moon.mod 必备字段齐备（name/version/license/readme/description/repository）。
#
# 用法: bash scripts/publish-check.sh
#   ARCHIVE_BASELINE=<N> bash scripts/publish-check.sh   # 临时覆盖条目数基线
#
# 条款来源：docs/mooncakes-发布方案.md §4.3（归档面治理）与 §6-B2（发布前冒烟）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

# 归档面基线：`moon package --list` 条目数（不含 moon 自身日志行）。
# 变更此值必须同步 docs/mooncakes-发布方案.md 的登记值并说明理由（评审可见）。
# 32 → 34（2026-09-14）：README 恢复官方布局（README.mbt.md + README.md 符号链接）并新增
# 模块根空包 moon.pkg 作 README 文档测试宿主（见 docs/README优化-冗余清理与最佳实践.md §6）。
BASELINE="${ARCHIVE_BASELINE:-34}"
# 分发面顶层白名单（除 lib/ 外允许出现的条目）。
ALLOW_TOP=$'LICENSE\nREADME.mbt.md\nREADME.md\nmoon.mod\nmoon.pkg\ncmd/main/main.mbt\ncmd/main/moon.pkg'
# 分发面**禁止**出现的路径前缀/模式（须为空的负向断言）。
DENY_PATTERNS=('/scripts/' '/docs/' '.cnb.yml' '.githooks' '.codebuddy' 'AGENTS.md' '_test.mbt' '_wbtest.mbt')

fail=0
echo "=== 发布前门禁 publish-check（归档面 + 质量基线）==="

# ---- ① 质量基线 -------------------------------------------------------------
echo "--- ① 质量基线 ---"
for stage in fmt-check check test; do
  if bash "scripts/$stage.sh" >/tmp/publish-check-$stage.log 2>&1; then
    printf '  ✅ %s\n' "$stage"
  else
    printf '  ❌ %s（详见 /tmp/publish-check-%s.log）\n' "$stage" "$stage"
    tail -5 "/tmp/publish-check-$stage.log" | sed 's/^/       /'
    fail=1
  fi
done

# ---- ② 归档面条目数基线 ------------------------------------------------------
echo "--- ② 归档面条目数基线 ---"
raw="$(mktemp)"
moon package --list >"$raw" 2>&1 || true
# 剔除 moon 自身的进度/日志行，只留条目
grep -vE '^(Running|Check|Finished|Package to|Warning|Error)' "$raw" \
  | sed 's/:[0-9]*$//' | sed 's/[[:space:]]*$//' | grep -v '^$' >"$raw.items"
count="$(wc -l <"$raw.items" | tr -d ' ')"
echo "  登记基线: $BASELINE 项　实测: $count 项"
if [[ "$count" != "$BASELINE" ]]; then
  echo "  ❌ 归档条目数与基线不符（差 $((count - BASELINE))）"
  echo "     处置：确认是预期变化 → 同步改本脚本 BASELINE 与 docs/mooncakes-发布方案.md §4.3；"
  echo "           非预期 → 检查 .moonignore 是否被削弱。"
  echo "     —— 当前条目 ——"
  sed 's/^/       /' "$raw.items"
  fail=1
else
  echo "  ✅ 与基线一致"
fi

# ---- ③ 归档内容白名单 / 黑名单 ----------------------------------------------
echo "--- ③ 归档内容白名单 / 黑名单 ---"
# 白名单：非 lib/ 条目必须都在 ALLOW_TOP 内
bad_top="$(grep -v '^lib/' "$raw.items" | grep -vxF "$ALLOW_TOP" || true)"
if [[ -n "$bad_top" ]]; then
  echo "  ❌ 分发面出现白名单外的顶层条目："
  sed 's/^/       /' <<<"$bad_top"
  fail=1
else
  echo "  ✅ 非 lib/ 条目均在白名单内（$(grep -vc '^lib/' "$raw.items") 项：LICENSE/README.md/moon.mod/cmd/main）"
fi
# 黑名单：禁止出现维护者上下文与测试文件
deny_hit=""
for pat in "${DENY_PATTERNS[@]}"; do
  hit="$(grep -F "$pat" "$raw.items" || true)"
  [[ -n "$hit" ]] && deny_hit+="$hit"$'\n'
done
if [[ -n "$deny_hit" ]]; then
  echo "  ❌ 分发面混入禁止项："
  sed 's/^/       /' <<<"$deny_hit"
  fail=1
else
  echo "  ✅ 无 scripts/ docs/ 测试文件 / 平台配置混入"
fi
rm -f "$raw" "$raw.items"

# ---- ④ 元数据自检 ------------------------------------------------------------
echo "--- ④ moon.mod 元数据自检 ---"
for field in name version readme license description repository; do
  if grep -qE "^${field}[[:space:]]*=" moon.mod; then
    printf '  ✅ %s\n' "$field"
  else
    printf '  ❌ 缺字段 %s（mooncakes 页面会缺信息）\n' "$field"
    fail=1
  fi
done
# name 必须以「已登录用户名」开头（无法离线核验，只做格式断言）
name_val="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' moon.mod | head -1)"
if [[ "$name_val" == */* ]]; then
  echo "  ✅ name 形如 <user>/<module>：$name_val"
else
  echo "  ❌ name 未以 <user>/<module> 形式声明：$name_val"
  fail=1
fi

echo
if (( fail )); then
  echo ">> 发布前门禁未通过：请按上面 ❌ 逐项修正后再发布（发布不可逆）。"
  exit 1
fi
echo ">> 发布前门禁通过：归档面 ${count} 项、无维护者上下文混入、元数据齐备、质量基线全绿。"
echo "   注：本门禁**不含**实际发布动作（需本地 moon login，见 docs/mooncakes-发布方案.md §6-C）。"
