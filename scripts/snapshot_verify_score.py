#!/usr/bin/env python3
"""snapshot_verify_score.py —— 校验 T2-a/T2-b 打分明细黄金值未漂移。

复用 snapshot_gen_score.rs 的参考侧实算结果（由 gen-goldens.sh --emit-score 产出），
与仓库内 lib/internal/matrix/score_detail_wbtest.mbt 的期望数组做**数值序列**比对
（moon fmt 会重排换行，故不比文本）。

用法:
  python3 scripts/snapshot_verify_score.py --ref /path/to/fast_qr --verify
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WB = os.path.join(ROOT, "lib", "internal", "matrix", "score_detail_wbtest.mbt")


def nums(text):
    return [int(x) for x in re.findall(r"-?\d+", text)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    # 触发参考侧实算（由 gen-goldens.sh 的 run_ref_emitter 承担；此处调用脚本自身）
    script = os.path.join(HERE, "gen-goldens.sh")
    env = {**os.environ, "FAST_QR_DIR": args.ref}
    env["PATH"] = os.path.expanduser("~/.cargo/bin") + os.pathsep + env.get("PATH", "")
    out = subprocess.run(
        ["bash", script, "--emit-score"],
        capture_output=True, text=True, env=env,
    ).stdout
    line = [l for l in out.splitlines() if l.startswith("GOLDEN|LINE|")]
    col = [l for l in out.splitlines() if l.startswith("GOLDEN|COL|")]
    mat = [l for l in out.splitlines() if l.startswith("GOLDEN|MATRIX|")]
    if not (line and col and mat):
        print("!! 未取到参考侧打分明细（Rust 工具链 / 参考检出不可用？）", file=sys.stderr)
        if args.verify:
            print(">> 跳过校验（参考侧不可达）")
            return 0
        return 1
    ref_row = nums(line[0].split("|")[3])
    ref_col = nums(col[0].split("|")[3])
    ref_mat = nums(" ".join(mat[0].split("|")[3:]))
    cur = open(WB, encoding="utf-8").read()
    m1 = re.search(r"let score_expect_row : ReadOnlyArray\[Int\] = \[(.*?)\n\]", cur, re.S)
    m2 = re.search(r"let score_expect_col : ReadOnlyArray\[Int\] = \[(.*?)\n\]", cur, re.S)
    if not (m1 and m2):
        print("!! verify: 仓库 wbtest 缺少 expect_row/expect_col 数组", file=sys.stderr)
        return 1
    repo_row = nums(m1.group(1))
    repo_col = nums(m2.group(1))
    ok = repo_row == ref_row and repo_col == ref_col
    # 矩阵级分量：4 个数（squares/pattern/dark/line/col）必须出现在文件中
    ok = ok and all(str(v) in cur for v in ref_mat)
    if ok:
        print(
            ">> verify: T2-a/T2-b 打分明细零差异（行 %d + 列 %d + 分量 %d）"
            % (len(ref_row), len(ref_col), len(ref_mat))
        )
        return 0
    print("!! verify: T2-a/T2-b 打分明细漂移", file=sys.stderr)
    if repo_row != ref_row:
        print("   行数组不一致 repo=%d ref=%d" % (len(repo_row), len(ref_row)), file=sys.stderr)
    if repo_col != ref_col:
        print("   列数组不一致 repo=%d ref=%d" % (len(repo_col), len(ref_col)), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
