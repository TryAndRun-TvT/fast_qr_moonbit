///|
/// mode.mbt —— 公共编码模式枚举（Numeric / Alphanumeric / Byte）
/// 对应参考：fast_qr v0.14.0 `src/encode.rs` 的 Mode（roadmap 批次 B7 骨架）
/// 职责：对外 API 的模式枚举与序号映射；编码进入内部时按序号选择编码路径。
/// 语义：`to_int` 序号 Numeric=0/Alphanumeric=1/Byte=2（与 Rust 变体顺序一致）；
///       S1 仅建骨架 + 序号映射，编码逻辑随批次 B7 落地。

///|
/// 数据编码模式（Kanji 模式暂不支持，见 fast_qr 说明）。
pub(all) enum Mode {
  /// 数字模式（仅 0-9）
  Numeric
  /// 字母数字模式（0-9、A-Z、$%*./:+-?.= 与空格）
  Alphanumeric
  /// 字节模式（任意）
  Byte
} derive(Eq, Debug)

///|
/// 模式序号：Numeric=0 / Alphanumeric=1 / Byte=2。
pub fn Mode::to_int(self : Mode) -> Int {
  match self {
    Numeric => 0
    Alphanumeric => 1
    Byte => 2
  }
}

///|
/// 由序号还原模式；越界回退到 `Byte`（最通用）。
pub fn Mode::from_int(i : Int) -> Mode {
  match i {
    0 => Numeric
    1 => Alphanumeric
    _ => Byte
  }
}
