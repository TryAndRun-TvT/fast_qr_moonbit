///|
/// helpers.mbt —— 终端输出工具（Unicode 半块字符画）
/// 对应参考：fast_qr v0.14.0 `src/helpers.rs`（roadmap 批次 B11 / S7 输出层）。
/// 职责：把 `QRCode` 渲染为「含边距的终端字符画」字符串（两行模块合一为一行字符），
///       供 `QRCode::to_str()` / `QRCode::print()` 便捷方法委托（见 qr.mbt §S7）。
/// 语义对齐（逐字符核对参考 helpers.rs `print_line`/`print_matrix_with_margin`）：
///   - 四态映射：(真,真)→' '、 (真,假)→'▄'、 (假,真)→'▀'、 (假,假)→'█'（真 = Module DARK）。
///   - 上下各补一条两模块高边距，左右各补一模块边距；末奇数行单独与全亮空行合并。
///   - 顶层返回纯字符串，`print` 的 stdout 副作用由 qr.mbt 承担，与参考分工同构。

///|
/// 半块字符：两行模块里「上暗下亮」取 TOP（上面那半块）。
const S7_EMPTY : Char = ' '

///|
/// 全暗（亮-亮 因映射反转，参考将 DARK 当背景）
const S7_BLOCK : Char = '█'

///|
/// 上半个实块
const S7_TOP : Char = '▀'

///|
/// 下半个实块
const S7_BOTTOM : Char = '▄'

///|
/// 把一行 `Module` 序列化成语义布尔数组（true=DARK），供打印/四态映射复用。
fn s7_row_values(qr : QRCode, row : Int, size : Int) -> Array[Bool] {
  let arr = Array::make(size, false)
  let mut c = 0
  while c < size {
    arr[c] = qr.get(row, c).value()
    c += 1
  }
  arr
}

///|
/// 两行合一：按 (上[i], 下[i]) 四态逐列映射输出一行字符。
/// `size` 为该行模块宽度；`above`/`below` 为两条模块行的明暗数组。
fn s7_print_line(
  above : Array[Bool],
  below : Array[Bool],
  size : Int,
) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < size {
    match (above[i], below[i]) {
      (true, true) => sb.write_char(S7_EMPTY)
      (true, false) => sb.write_char(S7_BOTTOM)
      (false, true) => sb.write_char(S7_TOP)
      (false, false) => sb.write_char(S7_BLOCK)
    }
    i += 1
  }
  sb.to_string()
}

///|
/// 终端画渲染：`QRCode` → 含边距的 Unicode 半块字符画字符串（对齐参考 helpers.rs
/// `print_matrix_with_margin`）。纯确定性，无 IO 副作用。
/// - 首行：左边距 `▄` + 上边距两行合一（全 `▄`）+ 右边距 `▄` + 换行；
/// - 中间：每两行模块合并一行（`(0..size-1).step_by(2)`），左/右边距 `█`，行尾换行；
/// - 末行：`qr[size-1]` 与一条全亮空行合并，右边距 `█`（末尾无换行，对齐参考）。
pub fn print_matrix_with_margin(qr : QRCode) -> String {
  let size = qr.size()
  let sb = StringBuilder()
  // 上边距：line1 = size 个暗(empty(true))、line2 = size 个亮(empty(false))
  let above = Array::make(size, true)
  let below = Array::make(size, false)
  let top_line = s7_print_line(above, below, size)
  sb.write_char(S7_BOTTOM)
  sb.write_string(top_line)
  sb.write_char(S7_BOTTOM)
  sb.write_char('\n')
  // 中间两行合一：i = 0, 2, 4, ... < size-1
  let mut i = 0
  while i < size - 1 {
    let row_up = s7_row_values(qr, i, size)
    let row_dn = s7_row_values(qr, i + 1, size)
    let line = s7_print_line(row_up, row_dn, size)
    sb.write_char(S7_BLOCK)
    sb.write_string(line)
    sb.write_char(S7_BLOCK)
    sb.write_char('\n')
    i += 2
  }
  // 末行（size 恒奇数）：qr[size-1] 与全亮(empty(false))合并
  let last = s7_row_values(qr, size - 1, size)
  let blank = Array::make(size, false)
  let last_line = s7_print_line(last, blank, size)
  sb.write_char(S7_BLOCK)
  sb.write_string(last_line)
  sb.write_char(S7_BLOCK)
  sb.to_string()
}

///|
/// `QRCode` 渲染便捷方法（原 `qr_output.mbt`，S11 v4 合并）：渲染终端 Unicode 半块
/// 字符画（含边距）整串字符串。纯确定性、无 IO 副作用。
/// 与渲染引擎同文件后，`to_str` ↔ `print_matrix_with_margin` 的委托关系一目了然。
pub fn QRCode::to_str(self : QRCode) -> String {
  print_matrix_with_margin(self)
}

///|
/// 打印终端字符画到 stdout（唯一承担 stdout 副作用的方法，走 `println`）。
pub fn QRCode::print(self : QRCode) -> Unit {
  println(self.to_str())
}
