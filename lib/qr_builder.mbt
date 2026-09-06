///|
/// qr_builder.mbt —— 公共 QRBuilder 构造器
/// 对应参考：fast_qr v0.14.0 `src/qr.rs:200` QRBuilder（`lib.rs:75-80` 导出面）。
/// 职责：`QRBuilder` builder 模式——以字节/字符串输入 + 链式 setter（mode/ecl/version/mask，
///       不可变式返回新实例），`build` 委托 `QRCode::build` 单一路径完成编排。
/// 架构决策（D7）：MoonBit 用不可变链式（值语义），每个 setter 返回新 `QRBuilder`；
///       字段默认值全 `None` 交由 `QRCode::build` 的 select_capacity 语义。
/// 架构决策（D11，S8）：从 qr.mbt 拆出 QRBuilder 子关注到本文件（同包搬移、无逻辑改动），见
///       docs/S8-内部结构归位与分层-实现方案.md §3.2。结果容器/错误在 qr.mbt，编排在 qr_build.mbt。

///|
/// QR 构造器（builder 模式）。持有输入数据与可选参数，链式 setter 返回新实例。
pub(all) struct QRBuilder {
  /// 输入字节
  input : Array[Byte]
  /// 强制编码模式（None = best_encoding 自动）
  mode : Mode?
  /// 强制纠错级别（None = 默认 Q）
  ecl : ECL?
  /// 强制版本（None = 最小适配）
  version : Version?
  /// 强制掩码（None = 自动择优）
  mask : Mask?
}

///|
/// 以字节输入构造 `QRBuilder`（全部参数缺省 None，走自动）。
pub fn QRBuilder::new(input : Array[Byte]) -> QRBuilder {
  QRBuilder::{ input, mode: None, ecl: None, version: None, mask: None, }
}

///|
/// 便捷构造：以字符串输入（内部转字节数组，对齐 fast_qr `new` 的 `Into<Vec<u8>>` 泛型自由度）。
pub fn QRBuilder::from_string(s : String) -> QRBuilder {
  let input : Array[Byte] = []
  for ch in s {
    input.push(ch.to_int().to_byte())
  }
  QRBuilder::new(input)
}

///|
/// 强制编码模式（不可变式：返回新 `QRBuilder`）。
pub fn QRBuilder::mode(self : QRBuilder, m : Mode) -> QRBuilder {
  QRBuilder::{
    input: self.input,
    mode: Some(m),
    ecl: self.ecl,
    version: self.version,
    mask: self.mask,
  }
}

///|
/// 强制纠错级别（不可变式：返回新 `QRBuilder`）。
pub fn QRBuilder::ecl(self : QRBuilder, e : ECL) -> QRBuilder {
  QRBuilder::{
    input: self.input,
    mode: self.mode,
    ecl: Some(e),
    version: self.version,
    mask: self.mask,
  }
}

///|
/// 强制版本（不可变式：返回新 `QRBuilder`）。
pub fn QRBuilder::version(self : QRBuilder, v : Version) -> QRBuilder {
  QRBuilder::{
    input: self.input,
    mode: self.mode,
    ecl: self.ecl,
    version: Some(v),
    mask: self.mask,
  }
}

///|
/// 强制掩码（不可变式：返回新 `QRBuilder`）。
pub fn QRBuilder::mask(self : QRBuilder, m : Mask) -> QRBuilder {
  QRBuilder::{
    input: self.input,
    mode: self.mode,
    ecl: self.ecl,
    version: self.version,
    mask: Some(m),
  }
}

///|
/// 计算并返回 `QRCode`。直接委托 `QRCode::build(input, mode, ecl, version, mask)`，
/// 缺省字段以 `None` 进入 `select_capacity` 语义（mode 自动 / ecl 默认 Q / version 最小 / mask 择优）。
pub fn QRBuilder::build(self : QRBuilder) -> Result[QRCode, QRCodeError] {
  QRCode::build(self.input, self.mode, self.ecl, self.version, self.mask)
}
