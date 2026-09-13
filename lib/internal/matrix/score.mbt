///|
/// score.mbt —— 掩码评分（4 条惩罚规则，S5 落地）
/// 对应参考：fast_qr v0.14.0 `src/score.rs`（roadmap 批次 B10 后半）
/// 职责：N1 连续同色（行/列）、N2 2×2 同色块、N3 11 位窗口命中类 finder 图案、
///       N4 暗模块比例查表；总分越低越优。
/// 关键语义（framework §五.6 / 掩码与评分不变量）：
///   - quiet zone：N3 滚动窗口行首以 0 起始（相当于补 4 浅色）、行尾补 4 浅色移位，
///     双侧浅命中计两次 40（N1 运行只在符号内结算，quiet zone 仅参与 N3 图案窗口）；
///   - 2×2 触及非 Data 模块不计分且连续性归零（N2 类型门槛）；
///   - 列评分必须在掩码后做（placement 历史 bug 铁律）；评分只对 Data 计；
///   - N4 查 constants.percent_score_table（S5 落）。
/// 介质：原始字节矩阵 `Array[Int]`（D3），坐标扁平 = 行*size + 列。
/// 依赖规则：不依赖 lib 公共包；仅依赖本包 module helper + constants（同包/已有 import）。

///|
/// N3 两个目标 11 位窗口（行首/尾各 4 浅色补齐）：浅色在前的 finder 类图案。
let pattern_light_before : Int = 0b00001011101

///|
/// 浅色在后的 finder 类图案（行尾 4 浅色补齐后命中）。
let pattern_light_after : Int = 0b10111010000

///|
/// 11 位窗口掩码（截断移位溢出）。
let pattern_window_mask : Int = 0b11111111111

///|
/// 对一段逻辑行（行=连续切片；列=跳跃访问）做 N1 运行结算 + N3 图案窗口扫描。
/// `get(i)` 返回第 i 格 packed 值（明暗|类型<<1）；返回 (pattern_score, run_line_score)。
///
/// **实现委托生产路径 `line_scan_buf`**（S11 §4.1/§10.6 P1-2 延伸）：本函数原为与
/// `line_scan_buf` 逐位等价的**独立副本**，仅被白盒 helper `test_line_run`/
/// `test_line_pattern` 使用——正属 S11 §3.2 同类的「双份实现漂移风险」。改为把
/// `get` 回调物化到临时连续缓冲后**直接复用 `line_scan_buf`**，既消副本又使
/// 白盒断言测的**就是**生产算法（不再 `actual == actual` 的同源问题）。
fn line_score(get : (Int) -> Int, len : Int) -> (Int, Int) {
  let buf = Array::make(len, 0)
  let mut i = 0
  while i < len {
    buf[i] = get(i)
    i += 1
  }
  let (patt, run, _) = line_scan_buf(buf, 0, len)
  (patt, run)
}

///|
/// 对一段**连续**缓冲区 `buf[off .. off+len)` 做 N1 + N3 + N4 计数扫描（无闭包、无间接调用）。
/// 与 `line_score` 逐位等价，仅取数方式由回调改为直接索引（S9n P2）；额外累计暗格数供 N4
/// 复用同一趟（S9n P2b，免去 `score_dark` 的独立全矩阵趟）。
/// 返回 (pattern_score, run_line_score, dark_count)。
fn line_scan_buf(buf : Array[Int], off : Int, len : Int) -> (Int, Int, Int) {
  let mut patt = 0
  let mut run = 0
  let mut dark = 0
  let mut count = 1
  let mut current = 1 - (buf[off] & 1) // = !line[0].value()：起始与首格相反
  let mut buffer : Int = 0
  let mut i = 0
  while i < len {
    let v = buf[off + i]
    let val = v & 1
    dark = dark + val
    buffer = ((buffer << 1) | val) & pattern_window_mask
    if buffer == pattern_light_before || buffer == pattern_light_after {
      patt = patt + 40
    }
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
  // 行尾补 4 浅色移位：仅浅色在后的图案仍可在此命中。
  let mut j = 0
  while j < 4 {
    buffer = (buffer << 1) & pattern_window_mask
    if buffer == pattern_light_after {
      patt = patt + 40
    }
    j += 1
  }
  (patt, run, dark)
}

///|
/// N1 行运行分 + N3 行图案分 + N4 暗格计数（整矩阵逐行扫描，直接切片，无闭包）。
/// 返回 (run, patt, dark)；dark 覆盖全矩阵（含功能图案），与 `score_dark` 的计数口径一致。
fn line_rows(m : Array[Int], size : Int) -> (Int, Int, Int) {
  let mut run = 0
  let mut patt = 0
  let mut dark = 0
  let mut row = 0
  while row < size {
    let (p, r, d) = line_scan_buf(m, row * size, size)
    run = run + r
    patt = patt + p
    dark = dark + d
    row += 1
  }
  (run, patt, dark)
}

///|
/// N1 列运行分 + N3 列图案分：先把列收集进复用缓冲，再做连续扫描
/// （对照参考 `score.rs:150-175`，消除 `i*size+col` 跳访与每列闭包）。列评分须在掩码后做。
/// 暗格计数已在行趟完成，列趟不再重复累计。
fn line_cols(m : Array[Int], size : Int) -> (Int, Int) {
  let mut run = 0
  let mut patt = 0
  let colbuf = Array::make(size, 0)
  let mut col = 0
  while col < size {
    let mut i = 0
    while i < size {
      colbuf[i] = m[i * size + col]
      i += 1
    }
    let (p, r, _) = line_scan_buf(colbuf, 0, size)
    run = run + r
    patt = patt + p
    col += 1
  }
  (run, patt)
}

///|
/// 白盒用：对一段逻辑行返回运行分（参考 test_score_line）。仅供 *_wbtest 内部调用。
pub fn test_line_run(get : (Int) -> Int, len : Int) -> Int {
  line_score(get, len).1
}

///|
/// 白盒用：对一段逻辑行返回图案分（参考 test_score_pattern）。
pub fn test_line_pattern(get : (Int) -> Int, len : Int) -> Int {
  line_score(get, len).0
}

///|
/// N1 汇总：整矩阵 行运行 + 列运行 分。
pub fn score_line(m : Array[Int], size : Int) -> Int {
  let (rr, _, _) = line_rows(m, size)
  let (cr, _) = line_cols(m, size)
  rr + cr
}

///|
/// N3 汇总：整矩阵 行 + 列 图案命中 40 分（quiet zone 双侧命中各计）。
pub fn score_pattern(m : Array[Int], size : Int) -> Int {
  let (_, rp, _) = line_rows(m, size)
  let (_, cp) = line_cols(m, size)
  rp + cp
}

///|
/// N2 2×2 同色块分（参考 `matrix_score_squares`）。触及非 Data 不计且连续性归零。
pub fn score_squares(m : Array[Int], size : Int) -> Int {
  let mut square = 0
  let mut i = 0
  while i < size - 1 {
    let mut count_data = 2
    let mut buffer = 0
    buffer = buffer | ((m[i * size] & 1) << 2)
    buffer = buffer | ((m[(i + 1) * size] & 1) << 3)
    let mut j = 0
    while j < size - 1 {
      buffer = buffer >> 2
      buffer = buffer | ((m[i * size + (j + 1)] & 1) << 2)
      buffer = buffer | ((m[(i + 1) * size + (j + 1)] & 1) << 3)
      if !is_data_byte(m[i * size + (j + 1)]) ||
        !is_data_byte(m[(i + 1) * size + (j + 1)]) {
        count_data = 0
      }
      if count_data >= 2 && (buffer == 0b1111 || buffer == 0b0000) {
        square = square + 3
      }
      count_data = count_data + 1
      j += 1
    }
    i += 1
  }
  square
}

///|
/// N4 暗模块比例分（参考 `dark_module_score`）：统计暗模块 → 占比 → 查 constants 惩罚表。
pub fn score_dark(m : Array[Int], size : Int) -> Int {
  let mut dark = 0
  let mut i = 0
  while i < size * size {
    if (m[i] & 1) == 1 {
      dark = dark + 1
    }
    i += 1
  }
  let percent = dark * 100 / (size * size)
  @constants.percent_score(percent)
}

///|
/// 4 条规则总分（越低越优）。供 placement 择优主循环调用。
/// = N1(行+列运行) + N2(squares) + N3(行+列图案) + N4(dark)。
/// N4 的暗格计数已并入行趟（S9n P2b），此处不再单独扫全矩阵；
/// 暗比查表与 `score_dark` 逐位一致（同一 dark 计数 → 同一 percent → 同一分值）。
pub fn score(m : Array[Int], size : Int) -> Int {
  let (rr, rp, dark) = line_rows(m, size)
  let (cr, cp) = line_cols(m, size)
  let squares = score_squares(m, size)
  let percent = dark * 100 / (size * size)
  rr + rp + cr + cp + @constants.percent_score(percent) + squares
}
