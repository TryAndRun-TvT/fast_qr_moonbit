#!/usr/bin/env bash
# publish-check.sh —— 发布前门禁（mooncakes 归档面 + 元数据 + 质量基线）
#
# 目的：把「发布不可逆」这件事变成**可执行、可在 CI 跑**的门禁。
#   官方文档未给出 `yank`/撤回命令（实测 `moon publish --help` 无相关选项），
#   故必须假设「已发布版本不可撤回」——发布前门禁必须先可执行、再谈发布。
#
# 本门禁做五件事（全部只读、零网络、秒级）：
#   ① 质量基线：fmt --check / check --deny-warn / test；
#   ② 归档面基线：把 `moon package --list` 的条目数钉在**登记值**上，防「归档悄悄膨胀」；
#   ③ 归档内容白名单：断言分发面只含 lib/** + cmd/main + 三件套，且**不含** scripts/docs/测试；
#   ④ 元数据自检：moon.mod 必备字段齐备（name/version/license/readme/description/repository）；
#   ⑤ 发布面链接可达性（离线静态）：归档内文件（README/LICENSE/...）**不得**用相对链接指向
#      **归档外**路径（`docs/**`、`AGENTS.md`），否则 mooncakes 落地页会 404。
#
# 用法: bash scripts/publish-check.sh
#   ARCHIVE_BASELINE=<N> bash scripts/publish-check.sh   # 临时覆盖条目数基线
#   PUBLISH_LINK_NET=1 bash scripts/publish-check.sh     # 额外对 README 的 https 链接做 HEAD 校验
#
# 条款来源：docs/mooncakes-发布方案.md §4.3（归档面治理）与 §6-B2（发布前冒烟）；
#   ⑤ 为 v6 新增（ISSUE #47 / README 优化评估报告第二轮 P0-A）。
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

# ---- ⑤ 发布面链接可达性（离线静态 + 可选网络） ------------------------------
echo "--- ⑤ 发布面链接可达性（归档内 Markdown 不得有指向归档外的相对链接）---"
# 机制：mooncakes 渲染 README 时把相对链接 r 重写为
#   https://assets.mooncakes.io/source/<name>@<version>/<r>
# 而 .moonignore 排除 /docs/ 与 /AGENTS.md → 这类链接在落地页 404。
# 口径：**归档内**文件（moon package --list 的条目）中，若出现相对链接指向归档外的目标，
#       即判定失败（要求改用仓库绝对链接，见 README「链接约定」）。
# 说明：只查「归档内**以外**」的目标；指向归档内文件（LICENSE、cmd/main/main.mbt）的相对链接合法。
# 注：`moon package --list` 的进度日志直接写终端，`2>/dev/null` 无法屏蔽；
#     为稳定取条目，落临时文件后过滤（与 ② 同法）。
declare -A ARCHIVE_MEMBER=()
arch_tmp="$(mktemp)"
moon package --list >"$arch_tmp" 2>&1 || true
grep -vE '^(Running|Check|Finished|Package to|Warning|Error)' "$arch_tmp" \
  | sed 's/:[0-9]*$//' | sed 's/[[:space:]]*$//' | grep -v '^$' >"$arch_tmp.items"
while IFS= read -r m; do [[ -n "$m" ]] && ARCHIVE_MEMBER["$m"]=1; done <"$arch_tmp.items"
rm -f "$arch_tmp" "$arch_tmp.items"

# 需要检查的归档内 Markdown：moon.mod 的 readme 字段（去重）
PUB_READMES=()
while IFS= read -r rd; do
  [[ -z "$rd" || ! -f "$rd" ]] && continue
  dup=0; for x in "${PUB_READMES[@]:-}"; do [[ "$x" == "$rd" ]] && dup=1; done
  (( dup )) || PUB_READMES+=("$rd")
done < <(sed -n 's/^readme[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' moon.mod)
[[ -f README.md ]] && { dup=0; for x in "${PUB_READMES[@]:-}"; do [[ "$x" == "README.md" ]] && dup=1; done; (( dup )) || PUB_READMES+=("README.md"); }

bad_links=0
checked_pub=0
for f in "${PUB_READMES[@]}"; do
  [[ -f "$f" ]] || continue
  # 提取相对链接（跳过 http(s)/mailto/纯锚点/绝对路径），忽略代码块与行内 code span
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in http://*|https://*|mailto:*|tel:*|\#*|/*) continue ;; esac
    path="${target%%#*}"
    [[ -z "$path" ]] && continue
    path="$(printf '%b' "${path//%/\\x}")"
    # 归一化相对路径（折叠 ./ ../）
    resolved="$(realpath -m --relative-to=. "$path" 2>/dev/null || echo "$path")"
    checked_pub=$((checked_pub + 1))
    if [[ -z "${ARCHIVE_MEMBER[$resolved]:-}" ]]; then
      printf '  ❌ %s -> %s（解析为 %s，**不在发布归档内** → mooncakes 落地页会 404）\n' "$f" "$target" "$resolved"
      bad_links=$((bad_links + 1))
    fi
  done < <(awk '
    /^[[:space:]]*```/ { inblock = !inblock; next }
    inblock { next }
    { line = $0
      while (match(line, /`[^`]*`/)) { line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH) }
      # Markdown 链接/图片 [x](path) / ![x](path)
      while (match(line, /!?\[[^]]*\]\([^)]*\)/)) {
        seg = substr(line, RSTART, RLENGTH)
        sub(/^!?\[[^]]*\]\(/, "", seg); sub(/\)$/, "", seg)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", seg)
        sub(/[[:space:]]+".*"$/, "", seg)
        print seg
        line = substr(line, RSTART + RLENGTH)
      }
      # HTML 内联 <img src="..."> / <a href="...">（含单/双引号）
      line = $0
      while (match(line, /(src|href)=["'"'"'][^"'"'"']*["'"'"']/)) {
        seg = substr(line, RSTART, RLENGTH)
        sub(/^(src|href)=["'"'"']/, "", seg); sub(/["'"'"']$/, "", seg)
        print seg
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$f")
done

if (( bad_links > 0 )); then
  echo "  ❌ 归档内文件出现 $bad_links 条「指向归档外」的相对链接（共查 $checked_pub 条）"
  echo "     处置：改为仓库绝对链接 https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/<path>"
  echo "           （口径见 README「链接约定」与 docs/README优化-冗余清理与最佳实践.md §9）"
  fail=1
else
  echo "  ✅ 归档内文件（${PUB_READMES[*]}）共 $checked_pub 条相对链接，**全部**指向归档内成员"
fi

# 可选：网络校验 README 的 https 外链（默认关闭；CI/联网时用 PUBLISH_LINK_NET=1 打开）
if [[ "${PUBLISH_LINK_NET:-0}" == "1" ]]; then
  echo "  · 网络校验 README 的 https 链接（PUBLISH_LINK_NET=1）..."
  net_bad=0
  while IFS= read -r url; do
    code="$(curl -s -o /dev/null -I -w '%{http_code}' --max-time 15 "$url" || echo "000")"
    if [[ "$code" != 2* && "$code" != 3* ]]; then
      printf '    ❌ %s -> HTTP %s\n' "$url" "$code"
      net_bad=$((net_bad + 1))
    fi
  done < <(grep -oE 'https://[^)"'"'"' ]+' docs/README优化-冗余清理与最佳实践.md >/dev/null 2>&1; \
           awk '
             /^[[:space:]]*```/ { inblock = !inblock; next }
             inblock { next }
             { line = $0
               while (match(line, /`[^`]*`/)) { line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH) }
               while (match(line, /!?\[[^]]*\]\([^)]*\)/)) {
                 seg = substr(line, RSTART, RLENGTH)
                 sub(/^!?\[[^]]*\]\(/, "", seg); sub(/\)$/, "", seg)
                 if (seg ~ /^https?:\/\//) print seg
                 line = substr(line, RSTART + RLENGTH)
               }
             }' README.md | sed 's/[[:space:]]*$//' | sort -u)
  if (( net_bad > 0 )); then
    echo "  ❌ $net_bad 条外链不可达"
    fail=1
  else
    echo "  ✅ 外链可达性通过（或无可检外链）"
  fi
fi

echo
if (( fail )); then
  echo ">> 发布前门禁未通过：请按上面 ❌ 逐项修正后再发布（发布不可逆）。"
  exit 1
fi
echo ">> 发布前门禁通过：归档面 ${count} 项、无维护者上下文混入、元数据齐备、发布面链接可达、质量基线全绿。"
echo "   注：本门禁**不含**实际发布动作（需本地 moon login，见 docs/mooncakes-发布方案.md §6-C）。"
