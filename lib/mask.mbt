///|
/// mask.mbt —— 公共掩码枚举（0-7）
/// 对应参考：fast_qr v0.14.0 `src/datamasking.rs` 的 Mask（roadmap 批次 B10）。
/// 职责：对外 API 的掩码枚举与序号映射；进入择优/强制掩码时转序号传给 internal/matrix。
/// 语义：8 种掩码，`to_int` 序号 = 掩码编号 0..=7，与数据放置公式一一对应。
/// 实现归属：本文件只承载公共枚举与序号映射；掩码图案与择优实现在
///       `lib/internal/matrix/datamasking.mbt`（图案，批次 B10）与 `score.mbt`（评分择优，S5 已落地）。

///|
/// QR 掩码图案（编号 0..=7）。`None`（自动选择）由 QRBuilder 的 `Option` 语义表达。
pub(all) enum Mask {
  /// n°0：`(x + y) % 2 == 0`
  Checkerboard
  /// n°1：`y % 2 == 0`
  HorizontalLines
  /// n°2：`x % 3 == 0`
  VerticalLines
  /// n°3：`(x + y) % 3 == 0`
  DiagonalLines
  /// n°4：`((x/3) + (y/2)) % 2 == 0`
  LargeCheckerboard
  /// n°5：`(x*y)%2 + (x*y)%3 == 0`
  Fields
  /// n°6：`((x*y)%2 + (x*y)%3) % 2 == 0`
  Diamonds
  /// n°7：`((x+y)%2 + (x*y)%3) % 2 == 0`
  Meadow
} derive(Eq, Debug)

///|
/// 掩码序号 0..=7。
pub fn Mask::to_int(self : Mask) -> Int {
  match self {
    Checkerboard => 0
    HorizontalLines => 1
    VerticalLines => 2
    DiagonalLines => 3
    LargeCheckerboard => 4
    Fields => 5
    Diamonds => 6
    Meadow => 7
  }
}

///|
/// 由序号还原掩码；越界回退到 `Meadow`（n°7）。
pub fn Mask::from_int(i : Int) -> Mask {
  match i {
    0 => Checkerboard
    1 => HorizontalLines
    2 => VerticalLines
    3 => DiagonalLines
    4 => LargeCheckerboard
    5 => Fields
    6 => Diamonds
    _ => Meadow
  }
}
