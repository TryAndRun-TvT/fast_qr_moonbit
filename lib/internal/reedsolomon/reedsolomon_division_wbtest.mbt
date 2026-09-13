///|
/// 逐字节比对余数，失败信息含组号与下标（铁律 4）。
/// 注意：MoonBit 的 fail 需在 test 体内直接调用，故本 test 展开为逐组内联断言。
test "t1c_division_golden_remainders" {
  // v05q_01: V05-ECL2，gen 长 19，余数 18 字节
  let gen_v05q_01 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_01.length(), 19)
  let rem_v05q_01 = division(
    hex_bytes("43554686572655c277320612066726"),
    gen_v05q_01,
  )
  let want_v05q_01 = hex_ints("d5c70b2d73f7f1dfe5f89a759a6f56a16f27")
  if rem_v05q_01.length() != want_v05q_01.length() {
    fail(
      "v05q_01: remainder length got=" +
      rem_v05q_01.length().to_string() +
      " want=" +
      want_v05q_01.length().to_string(),
    )
  }
  let mut i_v05q_01 = 0
  while i_v05q_01 < want_v05q_01.length() {
    if rem_v05q_01[i_v05q_01].to_int() != want_v05q_01[i_v05q_01] {
      fail(
        "v05q_01: remainder byte " +
        i_v05q_01.to_string() +
        " got=" +
        rem_v05q_01[i_v05q_01].to_int().to_string() +
        " want=" +
        want_v05q_01[i_v05q_01].to_string(),
      )
    }
    i_v05q_01 += 1
  }
  // v05q_02: V05-ECL2，gen 长 19，余数 18 字节
  let gen_v05q_02 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_02.length(), 19)
  let rem_v05q_02 = division(
    hex_bytes("f6f642077686f207265616c6c79206"),
    gen_v05q_02,
  )
  let want_v05q_02 = hex_ints("57cc603ccab67c9dc8861b81d111a3a37885")
  if rem_v05q_02.length() != want_v05q_02.length() {
    fail(
      "v05q_02: remainder length got=" +
      rem_v05q_02.length().to_string() +
      " want=" +
      want_v05q_02.length().to_string(),
    )
  }
  let mut i_v05q_02 = 0
  while i_v05q_02 < want_v05q_02.length() {
    if rem_v05q_02[i_v05q_02].to_int() != want_v05q_02[i_v05q_02] {
      fail(
        "v05q_02: remainder byte " +
        i_v05q_02.to_string() +
        " got=" +
        rem_v05q_02[i_v05q_02].to_int().to_string() +
        " want=" +
        want_v05q_02[i_v05q_02].to_string(),
      )
    }
    i_v05q_02 += 1
  }
  // v05q_03: V05-ECL2，gen 长 19，余数 18 字节
  let gen_v05q_03 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_03.length(), 19)
  let rem_v05q_03 = division(
    hex_bytes("b6e6f777320776865726520686973207"),
    gen_v05q_03,
  )
  let want_v05q_03 = hex_ints("9474b1d44c854bf2ee4cc3e6bd0a6cf0c08d")
  if rem_v05q_03.length() != want_v05q_03.length() {
    fail(
      "v05q_03: remainder length got=" +
      rem_v05q_03.length().to_string() +
      " want=" +
      want_v05q_03.length().to_string(),
    )
  }
  let mut i_v05q_03 = 0
  while i_v05q_03 < want_v05q_03.length() {
    if rem_v05q_03[i_v05q_03].to_int() != want_v05q_03[i_v05q_03] {
      fail(
        "v05q_03: remainder byte " +
        i_v05q_03.to_string() +
        " got=" +
        rem_v05q_03[i_v05q_03].to_int().to_string() +
        " want=" +
        want_v05q_03[i_v05q_03].to_string(),
      )
    }
    i_v05q_03 += 1
  }
  // v05q_04: V05-ECL2，gen 长 19，余数 18 字节
  let gen_v05q_04 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_04.length(), 19)
  let rem_v05q_04 = division(
    hex_bytes("46f77656c206973210ec11ec11ec11ec"),
    gen_v05q_04,
  )
  let want_v05q_04 = hex_ints("eb9f05ad18933b216a28ffac52028320b2ec")
  if rem_v05q_04.length() != want_v05q_04.length() {
    fail(
      "v05q_04: remainder length got=" +
      rem_v05q_04.length().to_string() +
      " want=" +
      want_v05q_04.length().to_string(),
    )
  }
  let mut i_v05q_04 = 0
  while i_v05q_04 < want_v05q_04.length() {
    if rem_v05q_04[i_v05q_04].to_int() != want_v05q_04[i_v05q_04] {
      fail(
        "v05q_04: remainder byte " +
        i_v05q_04.to_string() +
        " got=" +
        rem_v05q_04[i_v05q_04].to_int().to_string() +
        " want=" +
        want_v05q_04[i_v05q_04].to_string(),
      )
    }
    i_v05q_04 += 1
  }
  // struct_31_0: V05-ECL2，gen 长 19，余数 18 字节
  let gen_struct_31_0 = @constants.get_polynomial(4, 2)
  assert_eq(gen_struct_31_0.length(), 19)
  let rem_struct_31_0 = division(
    hex_bytes("1cc36424af0b23f31c893bb6c1"),
    gen_struct_31_0,
  )
  let want_struct_31_0 = hex_ints("647d9787aef5eef51d19d5a92dcebd76a388")
  if rem_struct_31_0.length() != want_struct_31_0.length() {
    fail(
      "struct_31_0: remainder length got=" +
      rem_struct_31_0.length().to_string() +
      " want=" +
      want_struct_31_0.length().to_string(),
    )
  }
  let mut i_struct_31_0 = 0
  while i_struct_31_0 < want_struct_31_0.length() {
    if rem_struct_31_0[i_struct_31_0].to_int() !=
      want_struct_31_0[i_struct_31_0] {
      fail(
        "struct_31_0: remainder byte " +
        i_struct_31_0.to_string() +
        " got=" +
        rem_struct_31_0[i_struct_31_0].to_int().to_string() +
        " want=" +
        want_struct_31_0[i_struct_31_0].to_string(),
      )
    }
    i_struct_31_0 += 1
  }
  // struct_31_1: V05-ECL2，gen 长 19，余数 18 字节
  let gen_struct_31_1 = @constants.get_polynomial(4, 2)
  assert_eq(gen_struct_31_1.length(), 19)
  let rem_struct_31_1 = division(
    hex_bytes("2325fbbd08a90f223b89bb7286"),
    gen_struct_31_1,
  )
  let want_struct_31_1 = hex_ints("68770e261ca3f64d2cc20879b7a1ae9dae16")
  if rem_struct_31_1.length() != want_struct_31_1.length() {
    fail(
      "struct_31_1: remainder length got=" +
      rem_struct_31_1.length().to_string() +
      " want=" +
      want_struct_31_1.length().to_string(),
    )
  }
  let mut i_struct_31_1 = 0
  while i_struct_31_1 < want_struct_31_1.length() {
    if rem_struct_31_1[i_struct_31_1].to_int() !=
      want_struct_31_1[i_struct_31_1] {
      fail(
        "struct_31_1: remainder byte " +
        i_struct_31_1.to_string() +
        " got=" +
        rem_struct_31_1[i_struct_31_1].to_int().to_string() +
        " want=" +
        want_struct_31_1[i_struct_31_1].to_string(),
      )
    }
    i_struct_31_1 += 1
  }
  // small_1: V01-ECL0，gen 长 8，余数 7 字节
  let gen_small_1 = @constants.get_polynomial(0, 0)
  assert_eq(gen_small_1.length(), 8)
  let rem_small_1 = division(hex_bytes("2009"), gen_small_1)
  let want_small_1 = hex_ints("10460cc8346ae5")
  if rem_small_1.length() != want_small_1.length() {
    fail(
      "small_1: remainder length got=" +
      rem_small_1.length().to_string() +
      " want=" +
      want_small_1.length().to_string(),
    )
  }
  let mut i_small_1 = 0
  while i_small_1 < want_small_1.length() {
    if rem_small_1[i_small_1].to_int() != want_small_1[i_small_1] {
      fail(
        "small_1: remainder byte " +
        i_small_1.to_string() +
        " got=" +
        rem_small_1[i_small_1].to_int().to_string() +
        " want=" +
        want_small_1[i_small_1].to_string(),
      )
    }
    i_small_1 += 1
  }
}
