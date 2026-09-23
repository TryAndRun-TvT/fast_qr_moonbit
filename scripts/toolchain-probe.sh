#!/usr/bin/env bash
# toolchain-probe.sh —— 工具链版本与「潜伏告警」探针（只读 / 非阻断）
#
# 目的：把「工具链将来会怎么变红」提前看见——
#   工具链升级后**默认开启**的新告警会直接砸红门禁；而默认**关闭**的告警
#   （如 `0073 unnecessary_annotation` / `0074 missing_doc`）平时完全看不见。
# 本脚本做三件事（全部只读、零网络）：
#   ① 打印 `moon version`，并与 `setup-moonbit.sh` 的期望版本对照（漂移即提示）；
#   ② 用 `moon check --warn-list +a` 暴露**当前全部**告警（含默认关闭）的编号直方图 + 文件 Top；
#   ③ 打印包级依赖图（`moon tree --package`），佐证「零外部依赖」。
#
# 纪律（同 docs-date-check.sh）：「发现告警」**永不**导致非零退出（只提示）；
#   仅当工具链不可用等**工具级错误**才非零退出。
# 依据：docs/01-规格/moonbit-工具链版本与特性适配评估.md §5 / §6-P1。
# 用法: bash scripts/toolchain-probe.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.moon/bin:$PATH"

if ! command -v moon >/dev/null 2>&1; then
  echo "❌ 未找到 moon（export PATH=\"\$HOME/.moon/bin:\$PATH\" 或 bash scripts/setup-moonbit.sh）" >&2
  exit 1
fi

echo "=== 工具链探针（只读 / 非阻断）==="
echo "--- ① 版本 ---"
moon version | head -1 | sed 's/^/    /'
expected="$(grep -oE 'MOON_EXPECTED_VERSION:-[0-9.]+' scripts/setup-moonbit.sh | head -1 | sed 's/.*:-//')"
actual="$(moon version | head -1 | awk '{print $2}')"
if [[ -n "$expected" ]]; then
  if [[ "$actual" == "$expected" ]]; then
    echo "    ✅ 与 setup-moonbit.sh 期望版本一致（$expected）"
  else
    echo "    ⚠️ 与期望版本 $expected 不一致（实际 $actual）—— 处置见 §6-P0" >&2
  fi
fi

echo ""
echo "--- ② 全部告警（含默认关闭；moon check --warn-list +a）---"
tmp="$(mktemp)"
moon check --warn-list +a >"$tmp" 2>&1 || true
python3 - "$tmp" "$ROOT" <<'PY'
import collections, re, sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
root = sys.argv[2].rstrip("/") + "/"
code = None
hist = collections.Counter()
files = collections.defaultdict(collections.Counter)
for ln in lines:
    m = re.search(r"Warning: \[(\d+)\]", ln)
    if m:
        code = m.group(1)
        continue
    fm = re.search(r"╭─\[ (.+?):\d+:\d+ \]", ln)
    if fm and code:
        files[code][fm.group(1).replace(root, "")] += 1
        hist[code] += 1
        code = None
if not hist:
    print("    （无告警）")
else:
    print("    编号    处数   文件 Top")
    for c, n in hist.most_common():
        top = ", ".join(f"{f}×{k}" for f, k in files[c].most_common(3))
        print(f"    {c}   {n:4d}   {top}")
    print(f"    合计 {sum(hist.values())} 处；编号 {', '.join(sorted(hist))}")
PY
rm -f "$tmp"

echo ""
echo "--- ③ 包级依赖图（moon tree --package，前 12 行）---"
moon tree --package 2>&1 | sed -n '1,12p' | sed 's/^/    /'

echo ""
echo ">> 探针完成（仅报告，不影响门禁）。判定与处置见 docs/01-规格/moonbit-工具链版本与特性适配评估.md §6。"
