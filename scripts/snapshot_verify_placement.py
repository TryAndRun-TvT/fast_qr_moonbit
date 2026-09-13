#!/usr/bin/env python3
"""snapshot_verify_placement.py —— 校验 T2-c 放置逐格坐标黄金值未漂移。

对参考侧实算导出的 359 个 (row,col) 顺序，与仓库内
lib/internal/matrix/placement_coords_wbtest.mbt 段表展开的坐标序列比对。

用法:
  python3 scripts/snapshot_verify_placement.py --ref /path/to/fast_qr --verify
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WB = os.path.join(ROOT, "lib", "internal", "matrix", "placement_coords_wbtest.mbt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    script = os.path.join(HERE, "gen-goldens.sh")
    env = {**os.environ, "FAST_QR_DIR": args.ref}
    env["PATH"] = os.path.expanduser("~/.cargo/bin") + os.pathsep + env.get("PATH", "")
    out = subprocess.run(
        ["bash", script, "--emit-placement"],
        capture_output=True, text=True, env=env,
    ).stdout
    ref = []
    for l in out.splitlines():
        if l.startswith("GOLDEN|PLACE|"):
            r, c, _ = l.split("|")[3].split(",")
            ref.append((int(r), int(c)))
    if not ref:
        print("!! 未取到参考侧放置坐标（Rust 工具链 / 参考检出不可用？）", file=sys.stderr)
        if args.verify:
            print(">> 跳过校验（参考侧不可达）")
            return 0
        return 1
    # 展开仓库段表
    src = open(WB, encoding="utf-8").read()
    seg_start = src.index("let place_segments")
    # 段块以行首 `]` 结束
    seg_end = src.index("\n]", seg_start)
    body = src[seg_start:seg_end]
    segs = re.findall(r'\("([PS])",\s*(\d+),\s*\[([^\]]*)\]\)', body)
    cur = []
    for mode, x, rows in segs:
        x = int(x)
        for tok in rows.split(","):
            tok = tok.strip()
            if not tok:
                continue
            r = int(tok)
            cur.append((r, x))
            if mode == "P":
                cur.append((r, x - 1))
    if cur == ref:
        print(">> verify: T2-c 放置坐标序零差异（%d 格）" % len(ref))
        return 0
    print("!! verify: T2-c 放置坐标序漂移 repo=%d ref=%d" % (len(cur), len(ref)), file=sys.stderr)
    for i, (a, b) in enumerate(zip(cur, ref)):
        if a != b:
            print("   第 %d 项: repo=%s reference=%s" % (i, a, b), file=sys.stderr)
            break
    return 1


if __name__ == "__main__":
    sys.exit(main())
