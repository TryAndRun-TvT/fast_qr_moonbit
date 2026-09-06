///|
/// s7_terminal_test.mbt —— S7 终端画 to_str 全串字节对齐（黑盒 _test.mbt）
/// 基准：fast_qr v0.14.0 `s7term` 例程对同一 (content, mode, ecl, version, mask) 经 QRCode::build
///       产出的 `to_str()` 参考**全串**（参考用 Rust 生成，禁止手抄）。本仓库 build 路径已在 S4/S6
///       快照逐位对齐参考矩阵，故同参 to_str 全串应逐字节一致。
/// 覆盖：T1=V01 短码、T2=V05（含对齐/时序/finder 多图案）真实 QR 终端画 + 受控 7x7 小矩阵
///       （TERMMINI，锁边距/末行/四态映射细节）。
fn hi_input() -> Array[Byte] {
  let r : Array[Byte] = []
  for ch in "hi" {
    r.push(ch.to_int().to_byte())
  }
  r
}

///|
/// c1 = "HELLO WORLD 1234567890 ABCDEFGHIJKLMNOP"（Byte L V05）。
fn hello_input() -> Array[Byte] {
  let r : Array[Byte] = []
  for ch in "HELLO WORLD 1234567890 ABCDEFGHIJKLMNOP" {
    r.push(ch.to_int().to_byte())
  }
  r
}

///|
/// 构造 7x7 受控矩阵：置暗格集合与参考 mini 例程一致（其余亮）。
fn mini7() -> QRCode {
  let qr = QRCode::default(7)
  let dark : Array[(Int, Int)] = [
    (0, 0),
    (0, 1),
    (0, 6),
    (1, 0),
    (1, 3),
    (1, 5),
    (2, 2),
    (2, 4),
    (3, 3),
    (3, 6),
    (4, 0),
    (4, 2),
    (4, 4),
    (4, 6),
    (5, 1),
    (5, 5),
    (6, 0),
    (6, 3),
    (6, 6),
  ]
  let mut m = qr
  for cell in dark {
    let (r, c) = cell
    m = m.set(r, c, Module::data(true))
  }
  m
}

///|
/// T1：真实 V01 短码 to_str 全串对齐（Byte/L/V01/mask0）。
test "s7_term_t1_v01" {
  let qr = match
    QRCode::build(
      hi_input(),
      Some(Mode::Byte),
      Some(ECL::L),
      Some(Version::V01),
      Some(Mask::Checkerboard),
    ) {
    Ok(q) => q
    Err(_) => abort("t1 build")
  }
  let want = "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄\n█ ▄▄▄▄▄ ███▄█ █ ▄▄▄▄▄ █\n█ █   █ █▄█▄█▀█ █   █ █\n█ █▄▄▄█ ██ ▀ ▄█ █▄▄▄█ █\n█▄▄▄▄▄▄▄█ █ █▄█▄▄▄▄▄▄▄█\n█▄  █▄▄▄ ▄█ ▀▄ ▄▀█▀ ▀▀█\n██▄  ▄▄▄▄▄▄█ ▀ ▄ ▀ ▄ ▄█\n█▄██▄█▄▄█ █ ▄█▄ ▄██ ▀▀█\n█ ▄▄▄▄▄ █   █▄█▀█▄█▀  █\n█ █   █ █▄ █▀▄▀▄▀▄▀▄▀▄█\n█ █▄▄▄█ █  ▄ ▀ ▄ ▀ ▄▀▄█\n█▄▄▄▄▄▄▄█▄██▄█▄▄▄█▄▄▄▄█"
  if qr.to_str() != want {
    fail("t1 to_str mismatch")
  }
}

///|
/// T2：真实 V05 长码 to_str 全串对齐（Byte/L/V05/mask3，含对齐/时序/finder 多图案）。
test "s7_term_t2_v05" {
  let qr = match
    QRCode::build(
      hello_input(),
      Some(Mode::Byte),
      Some(ECL::L),
      Some(Version::V05),
      Some(Mask::DiagonalLines),
    ) {
    Ok(q) => q
    Err(_) => abort("t2 build")
  }
  let want = "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄\n█ ▄▄▄▄▄ █▄▄████▀ ▄▀▄▀ ▄███ ▀▄ █ ▄▄▄▄▄ █\n█ █   █ █ ▀█ ▄▄▄▄▀█ ▀ ▀█ ▄▄▀█▄█ █   █ █\n█ █▄▄▄█ █▄ ▄▄▀▄▀██▀ ▀  ▄▄▀▄▄█ █ █▄▄▄█ █\n█▄▄▄▄▄▄▄█▄▀▄▀▄▀ █▄█▄█ ▀▄▀▄█▄█▄█▄▄▄▄▄▄▄█\n█ ▄ ▄██▄█▄▀███▄▄▀ █ ▄▀▀███ ▄   ██▄ ▄█▄█\n█ ▄▄█ ▄▄█ █ ▀▀▀  █▄▀▄ ██▀▀▀█▀▄▀▀██▀▀ ▀█\n█ ██▀▀▄▄▀▀   █▀██▄█ ▄  ▀ █▀ ▄▀█ ▄ ▀█ ██\n█ ▄▄▀▀█▄ ▄▄▄█ ▀▄▀█  ▄▄▄██ ▄ █ █ ▀█▄█▄▀█\n█▄▀█▄▀▄▄  ▄█▄▀▀███▄▄▀ █ ▄▀████ ▀ █▀██▄█\n█▀█▄  ▀▄█▄ ▀▄ ██▀▀▀  █▄▀▄ ▄ ▄ ██▀▀▀▄ ▄█\n█▀▄█▀▀▀▄▄█▄█▄  ▀ █▀██▄█ ▄  ▄▀ ▀██▄ ▄▄ █\n█▀▄▄▀█▀▄█▀██▄▄▄██ ▀▄▀█  ▄▄ ▀██▄█ █▀ ▀██\n██▀▄█▄▄▄▀▄ █▀ █ ▄▀▀███▄▄▀ █▄▄▀▀ ▄  ▀ ▄█\n█▀▄▄█▀█▄█▄ ▀ █▄▀▄ ██▀▀▀  █▄████▀▄▄█▄▄▀█\n██████▄▄█ ▄ █▄█ ▄  ▀ █▀██▄█▄█ ▄▄▄ ▀▀▄▄█\n█ ▄▄▄▄▄ ██▀▀▀█  ▄▄▄██ ▀▄▀█    █▄█ ▄█▄ █\n█ █   █ █▀ ███▄▄▀ █ ▄▀▀███▄▄▀     ▀█▄██\n█ █▄▄▄█ █ ▄ ▀▀▀  █▄▀▄ ██▀▀▀ █▀▄██▄█▀▄██\n█▄▄▄▄▄▄▄█▄██▄████▄█▄▄▄▄█▄█████▄▄███▄▄▄█"
  if qr.to_str() != want {
    fail("t2 to_str mismatch")
  }
}

///|
/// TERMMINI：受控 7x7 小矩阵 to_str 全串对齐（锁边距两行合一/四态/末行细节）。
test "s7_term_mini7" {
  let m = mini7()
  let want = "▄▄▄▄▄▄▄▄▄\n█ ▄█▀█▀▄█\n███▄▀▄█▀█\n█▄▀▄█▄▀▄█\n█▄██▄██▄█"
  if m.to_str() != want {
    fail("mini terminal mismatch")
  }
}

///|
/// 委托护栏：QRCode::to_str() 恒等于顶层 print_matrix_with_margin()。
test "s7_term_delegate_guard" {
  let qr = match
    QRCode::build(
      hi_input(),
      Some(Mode::Byte),
      Some(ECL::L),
      Some(Version::V01),
      Some(Mask::Checkerboard),
    ) {
    Ok(q) => q
    Err(_) => abort("delegate build")
  }
  if qr.to_str() != print_matrix_with_margin(qr) {
    fail("to_str != print_matrix_with_margin")
  }
}
