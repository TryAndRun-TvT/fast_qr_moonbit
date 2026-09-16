#!/usr/bin/env bash
# docs-ref-check.sh —— 章节引用门禁（S12 §14 E1）
#
# 目的：`docs-link-check.sh` 只校验**文件级**链接可达，抓不到「篇章内部章节引用」
#   这类漂移。实证（S12 §13.4）：`S12 §3.3` 曾引用 **`S11 §9.1` / `S11 §9.2`**，
#   而 S11 的 §9 **没有子节**——整链门禁当时全绿，人工复核才发现。
#
# 判据：文中形如 `S<N>[a-z] §M[.K...]` 的引用，必须在被引篇目内**存在该编号的标题**。
#   编号来源 = 被引篇目内形如 `## M` / `### M.K` 的标题前缀（两/三级标题并存都认）。
#
# 识别范围（保守，宁漏勿误）：
#   - 只认被引篇目在 `docs/` 里**存在**的 `S<N>[a-z]` 代号（映射见 maps）引用；
#     无法映射到具体文件的（如 `S9x` 泛指一族）**跳过**，不制造假红；
#   - 标题编号须以「数字开头 + 非数字结尾边界」匹配，避免 `§3` 匹配到 `§30`。
#
# 用法: bash scripts/docs-ref-check.sh
# 退出码: 0 = 无漂移；1 = 存在失效章节引用
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== 章节引用门禁（S12 §14 E1）==="
python3 - <<'PYEOF'
import os, re, subprocess, sys

SCAN_EXTRA = ["README.md", "AGENTS.md"]
files = [f.decode() for f in subprocess.run(
    ["git", "ls-files", "-z", "docs/*.md"], capture_output=True).stdout.split(b"\0") if f]
for extra in SCAN_EXTRA:
    if os.path.isfile(extra):
        files.append(extra)

# 代号 → 文件：docs/ 内以 `S<N>[a-z]` 开头（可带 `-` 后缀）的 md
code2file = {}
for f in files:
    b = os.path.basename(f)
    m = re.match(r"^(S\d+[a-z]?)[-.]", b)
    if m:
        code2file.setdefault(m.group(1), []).append(f)

def headings(path):
    """返回该文件内所有标题编号集合（'3'、'3.2' 都收）。"""
    hs = set()
    for line in open(path, encoding="utf-8"):
        # 标题形如 `## 3. xxx` / `### 3.2 xxx`：取标题起始的编号（数字段 + 可选 `.数字` 段），
        # 编号后允许 `.`、空格、`、`等分隔符；用 (?![\d]) 防止 `3` 误配 `30`。
        m = re.match(r"^#{1,6}\s+(\d+(?:\.\d+)*)\.?(?![\d])", line.strip())
        if m:
            hs.add(m.group(1))
    return hs

cache = {}
def heads_of(path):
    if path not in cache:
        cache[path] = headings(path)
    return cache[path]

REF_RE = re.compile(r"\b(S\d+[a-z]?)\s*[§#]\s*(\d+(?:\.\d+)*)(?![\d])")

def strip_code_spans(line):
    """去掉行内 code span（反引号对）内容。

    反引号里的 `S11 §9.1` 是**对「失效引用」的引述**（如 S12 §13.4 记录曾修过的死引用），
    不是活引用；不剥离会制造假红。剥离后再匹配，才对应「读者能点/能跳」的引用。
    """
    return re.sub(r"`[^`]*`", "", line)

bad, scanned, skipped = [], 0, 0
for f in files:
    for lineno, line in enumerate(open(f, encoding="utf-8"), 1):
        for code, sec in REF_RE.findall(strip_code_spans(line)):
            targets = code2file.get(code)
            if not targets:
                skipped += 1
                continue
            scanned += 1
            if not any(sec in heads_of(t) for t in targets):
                bad.append((f, lineno, code, sec, targets))

for f, lineno, code, sec, targets in bad:
    print("  ❌ %s:%d：引用 `%s §%s`，但 %s 内无该编号标题" % (
        f, lineno, code, sec, "/".join(targets)))
print("  COUNT=%d" % len(bad))
print("  实扫 %d 处可映射引用；%d 处泛指代号已跳过" % (scanned, skipped))
sys.exit(1 if bad else 0)
PYEOF
