///|
/// ecl.mbt —— 纠错级别（ECL：L / M / Q / H）
/// 对应参考：fast_qr v0.14.0 `src/ecl.rs`（roadmap 批次 B1）
/// 职责：对外 ECL 枚举与序号映射；作为容量选择与查表的第一参数。
/// 语义：与 Rust 变体顺序一致（L/M/Q/H），`to_int` 序号 L=0/M=1/Q=2/H=3；
///       默认纠错级别为 Quartile（Q），供 QRBuilder 缺省时选用。

///|
/// 纠错级别（ECL）。共四级，对应 ISO/IEC 18004 纠错容量：
/// L=7%、M=15%、Q=25%、H=30%。
pub(all) enum ECL {
  /// Low，7% —— 纠错最弱、容量最大
  L
  /// Medium，15%
  M
  /// Quartile，25%（fast_qr 默认级别）
  Q
  /// High，30% —— 纠错最强、容量最小
  H
} derive(Eq, Debug)

///|
/// 纠错级别的序号（0..=3，按 L/M/Q/H 顺序）。
/// 供容量/分组查表的第一维使用，与 Rust 变体判别值一致。
pub fn ECL::to_int(self : ECL) -> Int {
  match self {
    L => 0
    M => 1
    Q => 2
    H => 3
  }
}

///|
/// 由序号还原纠错级别；越界回退为 `H`（最高纠错）。
pub fn ECL::from_int(i : Int) -> ECL {
  match i {
    0 => L
    1 => M
    2 => Q
    _ => H
  }
}

///|
/// 纠错级别在字符串输出中对应的字符（供 Display/to_str 使用）。
pub fn ECL::to_char(self : ECL) -> Char {
  match self {
    L => 'L'
    M => 'M'
    Q => 'Q'
    H => 'H'
  }
}
