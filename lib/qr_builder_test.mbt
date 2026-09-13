///|
/// qr_builder_test.mbt —— QRBuilder 公共构造器黑盒测试（_test.mbt，包外）
/// 基准：fast_qr v0.14.0 `lib.rs:75-80` 导出面的 QRBuilder 同名构造器 + 链式 setter。
/// 语义（D7 值语义）：每个 setter 返回新 QRBuilder；`build` 委托 QRCode::build。
/// 验证：链式组合 == QRCode::build 同参；默认缺省（mode=None→自动、ecl=None→Q、
///       version=None→最小、mask=None→择优）语义与 QRCode::build 一致。
/// 注意：`bstr` 辅助函数复用 fast_qr_moonbit_test.mbt 已有同名顶层函数（同包共享）。

///|
/// QRBuilder 链式（不可变）各 setter 组合的输出 == QRCode::build 同参结果（等值护栏）。
test "qr_builder_chain_equals_build_fixed" {
  let input = bstr("hi")
  // 指定 mode/ecl/version/mask：走固定 mask 路径
  let via_builder = QRBuilder::new(input)
    .mode(Mode::Byte)
    .ecl(ECL::L)
    .version(Version::V05)
    .mask(Mask::Fields)
    .build()
  let via_func = QRCode::build(
    input,
    Some(Mode::Byte),
    Some(ECL::L),
    Some(Version::V05),
    Some(Mask::Fields),
  )
  match (via_builder, via_func) {
    (Ok(a), Ok(b)) => {
      assert_eq(a.size(), b.size())
      assert_eq(a.data(), b.data())
    }
    _ => fail("expected both Ok")
  }
}

///|
/// QRBuilder 链式各 setter 组合的输出 == QRCode::build 同参结果（mask 自动择优路径）。
test "qr_builder_chain_equals_build_auto" {
  let input = bstr("Hello World!")
  // 固定 mode/ecl/version、mask=None → 自动择优
  let via_builder = QRBuilder::new(input)
    .mode(Mode::Byte)
    .ecl(ECL::M)
    .version(Version::V02)
    .build()
  let via_func = QRCode::build(
    input,
    Some(Mode::Byte),
    Some(ECL::M),
    Some(Version::V02),
    None,
  )
  match (via_builder, via_func) {
    (Ok(a), Ok(b)) => {
      assert_eq(a.size(), b.size())
      assert_eq(a.data(), b.data())
      assert_eq(a.mask(), b.mask())
    }
    _ => fail("expected both Ok")
  }
}

///|
/// QRBuilder 默认缺省（全 None 纯自动路径）：与 QRCode::build 全 None 结果一致，
/// 且 mode 自动回退（纯数字→Numeric）、ecl 默认 Q、version 最小、mask 自动择优。
test "qr_builder_default_auto_path" {
  let input = bstr("12345") // 纯数字 → Numeric 模式
  let via_builder = QRBuilder::new(input).build()
  let via_func = QRCode::build(input, None, None, None, None)
  match (via_builder, via_func) {
    (Ok(a), Ok(b)) => {
      assert_eq(a.data(), b.data())
      assert_eq(a.version(), b.version())
      assert_eq(a.ecl(), b.ecl())
      assert_eq(a.mask(), b.mask())
      assert_eq(a.mode(), b.mode())
      // 语义核对：ecl 默认 Q；mode 自动回退 Numeric
      assert_eq(a.ecl(), Some(ECL::Q))
      assert_eq(a.mode(), Some(Mode::Numeric))
      assert_eq(a.version(), Some(Version::V01))
    }
    _ => fail("expected both Ok")
  }
}

///|
/// QRBuilder::from_string 便捷入口等价于 QRBuilder::new(字节数组)。
test "qr_builder_from_string_equals_bytes" {
  let s = "https://example.com/"
  let via_str = QRBuilder::from_string(s).build()
  let via_bytes = QRBuilder::new(bstr(s)).build()
  match (via_str, via_bytes) {
    (Ok(a), Ok(b)) => assert_eq(a.data(), b.data())
    _ => fail("expected both Ok")
  }
}

///|
/// QRBuilder 错误面：数据超 V40 容量 → Err(EncodedData)。
test "qr_builder_data_too_big" {
  let input = Array::make(2000, b'x')
  let r = QRBuilder::new(input).mode(Mode::Byte).build()
  match r {
    Ok(_) => fail("expected Err(EncodedData)")
    Err(e) => if e != EncodedData { fail("expected EncodedData, got other") }
  }
}

///|
/// QRBuilder 错误面：指定版本小于最小适配 → Err(SpecifiedVersion)。
test "qr_builder_version_too_small" {
  let input = bstr("1234567890123456789012345678") // Numeric-Q 需 V02
  let r = QRBuilder::new(input).version(Version::V01).build()
  match r {
    Ok(_) => fail("expected Err(SpecifiedVersion)")
    Err(e) =>
      if e != SpecifiedVersion {
        fail("expected SpecifiedVersion, got other")
      }
  }
}

///|
/// T2-d：择优「列参与评分」回归（S10 §6 T2-d，参考 issue #77 方法迁移）。
///
/// 背景：参考 fast_qr issue #77 的 bug 是「转置取自未掩码矩阵 → 各 mask 的竖向惩罚恒等」，
/// 于是 `https://fast-qr.com/` + ECL H 会错误地选中 `VerticalLines`；
/// 修好列感知评分后应选中 `Diamonds`。
///
/// 因此本用例锁的是**行为结果**（选中 Diamonds = 序号 6），而非某个中间量：
/// 若实现退回「列不参与评分」，mask 会变，本用例即红。
/// 参考：fast_qr v0.14.0 `src/tests/score.rs::mask_selection_considers_columns`。
test "t2d_mask_selection_considers_columns" {
  let inp : Array[Byte] = []
  for ch in "https://fast-qr.com/".to_array() {
    inp.push(ch.to_int().to_byte())
  }
  match QRBuilder::new(inp).ecl(ECL::H).build() {
    Ok(qr) =>
      match qr.mask {
        Some(m) =>
          if m.to_int() != 6 {
            fail(
              "t2d: 择优 mask 应为 Diamonds(6)，got=" +
              m.to_int().to_string() +
              "（若为 2=VerticalLines 说明列未参与评分，参考 issue #77）",
            )
          }
        None =>
          fail("t2d: 自动择优路径应写入 mask 元数据，got=None")
      }
    Err(_) =>
      fail("t2d: 构建失败（输入应可容纳于自动择版本）")
  }
}
