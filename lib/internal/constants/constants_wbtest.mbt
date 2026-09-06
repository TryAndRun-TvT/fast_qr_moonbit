///|
/// constants_wbtest.mbt —— capacity/hardcode 白盒黄金测试
/// 期望值来自 fast_qr v0.14.0 参考源码（Version::get 分段 / hardcode 表）。

///|
test "version_for_numeric_l" {
  // Numeric(0)-L(0)：41→V01，42→V02，… 7090→V40，超界→-1
  assert_eq(version_for(0, 0, 0), 0)
  assert_eq(version_for(0, 0, 41), 0)
  assert_eq(version_for(0, 0, 42), 1)
  assert_eq(version_for(0, 0, 7089), 39)
  assert_eq(version_for(0, 0, 10000), -1)
}

///|
test "version_for_byte_h" {
  // Byte(2)-H(3)：V01 上限 7
  assert_eq(version_for(2, 3, 7), 0)
  assert_eq(version_for(2, 3, 8), 1)
}

///|
test "capacity_bytes_lookup" {
  // Numeric-L-V01 = 41；Byte-L-V01 = 17；Alphanumeric-M-V40 = 3391
  assert_eq(capacity_bytes(0, 0, 0), 41)
  assert_eq(capacity_bytes(2, 0, 0), 17)
  assert_eq(capacity_bytes(1, 1, 39), 3391)
}

///|
test "max_bytes_and_data_codewords" {
  assert_eq(max_bytes(0), 26) // V1
  assert_eq(max_bytes(39), 3706) // V40
  // data_codewords L-V1=19, Q-V5=62, H-V40=1276
  assert_eq(data_codewords(0, 0), 19)
  assert_eq(data_codewords(2, 4), 62)
  assert_eq(data_codewords(3, 39), 1276)
  assert_eq(data_bits(0, 0), 19 * 8)
}

///|
test "information_alignment_missing" {
  assert_eq(information(0), 0) // V1
  assert_eq(information(6), 31892) // V7 版本信息
  assert_eq(alignment_grid(0).length(), 0) // V1 无对齐
  let v7 = alignment_grid(6)
  assert_eq(v7, [6, 22, 38])
  assert_eq(missing_bits(1), 7) // V2
  assert_eq(missing_bits(13), 3) // V14
  assert_eq(missing_bits(20), 4) // V21
}

///|
test "ecc_to_groups_and_polynomial" {
  // ecc_to_groups L-V1 = (1,19,0,0)
  assert_eq(ecc_to_groups(0, 0), (1, 19, 0, 0))
  // ecc_to_groups L-V10 = (2,68,2,69)
  assert_eq(ecc_to_groups(0, 9), (2, 68, 2, 69))
  // get_polynomial V01-L = [0,87,229,146,149,238,102,21]（度 7）
  let p = get_polynomial(0, 0)
  assert_eq(p, [
    (0).to_byte(),
    (87).to_byte(),
    (229).to_byte(),
    (146).to_byte(),
    (149).to_byte(),
    (238).to_byte(),
    (102).to_byte(),
    (21).to_byte(),
  ])
  // V40-H 度 30（长 31）
  assert_eq(get_polynomial(39, 3).length(), 31)
}

///|
test "format_information" {
  // L-mask0 期望 0b111_0111_1100_0100 = 30660
  assert_eq(format_information(0, 0), 30660)
  // H-mask7 期望 0b000_1000_0011_1011 = 2107
  assert_eq(format_information(3, 7), 2107)
}
