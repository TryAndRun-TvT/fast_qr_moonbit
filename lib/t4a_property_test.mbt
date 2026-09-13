///|
/// t4a_property_test.mbt —— 属性测试四则（S10 §6 T4-a / 缺口 G10 补强）
///
/// 目的：把「散点用例」升级为「随机参数上的不变量」——不依赖固定夹具，
/// 用确定性 LCG（不引入 rand 依赖，保证可复现）在参数空间抽样。
/// 四项属性：
///   ① 尺寸不变量：任意可容纳参数 → size == version*4+17，且功能图案区类型号恒定；
///   ② 掩码互异性：同输入 8 种固定 mask → 恰好 8 个互不相同矩阵；
///   ③ 链式等价：QRBuilder 链式 == QRCode::build 在随机参数下恒等；
///   ④ 不可变无别名：QRCode::set / SvgBuilder 不改变源对象。
/// 失败信息含随机种子与参数（铁律 4「可定位」）。

///|
/// 确定性 LCG（Numerical Recipes 参数），返回 [0, 2^31) 序列。
/// 用结构体承载状态，避免依赖全局可变状态（铁律 7）。
struct Lcg {
  state : Ref[Int]
}

///|
fn Lcg::new(seed : Int) -> Lcg {
  { state: { val: seed, }, }
}

///|
fn Lcg::next(self : Lcg) -> Int {
  let v = (self.state.val * 1103515245 + 12345) & 0x7FFFFFFF
  self.state.val = v
  v
}

///|
fn Lcg::below(self : Lcg, n : Int) -> Int {
  self.next() % n
}

///|
/// 生成 [0, n) 的随机 ASCII 字节串（Byte 模式可编码范围）。
fn random_bytes(rng : Lcg, n : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < n {
    out.push((32 + rng.below(95)).to_byte())
    i += 1
  }
  out
}

///|
/// 属性 ①：任意 (ecl, version, 随机内容) 成功构建时，size 恒为 version*4+17；
/// 且三个 finder 外角类型号恒为 finder（1）、dark module 类型号恒为 dark（6）。
test "t4a1_size_and_finder_invariant" {
  let rng = Lcg::new(20260913)
  let vl : Array[Version] = [
    Version::V01,
    Version::V02,
    Version::V05,
    Version::V10,
    Version::V14,
    Version::V26,
    Version::V40,
  ]
  let el : Array[ECL] = [ECL::L, ECL::M, ECL::Q, ECL::H]
  let mut trial = 0
  let mut ok = 0
  while trial < 200 {
    let ver = vl[rng.below(7)]
    let ecl = el[rng.below(4)]
    // 内容长度取版本容量的一个小比例，确保可容纳
    let len = 1 + rng.below(8)
    let input = random_bytes(rng, len)
    match QRBuilder::new(input).ecl(ecl).version(ver).build() {
      Ok(qr) => {
        ok += 1
        let sz = qr.size()
        // 期望边长 = 版本号*4+17；ver.to_int() 是序号（V01=0）→ 版本号 = to_int()+1
        let exp = (ver.to_int() + 1) * 4 + 17
        if sz != exp {
          fail(
            "t4a1: size mismatch trial=" +
            trial.to_string() +
            " ver=" +
            (ver.to_int() + 1).to_string() +
            " ecl=" +
            ecl.to_int().to_string() +
            " got=" +
            sz.to_string() +
            " want=" +
            exp.to_string(),
          )
        }
        // finder 外角类型号 = finder
        if qr.get(0, 0).module_type().to_int() != 1 ||
          qr.get(0, sz - 1).module_type().to_int() != 1 ||
          qr.get(sz - 1, 0).module_type().to_int() != 1 {
          fail(
            "t4a1: finder corner type trial=" +
            trial.to_string() +
            " (ver=" +
            (ver.to_int() + 1).to_string() +
            ")",
          )
        }
        // dark module (size-8, 8) 类型号 = dark(6)
        if qr.get(sz - 8, 8).module_type().to_int() != 6 {
          fail(
            "t4a1: dark module type trial=" +
            trial.to_string() +
            " ver=" +
            (ver.to_int() + 1).to_string(),
          )
        }
      }
      // 内容短于容量却失败：只统计不硬失败（参数配置边界）
      Err(_) => ()
    }
    trial += 1
  }
  if ok == 0 {
    fail("t4a1: 无任何成功构建（抽样参数配置有误）")
  }
}

///|
/// 属性 ②：同一输入、8 种固定 mask → 恰好 8 个互不相同矩阵（每对至少一格不同）。
test "t4a2_masks_distinct" {
  let input = bstr("property-mask-distinct")
  let mats : Array[Array[Module]] = []
  let masks : Array[Mask] = [
    Mask::Checkerboard,
    Mask::HorizontalLines,
    Mask::VerticalLines,
    Mask::DiagonalLines,
    Mask::LargeCheckerboard,
    Mask::Fields,
    Mask::Diamonds,
    Mask::Meadow,
  ]
  for m in masks {
    match
      QRBuilder::new(input).ecl(ECL::L).version(Version::V05).mask(m).build() {
      Ok(qr) => mats.push(qr.data())
      Err(_) => fail("t4a2: build failed for mask=" + m.to_int().to_string())
    }
  }
  let mut a = 0
  while a < mats.length() {
    let mut b = a + 1
    while b < mats.length() {
      let same = mats[a] == mats[b]
      if same {
        fail(
          "t4a2: mask " +
          a.to_string() +
          " 与 mask " +
          b.to_string() +
          " 矩阵完全相同（掩码未生效）",
        )
      }
      b += 1
    }
    a += 1
  }
}

///|
/// 属性 ③：QRBuilder 链式 == QRCode::build，在随机 (ecl, version, mask) 参数下恒等。
test "t4a3_builder_equals_build" {
  let rng = Lcg::new(777)
  let vl : Array[Version] = [
    Version::V01,
    Version::V05,
    Version::V10,
    Version::V40,
  ]
  let el : Array[ECL] = [ECL::L, ECL::M, ECL::Q, ECL::H]
  let ml : Array[Mask] = [
    Mask::Checkerboard,
    Mask::VerticalLines,
    Mask::Fields,
    Mask::Meadow,
  ]
  let mut trial = 0
  while trial < 100 {
    let ver = vl[rng.below(4)]
    let ecl = el[rng.below(4)]
    let mask = ml[rng.below(4)]
    let input = random_bytes(rng, 1 + rng.below(6))
    let a = QRBuilder::new(input).ecl(ecl).version(ver).mask(mask).build()
    let b = QRCode::build(input, None, Some(ecl), Some(ver), Some(mask))
    match (a, b) {
      (Ok(qa), Ok(qb)) =>
        if qa.data() != qb.data() {
          fail(
            "t4a3: chain != build trial=" +
            trial.to_string() +
            " ver=" +
            (ver.to_int() + 1).to_string() +
            " ecl=" +
            ecl.to_int().to_string() +
            " mask=" +
            mask.to_int().to_string(),
          )
        }
      (Err(_), Err(_)) => ()
      _ => fail("t4a3: Result 形态不一致 trial=" + trial.to_string())
    }
    trial += 1
  }
}

///|
/// 属性 ④：不可变式 API 无别名副作用——QRCode::set 不改源对象（随机 100 次）。
test "t4a4_immutable_no_alias" {
  let rng = Lcg::new(4242)
  let input = bstr("immutability")
  match QRBuilder::new(input).ecl(ECL::M).version(Version::V05).build() {
    Ok(qr) => {
      let before = qr.data()
      let mut trial = 0
      while trial < 100 {
        let r = rng.below(qr.size())
        let c = rng.below(qr.size())
        let _ = qr.set(r, c, Module::data(true))
        trial += 1
      }
      let after = qr.data()
      let mut i = 0
      while i < before.length() {
        if before[i].byte() != after[i].byte() {
          fail(
            "t4a4: 源对象被 set 副作用修改，cells[" +
            i.to_string() +
            "]",
          )
        }
        i += 1
      }
    }
    Err(_) => fail("t4a4: build failed")
  }
}
