#!/usr/bin/env python3
"""snapshot_gen_default.py —— T0-c 独立数字真值抽取器（开发期工具，不参与 push CI）。

从参考 fast_qr v0.14.0 `src/tests/default.rs` 抽取 V1/V3/V7 三个矩阵：
  - bool 真值矩阵（`MAT_FAST_QR_COM*_BOOL`）——源自 **Python `qrcode`** 库产物（独立真值）；
  - 带类型矩阵（`mat_fast_qr_com_*`）——参考据此断言的期望（`FIND(T)`/`DATA(F)`/… 编码）。
输出 MoonBit 可直接内联的 hex 串（每格 1 字节 = 明暗 | 类型<<1）。

来源钉版：fast_qr commit 53e8c99（Cargo.toml version 0.14.0）。
用法:
  python3 scripts/snapshot_gen_default.py --ref /path/to/fast_qr > lib/.../s10c_body.mbt
  python3 scripts/snapshot_gen_default.py --ref /path/to/fast_qr --verify
"""
import argparse
import os
import re
import sys

TYPE = {"DARK": 6, "DATA": 0, "ALIG": 2, "FORM": 4, "VERS": 5, "TIMG": 3, "FIND": 1, "EMPT": 7}
CASES = [
    ("v1", "MAT_FAST_QR_COM_V1_BOOL", "mat_fast_qr_com_v1", 0),
    ("v3", "MAT_FAST_QR_COM_BOOL", "mat_fast_qr_com_v3", 2),
    ("v7", "MAT_FAST_QR_COM_V7_BOOL", "mat_fast_qr_com_v7", 6),
]
WB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                  "lib", "internal", "matrix", "s10c_independent_truth_wbtest.mbt")


def parse_bool(src, name):
    m = re.search(re.escape(name) + r": \[\[bool; (\d+)\]; \d+\] = \[(.*?)\n    \];", src, re.S)
    n = int(m.group(1))
    rows = re.findall(r"\[([^\]]+)\]", m.group(2))
    return n, [bytes(1 if c.strip() == "true" else 0 for c in r.split(",") if c.strip())
               for r in rows]


def parse_typed(src, name):
    m = re.search(re.escape(name) + r": \[\[Module; (\d+)\]; \d+\] = \[(.*?)\n    \];", src, re.S)
    n = int(m.group(1))
    rows = re.findall(r"\[([^\]]+)\]", m.group(2))
    out = []
    for r in rows:
        cells = [c.strip() for c in r.split(",") if c.strip()]
        out.append(bytes((TYPE[re.match(r"(\w+)\(", c).group(1)] << 1) | (1 if "(T)" in c else 0)
                         for c in cells))
    return n, out


def render(src):
    data = {}
    for label, bn, tn, ver in CASES:
        n, bo = parse_bool(src, bn)
        n2, ty = parse_typed(src, tn)
        assert n == n2, f"{label}: size mismatch {n} vs {n2}"
        data[label] = (n, bo, ty)
    head = '''///|
/// s10c_independent_truth_test.mbt —— T0-c 独立数字真值（S10 §6 T0-c / 缺口 G13）
///
/// 本仓库测试体系里**唯一非自证**的真值来源：参考 fast_qr v0.14.0 `src/tests/default.rs`
/// 的 V1/V3/V7 矩阵源自 **Python `qrcode` 库**产物，与 fast_qr 自身实现、与本项目实现
/// 均**无同源关系**。它锁的是「功能图案的类型号布局 + 明暗」是否符合外部第三方实现。
///
/// 期望值由 `bash scripts/gen-goldens.sh --emit-default`（内部 snapshot_gen_default.py）
/// 从参考 default.rs 抽取，禁止手抄；以 hex 串内联（每格 1 字节 = 明暗|类型<<1）。
///
/// 断言方式与参考 `from_bool_v*` 同构：`create_matrix(version)` 布好功能图案类型后，
/// 逐格置入独立 bool 真值的明暗，再与参考**带类型**的期望矩阵逐格比对。
/// 说明：internal 不可从黑盒 _test.mbt 触达，故本文件为白盒 *_wbtest.mbt。
/// BEGIN GENERATED (snapshot_gen_default.py)
/// END GENERATED
'''
    body = []
    body.append('''///|
/// bool 真值（'0'/'1' 连续串，行主序）→ 带类型矩阵（白盒直触 create_matrix/set_value）。
fn build_from_bool_truth(ver_idx : Int, n : Int, bits : String) -> Array[Int] {
  let m = create_matrix(ver_idx)
  let chars = bits.to_array()
  let mut i = 0
  while i < n * n {
    m[i] = set_value(m[i], if chars[i] == '1' { 1 } else { 0 })
    i += 1
  }
  m
}

///|
/// hex 串 → Array[Int]（每字节两位）。
fn hex_ints(s : String) -> Array[Int] {
  let out : Array[Int] = []
  let chars = s.to_array()
  let mut i = 0
  while i + 1 < chars.length() {
    out.push(hex_digit(chars[i]) * 16 + hex_digit(chars[i + 1]))
    i += 2
  }
  out
}

///|
/// 单字符 hex → 0..15。
fn hex_digit(c : Char) -> Int {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 97 && n <= 102 {
    n - 87
  } else {
    n - 55
  }
}

///|
test "t0c_independent_truth_default" {''')
    for label, bn, tn, ver in CASES:
        n, bo, ty = data[label]
        boolhex = "".join("1" if r[j] else "0" for r in bo for j in range(n))
        tyhex = "".join(f"{b:02x}" for r in ty for b in r)
        body.append(f'''  // --- {label.upper()}（{n}×{n}）---
  let got_{label} = build_from_bool_truth({ver}, {n}, "{boolhex}")
  let want_{label} = hex_ints("{tyhex}")
  let mut i_{label} = 0
  while i_{label} < want_{label}.length() {{
    if got_{label}[i_{label}] != want_{label}[i_{label}] {{
      fail(
        "{label}: cell (" +
        (i_{label} / {n}).to_string() +
        "," +
        (i_{label} % {n}).to_string() +
        ") got=" +
        got_{label}[i_{label}].to_string() +
        " want=" +
        want_{label}[i_{label}].to_string(),
      )
    }}
    i_{label} += 1
  }}''')
    body.append("}")
    return head + "\n" + "\n".join(body) + "\n", data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    src = open(os.path.join(args.ref, "src", "tests", "default.rs"), encoding="utf-8").read()
    gen, _ = render(src)
    if args.verify:
        cur = open(WB, encoding="utf-8").read()
        a = [int(x) for x in re.findall(r"-?\d+", cur)]
        b = [int(x) for x in re.findall(r"-?\d+", gen)]
        if a == b:
            print(">> verify: T0-c 独立真值零差异（%d 项数值）" % len(a))
            return 0
        print("!! verify: T0-c 真值漂移", file=sys.stderr)
        return 1
    sys.stdout.write(gen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
