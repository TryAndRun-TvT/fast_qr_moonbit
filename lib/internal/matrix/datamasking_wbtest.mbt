///|
/// datamasking 包内白盒测试：8 掩码公式 + apply_mask 只翻 Data 类模块。
/// 覆盖：各掩码在 (x,y) 数学式；apply_mask 对含功能图案的矩阵只翻转 Data 格子。

///|
test "mask_at 前 4 号掩码公式" {
  // mask 0：(x+y)%2==0
  if !mask_at(0, 0, 0) || mask_at(1, 0, 0) {
    fail("mask0: (0,0)真、(1,0)假")
  }
  // mask 1：y%2==0
  if !mask_at(0, 0, 1) || !mask_at(3, 2, 1) || mask_at(0, 1, 1) {
    fail("mask1: y 偶为真、y 奇为假")
  }
  // mask 2：x%3==0
  if !mask_at(0, 0, 2) || !mask_at(3, 5, 2) || mask_at(1, 0, 2) {
    fail("mask2: x 3 的倍数真")
  }
  // mask 3：(x+y)%3==0
  if !mask_at(1, 2, 3) || !mask_at(0, 0, 3) || mask_at(1, 1, 3) {
    fail("mask3: (x+y)%3==0")
  }
}

///|
test "mask_at 5/6/7 网格公式" {
  // mask 5：(xy)%2+(xy)%3==0。取 x=y=0 →0；x=1,y=1→1%2+1%3=1+1=2≠0 假
  if !mask_at(0, 0, 5) || mask_at(1, 1, 5) {
    fail("mask5")
  }
  // mask 6：((xy)%2+(xy)%3)%2==0。x=1,y=1 → (1+1)%2=0 真；x=0,y=0→0 真
  if !mask_at(1, 1, 6) {
    fail("mask6")
  }
  // mask 7：((x+y)%2+(xy)%3)%2==0
  if !mask_at(0, 0, 7) {
    fail("mask7 (0,0)")
  }
}

///|
test "apply_mask 只翻转 Data 类、不动功能图案明暗" {
  let size = 21
  let m = FixedArray::make(size * size, pack(1, module_type_data)) // 全 Data 暗
  // 放一个 finder 亮 + 一个 format 亮，确保它们不被翻转
  m[0] = pack(0, module_type_finder) // (0,0) finder 亮
  m[1] = pack(0, module_type_format) // (1,0) format 亮
  let masked = apply_mask(m, size, 1) // mask1: y%2==0 ⇒ 奇数行不翻
  // 原 (0,0) 与 (1,0) 都是 y=0 ⇒ mask1 真 ⇒ 若 Data 会被翻；但它们非 Data，必须保持亮
  if value_of(masked[0]) != 0 || module_type_of(masked[0]) != module_type_finder {
    fail("apply_mask 不应翻转 finder 模块")
  }
  if value_of(masked[1]) != 0 || module_type_of(masked[1]) != module_type_format {
    fail("apply_mask 不应翻转 format 模块")
  }
  // Data 暗格 (x=0,y=1)：mask1 y=1 假 ⇒ 保持暗
  if value_of(masked[1 * size + 0]) != 1 {
    fail("y=1 Data 在 mask1 下不应翻转")
  }
  // Data 暗格 (x=0,y=0 之下找 y=0 的 Data)：但 (0,0)/(1,0) 被占；看 (5,0) Data 暗，mask1 真 ⇒ 翻为亮
  if value_of(masked[0 * size + 5]) != 0 {
    fail("y=0 Data 在 mask1 下应翻为亮")
  }
}

///|
/// S9n P0：特化 `apply_mask` 与「逐格 `mask_at` 判定」参考实现**逐位等价**
/// （8 掩码 × 多尺寸 × Data/非 Data 混合矩阵）。防止步长/余数几何写错。
test "apply_mask 特化与逐格参考逐位等价" {
  let sizes : ReadOnlyArray[Int] = [21, 25, 29, 45, 57, 177]
  let mut si = 0
  while si < sizes.length() {
    let size = sizes[si]
    // 混合类型矩阵：按 (i*7+3)%9 分配类型号，覆盖 Data(0) 与 7 种功能图案，明暗交错
    let m = FixedArray::make(size * size, pack(0, module_type_data))
    let mut i = 0
    while i < size * size {
      let t = (i * 7 + 3) % 9
      let t2 = if t > 7 { module_type_data } else { t }
      m[i] = pack(i & 1, t2)
      i += 1
    }
    let mut k = 0
    while k < 8 {
      let got = apply_mask(m, size, k)
      // 参考实现：逐格 is_data_byte && mask_at → toggle
      let want = m.copy()
      let mut y = 0
      while y < size {
        let mut x = 0
        while x < size {
          let idx = y * size + x
          if is_data_byte(want[idx]) && mask_at(x, y, k) {
            want[idx] = toggle_value(want[idx])
          }
          x += 1
        }
        y += 1
      }
      let mut j = 0
      while j < size * size {
        if got[j] != want[j] {
          fail(
            "特化 apply_mask 与参考不一致：size=\{size} mask=\{k} idx=\{j}",
          )
        }
        j += 1
      }
      k += 1
    }
    si += 1
  }
}
