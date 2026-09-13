#!/usr/bin/env python3
"""snapshot_gen_tables.py —— 常量表「全表值指纹」生成器（开发期工具，不参与 push CI）。

S10 §6 T1-f：数值型常量表在「非抽查点」无保护（附录 E M11/M12 实测漏检）。
本脚本把参考侧 fast_qr 的**全表**（而非抽查点）导出为规范化指纹，供
lib/internal/constants/constants_wbtest.mbt 逐行断言，从而让「中间项被改一个值」
也能被测出（修复 T1-f 目标）。

来源（铁律 1：参考值禁止手抄，一律由脚本在参考侧产出）：
  - fast_qr commit 53e8c99（Cargo.toml version 0.14.0）
  - src/version.rs      → Version::get 分段 → 容量表 capacity[mode][ecl][version]
                           （取每段上界，即 3×4×40 的最大字符数）
  - src/hardcode.rs     → data_codewords / ecm_to_format_information /
                           ecc_to_groups / PERCENT_SCORE

用法:
  python3 scripts/snapshot_gen_tables.py --ref /path/to/fast_qr
  python3 scripts/snapshot_gen_tables.py --ref /path/to/fast_qr --verify
      --verify：与仓库内 lib/internal/constants/constants_wbtest.mbt 的指纹块比对，
                零差异退出 0；有差异打印 diff 并退出 1。
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WB = os.path.join(ROOT, "lib", "internal", "constants", "constants_wbtest.mbt")

MODES = ["Numeric", "Alphanumeric", "Byte"]
ECLS = ["L", "M", "Q", "H"]


def _read(ref, *parts):
    p = os.path.join(ref, *parts)
    with open(p, encoding="utf-8") as f:
        return f.read()


def parse_capacity(src):
    """解析 Version::get 的 match 分段，返回 [[[int]*40]*4]*3。

    顶层 match mode { Mode::X => match ecl { ECL::Y => match len { a..=b => Some(Vnn), ... } } }
    """
    # 截取 get 函数体
    body = src[src.index("pub(crate) const fn get("):]
    # 三段式：Mode::X => match ecl { ... } —— 用顺序扫描配对括号
    table = []
    for mode in MODES:
        m = re.search(r"Mode::" + mode + r"\s*=>\s*match ecl \{", body)
        if not m:
            raise SystemExit(f"未找到 Mode::{mode} 分段")
        seg = extract_braced(body, m.end() - 1)
        per_ecl = []
        for ecl in ECLS:
            e = re.search(r"ECL::" + ecl + r"\s*=>\s*match len \{", seg)
            if not e:
                raise SystemExit(f"未找到 {mode}-{ecl} 分段")
            lens = extract_braced(seg, e.end() - 1)
            # 分段按出现顺序；取每段上界 => 该版本容量
            ups = []
            for _lo, hi, _v in re.findall(r"(\d+)\.\.=(\d+)\s*=>\s*Some\(V(\d+)\)", lens):
                ups.append(int(hi))  # 容量 = 段上界
            if len(ups) != 40:
                raise SystemExit(f"{mode}-{ecl} 段数 {len(ups)} != 40")
            per_ecl.append(list(ups))
        table.append(per_ecl)
    return table


def extract_braced(s, open_idx):
    """s[open_idx] == '{'，返回配对花括号内的内容。"""
    assert s[open_idx] == "{", s[open_idx - 20:open_idx + 5]
    depth = 0
    for i in range(open_idx, len(s)):
        if s[i] == "{":
            depth += 1
        elif s[i] == "}":
            depth -= 1
            if depth == 0:
                return s[open_idx + 1:i]
    raise SystemExit("花括号不配对")


def parse_data_codewords(src):
    """解析 hardcode.rs data_codewords 的 const L/M/Q/H: [u16; 40]。"""
    body = src[src.index("pub const fn data_codewords("):]
    out = []
    for ecl in ECLS:
        m = re.search(r"const " + ecl + r": \[u16; 40\] = \[(.*?)\];", body, re.S)
        if not m:
            raise SystemExit(f"未找到 data_codewords const {ecl}")
        nums = [int(x) for x in re.findall(r"\d+", m.group(1))]
        if len(nums) != 40:
            raise SystemExit(f"data_codewords {ecl} 长度 {len(nums)}")
        out.append(nums)
    return out


def parse_format_information(src):
    """解析 ecm_to_format_information 的 L/M/Q/H 常量（二进制字面量）。"""
    body = src[src.index("pub const fn ecm_to_format_information("):]
    out = []
    for ecl in ECLS:
        m = re.search(r"const " + ecl + r": \[u16; 8\] = \[(.*?)\];", body, re.S)
        if not m:
            raise SystemExit(f"未找到 format const {ecl}")
        vals = []
        for tok in re.findall(r"0b[01_]+|\d+", m.group(1)):
            vals.append(int(tok.replace("_", ""), 2) if tok.startswith("0b") else int(tok))
        if len(vals) != 8:
            raise SystemExit(f"format {ecl} 长度 {len(vals)}")
        out.append(vals)
    return out


def parse_ecc_to_groups(src):
    """解析 ecc_to_groups 的 (g1c<<24 | g1s<<16 | g2c<<8 | g2s)。"""
    body = src[src.index("pub const fn ecc_to_groups("):]
    out = []
    for ecl in ECLS:
        m = re.search(r"const " + ecl + r": \[u32; 40\] = \[(.*?)\];", body, re.S)
        if not m:
            raise SystemExit(f"未找到 ecc_to_groups const {ecl}")
        rows = []
        for line in m.group(1).splitlines():
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            g1c = int(re.search(r"\((\d+)\s*<<\s*24\)", line).group(1))
            g1s = int(re.search(r"\((\d+)\s*<<\s*16\)", line).group(1))
            m2 = re.search(r"\((\d+)\s*<<\s*8\)", line)
            g2c = int(m2.group(1)) if m2 else 0
            m3 = re.search(r"\|\s*(\d+)\s*,", line)
            g2s = int(m3.group(1)) if m3 else 0
            rows.append((g1c, g1s, g2c, g2s))
        if len(rows) != 40:
            raise SystemExit(f"ecc_to_groups {ecl} 行数 {len(rows)}")
        out.append(rows)
    return out


def parse_percent_score(src):
    m = re.search(r"pub const PERCENT_SCORE: \[u8; 100\] = \[(.*?)\];", src, re.S)
    if not m:
        raise SystemExit("未找到 PERCENT_SCORE")
    vals = [int(x) for x in re.findall(r"\d+", m.group(1))]
    if len(vals) != 100:
        raise SystemExit(f"PERCENT_SCORE 长度 {len(vals)}")
    return vals


def fmt_rows(rows, per_line=12):
    lines = []
    for r in rows:
        lines.append("      " + ", ".join(str(x) for x in r) + ",")
    return "\n".join(lines)


def render(ref):
    version = _read(ref, "src", "version.rs")
    hardcode = _read(ref, "src", "hardcode.rs")
    cap = parse_capacity(version)
    dcw = parse_data_codewords(hardcode)
    fmt = parse_format_information(hardcode)
    ecc = parse_ecc_to_groups(hardcode)
    pct = parse_percent_score(hardcode)

    out = []
    out.append("/// BEGIN GENERATED: snapshot_gen_tables.py")
    out.append("/// 来源 fast_qr commit 53e8c99 (v0.14.0)；禁止手改，重跑 --verify 核对。")
    # 容量表：3×4×40，按行输出（每行 = 一个 (mode,ecl) 的 40 项）
    out.append("/// capacity_table[mode][ecl][version] 全表（3×4×40，逐行 40 项）")
    cap_flat = []
    for m in range(3):
        for e in range(4):
            cap_flat.append(cap[m][e])
    out.append("let exp_capacity_rows : Array[Array[Int]] = [")
    for r in cap_flat:
        out.append("  [" + ", ".join(str(x) for x in r) + "],")
    out.append("]")
    # data_codewords：4×40
    out.append("")
    out.append("/// data_codewords_table[ecl][version] 全表（4×40）")
    out.append("let exp_data_codewords_rows : Array[Array[Int]] = [")
    for r in dcw:
        out.append("  [" + ", ".join(str(x) for x in r) + "],")
    out.append("]")
    # format：4×8
    out.append("")
    out.append("/// format_information_table[ecl][mask] 全表（4×8）")
    out.append("let exp_format_rows : Array[Array[Int]] = [")
    for r in fmt:
        out.append("  [" + ", ".join(str(x) for x in r) + "],")
    out.append("]")
    # ecc_to_groups：4×40 四元组
    out.append("")
    out.append("/// ecc_to_groups_table[ecl][version] 全表（4×40 四元组）")
    out.append("let exp_ecc_groups_rows : Array[Array[(Int, Int, Int, Int)]] = [")
    for r in ecc:
        out.append("  [" + ", ".join(f"({a}, {b}, {c}, {d})" for a, b, c, d in r) + "],")
    out.append("]")
    # percent_score：100
    out.append("")
    out.append("/// percent_score_table[percent] 全表（100）")
    out.append("let exp_percent_score : Array[Int] = [")
    for i in range(0, 100, 20):
        out.append("  " + ", ".join(str(x) for x in pct[i:i + 20]) + ",")
    out.append("]")
    out.append("/// END GENERATED")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True, help="fast_qr 检出根目录（含 src/）")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    if not os.path.isdir(os.path.join(args.ref, "src")):
        raise SystemExit(f"--ref 不是 fast_qr 检出：{args.ref}")
    gen = render(args.ref)
    if args.verify:
        with open(WB, encoding="utf-8") as f:
            cur = f.read()
        m = re.search(r"/// BEGIN GENERATED: snapshot_gen_tables\.py\n(.*?)/// END GENERATED", cur, re.S)
        if not m:
            print("!! 仓库 wbtest 缺少 GENERATED 指纹块", file=sys.stderr)
            return 1
        cur_block = "/// BEGIN GENERATED: snapshot_gen_tables.py\n" + m.group(1) + "/// END GENERATED\n"
        if cur_block == gen:
            print(">> verify: 全表指纹零差异")
            return 0
        import difflib
        print("!! verify: 指纹漂移", file=sys.stderr)
        for line in difflib.unified_diff(cur_block.splitlines(), gen.splitlines(),
                                         "repo", "reference", lineterm=""):
            print(line, file=sys.stderr)
        return 1
    sys.stdout.write(gen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
