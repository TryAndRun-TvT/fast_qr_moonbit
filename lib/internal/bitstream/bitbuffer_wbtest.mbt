///|
/// bitbuffer_wbtest.mbt —— bitbuffer（CompactQR）白盒测试
/// 黄金数据来源：/fast_qr/src/tests/compact.rs（fast_qr v0.14.0）转译。

///|
/// Int → Byte（低位截断）。
fn b(i : Int) -> Byte {
  (i & 0xFF).to_byte()
}

///|
/// 读取数据前 `n` 个字节（越界视为 0——Rust 中未写槽恒为 0）。
fn bytes_head(q : CompactQR, n : Int) -> Array[Int] {
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

///|
test "push8_lined" {
  let q = from_bits(64)
  q.push_u8(b(0))
  q.push_u8(b(1))
  q.push_u8(b(2))
  assert_eq(q.len(), 8 * 3)
  assert_eq(bytes_head(q, 4), [0, 1, 2, 0])
}

///|
test "push_bits_half" {
  let q = from_bits(64)
  q.push_bits(0b1111, 4)
  assert_eq(q.len(), 4)
  q.push_bits(0, 8)
  assert_eq(q.len(), 12)
  q.push_bits(0b1111, 4)
  assert_eq(q.len(), 16)
  assert_eq(bytes_head(q, 4), [0b1111_0000, 0b0000_1111, 0, 0])
}

///|
test "push_bits_random" {
  let q = from_bits(64)
  q.push_bits(0b1111, 2)
  assert_eq(q.len(), 2)
  assert_eq(bytes_head(q, 4), [0b1100_0000, 0, 0, 0])

  q.push_bits(0, 1)
  assert_eq(q.len(), 3)
  assert_eq(bytes_head(q, 4), [0b1100_0000, 0, 0, 0])

  q.push_bits(5, 3)
  assert_eq(q.len(), 6)
  assert_eq(bytes_head(q, 4), [0b1101_0100, 0, 0, 0])

  q.push_bits(0b1101, 2)
  assert_eq(q.len(), 8)
  assert_eq(bytes_head(q, 4), [0b1101_0101, 0, 0, 0])
}

///|
test "push_bits_push8" {
  let q = from_bits(64)
  q.push_bits(0b1111, 3)
  assert_eq(bytes_head(q, 4), [0b1110_0000, 0, 0, 0])

  q.push_u8(b(0b1001_1110))
  assert_eq(bytes_head(q, 4), [0b1111_0011, 0b1100_0000, 0, 0])
}

///|
test "push_bits_push8_2" {
  let q = from_bits(64)
  q.push_bits(0b1111, 3)
  q.push_u8(b(0b1001_1110))
  assert_eq(bytes_head(q, 4), [0b1111_0011, 0b1100_0000, 0, 0])
  q.push_u8(b(0b1001_1110))
  assert_eq(bytes_head(q, 4), [0b1111_0011, 0b1101_0011, 0b1100_0000, 0])
}

///|
test "push8_push_bits" {
  let q = from_bits(64)
  q.push_u8(b(0b1001_1110))
  assert_eq(bytes_head(q, 4), [0b1001_1110, 0, 0, 0])

  q.push_bits(0b1_1011_1001_1110, 13)
  assert_eq(bytes_head(q, 4), [0b1001_1110, 0b1101_1100, 0b1111_0000, 0])
}

///|
test "push_slice" {
  let q = from_bits(64)
  q.push_u8_slice([b(0b1001_1110), b(0b1001_1110), b(0b1001_1110)])
  assert_eq(bytes_head(q, 4), [0b1001_1110, 0b1001_1110, 0b1001_1110, 0])
}

///|
test "push_slice_off" {
  let q = from_bits(64)
  q.push_bits(0b1111, 3)
  q.push_u8_slice([b(0), b(0b1111_1111), b(0)])
  assert_eq(bytes_head(q, 4), [0b1110_0000, 0b0001_1111, 0b1110_0000, 0])
}

///|
test "push_bitfs_off" {
  let q = from_bits(64)
  q.push_bits(0b0_0000_0000_0000_0000, 17)
  assert_eq(q.len(), 17)
  q.push_bits(0b1_1111_1111_1111_1111, 17)
  q.push_bits(0b0_0000_0000_0000_0000, 17)
  q.push_bits(0b1, 2)
  q.push_u8(b(0b1111_1111))
  // 参考：push_u8(255) 把 byte6 累加成 0b0000_1111=15
  assert_eq(bytes_head(q, 8), [
    0, 0, 0b0111_1111, 0b1111_1111, 0b1100_0000, 0, 0b0000_1111, 0b1111_1000,
  ])
}

///|
test "push_random" {
  let q = from_bits(64)
  q.push_bits(1, 1)
  q.push_u8(b(0b1010_1010))
  q.push_bits(1, 1)
  q.push_bits(1, 3)
  assert_eq(bytes_head(q, 8), [0b1101_0101, 0b0100_1000, 0, 0, 0, 0, 0, 0])
}

///|
test "fill_236_17" {
  let q = from_bits(16)
  q.push_bits(0b1111, 4)
  q.push_bits(0, 4)
  q.fill()
  // 容量 2 字节，已写 1 字节，剩余 1 字节填 [236,17][0] = 236
  assert_eq(bytes_head(q, 2), [0b1111_0000, 236])
}
