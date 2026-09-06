///|
/// 黑盒测试（_test.mbt，包外运行，只能访问 `pub` API）
/// 通过模块公共面验证 S1 数据结构层行为：公共枚举序号、Module 位语义、QRCode 容器。
test "public_ecl_api" {
  // ECL 序号映射与默认级别
  assert_eq(ECL::L.to_int(), 0)
  assert_eq(ecl_default().to_int(), ECL::Q.to_int())
}

///|
test "public_version_size" {
  // Version 序号 → 矩阵边长（版本号 * 4 + 17）
  assert_eq(Version::V01.width(), 21)
  assert_eq(Version::V40.width(), 177)
  assert_eq(Version::V40.to_int(), 39)
}

///|
test "public_mode_mask" {
  assert_eq(Mode::Byte.to_int(), 2)
  assert_eq(Mask::Meadow.to_int(), 7)
}

///|
test "public_module_value" {
  // Module 明暗读写
  let dark = Module::data(true)
  assert_eq(dark.value(), true)
  let light = Module::data(false)
  assert_eq(light.set(true).value(), true)
  assert_eq(light.toggle().value(), true)
}

///|
test "public_module_type" {
  assert_eq(Module::finder_pattern(false).module_type().to_int(), 1)
  assert_eq(Module::dark(true).module_type().to_int(), 6)
}

///|
test "public_qrcode_default" {
  let qr = QRCode::for_version(Version::V40)
  assert_eq(qr.size(), 177)
  // 默认矩阵全为亮色数据模块
  assert_eq(qr.get(0, 0).value(), false)
  assert_eq(qr.data().length(), QR_MAX_MODULES)
  assert_eq(QR_MAX_WIDTH, 177)
}

///|
test "public_qrcode_meta_defaults" {
  let qr = QRCode::default(21)
  let (v, ecl, mask, mode) = qr.meta()
  assert_eq(v, None)
  assert_eq(ecl, None)
  assert_eq(mask, None)
  assert_eq(mode, None)
}

///|

///|
/// ASCII 串 → Byte 数组（测试辅助）。
fn bstr(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in s {
    out.push(ch.to_int().to_byte())
  }
  out
}

///|
test "public_select_capacity_auto" {
  // Numeric 全数字 → best=Numeric(0)，ecl 默认 Q(2)，V01 可容 5 位 → Ok((0,2,0))
  let input = bstr("12345")
  let r = QRCode::select_capacity(input, None, None, None)
  match r {
    Ok((m, e, v)) => {
      assert_eq(m, 0)
      assert_eq(e, 2)
      assert_eq(v, 0)
    }
    Err(_) => fail("expected Ok for small numeric")
  }
}

///|
test "public_select_capacity_specified_ok" {
  // 指定 version V05(4) >= 自动 V01(0) → 采用 V05
  let input = bstr("12345")
  let r = QRCode::select_capacity(input, None, None, Some(Version::V05))
  match r {
    Ok((_, _, v)) => assert_eq(v, Version::V05.to_int())
    Err(_) => fail("expected Ok when specified version big enough")
  }
}

///|
test "public_select_capacity_too_small_version" {
  // Numeric-Q V01 上限 27；28 位需 V02，强制 V01 → SpecifiedVersion
  let input = bstr("1234567890123456789012345678")
  let r = QRCode::select_capacity(input, None, None, Some(Version::V01))
  match r {
    Ok(_) => fail("expected Err(SpecifiedVersion)")
    Err(e) =>
      if e != SpecifiedVersion {
        fail("expected SpecifiedVersion, got other")
      }
  }
}

///|
test "public_select_capacity_data_too_big" {
  // Byte-Q 全 2000 字节超 V40(1663) → EncodedData
  let input = Array::make(2000, b'x')
  let r = QRCode::select_capacity(input, Some(Mode::Byte), None, None)
  match r {
    Ok(_) => fail("expected Err(EncodedData)")
    Err(e) => if e != EncodedData { fail("expected EncodedData, got other") }
  }
}
