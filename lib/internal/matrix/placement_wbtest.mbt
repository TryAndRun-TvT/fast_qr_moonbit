///|
/// placement 包内白盒测试：之字形放置位序 / 跳过功能模块 / 总装产物自洽。
/// 语义护栏：放置位按大端序、只写 Data 类、跳第 6 列与功能图案；
///       逆序读回应还原喂入的码字位流（等价参考 placement.rs 的遍历序）。
/// 介质：原始字节矩阵 packed = 明暗|类型<<1（见本包 module.mbt）。

///|
/// 在 V1(size 21) 空功能矩阵喂 26 字节全 0xFF（208 位全 1），
/// 断言所有 Data 模块置暗、功能模块未被改写、总 Data 数 = 208。
test "place_on_matrix_data: 全 1 填满 Data 且不碰功能图案" {
  let m = create_matrix(0) // V01, size 21
  let size = 21
  let ones = Array::make(26, (0xFF).to_byte())
  place_on_matrix_data(m, size, ones)
  let mut data_dark = 0
  let mut total_data = 0
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      let b = m[y * size + x]
      if is_data_byte(b) {
        total_data += 1
        if value_of(b) == 1 {
          data_dark += 1
        }
      }
      x += 1
    }
    y += 1
  }
  if total_data != 208 {
    fail("V1 应有 208 个 Data 模块，实际 \{total_data}")
  }
  if data_dark != 208 {
    fail("喂全 1 后所有 Data 应置暗，实际暗数 \{data_dark}")
  }
}

///|
/// 逆序读回验证：按参考之字形遍历把 Data 明暗位重排，应与喂入位流一致。
/// 用 V1 + 26 字节确定性 pattern，覆盖跳第 6 列与 y 向交替。
test "place_on_matrix_data: 读回位序与喂入码字一致" {
  let m = create_matrix(0)
  let size = 21
  let feed : Array[Byte] = []
  let mut i = 0
  while i < 26 {
    feed.push((i & 0xFF).to_byte())
    i += 1
  }
  place_on_matrix_data(m, size, feed)
  // 逆序读回（等价参考遍历）
  let mut rev = true
  let mut idx = 0
  let cols = build_right_cols(size)
  let mut step = 0
  while step < cols.length() {
    let x = cols[step]
    if rev {
      let mut y = size - 1
      while y >= 0 {
        idx = check_one(m, size, y, x, idx, feed)
        idx = check_one(m, size, y, x - 1, idx, feed)
        y -= 1
      }
    } else {
      let mut y = 0
      while y < size {
        idx = check_one(m, size, y, x, idx, feed)
        idx = check_one(m, size, y, x - 1, idx, feed)
        y += 1
      }
    }
    rev = !rev
    step += 2
  }
  // idx 走到全部 208 位即读回一致（check_one 内部逐位断言失败即中止）
}

///|
/// 右列序列：`(0..6)∪(7..size)` 逆序后隔项取一（最右偶列起、跳第 6 列）。
fn build_right_cols(size : Int) -> FixedArray[Int] {
  let out : Array[Int] = []
  let mut c = size - 1
  while c >= 0 {
    if c != 6 {
      out.push(c)
    }
    c -= 1
  }
  FixedArray::from_array(out)
}

///|
/// 读回单格并比对；不符则经 fail 中止（需在 test 体内可达的辅助，故用 abort 语义）。
fn check_one(
  m : FixedArray[Int],
  size : Int,
  y : Int,
  x : Int,
  idx : Int,
  feed : Array[Byte],
) -> Int {
  if x < 0 || x >= size {
    return idx
  }
  let pos = y * size + x
  if is_data_byte(m[pos]) {
    let bit = (feed[idx / 8].to_int() >> (7 - idx % 8)) & 1
    if value_of(m[pos]) != bit {
      // 直接抛出硬错误（whitebox 测试体可 catch 不到，用断言式失败）
      abort("读回第 \{idx} 位不符：格 (y=\{y},x=\{x})")
    }
    return idx + 1
  }
  idx
}

///|
/// 总装产物自洽：create_fixed_qr 后 Data 以外格子的类型号均非 0。
test "create_fixed_qr: 掩码不破坏功能格类型" {
  let m = create_fixed_qr(Array::make(26, b'\x00'), 0, 0, 0)
  let size = 21
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      let b = m[y * size + x]
      if !is_data_byte(b) && module_type_of(b) == 0 {
        fail("非 Data 类型号不应为 0")
      }
      x += 1
    }
    y += 1
  }
}
