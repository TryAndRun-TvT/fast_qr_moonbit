#!/usr/bin/env bash
# docs-consistency.sh —— 文档一致性门禁（S12 §6.2 D4 / §7.1 / §7.4）
#
# 目的：把「文档与实现的一致性收敛」从**人眼巡检**换成**可执行门禁**。
# 背景（S12 §3.3 实证）：测试用例计数「146 → 147」在两个版本内**二次漂移**，
#   说明「靠人巡检」不可持续；SDD 的答案是 `implement → converge` 机制化。
#
# 三项断言（相互独立，任一红即整链红）：
#   ① 状态字段：docs/**/*.md 每篇头部须含 `> **状态**：`，值域 `现行|历史|已失效`；
#      `历史` 须带 `并入：`（写明结论去哪了）；`现行`/`历史` 不得声明已失效前提为现行口径。
#   ② 计数漂移：仓库内声明为「登记处」的文档值，与**实跑**结果比对，不一致即红。
#      非登记处篇章的数字**不设为门禁**（避免噪音——历史篇里的旧数字是史料，不是漂移）。
#   ②b 版本漂移：README（公开落地页）**不得写死当前版本号**（S12 §3.3 P3 / S11 §9.2）——
#      必须写「已发布（首个版本）」+ 指向版本页；`moon.mod` 的 version 是唯一真值源。
#   ③ 索引覆盖：docs/** 每篇必须在 `docs/README-导航与索引.md` 中出现（反「新增文档漏更新索引」）。
#   ④ 文档规模：docs/**/*.md 单篇 ≤DOC_LIMIT 行（AGENTS.md §四 已定，此前只管 .mbt，此处补齐）。
#
# 用法: bash scripts/docs-consistency.sh
#   SKIP_SLOW=1  bash scripts/docs-consistency.sh   # 跳过 ②（不跑 moon test）
# 环境变量: DOC_LIMIT（默认 800）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"
DOC_LIMIT="${DOC_LIMIT:-800}"

REGISTRY="docs/S10b-测试覆盖率报告.md"   # ② 测试计数的登记处（S12 §6.2 D4-1）
INDEX="docs/README-导航与索引.md"

echo "=== 文档一致性门禁（S12 D4）==="
fail=0

mapfile -d '' -t FILES < <(git ls-files -z 'docs/*.md')
if (( ${#FILES[@]} == 0 )); then
  echo "!! 未找到 docs/**/*.md" >&2
  exit 1
fi

# ── ① 状态字段 ──────────────────────────────────────────────────────────────
echo
echo "-- ① 状态字段（状态 | 历史须带「并入：」）"
status_fail=0
for f in "${FILES[@]}"; do
  line="$(grep -m1 '^> \*\*状态\*\*：' "$f" || true)"
  if [[ -z "$line" ]]; then
    printf '  ❌ %s：缺少 `> **状态**：` 头部字段\n' "$f"
    status_fail=1; continue
  fi
  val="$(sed -E 's/^> \*\*状态\*\*：([^　|]*).*/\1/' <<<"$line")"
  case "$val" in
    现行|历史|已失效) ;;
    *) printf '  ❌ %s：状态值 `%s` 不在值域 `现行|历史|已失效`\n' "$f" "$val"; status_fail=1; continue ;;
  esac
  if [[ "$val" == "历史" ]] && ! grep -q '并入：' <<<"$line"; then
    printf '  ❌ %s：状态为「历史」但缺少 `并入：`（结论去哪了）\n' "$f"
    status_fail=1; continue
  fi
  if ! grep -q '日期：[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' <<<"$line"; then
    printf '  ❌ %s：状态头缺少 `日期：YYYY-MM-DD`\n' "$f"; status_fail=1; continue
  fi
  if ! grep -q '索引：' <<<"$line"; then
    printf '  ❌ %s：状态头缺少 `索引：`（在导航中的归属）\n' "$f"; status_fail=1; continue
  fi
done
if (( status_fail )); then fail=1; else echo "  ✅ ${#FILES[@]} 篇状态字段齐备且值域合法"; fi

# ── ② 计数漂移（登记处 vs 实跑）──────────────────────────────────────────────
echo
echo "-- ② 计数漂移（登记处：$REGISTRY）+ ②b 版本漂移"
if [[ "${SKIP_SLOW:-0}" == "1" ]]; then
  echo "  ⏭  跳过（SKIP_SLOW=1）"
else
  out="$(moon test 2>&1 || true)"     # set -e 下必须兜住：moon test 有红时返回非 0
  actual="$(sed -nE 's/.*Total tests: ([0-9]+).*/\1/p' <<<"$out" | tail -1)"
  if [[ -z "$actual" ]]; then
    echo "  ❌ 无法从 moon test 取到 `Total tests: N`（工具链缺失？输出尾部如下）"
    tail -3 <<<"$out" | sed 's/^/     /'
    fail=1
  else
    declared="$(sed -nE 's/.*<!-- test-count: ([0-9]+) -->.*/\1/p' "$REGISTRY" | head -1)"
    if [[ -z "$declared" ]]; then
      echo "  ❌ 登记处 $REGISTRY 未声明 `<!-- test-count: N -->`"
      fail=1
    elif [[ "$declared" != "$actual" ]]; then
      echo "  ❌ 计数漂移：登记处 declared=$declared，实跑 actual=$actual"
      echo "     处置：更新 $REGISTRY 的 test-count 标记（并写明理由），或修正实现。"
      fail=1
    else
      echo "  ✅ 计数一致：test-count=$actual（实跑 `moon test`）"
    fi
  fi
fi

# ── ②b 版本漂移（README 不得写死当前版本号）──────────────────────────────────
ver="$(sed -nE 's/^version *= *"([^"]+)".*/\1/p' moon.mod | head -1)"
if [[ -z "$ver" ]]; then
  echo "  ❌ 无法从 moon.mod 取 version"
  fail=1
else
  # 允许出现的地方：依赖示例（`moon add ...@N`）与「精确版本以...为准」指向页。
  # 禁止：把当前版本号当作「发布状态」写死。
  if grep -qE "发布状态[^\n]*\`${ver}\`" README.md; then
    echo "  ❌ README.md 的「发布状态」写死了当前版本号 \`$ver\`（下次发布会漂移）"
    echo "     处置：改为「已发布（首个版本）」+ 指向 mooncakes 版本页（S11 §9.2）。"
    fail=1
  else
    echo "  ✅ README 未写死当前版本号（moon.mod version=$ver 仅作依赖示例）"
  fi
fi

# ── ③ 索引覆盖 ──────────────────────────────────────────────────────────────
echo
echo "-- ③ 索引覆盖（$INDEX）"
cover_fail=0
for f in "${FILES[@]}"; do
  [[ "$f" == "$INDEX" ]] && continue
  base="$(basename "$f")"
  # 索引里用相对链接指向该文件即可（basename 唯一，足以判定）
  if ! grep -qF "$base" "$INDEX"; then
    printf '  ❌ %s：未出现在 %s 中（新增文档须双更新索引）\n' "$f" "$INDEX"
    cover_fail=1
  fi
done
if (( cover_fail )); then fail=1; else echo "  ✅ ${#FILES[@]} 篇均已被索引收录"; fi

# ── ④ 文档规模 ──────────────────────────────────────────────────────────────
echo
echo "-- ④ 文档规模（单篇 ≤${DOC_LIMIT} 行）"
size_fail=0
for f in "${FILES[@]}"; do
  n="$(wc -l <"$f")"
  if (( n > DOC_LIMIT )); then
    printf '  ❌ %-58s %5d 行（超限 %d）\n' "$f" "$n" "$((n - DOC_LIMIT))"
    size_fail=1
  fi
done
if (( size_fail )); then
  echo "     处置：拆出「承接篇」并在两处索引登记（AGENTS.md §四）。"
  fail=1
else
  echo "  ✅ 全部文档在限内"
fi

echo
if (( fail )); then
  echo ">> 文档一致性门禁未通过（S12 §7.1/§7.4）。"
  exit 1
fi
echo ">> 文档一致性门禁通过。"
