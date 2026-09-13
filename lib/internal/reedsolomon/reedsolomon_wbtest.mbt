///|
/// reedsolomon_wbtest.mbt —— division / structure 白盒黄金测试
/// 黄金来源：fast_qr v0.14.0 src/tests/structure.rs（V05-Q 用例）。

///|
/// Int 列表 → Array[Byte]（低位截断）。
fn b(l : Array[Int]) -> Array[Byte] {
  let out : Array[Byte] = []
  for x in l {
    out.push((x & 0xFF).to_byte())
  }
  out
}

///|
/// data_codewords 输入（V05-Q，62 字节）。
fn data_v05q() -> Array[Byte] {
  b([
    67, 85, 70, 134, 87, 38, 85, 194, 119, 50, 6, 18, 6, 103, 38, 246, 246, 66, 7,
    118, 134, 242, 7, 38, 86, 22, 198, 199, 146, 6, 182, 230, 247, 119, 50, 7, 118,
    134, 87, 38, 82, 6, 134, 151, 50, 7, 70, 247, 118, 86, 194, 6, 151, 50, 16, 236,
    17, 236, 17, 236, 17, 236,
  ])
}

///|
/// 读取 out 前 n 个字节为 Int 列表。
fn head(out : Array[Byte], n : Int) -> Array[Int] {
  let r : Array[Int] = []
  let mut i = 0
  while i < n {
    r.push(out[i].to_int())
    i += 1
  }
  r
}

///|
/// structure 数据区交织结果（V05-Q 前 62 字节）。
test "structure_message_v05_q" {
  let out = structure(data_v05q(), 2, 4) // ecl=Q(2), version=V05(4)
  let expect = b([
    67, 246, 182, 70, 85, 246, 230, 247, 70, 66, 247, 118, 134, 7, 119, 86, 87, 118,
    50, 194, 38, 134, 7, 6, 85, 242, 118, 151, 194, 7, 134, 50, 119, 38, 87, 16,
    50, 86, 38, 236, 6, 22, 82, 17, 18, 198, 6, 236, 6, 199, 134, 17, 103, 146, 151,
    236, 38, 6, 50, 17, 7, 236,
  ])
  let got = head(out, 62)
  let mut i = 0
  while i < 62 {
    if got[i] != expect[i].to_int() {
      fail(
        "message mismatch at " +
        i.to_string() +
        ": got " +
        got[i].to_string() +
        " want " +
        expect[i].to_string(),
      )
    }
    i += 1
  }
}

///|
/// structure 纠错区交织结果（V05-Q，structure[62..134]，72 字节）。
test "structure_error_v05_q" {
  let out = structure(data_v05q(), 2, 4)
  let expect = b([
    213, 87, 148, 235, 199, 204, 116, 159, 11, 96, 177, 5, 45, 60, 212, 173, 115,
    202, 76, 24, 247, 182, 133, 147, 241, 124, 75, 59, 223, 157, 242, 33, 229, 200,
    238, 106, 248, 134, 76, 40, 154, 27, 195, 255, 117, 129, 230, 172, 154, 209,
    189, 82, 111, 17, 10, 2, 86, 163, 108, 131, 161, 163, 240, 32, 111, 120, 192,
    178, 39, 133, 141, 236,
  ])
  let mut i = 0
  while i < 72 {
    let got = out[62 + i].to_int()
    if got != expect[i].to_int() {
      fail(
        "error mismatch at " +
        i.to_string() +
        ": got " +
        got.to_string() +
        " want " +
        expect[i].to_string(),
      )
    }
    i += 1
  }
}

///|
/// division 单元自检：V01-L 数据块 19 字节 → 余数应等于 structure 中首块纠错（此处仅验证长度与零行为）。
test "division_len" {
  let gen = @constants.get_polynomial(0, 0) // V01-L：度 7，长 8
  assert_eq(gen.length(), 8)
  let data = data_v05q() // 用 62 字节做除法（非分块），仅验证余数长度 = gen.len-1
  let rem = division(data, gen)
  assert_eq(rem.length(), gen.length() - 1)
}

///|
/// hex 串 → Array[Byte]（每字节两位）。共享 helper（同包）：
/// 供 division/structure 黄金向量文件复用，避免重复定义。
fn hex_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  let chars = s.to_array()
  let mut i = 0
  while i + 1 < chars.length() {
    out.push((hex_digit(chars[i]) * 16 + hex_digit(chars[i + 1])).to_byte())
    i += 2
  }
  out
}

///|
/// hex 串 → Array[Int]（期望值比对用）。
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
