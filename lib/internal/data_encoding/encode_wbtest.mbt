///|
/// encode_wbtest.mbt —— data_encoding 三模式编码 + best_encoding 白盒黄金测试
/// 期望值来自 fast_qr v0.14.0 `src/tests/encode.rs` 转译（黄金字节按参考语义逐位核算，
/// 独立 Python 复核与 Rust 测试断言一致）。
/// 覆盖：best_encoding 自动回退、三编码器数据位段、header 字符计数、ascii_to_alphanumeric /
///       is_qr_alphanumeric 边界、完整 encode 管线（terminator/pad/fill）。

///|
/// ASCII 串 → Byte 数组。
fn s(str : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in str {
    out.push(ch.to_int().to_byte())
  }
  out
}

///|
/// 读 CompactQR 前 n 字节为 Int 列表（未写字节视为 0）。
fn head(q : @bitstream.CompactQR, n : Int) -> Array[Int] {
  let d = q.data()
  let out : Array[Int] = []
  let mut i = 0
  while i < n {
    let v = if i < d.length() { d[i].to_int() } else { 0 }
    out.push(v)
    i += 1
  }
  out
}

// ---------- best_encoding ----------

///|
test "best_encoding_modes" {
  assert_eq(best_encoding(s("589492")), 0) // 全数字 → Numeric
  assert_eq(best_encoding(s("HELLO WORLD")), 1) // 仅 alnum → Alphanumeric
  assert_eq(best_encoding(s("HELLO WORLD!")), 2) // '!' 非法 → Byte
  assert_eq(best_encoding(s("589492h")), 2) // 含字母 h → Byte
  assert_eq(best_encoding(s("HELLO WORLD, MY")), 2) // ',' 非法 → Byte
  assert_eq(best_encoding(s("")), 0) // 空串 → Numeric
}

///|
test "best_encoding_star_ampersand" {
  // '*' 是合法 QR alnum → Alnum；'&' 非法 → Byte（回归：此前误把 38 当 42）
  assert_eq(best_encoding(s("HELLO*WORLD")), 1)
  assert_eq(best_encoding(s("HELLO&WORLD")), 2)
  assert_eq(best_encoding(s("5*9")), 1)
}

///|
test "best_encoding_long" {
  // 参考 best_encoding_numeric_1 / alnum_1 / byte_2
  assert_eq(best_encoding(s("95904409521090298052194059450950249521940")), 0)
  assert_eq(
    best_encoding(
      s("HELLO WORLD MY NAME IS ERWAN VIVIEN: THIS IS A TEST//////"),
    ),
    1,
  )
  assert_eq(
    best_encoding(
      s("HELLO WORLD MY NAME, IS ERWAN VIVIEN: THIS IS A TEST//////"),
    ),
    2,
  )
}

// ---------- Numeric 数据位段（对照参考 encode_numeric_1..4） ----------

///|
test "encode_numeric_data1" {
  // '5894' cci10 → [16,18,77,64]
  let q = @bitstream.from_bits(64)
  encode_numeric(q, s("5894"), 10)
  assert_eq(head(q, 4), [16, 18, 77, 64])
}

///|
test "encode_numeric_data2" {
  // '58949' cci10 → [16,22,77,98]
  let q = @bitstream.from_bits(64)
  encode_numeric(q, s("58949"), 10)
  assert_eq(head(q, 4), [16, 22, 77, 98])
}

///|
test "encode_numeric_data3" {
  // '589491' cci10 → [16,26,77,122,192]
  let q = @bitstream.from_bits(64)
  encode_numeric(q, s("589491"), 10)
  assert_eq(head(q, 5), [16, 26, 77, 122, 192])
}

///|
test "encode_numeric_data4" {
  // '200505150001' cci10 → [16,48,200,126,73,96,4]
  let q = @bitstream.from_bits(64)
  encode_numeric(q, s("200505150001"), 10)
  assert_eq(head(q, 7), [16, 48, 200, 126, 73, 96, 4])
}

// ---------- Alphanumeric 数据位段（对照参考 encode_alphanumeric_1） ----------

///|
test "encode_alphanumeric_data" {
  // 'HELLO WORLD' cci9 → [32,91,11,120,209,114,220,77,67,64]
  let q = @bitstream.from_bits(64)
  encode_alphanumeric(q, s("HELLO WORLD"), 9)
  assert_eq(head(q, 10), [32, 91, 11, 120, 209, 114, 220, 77, 67, 64])
}

// ---------- Byte 数据位段（对照参考 encode_byte_1） ----------

///|
test "encode_byte_data" {
  // 'Hello WORLD!' cci8 → [64,196,134,86,198,198,242,5,116,245,36,196,66,16]
  let q = @bitstream.from_bits(64)
  encode_byte(q, s("Hello WORLD!"), 8)
  assert_eq(head(q, 14), [
    64, 196, 134, 86, 198, 198, 242, 5, 116, 245, 36, 196, 66, 16,
  ])
}

// ---------- header 字符计数 ----------

///|
/// 模式编码后从 bits 4..(4+cci) 读回字符计数。
fn header_len(input : Array[Byte], cci : Int, mode_code : Int) -> Int {
  let q = @bitstream.from_bits(64)
  match mode_code {
    0 => encode_numeric(q, input, cci)
    1 => encode_alphanumeric(q, input, cci)
    _ => encode_byte(q, input, cci)
  }
  let h = head(q, 8)
  let mut v = 0
  let mut bit = 0
  while bit < cci {
    let abs = 4 + bit
    let byte = h[abs / 8]
    let shift = 7 - abs % 8
    let b = (byte >> shift) & 1
    v = (v << 1) | b
    bit += 1
  }
  v
}

///|
test "header_char_count" {
  assert_eq(header_len(s("Hello WORLD!"), 8, 2), 12) // Byte
  assert_eq(header_len(s("5894"), 10, 0), 4) // Numeric
  assert_eq(header_len(s("HELLO WORLD"), 9, 1), 11) // Alnum
}

// ---------- ascii_to_alphanumeric / is_qr_alphanumeric 边界 ----------

///|
test "ascii_alnum_map" {
  assert_eq(ascii_to_alphanumeric(b'0'), 0)
  assert_eq(ascii_to_alphanumeric(b'9'), 9)
  assert_eq(ascii_to_alphanumeric(b'A'), 10)
  assert_eq(ascii_to_alphanumeric(b'Z'), 35)
  assert_eq(ascii_to_alphanumeric(b' '), 36)
  assert_eq(ascii_to_alphanumeric(b'$'), 37)
  assert_eq(ascii_to_alphanumeric(b'%'), 38)
  assert_eq(ascii_to_alphanumeric(b'*'), 39)
  assert_eq(ascii_to_alphanumeric(b'+'), 40)
  assert_eq(ascii_to_alphanumeric(b'-'), 41)
  assert_eq(ascii_to_alphanumeric(b'.'), 42)
  assert_eq(ascii_to_alphanumeric(b'/'), 43)
  assert_eq(ascii_to_alphanumeric(b':'), 44)
}

///|
test "is_qr_alnum" {
  assert_eq(is_qr_alphanumeric(b'0'), true)
  assert_eq(is_qr_alphanumeric(b'A'), true)
  assert_eq(is_qr_alphanumeric(b' '), true)
  assert_eq(is_qr_alphanumeric(b':'), true)
  assert_eq(is_qr_alphanumeric(b'*'), true) // '*' (42) 是 QR alnum 合法字符
  assert_eq(is_qr_alphanumeric(b'&'), false) // '&' (38) 不是 QR alnum 字符
  assert_eq(is_qr_alphanumeric(b'a'), false) // 小写字母不属于 QR alnum
  assert_eq(is_qr_alphanumeric(b'!'), false)
  assert_eq(is_qr_alphanumeric(b','), false)
  assert_eq(is_qr_alphanumeric(b'@'), false)
}

// ---------- 完整 encode 管线（terminator + pad_to_8 + fill） ----------

///|
/// V01-L Byte 'ab'：模式头(4)+cci(8)+2 字节(16)=28bit → terminator 补 4 → 32bit 已对齐
/// → fill 用 [236,17] 铺满 26 字节。前 4 字节 [64,38,22,32]，其后 [236,17] 交替。
test "encode_pipeline_byte_v1_l" {
  let q = encode(s("ab"), 0, 2, 0)
  let bytes = head(q, 26)
  assert_eq(bytes[:4], [64, 38, 22, 32])
  assert_eq(bytes[4], 236)
  assert_eq(bytes[5], 17)
  assert_eq(bytes[6], 236)
}

// ---------- 完整 encode 管线交叉验证（与独立 Python 参考逐字节核对） ----------

///|
test "encode_pipeline_numeric_v02_q" {
  // '01234567' → Numeric(0)-Q(2)-V02(1)：前 7 字节 + [236,17] 交替 fill
  let q = encode(s("01234567"), 2, 0, 1)
  let b = head(q, 44)
  assert_eq(b[:7], [16, 32, 12, 86, 97, 128, 236])
  assert_eq(b[7], 17)
  assert_eq(b[8], 236)
}

///|
test "encode_pipeline_alnum_v01_q" {
  // 'HELLO' → Alnum(1)-Q(2)-V01(0)：前 6 字节 + [236,17] 交替 fill
  let q = encode(s("HELLO"), 2, 1, 0)
  let b = head(q, 26)
  assert_eq(b[:6], [32, 43, 11, 120, 204, 0])
  assert_eq(b[6], 236)
  assert_eq(b[7], 17)
}

///|
test "encode_pipeline_byte_v03_m" {
  // 'abc' → Byte(2)-M(1)-V03(2)：前 5 字节 + [236,17] 交替 fill
  let q = encode(s("abc"), 1, 2, 2)
  let b = head(q, 70)
  assert_eq(b[:5], [64, 54, 22, 38, 48])
  assert_eq(b[5], 236)
  assert_eq(b[6], 17)
}
