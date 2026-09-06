///|
/// encode.mbt —— 数据编码（Numeric / Alphanumeric / Byte）
/// 对应参考：fast_qr v0.14.0 `src/encode.rs`（roadmap 批次 B7）
/// 职责：三模式编码写入位流缓冲；best_encoding 自动回退（Numeric→Alnum→Byte）；
///       terminator + 8 位对齐 + fill 占位（[236,17]）。
/// 关键语义：Numeric 3 位一组 10bit、Alnum 2 字符 11bit、Byte 直拷字节（framework §五.9）。
/// 所在包：internal/data_encoding（roadmap 批次 B7）。
/// 依赖规则：不依赖 lib 公共包；mode/ecl/version 以序号（Int）入参；依赖 internal/constants
///       （cci_bits/data_bits/max_bytes）与 internal/bitstream（CompactQR）。无环。
/// 产物：`encode` 返回 `CompactQR`，其 `data` 第 0..data_bits 位是 S4 reedsolomon.structure
///       的直接输入（放置层契约，见 S3 方案 §3.6）。
/// 对外（供 B8 / S4 调用，白盒 `_wbtest` 访问）：encode / encode_numeric / encode_alphanumeric /
///       encode_byte / best_encoding / ascii_to_alphanumeric / is_qr_alphanumeric。
/// 私有（encode.mbt 内部）：add_terminator / pad_to_8 / ascii_to_digit。

///|
/// 按模式编码并做收尾：写模式头+CCI+数据 → terminator → pad_to_8 → fill 占位。
/// 对应参考 `encode.rs::encode`。
/// 入参均为序号：mode_idx 0/1/2（Numeric/Alnum/Byte）、ecl_idx 0..=3、version_idx 0..=39。
pub fn encode(
  input : Array[Byte],
  ecl_idx : Int,
  mode_idx : Int,
  version_idx : Int,
) -> @bitstream.CompactQR {
  let cci = @constants.cci_bits(version_idx, mode_idx)
  let compact = @bitstream.CompactQR::from_version(version_idx)
  match mode_idx {
    0 => encode_numeric(compact, input, cci)
    1 => encode_alphanumeric(compact, input, cci)
    _ => encode_byte(compact, input, cci)
  }
  let dbits = @constants.data_bits(ecl_idx, version_idx)
  add_terminator(compact, dbits)
  pad_to_8(compact)
  compact.fill()
  compact
}

///|
/// 找最优编码模式：先试 Numeric（全 digit）、否则试 Alnum（全 is_qr_alphanumeric）、
/// 否则 Byte。返回序号 0/1/2。对应参考 `encode.rs::best_encoding`。
pub fn best_encoding(input : Array[Byte]) -> Int {
  // 试 Numeric
  let mut numeric_ok = true
  for c in input {
    if !digit(c) {
      numeric_ok = false
      break
    }
  }
  if numeric_ok {
    return 0
  }
  // 试 Alnum
  let mut alnum_ok = true
  for c in input {
    if !is_qr_alphanumeric(c) {
      alnum_ok = false
      break
    }
  }
  if alnum_ok {
    return 1
  }
  // 否则 Byte
  2
}

///|
/// Numeric 编码：模式头(0b0001,4) → CCI → 每 3 位 ASCII→digit 合成 10bit 数；
/// 余 1 位写 4bit、余 2 位写 7bit。对应参考 `encode.rs::encode_numeric`。
pub fn encode_numeric(
  compact : @bitstream.CompactQR,
  input : Array[Byte],
  cci_bits : Int,
) -> Unit {
  compact.push_bits(0b0001, 4)
  compact.push_bits(input.length(), cci_bits)

  let group = input.length() / 3 * 3
  let mut i = 0
  while i < group {
    let number = ascii_to_digit(input[i]) * 100 +
      ascii_to_digit(input[i + 1]) * 10 +
      ascii_to_digit(input[i + 2])
    compact.push_bits(number, 10)
    i += 3
  }

  // 剩余不足 3 位：拼成一个数，按余数写 4bit(余1) / 7bit(余2)
  let rem = input.length() - group
  if rem == 1 {
    compact.push_bits(ascii_to_digit(input[i]), 4)
  } else if rem == 2 {
    let number = ascii_to_digit(input[i]) * 10 + ascii_to_digit(input[i + 1])
    compact.push_bits(number, 7)
  }
}

///|
/// Alphanumeric 编码：模式头(0b0010,4) → CCI → 每 2 字符 `a*45+b` 写 11bit；
/// 单余字符写 6bit。对应参考 `encode.rs::encode_alphanumeric`。
pub fn encode_alphanumeric(
  compact : @bitstream.CompactQR,
  input : Array[Byte],
  cci_bits : Int,
) -> Unit {
  compact.push_bits(0b0010, 4)
  compact.push_bits(input.length(), cci_bits)

  let even = input.length() - input.length() % 2
  let mut i = 0
  while i < even {
    let a = ascii_to_alphanumeric(input[i])
    let b = ascii_to_alphanumeric(input[i + 1])
    compact.push_bits(a * 45 + b, 11)
    i += 2
  }
  if even != input.length() {
    compact.push_bits(ascii_to_alphanumeric(input[i]), 6)
  }
}

///|
/// Byte 编码：模式头(0b0100,4) → CCI → 直拷输入字节。
/// 对应参考 `encode.rs::encode_byte`。
pub fn encode_byte(
  compact : @bitstream.CompactQR,
  input : Array[Byte],
  cci_bits : Int,
) -> Unit {
  compact.push_bits(0b0100, 4)
  compact.push_bits(input.length(), cci_bits)
  compact.push_u8_slice(input)
}

///|
/// 加终止符：把长度推到数据码字区上限以内，最多补 4 个 0。
/// 对应参考 `encode.rs::add_terminator`。
fn add_terminator(compact : @bitstream.CompactQR, data_bits : Int) -> Unit {
  let need = data_bits - compact.len()
  let pad = if need < 4 { need } else { 4 }
  if pad > 0 {
    compact.push_bits(0, pad)
  }
}

///|
/// 对齐到字节边界。对应参考 `encode.rs::pad_to_8`。
fn pad_to_8(compact : @bitstream.CompactQR) -> Unit {
  let pad = (8 - compact.len() % 8) % 8
  if pad > 0 {
    compact.push_bits(0, pad)
  }
}

///|
/// ASCII 数字字符 → 数值（`'5'` → 5）。调用方保证字符为数字。
fn ascii_to_digit(c : Byte) -> Int {
  c.to_int() - 48 // b'0' = 48
}

///|
/// 是否为 ASCII 数字。
fn digit(c : Byte) -> Bool {
  let b = c.to_int()
  b >= 48 && b <= 57
}

///|
/// ASCII alnum 字符 → 45 进值：`0-9`→0..9、`A-Z`→10..35、` `→36 `$`→37
/// `%`→38 `*`→39 `+`→40 `-`→41 `.`→42 `/`→43 `:`→44。对应参考 `encode.rs::ascii_to_alphanumeric`。
pub fn ascii_to_alphanumeric(c : Byte) -> Int {
  let b = c.to_int()
  if b >= 48 && b <= 57 {
    b - 48
  } else if b >= 65 && b <= 90 {
    b - 65 + 10
  } else {
    match b {
      32 => 36 // ' '
      36 => 37 // '$'
      37 => 38 // '%'
      42 => 39 // '*'
      43 => 40 // '+'
      45 => 41 // '-'
      46 => 42 // '.'
      47 => 43 // '/'
      58 => 44 // ':'
      _ => abort("unexpected char in Alphanumeric mode: " + b.to_string())
    }
  }
}

///|
/// 是否为 QR alphanumeric 字符（0-9 / A-Z / 空格 / $%*+-./:）。
/// 对应参考 `encode.rs::is_qr_alphanumeric`。
pub fn is_qr_alphanumeric(c : Byte) -> Bool {
  let b = c.to_int()
  (b >= 48 && b <= 57) ||
  (b >= 65 && b <= 90) ||
  b == 32 ||
  b == 36 ||
  b == 37 ||
  b == 38 ||
  b == 43 ||
  b == 45 ||
  b == 46 ||
  b == 47 ||
  b == 58
}
