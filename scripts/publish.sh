#!/usr/bin/env bash
# publish.sh —— mooncakes 发布脚本（**默认干跑**，显式 `--publish` 才真发）
#
# 目的：把 docs/03-过程/mooncakes-发布方案.md §6-C 的发布动作从「记在文档里的一串命令」变成
#   **一条可复跑、带前置门禁、默认不可逆动作需显式确认**的脚本。
#   （`.cnb.yml` 不含任何发布动作：凭据属本地私有，AGENTS.md §一 禁止入库/进 CI。）
#
# 流程：① 环境自检（moon / 登录凭据 / 模块名与版本）
#      ② 发布前门禁 `publish-check.sh`（归档面 + 内容白/黑名单 + 元数据 + 质量基线）
#      ③ 归档清单 `moon package --list`
#      ④ 干跑 `moon publish --dry-run`（默认到此为止）
#      ⑤ 真实发布 `moon publish`（**仅 `--publish`**；不可逆，需确认）
#
# 用法:
#   bash scripts/publish.sh                 # ①~④：安全，可反复跑
#   bash scripts/publish.sh --dry-run        # 同上（显式写法）
#   bash scripts/publish.sh --publish        # ①~⑤：交互式确认（输入模块全名）
#   CONFIRM_NAME=TryAndRun-TvT/fast_qr_moonbit bash scripts/publish.sh --publish --yes
#                                            # 非交互确认（CI/脚本化用；名字必须对得上）
#
# 已知 CLI 行为：moon 0.1.20260904 的 `moon publish --dry-run` 即使服务端返回
#   `202 Accepted / Dry run completed successfully`，进程仍以 **exit 255** 退出。
#   故本脚本**不按退出码**判干跑成败，而是匹配输出文本（见 ④）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

MODE="dry-run"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --publish|--real|--go) MODE="publish" ;;
    --dry-run)             MODE="dry-run" ;;
    -y|--yes)              ASSUME_YES=1 ;;
    -h|--help)             sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "!! 未知参数: $arg（支持 --dry-run / --publish / --yes）" >&2; exit 2 ;;
  esac
done

name_val="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' moon.mod | head -1)"
ver_val="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' moon.mod | head -1)"
echo "=== mooncakes 发布脚本 publish.sh（模式: $MODE）==="
echo "    模块: ${name_val:-<解析失败>}　版本: ${ver_val:-<解析失败>}"
echo

# ---- ① 环境自检 -------------------------------------------------------------
echo "--- ① 环境自检 ---"
if ! command -v moon >/dev/null 2>&1; then
  echo "❌ 未找到 moon（export PATH=\"\$HOME/.moon/bin:\$PATH\" 或 bash scripts/setup-moonbit.sh）" >&2
  exit 1
fi
echo "  ✅ moon: $(moon version | head -1)"
if [[ -f "$HOME/.moon/credentials.json" ]]; then
  echo "  ✅ 登录凭据存在: ~/.moon/credentials.json（本地私有，勿入库）"
else
  echo "  ❌ 未登录：缺少 ~/.moon/credentials.json" >&2
  echo "     处置：moon login（或首次 moon register）；凭据不入库、不进 CI（AGENTS.md §一）。" >&2
  exit 1
fi
if [[ -z "$name_val" || "$name_val" != */* ]]; then
  echo "  ❌ moon.mod 的 name 未形如 <user>/<module>：$name_val" >&2
  exit 1
fi
echo "  ✅ name 形如 <user>/<module>"

# ---- ② 发布前门禁 -----------------------------------------------------------
echo "--- ② 发布前门禁 publish-check ---"
if bash scripts/publish-check.sh; then
  echo "  ✅ 门禁通过"
else
  echo "  ❌ 门禁未通过：发布中止（发布不可逆，见 docs/03-过程/mooncakes-发布方案.md §5.4）" >&2
  exit 1
fi

# ---- ③ 归档清单 -------------------------------------------------------------
echo "--- ③ 归档清单 moon package --list ---"
moon package --list | sed 's/^/     /'
echo "  （产物: _build/publish/${name_val//\//-}-${ver_val}.zip）"

# ---- ④ 干跑 ----------------------------------------------------------------
echo "--- ④ 干跑 moon publish --dry-run ---"
dry_log="$(mktemp)"
set +e
moon publish --dry-run >"$dry_log" 2>&1
dry_code=$?
set -e
sed 's/^/     /' "$dry_log"
# 判据：看服务端回执文本，不看退出码（exit 255 属该版本 CLI 已知行为）
if grep -q "Dry run completed successfully" "$dry_log" || grep -q "202 Accepted" "$dry_log"; then
  echo "  ✅ 干跑通过（Server status: 202 Accepted；退出码 $dry_code 属已知 CLI 行为，忽略）"
else
  echo "  ❌ 干跑未通过（退出码 $dry_code）：未见到 'Dry run completed successfully'" >&2
  rm -f "$dry_log"
  exit 1
fi
rm -f "$dry_log"

if [[ "$MODE" == "dry-run" ]]; then
  echo
  echo ">> 干跑流程结束（默认模式）。真实发布请显式执行："
  echo "     bash scripts/publish.sh --publish"
  exit 0
fi

# ---- ⑤ 真实发布（不可逆）----------------------------------------------------
echo "--- ⑤ 真实发布 moon publish（不可逆）---"
echo "    即将发布: ${name_val}@${ver_val} 至 mooncakes.io"
echo "    官方无「按版本撤回」（moon deprecate 仅整模块弃用）⇒ 单版本一旦发布不可撤回。"
if (( ASSUME_YES )); then
  if [[ "${CONFIRM_NAME:-}" != "$name_val" ]]; then
    echo "  ❌ 非交互确认失败：CONFIRM_NAME 与 moon.mod 的 name 不一致" >&2
    echo "     期望: CONFIRM_NAME=$name_val（当前: ${CONFIRM_NAME:-<未设置>}）" >&2
    exit 1
  fi
  echo "  ✅ 非交互确认通过（CONFIRM_NAME=$name_val）"
else
  printf '    请输入模块全名以确认（%s）: ' "$name_val"
  read -r answer
  if [[ "$answer" != "$name_val" ]]; then
    echo "  ❌ 输入不匹配，发布中止（期望: $name_val）" >&2
    exit 1
  fi
  echo "  ✅ 交互确认通过"
fi

set +e
moon publish
pub_code=$?
set -e
if (( pub_code == 0 )); then
  echo
  echo ">> 发布成功 ✅ —— https://mooncakes.io/docs/${name_val}"
  echo "   后续：C4 核验页面渲染；C5 干净环境 moon add ${name_val} 验证（docs/03-过程/mooncakes-发布方案.md §6-C）。"
else
  echo "!! 发布命令返回非 0（exit $pub_code）：请阅读上方输出定位原因" >&2
  echo "   常见：版本已存在（SemVer 不可重发）/ 网络 / 权限。" >&2
  exit "$pub_code"
fi
