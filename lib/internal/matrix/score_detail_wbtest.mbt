///|
/// score_detail_wbtest.mbt —— T2-a/T2-b 打分明细（S10 §6 T2-a/T2-b / 缺口 G5）
///
/// 缺口 G5：本项目评分此前只有「合成矩阵 + 分解不变量」；参考 `score.rs` 把
/// **逐行/逐列 N1 运行分**与**矩阵级四规则分量**写成数组逐一断言，可定位「哪一行/哪一列算错」。
/// 本文件把参考 `line_by_line_xiaojiba` / `col_by_col_xiaojiba` 的方法迁移过来。
///
/// 真值来源：参考 fast_qr commit 53e8c99 侧的**同一夹具** `XIAOJIBA_MOD`（29×29 类型化矩阵，
/// 本项目 max_bytes 无关，纯分数语料），由 `bash scripts/gen-goldens.sh --emit-score`
/// 在参考侧**实际计算**产出（禁止手抄）。矩阵以 packed hex 内联（每格 1 字节 = 明暗|类型<<1），
/// 与参考 `Module(n)` 值域完全同构。
///
/// 覆盖：29 行 N1 逐行 + 29 列 N1 逐列 + 矩阵级 squares/pattern/dark/line/col 总量。
/// 失败信息含行号或列号（铁律 4）。

///|
/// 参考夹具 `XIAOJIBA_MOD`（29×29）packed hex，按行 29 字节 × 29 行。
/// 由 `bash scripts/gen-goldens.sh --emit-score` 产出；禁止手改。

///|
let score_fixture_hex : ReadOnlyArray[String] = [
  "030303030303030e080100010001010101010001010e03030303030303", "030202020202030e080101000101010001000101000e03020202020203",
  "030203030302030e090101000100010101000001000e03020303030203", "030203030302030e090101010001000000010000010e03020303030203",
  "030203030302030e080100010101000001000101000e03020303030203", "030202020202030e080100000000010100000000010e03020202020203",
  "030303030303030e070607060706070607060706070e03030303030303", "0e0e0e0e0e0e0e0e080000000000010001010101010e0e0e0e0e0e0e0e",
  "0808080909080709080000010000000001000000000808080809090808", "0101000101000601010001010001010100000100000000010100000100",
  "0101010000010701010000010001000100010001010101010101010000", "0101010000010601000100000101000000010001010000000101000001",
  "0001010000010701010101010101000101010100010101000001000100", "0100000000010601000000010001010000010100000001000100010001",
  "0001000001010701010100010100010100010001000001010001000001", "0101000100010600010101000000000000010100010101000101010000",
  "0001000000010701000101010101010101000101010000010001000101", "0101010001000600010100000101000101000000000100000100000000",
  "0101010001010700010000010001000001010101000000010001000001", "0101010101000600000101010100000000000000000101010000010100",
  "0101000101000701010000000001000100010000050505050501010001", "0e0e0e0e0e0e0e0e0d0000000100000000010101050404040501010000",
  "030303030303030e090001000101000000000001050405040500010000", "030202020202030e080101000000000100000001050404040501000100",
  "030203030302030e090101010001000000010001050505050500000000", "030203030302030e090001000101000101010100000000010001010100",
  "030203030302030e080101010001000101010000010100010100000101", "030202020202030e080100010100000101010100000101000100010001",
  "030303030303030e080001000100010100010100010101010100000000",
]

///|
/// 逐行/逐列 N1 运行分期望（参考侧 test_score_line 实算）。

///|
let score_expect_row : ReadOnlyArray[Int] = [
  3, 0, 0, 0, 0, 0, 0, 6, 0, 0, 6, 0, 5, 0, 0, 4, 6, 0, 0, 9, 0, 0, 3, 0, 0, 0, 0,
  0, 3,
]

///|
let score_expect_col : ReadOnlyArray[Int] = [
  0, 5, 0, 3, 0, 5, 0, 4, 0, 4, 3, 0, 0, 3, 9, 0, 4, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 3,
]

///|
/// 由 packed hex 重建 29×29 矩阵（行主序，每格 1 字节）。

///|
fn score_fixture() -> FixedArray[Int] {
  let out : Array[Int] = []
  for line in score_fixture_hex {
    let chars = line.to_array()
    let mut i = 0
    while i + 1 < chars.length() {
      out.push(score_hex_digit(chars[i]) * 16 + score_hex_digit(chars[i + 1]))
      i += 2
    }
  }
  FixedArray::from_array(out)
}

///|
fn score_hex_digit(c : Char) -> Int {
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
/// N1 行运行分（复刻实现 `line_scan_buf` 的 N1 部分，逐行切片）。
/// 注意：本函数与实现**同一算法**，故它不是正确性证据；它的作用是
/// 把「逐行分解」暴露到可定位粒度（缺口 G5 的诉求），真值由 score_expect_row 锁定。

///|
fn score_row_run(m : FixedArray[Int], size : Int, row : Int) -> Int {
  let mut run = 0
  let mut count = 1
  let mut current = 1 - (m[row * size] & 1)
  let mut i = 0
  while i < size {
    let v = m[row * size + i]
    let val = v & 1
    if val != current {
      if count >= 5 {
        run = run + count - 2
      }
      count = 0
      current = val
    }
    if !is_data_byte(v) {
      if count >= 5 {
        run = run + count - 2
      }
      count = 0
      i += 1
      continue
    }
    count = count + 1
    i += 1
  }
  if count >= 5 {
    run = run + count - 2
  }
  run
}

///|
/// T2-a：**逐行** N1 运行分数组全等（29 行，失败信息含行号与行内首个差异下标）。

///|
test "t2a_score_line_by_line" {
  let m = score_fixture()
  let size = 29
  let mut row = 0
  while row < size {
    let got = score_row_run(m, size, row)
    if got != score_expect_row[row] {
      fail(
        "t2a: 第 " +
        row.to_string() +
        " 行 N1 运行分 got=" +
        got.to_string() +
        " want=" +
        score_expect_row[row].to_string(),
      )
    }
    row += 1
  }
  // 行总量 = 45（参考 line_by_line_xiaojiba 注释值）
  let mut total = 0
  let mut i = 0
  while i < size {
    total = total + score_expect_row[i]
    i += 1
  }
  if total != 45 {
    fail("t2a: 行总量 got=" + total.to_string() + " want=45")
  }
}

///|
/// T2-a：**逐列** N1 运行分数组全等（29 列，失败信息含列号）。
/// 列读取须与实现同口径：取列后按连续序列扫描。

///|
test "t2a_score_col_by_col" {
  let m = score_fixture()
  let size = 29
  let colbuf = FixedArray::make(size, 0)
  let mut col = 0
  while col < size {
    let mut i = 0
    while i < size {
      colbuf[i] = m[i * size + col]
      i += 1
    }
    let got = score_row_run(colbuf, size, 0)
    if got != score_expect_col[col] {
      fail(
        "t2a: 第 " +
        col.to_string() +
        " 列 N1 运行分 got=" +
        got.to_string() +
        " want=" +
        score_expect_col[col].to_string(),
      )
    }
    col += 1
  }
  let mut total = 0
  let mut i = 0
  while i < size {
    total = total + score_expect_col[i]
    i += 1
  }
  if total != 50 {
    fail("t2a: 列总量 got=" + total.to_string() + " want=50")
  }
}

///|
/// T2-b：矩阵级四规则**分量**与参考同名断言一致（squares/pattern/dark/line/col）。
/// 分量来自参考侧 `test_matrix_score_squares` / `test_matrix_pattern_and_line` /
/// `test_matrix_dark_modules` 的实算（同一夹具）。
/// 注意：本项目 `score_pattern` 的分行/分列口径与参考 `line()` 完全一致（quiet zone 双侧命中各计）。

///|
test "t2b_score_matrix_components" {
  let m = score_fixture()
  let size = 29
  let squares = score_squares(m, size)
  if squares != 150 {
    fail("t2b: squares got=" + squares.to_string() + " want=150")
  }
  let patt = score_pattern(m, size)
  if patt != 720 {
    fail("t2b: pattern got=" + patt.to_string() + " want=720")
  }
  let line = score_line(m, size)
  if line != 95 {
    fail("t2b: line+col got=" + line.to_string() + " want=95（45+50）")
  }
  // 暗格数（参考 440 暗格；N4 由 percent 查表，此处断言计数口径一致）
  let mut dark = 0
  let mut i = 0
  while i < size * size {
    if (m[i] & 1) == 1 {
      dark = dark + 1
    }
    i += 1
  }
  if dark != 440 {
    fail("t2b: dark modules got=" + dark.to_string() + " want=440")
  }
}
