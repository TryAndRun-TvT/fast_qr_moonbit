#!/usr/bin/env bash
# 重新生成 README 顶部示例二维码（docs/assets/qr-example.svg）。
#
# 背景：README 早期用 `moon run cmd/main` 的终端字符画（Unicode 半块 ▄▀█）展示二维码，
#   在按比例字体 / 窄屏下会被 Markdown 渲染器折行挤压而「变形」（扫不出、走样）。
#   改为 **SVG 矢量图**：等宽无关、可无限缩放不失真、体积小（约 2 KB）、可 diff 审计。
#
# 口径（与 lib 输出同源）：
#   - 输入 `https://example.com/`，全部自动（mode 自动、ECL=Q、version 最小、mask 择优）；
#   - 每个暗模块由本库 SVG 同款 `M{x},{y}h1v1h-1` 正方形拼成，仅做**最大矩形合并**压缩
#     （path 语义等价、逐格覆盖相同；不是本库 `SvgBuilder` 的逐格最小化输出）；
#   - 颜色 = 本库默认（背景 #ffffff / 模块 #000000），外加 viewBox/role/aria-label/title
#     可访问性属性（库不产出这些，故托管资产额外补上）。
#
# 依赖：MoonBit 工具链（临时包 cmd/qr-svg-gen，用完即删）+ node（sharp/jsQR 校验，可选）。
# 用法: bash scripts/gen-readme-qr-svg.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$ROOT/docs/assets/qr-example.svg"
TMP="$ROOT/cmd/qr-svg-gen"
CONTENT="https://example.com/"

mkdir -p "$ROOT/docs/assets" "$TMP"
cat > "$TMP/moon.pkg" << 'PKG_EOF'
// 一次性 SVG 资源生成器（README 示例码）：只构建二维码并导出暗格坐标，用完即删。
pkgtype(kind: "executable")

import {
  "tryandrun/fast_qr_moonbit/lib",
}
PKG_EOF
cat > "$TMP/main.mbt" << 'MBT_EOF'
///|
fn main {
  let qr = match @lib.QRBuilder::from_string("https://example.com/").build() {
    Ok(q) => q
    Err(_) => abort("demo content too large")
  }
  let n = qr.size()
  let sb = StringBuilder()
  let mut r = 0
  while r < n {
    let mut c = 0
    while c < n {
      if qr.get(r, c).value() {
        sb.write_string(r.to_string())
        sb.write_string(",")
        sb.write_string(c.to_string())
        sb.write_string(";")
      }
      c += 1
    }
    r += 1
  }
  println("N=" + n.to_string())
  println("DARK=" + sb.to_string())
}
MBT_EOF

RAW="$ROOT/.qr-svg-gen.out"
( cd "$ROOT" && moon run cmd/qr-svg-gen > "$RAW" )
rm -rf "$TMP"

python3 - "$RAW" "$OUT" "$CONTENT" << 'PY_EOF'
import re, sys
raw, out, content = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(raw, encoding='utf-8').read().split('\n')
n = int(next(l for l in text if l.startswith('N='))[2:])
dark = next(l for l in text if l.startswith('DARK='))[5:].strip().rstrip(';')
cells = {tuple(map(int, x.split(','))) for x in dark.split(';') if x}
margin = 4
W = n + 2 * margin
# 每行暗格的连续列段
segs = {}
for r in range(n):
    cols = sorted(c for rr, c in cells if rr == r)
    s = []
    for c in cols:
        if s and c == s[-1][1] + 1:
            s[-1][1] = c
        else:
            s.append([c, c])
    segs[r] = s
# 贪心合并：同一列区间在连续行上纵向合并
used, rects = set(), []
for r in range(n):
    for lo, hi in segs[r]:
        if (r, lo, hi) in used:
            continue
        h, rr = 1, r + 1
        while rr < n and any(a == lo and b == hi for a, b in segs[rr]) and (rr, lo, hi) not in used:
            h += 1
            rr += 1
        for x in range(r, r + h):
            used.add((x, lo, hi))
        rects.append((lo, r, hi - lo + 1, h))
d = ''.join(f"M{x + margin},{y + margin}h{w}v{h}h-{w}z" for x, y, w, h in rects)
# 注意：path 的 d 必须保持**单行**——librsvg（rsvg-convert / sharp 等）会把
# d 属性内的换行当作无效数据并截断路径，导致图形残缺（实测）；标签之间换行无碍。
svg = (
    f'<svg viewBox="0 0 {W} {W}" role="img" aria-label="QR code for {content}" '
    'xmlns="http://www.w3.org/2000/svg">\n'
    f'<title>fast_qr_moonbit 生成的二维码：{content}</title>\n'
    f'<rect width="{W}" height="{W}" fill="#ffffff"/>\n'
    f'<path d="{d}" fill="#000000"/>\n'
    '</svg>\n'
)
open(out, 'w', encoding='utf-8').write(svg)
print(f">>> {out}: {len(svg)} bytes, {len(rects)} rects ({len(cells)} modules), n={n}")
PY_EOF
rm -f "$RAW"
echo ">>> 生成完成。校验建议：用任意 SVG 渲染器（如 rsvg-convert / sharp）光栅化后扫码，"
echo "    应解回 \"$CONTENT\"；同时确认 d 属性为单行（见上方注释）。"
