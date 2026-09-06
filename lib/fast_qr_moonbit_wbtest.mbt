///|
/// 白盒测试（_wbtest.mbt，包内运行，可访问私有成员）
/// 覆盖 S1 数据结构层：Module 位打包、公共枚举序号映射、QRCode 容器。

// ---------- Module 位打包（参照 fast_qr module.rs 测试语义） ----------

test "module_data_light" {
  let m = Module::data(module_light())
  assert_eq(m.module_type().to_int(), ModuleType::Data.to_int())
  assert_eq(m.value(), false)
}

///|
test "module_value_light_dark" {
  let light = Module::data(false)
  assert_eq(light.value(), false)
  let dark = Module::data(true)
  assert_eq(dark.value(), true)
}

///|
test "module_set" {
  let m = Module::data(false)
  let m = m.set(true)
  assert_eq(m.value(), true)
}

///|
test "module_toggle" {
  let m = Module::data(false)
  assert_eq(m.toggle().value(), true)
  assert_eq(m.toggle().toggle().value(), false)
}

///|
test "module_each_type" {
  // 构造各类型模块，校验类型号与位布局一致（类型号写 bit1-3）
  let mods = [
    Module::data(true),
    Module::finder_pattern(true),
    Module::alignment(true),
    Module::timing(true),
    Module::format(true),
    Module::version(true),
    Module::dark(true),
    Module::empty(true),
  ]
  let mut expected = 0
  while expected < mods.length() {
    assert_eq(mods[expected].module_type().to_int(), expected)
    assert_eq(mods[expected].value(), true)
    expected += 1
  }
}

///|
test "module_type_from_int" {
  assert_eq(ModuleType::from_int(0).to_int(), 0)
  assert_eq(ModuleType::from_int(7).to_int(), 7)
  // 越界回退 Empty/Data 语义（当前实现回退 Empty）
  assert_eq(ModuleType::from_int(8).to_int(), 7)
}

// ---------- 公共枚举序号映射 ----------

///|
test "ecl_ordering" {
  assert_eq(ECL::L.to_int(), 0)
  assert_eq(ECL::M.to_int(), 1)
  assert_eq(ECL::Q.to_int(), 2)
  assert_eq(ECL::H.to_int(), 3)
  assert_eq(ecl_default().to_int(), ECL::Q.to_int())
  assert_eq(ECL::from_int(0).to_int(), 0)
  assert_eq(ECL::from_int(3).to_int(), 3)
  assert_eq(ECL::to_char(ECL::L), 'L')
}

///|
test "mode_ordering" {
  assert_eq(Mode::Numeric.to_int(), 0)
  assert_eq(Mode::Alphanumeric.to_int(), 1)
  assert_eq(Mode::Byte.to_int(), 2)
  assert_eq(Mode::from_int(2).to_int(), 2)
}

///|
test "mask_ordering" {
  assert_eq(Mask::Checkerboard.to_int(), 0)
  assert_eq(Mask::Meadow.to_int(), 7)
  assert_eq(Mask::from_int(7).to_int(), 7)
}

///|
test "version_ordering" {
  assert_eq(Version::V01.to_int(), 0)
  assert_eq(Version::V40.to_int(), 39)
  assert_eq(Version::V10.to_int(), 9)
  assert_eq(Version::from_int(39).to_int(), 39)
  assert_eq(Version::V01.width(), 21)
  assert_eq(Version::V40.width(), 177)
}

// ---------- QRCode 容器 ----------

///|
test "qr_code_default_meta" {
  let qr = QRCode::default(21)
  assert_eq(qr.size(), 21)
  let (_, ecl, _, _) = qr.meta()
  assert_eq(ecl, None)
  assert_eq(qr.data().length(), QR_MAX_MODULES)
}

///|
test "qr_code_for_version_size" {
  let qr = QRCode::for_version(Version::V40)
  assert_eq(qr.size(), 177)
  assert_eq(qr.data().length(), 31329)
  let (v, _, _, _) = qr.meta()
  assert_eq(v, Some(Version::V40))
}

///|
test "qr_code_get_set" {
  let qr = QRCode::for_version(Version::V01)
  // 默认全亮数据模块
  assert_eq(qr.get(0, 0).value(), false)
  let dark = Module::data(true)
  let qr2 = qr.set(0, 0, dark)
  assert_eq(qr2.get(0, 0).value(), true)
}

///|
test "qr_code_set_immutable_no_alias" {
  // 回归：QRCode::set 需不可变——返回新 QRCode 不得改到源（别名/共享数组回归）
  let qr = QRCode::for_version(Version::V01)
  let dark = Module::data(true)
  let qr2 = qr.set(0, 0, dark)
  assert_eq(qr2.get(0, 0).value(), true)
  // 源对象保持不受影响
  assert_eq(qr.get(0, 0).value(), false)
}
