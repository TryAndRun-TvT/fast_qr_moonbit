///|
/// 黑盒测试（_test.mbt，包外运行，只能访问 `pub` API）
/// 通过模块公共面验证 S1 数据结构层行为：公共枚举序号、Module 位语义、QRCode 容器。
test "public_ecl_api" {
  // ECL 序号映射与默认级别（缺省 Quartile，由 QRBuilder/select_capacity 直接取 ECL::Q）
  assert_eq(@lib.ECL::L.to_int(), 0)
  assert_eq(@lib.ECL::Q.to_int(), 2)
  assert_eq(@lib.ECL::to_char(@lib.ECL::Q), 'Q')
}

///|
test "public_version_size" {
  // Version 序号 → 矩阵边长（版本号 * 4 + 17）
  assert_eq(@lib.Version::V01.width(), 21)
  assert_eq(@lib.Version::V40.width(), 177)
  assert_eq(@lib.Version::V40.to_int(), 39)
}

///|
test "public_mode_mask" {
  assert_eq(@lib.Mode::Byte.to_int(), 2)
  assert_eq(@lib.Mask::Meadow.to_int(), 7)
}

///|
test "public_module_value" {
  // Module 明暗读写
  let dark = @lib.Module::data(true)
  assert_eq(dark.value(), true)
  let light = @lib.Module::data(false)
  assert_eq(light.set(true).value(), true)
  assert_eq(light.toggle().value(), true)
}

///|
test "public_module_type" {
  assert_eq(@lib.Module::new(false, FinderPattern).module_type().to_int(), 1)
  // DarkModule 走通用构造（S11 v4 删除了零语义增益的 Module::dark 便捷糖）
  assert_eq(@lib.Module::new(true, DarkModule).module_type().to_int(), 6)
}

///|
test "public_qrcode_default" {
  let qr = @lib.QRCode::empty(@lib.Version::V40)
  assert_eq(qr.size(), 177)
  // 默认矩阵全为亮色数据模块
  assert_eq(qr.get(0, 0).value(), false)
  assert_eq(qr.data().length(), @lib.QR_MAX_MODULES)
  // 最大边长与固定容量的一致性：177*177 == QR_MAX_MODULES（单一事实源口径，S11 v4）
  assert_eq(@lib.Version::V40.width(), 177)
  assert_eq(
    @lib.Version::V40.width() * @lib.Version::V40.width(),
    @lib.QR_MAX_MODULES,
  )
}

///|
test "public_qrcode_meta_defaults" {
  let qr = @lib.QRCode::default(21)
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
  let r = @lib.QRCode::select_capacity(input, None, None, None)
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
  let r = @lib.QRCode::select_capacity(
    input,
    None,
    None,
    Some(@lib.Version::V05),
  )
  match r {
    Ok((_, _, v)) => assert_eq(v, @lib.Version::V05.to_int())
    Err(_) => fail("expected Ok when specified version big enough")
  }
}

///|
test "public_select_capacity_too_small_version" {
  // Numeric-Q V01 上限 27；28 位需 V02，强制 V01 → SpecifiedVersion
  let input = bstr("1234567890123456789012345678")
  let r = @lib.QRCode::select_capacity(
    input,
    None,
    None,
    Some(@lib.Version::V01),
  )
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
  let r = @lib.QRCode::select_capacity(input, Some(@lib.Mode::Byte), None, None)
  match r {
    Ok(_) => fail("expected Err(EncodedData)")
    Err(e) => if e != EncodedData { fail("expected EncodedData, got other") }
  }
}

///|
/// 辅助：对 `select_capacity` 的 `Ok((mode,ecl,version))` 断言三元组；
/// 失败信息含模块.函数 + 参数指纹（对齐 T7-a 可定位性标准）。
fn assert_cap(
  label : String,
  input : Array[Byte],
  mode : @lib.Mode?,
  ecl : @lib.ECL?,
  v : @lib.Version?,
  want : (Int, Int, Int),
) -> Unit raise {
  match @lib.QRCode::select_capacity(input, mode, ecl, v) {
    Ok(t) =>
      if t != want {
        fail(
          "qr_build.select_capacity \{label}: got=(\{t.0},\{t.1},\{t.2}) want=(\{want.0},\{want.1},\{want.2}) len=\{input.length()}",
        )
      }
    Err(_) =>
      fail(
        "qr_build.select_capacity \{label}: got=Err want=Ok(\{want.0},\{want.1},\{want.2}) len=\{input.length()}",
      )
  }
}

///|
/// 辅助：断言 `Err(SpecifiedVersion)`（失败信息含参数指纹）。
fn assert_ver_low(
  label : String,
  input : Array[Byte],
  mode : @lib.Mode?,
  ecl : @lib.ECL?,
  v : @lib.Version?,
) -> Unit raise {
  match @lib.QRCode::select_capacity(input, mode, ecl, v) {
    Ok(t) =>
      fail(
        "qr_build.select_capacity \{label}: got=Ok(\{t.0},\{t.1},\{t.2}) want=Err(SpecifiedVersion) len=\{input.length()}",
      )
    Err(SpecifiedVersion) => ()
    Err(EncodedData) =>
      fail(
        "qr_build.select_capacity \{label}: got=Err(EncodedData) want=Err(SpecifiedVersion) len=\{input.length()}",
      )
  }
}

///|
/// 辅助：断言 `Err(EncodedData)`（失败信息含参数指纹）。
fn assert_too_big(
  label : String,
  input : Array[Byte],
  mode : @lib.Mode?,
  ecl : @lib.ECL?,
  v : @lib.Version?,
) -> Unit raise {
  match @lib.QRCode::select_capacity(input, mode, ecl, v) {
    Ok(t) =>
      fail(
        "qr_build.select_capacity \{label}: got=Ok(\{t.0},\{t.1},\{t.2}) want=Err(EncodedData) len=\{input.length()}",
      )
    Err(EncodedData) => ()
    Err(SpecifiedVersion) =>
      fail(
        "qr_build.select_capacity \{label}: got=Err(SpecifiedVersion) want=Err(EncodedData) len=\{input.length()}",
      )
  }
}

///|
/// T3-d 回归 ①：**显式模式必须参与版本选择**（v5 修复的核心 bug）。
/// 旧实现把 `mode_idx` 算好后从未用于容量判定（`version_for` 恒按 Numeric），
/// 于是显式 Alphanumeric/Byte + `v=None` 会被按 Numeric 预算放行，
/// 随后交错的却是 Alnum/Byte 编码器 → **静默错数据**（下游解码器读回 ≠ 输入）。
/// 真值来源：参考 fast_qr v0.14.0 `Version::get(mode, ecl, len)` 的 mode 分支
/// （由 Rust harness 在钉版 `53e8c99` 上实跑核对，19680 + 64480 组参数零差异）。
test "public_select_capacity_explicit_mode_respected" {
  // '1' × 41：Numeric-L V01 上限恰 41；Alnum-L 上限 25；Byte-L 上限 17。
  // 同一输入按模式给出**三个不同的最小版本**，这是「模式被尊重」的判据。
  let d41 = Array::make(41, b'1')
  assert_cap(
    "41-digit Numeric-L",
    d41,
    Some(@lib.Mode::Numeric),
    Some(@lib.ECL::L),
    None,
    (0, 0, 0),
  )
  assert_cap(
    "41-digit Alnum-L",
    d41,
    Some(@lib.Mode::Alphanumeric),
    Some(@lib.ECL::L),
    None,
    (1, 0, 1),
  )
  assert_cap(
    "41-digit Byte-L",
    d41,
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    None,
    (2, 0, 2),
  )
  // 交叉验证：同一输入 `mode=None` 自动回退到 Numeric → 仍是最小 V01
  assert_cap("41-digit auto-L", d41, None, Some(@lib.ECL::L), None, (0, 0, 0))
  // 非全数字串无法回退 Numeric：'A' × 30 自动 → Alnum（V01-L 上限 25 → V02）
  let a30 = Array::make(30, b'A')
  assert_cap("30-char auto-L", a30, None, Some(@lib.ECL::L), None, (1, 0, 1))
  assert_cap(
    "30-char Alnum-L",
    a30,
    Some(@lib.Mode::Alphanumeric),
    Some(@lib.ECL::L),
    None,
    (1, 0, 1),
  )
  assert_cap(
    "30-char Byte-L",
    a30,
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    None,
    (2, 0, 1),
  )
}

///|
/// T3-d 回归 ②：**显式版本越界必须报 `SpecifiedVersion`**（旧实现只校验 Numeric 容量）。
/// 旧实现下 `mode=Byte, ecl=H, version=V01, len=18` 不报错（Numeric-H-V01 上限 17）。
/// 真值：参考 V01 容量 Numeric-H=17 / Alnum-H=10 / **Byte-H=7**。
test "public_select_capacity_specified_version_mode_aware" {
  // ── Byte-H-V01 上限 7 ──
  assert_cap(
    "Byte-H-V01 len7",
    Array::make(7, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::H),
    Some(@lib.Version::V01),
    (2, 3, 0),
  )
  assert_ver_low(
    "Byte-H-V01 len8",
    Array::make(8, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::H),
    Some(@lib.Version::V01),
  )
  assert_ver_low(
    "Byte-H-V01 len18",
    Array::make(18, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::H),
    Some(@lib.Version::V01),
  )
  // 同一输入换 Numeric 模式：V01-H 上限 17 → len8 合法（证明判据确实按模式走）
  assert_cap(
    "Numeric-H-V01 len8",
    Array::make(8, b'1'),
    Some(@lib.Mode::Numeric),
    Some(@lib.ECL::H),
    Some(@lib.Version::V01),
    (0, 3, 0),
  )
  // ── Byte-L-V01 上限 17 ──
  assert_cap(
    "Byte-L-V01 len17",
    Array::make(17, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    Some(@lib.Version::V01),
    (2, 0, 0),
  )
  assert_ver_low(
    "Byte-L-V01 len18",
    Array::make(18, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    Some(@lib.Version::V01),
  )
  // ── Numeric-L-V01 上限 41 / Alnum-L-V01 上限 25 ──
  assert_cap(
    "Numeric-L-V01 len41",
    Array::make(41, b'1'),
    Some(@lib.Mode::Numeric),
    Some(@lib.ECL::L),
    Some(@lib.Version::V01),
    (0, 0, 0),
  )
  assert_ver_low(
    "Numeric-L-V01 len42",
    Array::make(42, b'1'),
    Some(@lib.Mode::Numeric),
    Some(@lib.ECL::L),
    Some(@lib.Version::V01),
  )
  assert_ver_low(
    "Alnum-L-V01 len26",
    Array::make(26, b'A'),
    Some(@lib.Mode::Alphanumeric),
    Some(@lib.ECL::L),
    Some(@lib.Version::V01),
  )
  // ── 显式大版本：按该版本自身 CCI 档位复算 ──
  assert_cap(
    "Byte-L-V40 len2953",
    Array::make(2953, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    Some(@lib.Version::V40),
    (2, 0, 39),
  )
  // len2954 超出 Byte-L 全谱系上限 → 先撞 EncodedData（全局上界先于指定版本检查），
  // 与参考 `Version::get` → None → EncodedData 的短路顺序一致。
  assert_too_big(
    "Byte-L-V40 len2954",
    Array::make(2954, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::L),
    Some(@lib.Version::V40),
  )
}

///|
/// T3-d 回归 ③：超大输入的错误面（显式模式 + 显式版本）。
test "public_select_capacity_too_big_mode_aware" {
  // Byte-Q V40 上限 1663；Byte-H V40 上限 1273
  assert_too_big(
    "Byte-Q len1664",
    Array::make(1664, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::Q),
    None,
  )
  assert_cap(
    "Byte-Q len1663",
    Array::make(1663, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::Q),
    None,
    (2, 2, 39),
  )
  assert_too_big(
    "Byte-H len1274",
    Array::make(1274, b'x'),
    Some(@lib.Mode::Byte),
    Some(@lib.ECL::H),
    None,
  )
}

///|
/// T3-d 回归 ④：`QRBuilder` 链式路径与 `select_capacity` 同源（端到端消费模式）。
/// 显式 Byte + 长输入必须走 **Byte 编码器**（头 0b0100），而非被静默按 Numeric 编码。
test "public_builder_explicit_mode_uses_mode_encoder" {
  // '1' × 30：显式 Byte + ECL L → 需 V02（Byte-L-V01 上限 17）
  let r_byte = @lib.QRBuilder::from_string("111111111111111111111111111111")
    .mode(@lib.Mode::Byte)
    .ecl(@lib.ECL::L)
    .build()
  match r_byte {
    Ok(q) => {
      assert_eq(q.mode(), Some(@lib.Mode::Byte))
      assert_eq(q.version(), Some(@lib.Version::V02))
      assert_eq(q.size(), 25)
    }
    Err(_) =>
      fail(
        "qr_builder.build(id='1'*30, mode=Byte, ecl=L): got=Err want=Ok V02 byte",
      )
  }
  // 同输入改 Numeric → V01（Numeric-L-V01 上限 41）
  let r_num = @lib.QRBuilder::from_string("111111111111111111111111111111")
    .mode(@lib.Mode::Numeric)
    .ecl(@lib.ECL::L)
    .build()
  match r_num {
    Ok(q) => {
      assert_eq(q.version(), Some(@lib.Version::V01))
      assert_eq(q.size(), 21)
    }
    Err(_) =>
      fail(
        "qr_builder.build(id='1'*30, mode=Numeric, ecl=L): got=Err want=Ok V01 numeric",
      )
  }
}

///|
/// `QRCode::empty(version)`（S11 §3.1/§10.6 P1-3）：公开的「空矩阵」构造——
/// 边长由版本推导、矩阵全亮、仅 version 元数据置位，作为宿主自建矩阵的干净起点。
/// S11 v4：删除 `for_version` 别名后本函数成为**唯一**空矩阵入口（本用例锁该契约）。
test "public_qrcode_empty" {
  let qr = @lib.QRCode::empty(@lib.Version::V01)
  assert_eq(qr.size(), 21)
  assert_eq(qr.data().length(), @lib.QR_MAX_MODULES)
  let (v, ecl, mask, mode) = qr.meta()
  assert_eq(v, Some(@lib.Version::V01))
  assert_eq(ecl, None)
  assert_eq(mask, None)
  assert_eq(mode, None)
  // 全亮：抽查角点与中心，均为亮色 Data 模块
  assert_eq(qr.get(0, 0).value(), false)
  assert_eq(qr.get(10, 10).value(), false)
  assert_eq(qr.get(20, 20).value(), false)
  // 可作为「逐格自建」起点：写入一格后再输出仍成立（不改源，不可变式）
  let built = qr.set(0, 0, @lib.Module::data(true))
  assert_eq(built.get(0, 0).value(), true)
  assert_eq(qr.get(0, 0).value(), false)
  // 版本 → 边长契约（V01=21），与 Version::width() 单一事实源一致
  assert_eq(@lib.Version::V01.width(), 21)
  // 另一版本交叉校验（非法入参不存在：Version 枚举穷尽 V01..V40）
  assert_eq(
    @lib.QRCode::empty(@lib.Version::V40).size(),
    @lib.Version::V40.width(),
  )
}

///|
/// `QRCode::build_fixed` 容量失败早退（S11 §4.1/§10.6 P1-2）：指定版本装不下时
/// 必须在编码前返回 `Err(SpecifiedVersion)`，而非静默错数据。
/// 真值来源：参考 fast_qr `QRCode::new` 的 `user_version >= version` 判定
/// （Numeric-Q V01 上限 27 位，28 位需 V02 → 强制 V01 应报错）。
test "public_build_fixed_specified_version_too_small" {
  let input = Array::make(28, b'1')
  match
    @lib.QRCode::build_fixed(
      input,
      Some(@lib.Mode::Numeric),
      Some(@lib.ECL::Q),
      Some(@lib.Version::V01),
      @lib.Mask::Checkerboard,
    ) {
    Ok(_) =>
      fail(
        "qr_build.build_fixed(id='1'*28, Numeric-Q, V01): got=Ok want=Err(SpecifiedVersion)",
      )
    Err(e) =>
      if e != SpecifiedVersion {
        fail(
          "qr_build.build_fixed(id='1'*28, Numeric-Q, V01): got=Err(other) want=Err(SpecifiedVersion)",
        )
      }
  }
}

///|
/// `QRCode::build_fixed` 数据过大早退：Byte-Q 超 V40(1663) → `Err(EncodedData)`。
test "public_build_fixed_data_too_big" {
  let input = Array::make(2000, b'A')
  match
    @lib.QRCode::build_fixed(
      input,
      Some(@lib.Mode::Byte),
      Some(@lib.ECL::Q),
      None,
      @lib.Mask::Checkerboard,
    ) {
    Ok(_) =>
      fail(
        "qr_build.build_fixed(2000 bytes, Byte-Q): got=Ok want=Err(EncodedData)",
      )
    Err(e) =>
      if e != EncodedData {
        fail(
          "qr_build.build_fixed(2000 bytes, Byte-Q): got=Err(other) want=Err(EncodedData)",
        )
      }
  }
}
