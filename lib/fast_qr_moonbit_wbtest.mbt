///|
/// 白盒测试（_wbtest.mbt，包内运行，可访问私有成员）
/// 覆盖 S1 数据结构层：Module 位打包、公共枚举序号映射、QRCode 容器。

// ---------- Module 位打包（参照 fast_qr module.rs 测试语义） ----------

test "module_data_light" {
  let m = Module::data(false)
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
  let types : ReadOnlyArray[ModuleType] = [
    Data,
    FinderPattern,
    Alignment,
    Timing,
    Format,
    Version,
    DarkModule,
    Empty,
  ]
  let mods : Array[Module] = []
  for t in types {
    mods.push(Module::new(true, t))
  }
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
  assert_eq(ECL::Q.to_int(), 2)
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

///|
/// T5-b（缺口 G8）：枚举**全量** `to_int` / `from_int` 回环 + 越界回退。
///
/// 背景：覆盖率报告（`bash scripts/coverage.sh`）显示 `Version::to_int` / `from_int`
/// 的分支有 12 行未覆盖——因为既有用例只抽查 V01/V10/V40。
/// 本用例按「回环 + 边界回退」穷举，既补覆盖也锁契约（G8：`from_*` 未知值回退未测）。
///
/// 口径：
///   - `Version`：40 个枚举全量回环；越界（负/40+）回退 V40；
///   - `ECL`/`Mode`/`Mask`：全量回环；越界按各自契约回退。
test "t5b_full_enum_roundtrip_and_bounds" {
  // Version：0..39 回环
  let mut i = 0
  while i < 40 {
    let v = Version::from_int(i)
    if v.to_int() != i {
      fail(
        "t5b: Version 回环 V" +
        (i + 1).to_string() +
        " got=" +
        v.to_int().to_string(),
      )
    }
    // width 契约：版本号*4+17
    if v.width() != (i + 1) * 4 + 17 {
      fail(
        "t5b: Version::width V" +
        (i + 1).to_string() +
        " got=" +
        v.width().to_string() +
        " want=" +
        ((i + 1) * 4 + 17).to_string(),
      )
    }
    i += 1
  }
  // Version 越界回退 V40（契约：最大版本）
  if Version::from_int(-1).to_int() != 39 {
    fail(
      "t5b: Version::from_int(-1) 应回退 V40(39)，got=" +
      Version::from_int(-1).to_int().to_string(),
    )
  }
  if Version::from_int(40).to_int() != 39 {
    fail(
      "t5b: Version::from_int(40) 应回退 V40(39)，got=" +
      Version::from_int(40).to_int().to_string(),
    )
  }
  // ECL：0..3 回环；越界回退 H(3)
  let mut e = 0
  while e < 4 {
    if ECL::from_int(e).to_int() != e {
      fail("t5b: ECL 回环 " + e.to_string())
    }
    e += 1
  }
  if ECL::from_int(-1).to_int() != 3 || ECL::from_int(4).to_int() != 3 {
    fail("t5b: ECL 越界应回退 H(3)")
  }
  // Mode：0..2 回环；越界回退 Byte(2)
  let mut m = 0
  while m < 3 {
    if Mode::from_int(m).to_int() != m {
      fail("t5b: Mode 回环 " + m.to_string())
    }
    m += 1
  }
  if Mode::from_int(-1).to_int() != 2 || Mode::from_int(3).to_int() != 2 {
    fail("t5b: Mode 越界应回退 Byte(2)")
  }
  // Mask：0..7 回环；越界回退 Meadow(7)
  let mut k = 0
  while k < 8 {
    if Mask::from_int(k).to_int() != k {
      fail("t5b: Mask 回环 " + k.to_string())
    }
    k += 1
  }
  if Mask::from_int(-1).to_int() != 7 || Mask::from_int(8).to_int() != 7 {
    fail("t5b: Mask 越界应回退 Meadow(7)")
  }
}

///|
/// T5-b（缺口 G8）：`Shape::from_name` 回环 + 未知名回退。
/// 既有 `s7_svg_test.mbt` 只测了 6 个内置形状的输出，未测名字解析面。
test "t5b_shape_from_name_roundtrip" {
  // 6 个内置形状的名字 ↔ 枚举**双向回环**（name() → from_name() 恒等）。
  let shapes : Array[Shape] = [
    Shape::Square,
    Shape::Circle,
    Shape::RoundedSquare,
    Shape::Vertical,
    Shape::Horizontal,
    Shape::Diamond,
  ]
  for sh in shapes {
    let n = sh.name()
    let back = Shape::from_name(n)
    if back != sh {
      fail("t5b: Shape 名字回环失败 name=" + n)
    }
  }
  // 大小写不敏感（契约：ASCII 折叠）
  if Shape::from_name("SQUARE") != Shape::Square {
    fail("t5b: Shape::from_name 应大小写不敏感（SQUARE）")
  }
  if Shape::from_name("DiAmOnD") != Shape::Diamond {
    fail("t5b: Shape::from_name 应大小写不敏感（DiAmOnD）")
  }
  // 未知名回退契约：回退 Square（对齐参考 From<String> for Shape）
  if Shape::from_name("not-a-shape") != Shape::Square {
    fail("t5b: Shape::from_name 未知名应回退 Square")
  }
}
