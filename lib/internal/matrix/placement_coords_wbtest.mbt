///|
/// placement_coords_wbtest.mbt —— T2-c 放置逐格坐标序列（S10 §6 T2-c / 缺口 G6）
///
/// 缺口 G6：`placement_wbtest.mbt` 的「位序读回」用的是与 `place_on_matrix_data`
/// **相同的遍历序**，属铁律 3 点名的 `actual == actual` 型护栏——只锁「实现与自身一致」，
/// 不提供正确性证据。参考 `structure.rs::placement` 则是**手工枚举 V02 的坐标序列**，
/// 可定位「哪一段/哪一格放错」。
///
/// 本文件把参考的枚举方法迁移过来：用**显式段表**（列 x、模式 P/S、行列表）重建 V02 的
/// 全部 **359** 个 Data 格访问序，再与「喂确定性码字后矩阵里 Data 格的实际明暗」逐格比对。
///
/// 真值链：段表由 `bash scripts/gen-goldens.sh --emit-placement` 在参考侧 53e8c99
/// 对同一夹具实算导出，MoonBit 侧已重排为**可读的 14 段**（人工可核）；
/// 断言两端分别为「段表推得的期望位」与「矩阵实际明暗位」，口径不同，**非 `actual == actual`**。
///
/// 夹具：V02（size 25），码字 `byte[i] = (i*11) & 0xFF`（i = 0..max_bytes-1=43），
/// 与参考测试同名同参数。失败信息含 (row,col) + 位序下标（铁律 4）。

///|
/// 段表：(模式, 列 x, 行列表)。
/// 模式 `"P"` 每行访问 (row, x) 与 (row, x-1) 两格；模式 `"S"` 只访问 (row, x)。
/// 行列表由参考侧实算导出后人工重排；顺序即访问序（不可排序，否则语义丢失）。

///|
let place_segments : ReadOnlyArray[(String, Int, ReadOnlyArray[Int])] = [
  ("P", 24, [24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9]),
  ("P", 22, [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]),
  ("P", 20, [24, 23, 22, 21, 15, 14, 13, 12, 11, 10, 9]),
  ("P", 18, [9, 10, 11, 12, 13, 14, 15, 21, 22, 23, 24]),
  ("P", 16, [24, 23, 22, 21]),
  ("S", 15, [20, 19, 18, 17, 16]),
  ("P", 16, [15, 14, 13, 12, 11, 10, 9, 8, 7, 5, 4, 3, 2, 1, 0]),
  ("P", 14, [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]),
  ("P", 12, [24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 5, 4, 3, 2, 1, 0]),
  ("P", 10, [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]),
  ("P", 8, [16, 15, 14, 13, 12, 11, 10, 9]),
  ("P", 5, [9, 10, 11, 12, 13, 14, 15, 16]),
  ("P", 3, [16, 15, 14, 13, 12, 11, 10, 9]),
  ("P", 1, [9, 10, 11, 12, 13, 14, 15, 16]),
]

///|
/// V02 的码字位流（与参考 `placement()` 夹具一致）：`byte[i] = (i*11) & 0xFF`，44 字节。

///|
let place_structure_hex : String = "000b16212c37424d58636e79848f9aa5b0bbc6d1dce7f2fd08131e29343f4a55606b76818c97a2adb8c3ced9e4"

///|
fn place_structure() -> Array[Byte] {
  let out : Array[Byte] = []
  let chars = place_structure_hex.to_array()
  let mut i = 0
  while i + 1 < chars.length() {
    out.push((place_hex_digit(chars[i]) * 16 + place_hex_digit(chars[i + 1])).to_byte())
    i += 2
  }
  out
}

///|
fn place_hex_digit(c : Char) -> Int {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 97 && n <= 102 {
    n - 87
  } else {
    n - 55
  }
}

///|
/// 把段表展开为 (row,col) 访问序。

///|
fn place_coord_seq() -> Array[(Int, Int)] {
  let seq : Array[(Int, Int)] = []
  for seg in place_segments {
    let (mode, x, rows) = seg
    for r in rows {
      seq.push((r, x))
      if mode == "P" {
        seq.push((r, x - 1))
      }
    }
  }
  seq
}

///|
/// T2-c：逐格断言矩阵 Data 格的明暗与「段表展开位流」一致。
/// 期望位 = 段表序 idx → structure[idx/8] 的第 (7-idx%8) 位（大端）；
/// 实际位 = 矩阵 (row,col) 格的明暗位——两端口径不同，故非自证。

///|
test "t2c_placement_coordinates_v02" {
  let ver = 1 // V02
  let size = ver * 4 + 21 // 25
  let m = create_matrix(ver)
  let st = place_structure()
  place_on_matrix_data(m, size, st)
  let seq = place_coord_seq()
  if seq.length() != 359 {
    fail(
      "t2c: 段表展开格数 got=" +
      seq.length().to_string() +
      " want=359（段表已漂移）",
    )
  }
  let mut idx = 0
  while idx < seq.length() {
    let (r, c) = seq[idx]
    let want_bit = (st[idx / 8].to_int() >> (7 - idx % 8)) & 1
    let got_bit = m[r * size + c] & 1
    if got_bit != want_bit {
      fail(
        "t2c: 格 (" +
        r.to_string() +
        "," +
        c.to_string() +
        ") idx=" +
        idx.to_string() +
        " got=" +
        got_bit.to_string() +
        " want=" +
        want_bit.to_string(),
      )
    }
    idx += 1
  }
  // 反向：段表与矩阵的 Data 集合必须完全一致（无遗漏、无重复、不误盖功能格）。
  let covered : Array[Int] = Array::make(size * size, 0)
  for rc in seq {
    let (r, c) = rc
    covered[r * size + c] = covered[r * size + c] + 1
  }
  let mut total_data = 0
  let mut y = 0
  while y < size {
    let mut x = 0
    while x < size {
      let b = m[y * size + x]
      let cov = covered[y * size + x]
      if is_data_byte(b) {
        total_data += 1
        if cov != 1 {
          fail(
            "t2c: Data 格 (" +
            y.to_string() +
            "," +
            x.to_string() +
            ") 覆盖次数 got=" +
            cov.to_string() +
            " want=1",
          )
        }
      } else if cov != 0 {
        fail(
          "t2c: 功能格 (" +
          y.to_string() +
          "," +
          x.to_string() +
          ") 被段表误覆盖（cov=" +
          cov.to_string() +
          "）",
        )
      }
      x += 1
    }
    y += 1
  }
  if total_data != 359 {
    fail("t2c: V02 Data 格总数 got=" + total_data.to_string() + " want=359")
  }
}
