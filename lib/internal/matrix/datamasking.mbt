///|
/// datamasking.mbt —— 8 种掩码图案（S4 B9b 前半，随 S4 落；评分择优留 S5）
/// 对应参考：fast_qr v0.14.0 `src/datamasking.rs`（roadmap 批次 B10 前半）
/// 职责：按 8 种 ISO/IEC 18004 掩码数学式，对矩阵中**只 Data 类模块**逐格判定是否翻转。
/// 关键语义：
///   - 掩码公式输入为模块坐标 (x=列, y=行)，true ⇒ 该 Data 模块 `toggle`（明暗翻转）；
///   - 功能图案（finder/timing/alignment/format/version/dark/empty）**不参与**掩码（不翻转）；
///   - 掩码 5/6 用 (x*y)%2 与 (x*y)%3；7 用 (x+y)%2 与 (x*y)%3（公式见下表，与 lib Mask 枚举注释一致）。
/// 性能（S9n P0 落地，2026-09-12）：`apply_mask` 不再逐格 `match` + 取模，而是按掩码号分派到
///   8 个**特化循环**（对照 fast_qr `datamasking.rs`）：
///   - 0–4 号用步长几何直接生成候选格（无每格 `match`、无每格 `%`）；
///   - 5–7 号利用公式对 x 的周期为 6，逐行只算 6 个余数判定，再按余数步进 6 生成候选格。
///   语义与旧实现**逐位等价**（保留 `mask_at` 供白盒/防御，见 datamasking_wbtest 对拍）。
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
/// 若 (y,x) 在界内且为 Data 模块，则翻转其明暗位（就地）。功能图案不翻。
fn toggle_data_at(m : FixedArray[Int], size : Int, y : Int, x : Int) -> Unit {
  if x < 0 || x >= size {
    return
  }
  let idx = y * size + x
  if is_data_byte(m[idx]) {
    m[idx] = toggle_value(m[idx])
  }
}

///|
/// 掩码 0：x%2 == y%2 ⇒ 每行从 `y&1` 起隔 2 列（≈½ 格）。
fn mask_0(m : FixedArray[Int], size : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut x = y & 1
    while x < size {
      toggle_data_at(m, size, y, x)
      x += 2
    }
    y += 1
  }
}

///|
/// 掩码 1：y%2==0 ⇒ 只扫偶数行（≈½ 格）。
fn mask_1(m : FixedArray[Int], size : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      toggle_data_at(m, size, y, x)
      x += 1
    }
    y += 2
  }
}

///|
/// 掩码 2：x%3==0 ⇒ 每行取 0,3,6,… 列（≈⅓ 格）。
fn mask_2(m : FixedArray[Int], size : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      toggle_data_at(m, size, y, x)
      x += 3
    }
    y += 1
  }
}

///|
/// 掩码 3：x ≡ -y (mod 3) ⇒ 起始列 `(3 - y%3)%3`、步长 3（≈⅓ 格）。
fn mask_3(m : FixedArray[Int], size : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut x = (3 - y % 3) % 3
    while x < size {
      toggle_data_at(m, size, y, x)
      x += 3
    }
    y += 1
  }
}

///|
/// 掩码 4：(x/3 + y/2)%2==0 ⇒ 每行按 `floor(x/3)` 奇偶取连续 3 列块，周期 6（≈½ 格）。
fn mask_4(m : FixedArray[Int], size : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut x = y / 2 % 2 * 3
    while x < size {
      toggle_data_at(m, size, y, x)
      toggle_data_at(m, size, y, x + 1)
      toggle_data_at(m, size, y, x + 2)
      x += 6
    }
    y += 1
  }
}

///|
/// 掩码 5/6/7：公式对 x 的周期为 6（只依赖 x%2 与 x%3），故逐行只对余数 0..5 判定，
/// 命中余数按步长 6 生成候选格——避免每格取模与 `match`，且只访问命中格。
fn mask_period6(m : FixedArray[Int], size : Int, mask_idx : Int) -> Unit {
  let mut y = 0
  while y < size {
    let mut r = 0
    while r < 6 {
      if mask_at(r, y, mask_idx) {
        let mut x = r
        while x < size {
          toggle_data_at(m, size, y, x)
          x += 6
        }
      }
      r += 1
    }
    y += 1
  }
}

///|
/// 对整张矩阵应用掩码 mask_idx：只翻转「Data 类模块 且 公式为 true」的格子。
/// 返回新矩阵（不可变式），不原地改源。按掩码号分派到特化循环（S9n P0），语义与逐格判定等价。
///
/// **前置不变式**：`mask_idx ∈ 0..=7`（二维码只有 8 种掩码）。
/// 越界为编程错误，`_` 分支改 **`abort` 护栏**（S11 §4.1/§10.6 P1-1）——原先的
/// `apply_mask_general` 逐格回退是「不可达兜底」，删除后把不变式变成**机器可查**：
/// 若未来有调用方越界，会在开发/测试期立刻暴露，而不是静默沿用掩码 7 公式。
pub fn apply_mask(
  m : FixedArray[Int],
  size : Int,
  mask_idx : Int,
) -> FixedArray[Int] {
  let out = m.copy()
  match mask_idx {
    0 => mask_0(out, size)
    1 => mask_1(out, size)
    2 => mask_2(out, size)
    3 => mask_3(out, size)
    4 => mask_4(out, size)
    5 | 6 | 7 => mask_period6(out, size, mask_idx)
    _ => abort("apply_mask: mask_idx out of range 0..=7")
  }
  out
}
