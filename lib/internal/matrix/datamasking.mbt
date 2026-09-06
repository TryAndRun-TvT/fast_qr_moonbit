///|
/// datamasking.mbt —— 8 种掩码图案（S4 B9b 前半，随 S4 落；评分择优留 S5）
/// 对应参考：fast_qr v0.14.0 `src/datamasking.rs`（roadmap 批次 B10 前半）
/// 职责：按 8 种 ISO/IEC 18004 掩码数学式，对矩阵中**只 Data 类模块**逐格判定是否翻转。
/// 关键语义：
///   - 掩码公式输入为模块坐标 (x=列, y=行)，true ⇒ 该 Data 模块 `toggle`（明暗翻转）；
///   - 功能图案（finder/timing/alignment/format/version/dark/empty）**不参与**掩码（不翻转）；
///   - 掩码 5/6 用 (x*y)%2 与 (x*y)%3；7 用 (x+y)%2 与 (x*y)%3（公式见下表，与 lib Mask 枚举注释一致）。
/// 所在包：internal/matrix；不依赖 lib，掩码以序号（Int）入参。

///|
/// 8 种掩码在 (x,y) 处是否置暗（true ⇒ 翻转该 Data 模块）。掩码号 0..=7。
/// ISO/IEC 18004 表 10：
///   0  Checkerboard      (x+y)%2==0
///   1  HorizontalLines   y%2==0
///   2  VerticalLines     x%3==0
///   3  DiagonalLines     (x+y)%3==0
///   4  LargeCheckerboard (x//3 + y//2)%2==0
///   5  Fields            (x*y)%2 + (x*y)%3 == 0
///   6  Diamonds          ((x*y)%2 + (x*y)%3) % 2 == 0
///   7  Meadow            ((x+y)%2 + (x*y)%3) % 2 == 0
pub fn mask_at(x : Int, y : Int, mask_idx : Int) -> Bool {
  match mask_idx {
    0 => (x + y) % 2 == 0
    1 => y % 2 == 0
    2 => x % 3 == 0
    3 => (x + y) % 3 == 0
    4 => (x / 3 + y / 2) % 2 == 0
    5 => x * y % 2 + x * y % 3 == 0
    6 => (x * y % 2 + x * y % 3) % 2 == 0
    _ => ((x + y) % 2 + x * y % 3) % 2 == 0
  }
}

///|
/// 对整张矩阵应用掩码 mask_idx：只翻转「Data 类模块 且 公式为 true」的格子。
/// 返回新矩阵（不可变式），不原地改源。
pub fn apply_mask(m : Array[Int], size : Int, mask_idx : Int) -> Array[Int] {
  let out = m.copy()
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      let idx = y * size + x
      if is_data_byte(out[idx]) && mask_at(x, y, mask_idx) {
        out[idx] = toggle_value(out[idx])
      }
      x += 1
    }
    y += 1
  }
  out
}
