#!/usr/bin/env bash
# docs-consistency.sh —— 文档一致性门禁（S12 §6.2 D4 / §7.1 / §7.4）
#
# 目的：把「文档与实现的一致性收敛」从**人眼巡检**换成**可执行门禁**。
# 背景（S12 §3.3 实证）：测试用例计数「146 → 147」在两个版本内**二次漂移**，
#   说明「靠人巡检」不可持续；SDD 的答案是 `implement → converge` 机制化。
#
# 四项断言（相互独立，任一红即整链红）：
#   ① 状态字段：docs/**/*.md 每篇头部须含 `> **状态**：`，值域 `现行|历史|已失效`；
#      `历史` 须带 `并入：`（写明结论去哪了）；`现行`/`历史` 不得声明已失效前提为现行口径。
#   ② 计数漂移：仓库内声明为「登记处」的文档值，与**实跑**结果比对，不一致即红。
#      非登记处篇章的数字**不设为门禁**（避免噪音——历史篇里的旧数字是史料，不是漂移）。
#   ②b 版本漂移：README（公开落地页）**不得写死当前版本号**（S12 §3.3 P3 / S11 §9.2）——
#      必须写「已发布（首个版本）」+ 指向版本页；`moon.mod` 的 version 是唯一真值源。
#   ③ 索引覆盖（正向）：docs/** 每篇必须在 `docs/README.md` 中以**相对链接**出现；
#      且须在 §0–§6 **摘要区**按名链接过一次（不能只在 §7/§8 的全量清单里露脸）——
#      否则「入索引」退化成「塞进一张表」，读者在读者路径/议题表里根本找不到它。
#   ③b 索引反查（反向）：索引里指向 docs 的每条相对链接必须**存在**。与 `docs-link-check.sh`
#      互补——后者按**仓库实际文件**遍历，查不到「索引里写了、文件却删了」的游离引用。
#   ③c 无子目录 README：`docs/**` 不得出现第二个名为 `README.md` 的文件（AGENTS.md §四 准入 4
#      「不新建索引的索引」）。现状 `docs/移植参考/` 的域首页是 `fast-qr-索引.md`，保持不动即可。
#   ④ 文档规模：docs/**/*.md 单篇 ≤DOC_LIMIT 行（AGENTS.md §四 已定，此前只管 .mbt，此处补齐）。
#
# 用法: bash scripts/docs-consistency.sh
#   SKIP_SLOW=1  bash scripts/docs-consistency.sh   # 跳过 ②（不跑 moon test）
# 环境变量: DOC_LIMIT（默认 800）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# moon 工具链不在系统 PATH 时，本脚本会「安静地」读错输出（见下 ② 的 Total tests 说明）。
# 这里强制把官方安装位补进 PATH，避免「门禁红、但报错原因指向 moon 缺失」的误诊。
export PATH="$HOME/.moon/bin:$PATH"
DOC_LIMIT="${DOC_LIMIT:-800}"

REGISTRY="docs/S10b-测试覆盖率报告.md"   # ② 测试计数的登记处（S12 §6.2 D4-1）
INDEX="docs/README.md"

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
  # 只认**行首**的 `Total tests:`；不可用 `.*Total` 宽匹配——moon 失败输出的末行
  # 提示语本身含 `Total tests: ...`，宽匹配会把它当计数，反而在「解析失败」时看似通过。
  if grep -qE '^Total tests: [0-9]+' <<<"$out"; then
    actual="$(grep -E '^Total tests: [0-9]+' <<<"$out" | tail -1 | sed -E 's/^Total tests: ([0-9]+),.*$/\1/')"
  else
    actual=""
  fi
  if [[ -z "$actual" ]]; then
    echo "  ❌ 无法从 moon test 取到行首 `Total tests: N`（工具链缺失？输出尾部如下）"
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

# ── ③ 索引覆盖（正向：文件 → 索引）──────────────────────────────────────────
# 判据分两层，均由 python3 解析真实 Markdown 链接（不用 grep，避免子串假绿）：
#   L1 存在性：该文件的**相对链接**在索引里出现过（basename 被 grep 到不算）；
#   L2 摘要区：该链接至少一次出现在 §0–§6（读者路径/议题表），而非只在 §7/§8 全量清单。
#   特例 TOC：状态头里「日期 …… 索引：[…] §N」是**逐篇可达**的分面索引，
#   视同 L1+L2 通过（S12 §7.3 模板要求），否则 40+ 篇都会因「只列在清单里」被判红。
echo
echo "-- ③ 索引覆盖（正向：文件 → 索引；含摘要区按名链接）"
cover_out="$(python3 - "$INDEX" "$DOC_LIMIT" <<'PYEOF'
import os, re, subprocess, sys
index, _ = sys.argv[1], sys.argv[2]
files = subprocess.run(["git","ls-files","-z","docs/*.md"],capture_output=True).stdout.decode().split("\0")
files = [f for f in files if f]
text = open(index, encoding="utf-8").read()
lines = text.split("\n")
# 摘要区 = 第一个 H2(§7) 之前 + §8 之后（§8 是「按文件名检索」清单，不作摘要）
b7 = next((i for i,l in enumerate(lines,1) if l.startswith("## 7.")), 10**9)
b8 = next((i for i,l in enumerate(lines,1) if l.startswith("## 8.")), 10**9)

def targets(line):
    for l in re.findall(r'\]\(([^)]+)\)', line):
        if l.startswith(("http://","https://","#")): continue
        t = l.split("#")[0]
        if not t: continue
        yield os.path.relpath(os.path.normpath(os.path.join("docs", t)), "docs")

def links_of(f):
    """返回 (行号, 行内容) 列表；判据 = 归一化后的仓库相对路径精确相等。

    不可用 basename 比较：`docs/移植参考/**` 12 篇的 basename 在索引里出现，
    但链接写的是 `./移植参考/...`（**带子目录**），basename 比较会误判为「已入索引」。
    """
    rel = os.path.relpath(f, "docs"); hits = []
    for i, line in enumerate(lines, 1):
        if rel in set(targets(line)): hits.append((i, line))
    return hits

fails = []
for f in files:
    base = os.path.basename(f)
    if os.path.relpath(f, "docs") == "README.md": continue   # 索引自身
    hits = links_of(f)
    if not hits:
        fails.append(("L1", f, "索引中无指向本文件的相对链接（basename 命中不算）"))
        continue
    in_mid = any(b7 < i < b8 or i < b7 for i, _ in hits)   # §0–§6 或 §8 之后
    if not in_mid:
        toc = re.search(r"索引：\[[^\]]*\]\([^)]+\)\s*(§[0-9.]+)?", text[:0] or "")
        status_line = ""
        try:
            for line in open(f, encoding="utf-8"):
                if line.startswith("> **状态**："): status_line = line; break
        except OSError:
            pass
        if "§" not in status_line:
            fails.append(("L2", f, "只在 §7/§8 清单中出现，未在 §0–§6 摘要区按名链接（且状态头无 `索引：… §N`）"))
for kind, f, why in fails:
    print("  ❌ %s [%s]：%s" % (f, kind, why))
print("  COUNT=%d" % len(fails))
PYEOF
)"
echo "$cover_out" | grep -v '^  COUNT=' || true
if grep -q '^  COUNT=0$' <<<"$cover_out"; then
  echo "  ✅ ${#FILES[@]} 篇均已被索引收录（含摘要区按名链接）"
else
  fail=1
fi

# ── ③b 索引反查（反向：索引 → 文件）────────────────────────────────────────
# docs-link-check.sh 遍历「仓库实际文件」，故查不到「索引里写了、文件已删」的游离引用；
# 本项把索引里的每条 docs 相对链接回查文件系统，补齐该方向。
echo
echo "-- ③b 索引反查（反向：索引 → 文件存在性）"
rev_out="$(python3 - "$INDEX" <<'PYEOF'
import os, re, sys
index = sys.argv[1]
text = open(index, encoding="utf-8").read()
bad = []
for i, line in enumerate(text.split("\n"), 1):
    for l in re.findall(r'\]\(([^)]+)\)', line):
        if l.startswith(("http://","https://","#")): continue
        t = l.split("#")[0]
        if not t: continue
        tgt = os.path.normpath(os.path.join("docs", t))
        if os.path.isfile(tgt): continue
        if os.path.isdir(os.path.normpath(os.path.join("docs", t.rstrip("/")))): continue
        bad.append((i, l))
for i, l in bad:
    print("  ❌ %s:%d：指向不存在的目标 `%s`" % (index, i, l))
print("  COUNT=%d" % len(bad))
PYEOF
)"
echo "$rev_out" | grep -v '^  COUNT=' || true
if grep -q '^  COUNT=0$' <<<"$rev_out"; then echo "  ✅ 索引内所有相对链接均可达"; else fail=1; fi

# ── ③c 无子目录 README（不新建「索引的索引」）──────────────────────────────
echo
echo "-- ③c 无子目录 README（AGENTS.md §四 准入 4）"
submd="$(git ls-files docs | grep -E '\.md$' | grep -E '(^|/)README\.md$' | grep -vx 'docs/README\.md' || true)"
if [[ -n "$submd" ]]; then
  printf '  ❌ 发现子目录 README（「索引的索引」）：\n'
  sed 's/^/       /' <<<"$submd"
  echo "     处置：域首页请用「域-索引.md」命名（如 docs/移植参考/fast-qr-索引.md）。"
  fail=1
else
  echo "  ✅ docs/** 除索引自身外无 README.md"
fi

# ── ④ 文档规模 ──────────────────────────────────────────────────────────────
# 注意：这里曾把 $DOC_LIMIT 当「输出文件」传给 python（见 git 历史），导致
# 「文档超限」被判成「文件消失」。判据只保留一件事：行数 ≤ DOC_LIMIT。
echo
echo "-- ④ 文档规模（单篇 ≤${DOC_LIMIT} 行）"
size_fail=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    printf '  ❌ %s：git 已登记但工作区缺失（需 `git checkout` 或 `git rm --cached`）\n' "$f"
    size_fail=1; continue
  fi
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

# ── ⑤ 日期漂移提示（非阻断，S12 §14 E2）────────────────────────────────────
# 与 ①②③ 不同：日期判据依赖 git 时间（受 rebase / 横切提交影响），故**只提示不阻断**。
# 具体口径与噪音抑制见 scripts/docs-date-check.sh 头部注释。
echo
echo "-- ⑤ 状态头日期漂移提示（仅警告，不阻断）"
bash "$ROOT/scripts/docs-date-check.sh" 2>&1 | sed '1d' | sed 's/^  /  /'

echo
if (( fail )); then
  echo ">> 文档一致性门禁未通过（S12 §7.1/§7.4）。"
  exit 1
fi
echo ">> 文档一致性门禁通过。"
