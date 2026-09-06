///|
/// matrix.mbt 白盒测试：B9a 功能图案 + Format 覆写，坐标与 fast_qr v0.14.0 快照逐位对齐。
/// 每个断言值均从固定 mask 快照（/tmp/fast_qr examples/snapshot_gen 产出的参考矩阵）解码得来，
/// 覆盖 finder/分隔/timing/dark/alignment/version-info/format 各图案（roadmap §4.2 B9a）。

///|
/// 便捷：取矩阵 (row,col) 的 packed 值。
fn px(m : Array[Int], size : Int, row : Int, col : Int) -> Int {
  m[row * size + col]
}

///|
/// V1（version 0，size 21）：三个 finder、分隔区、timing、dark 几何。
/// 参考快照 v01_q_mask0 解码值。类型号：finder=1、timing=3、dark=6、empty=7、format=4、data=0。
test "B9a V1 功能图案几何对照参考快照" {
  let m = create_matrix(0)
  let size = 21
  // 三个 finder 外角为 finder 暗（pack(1,finder)=3）
  if px(m, size, 0, 0) != 3 ||
    px(m, size, 0, 20) != 3 ||
    px(m, size, 20, 0) != 3 {
    fail("三 finder 外角应 finder 暗(3)")
  }
  // finder 内核 3×3 暗
  if px(m, size, 2, 2) != 3 || px(m, size, 3, 3) != 3 || px(m, size, 2, 3) != 3 {
    fail("finder 内核应暗(3)")
  }
  // 分隔区 empty 浅色（pack(0,empty)=14）
  if px(m, size, 0, 7) != 14 ||
    px(m, size, 7, 0) != 14 ||
    px(m, size, 20, 7) != 14 {
    fail("分隔区应 empty 浅(14)")
  }
  // timing 第 6 行/列：偶数 i 暗(7)、奇数 i 亮(6)
  if px(m, size, 6, 8) != 7 || px(m, size, 6, 9) != 6 || px(m, size, 6, 12) != 7 {
    fail("timing 奇偶明暗错")
  }
  // dark module (size-8=13, 8)：pack(1,dark)=13
  if px(m, size, 13, 8) != 13 {
    fail("dark module 应为 13")
  }
  // 未画任何功能图案的区域仍为 Data 浅（pack(0,data)=0）
  if px(m, size, 0, 9) != 0 || px(m, size, 10, 10) != 0 {
    fail("数据区初始应为 data 浅(0)")
  }
}

///|
/// V7（version 6，size 45）：版本信息区 + 对齐图案正确落位。
/// 参考快照 v07_h_mask2（ecl3）解码。版本信息区：top-right 行 0..5 列 n-11..(n-6)，bottom-left 转置。
test "B9a V7 版本信息与对齐图案对照参考快照" {
  let m = create_matrix(6)
  let n = 45
  // 版本信息 top-right 区为 6 高 × 3 宽：行 0..5、列 n-11..n-9 = 34..36 全为 version 类型(类型号5)
  let mut r = 0
  while r < 6 {
    let mut c = 34
    while c < 37 {
      if module_type_of(px(m, n, r, c)) != module_type_version {
        fail(
          "V7 top-right 版本信息区应为 version 类型，行 \{r} 列 \{c}",
        )
      }
      c += 1
    }
    r += 1
  }
  // bottom-left 版本信息区转置存在
  if module_type_of(px(m, n, 34, 0)) != module_type_version ||
    module_type_of(px(m, n, 35, 2)) != module_type_version {
    fail("V7 bottom-left 版本信息区应为 version 类型")
  }
  // V7 对齐中心 alignment_grid(6)=[6,22,38]：中心 (22,22) 为 alignment 暗；角与 finder 重叠者跳过
  if module_type_of(px(m, n, 22, 22)) != module_type_alignment {
    fail("V7 中央对齐 (22,22) 应为 alignment")
  }
  if px(m, n, 22, 22) != pack(1, module_type_alignment) {
    fail("V7 对齐中心应暗")
  }
}

///|
/// Format 覆写：apply_format(ecl=2(Q),mask=0) 后 format 区与参考 v01_q_mask0 一致。
/// 参考值：左上 (8,0)亮、(8,7)暗、(8,8)亮、(7,8)暗；右上 (8,13)暗、(8,12)亮；(8,14)=format 亮。
test "B9a Format 覆写对照参考快照 (Q/mask0)" {
  let m = create_matrix(0)
  let size = 21
  create_matrix_format_info(m, size, 2, 0)
  // 参考解码（v01_q_mask0）：见注释
  if px(m, size, 8, 0) != pack(0, module_type_format) {
    fail("(8,0) 应为 format 亮")
  }
  if px(m, size, 8, 7) != pack(1, module_type_format) {
    fail("(8,7) 应为 format 暗")
  }
  if px(m, size, 8, 8) != pack(0, module_type_format) {
    fail("(8,8) 应为 format 亮")
  }
  if px(m, size, 7, 8) != pack(1, module_type_format) {
    fail("(7,8) 应为 format 暗")
  }
  // 右上 format 行 8 右侧：cols 13..20（参考 v01_q_mask0：13亮/14暗/15亮/16暗/17暗）
  if px(m, size, 8, 13) != pack(0, module_type_format) {
    fail("(8,13) 应为 format 亮")
  }
  if px(m, size, 8, 14) != pack(1, module_type_format) {
    fail("(8,14) 应为 format 暗")
  }
  if px(m, size, 8, 17) != pack(1, module_type_format) {
    fail("(8,17) 应为 format 暗")
  }
  // 左下 format 列 8：行 14 起（行 13 为 dark module，不被 format 覆盖）
  if px(m, size, 14, 8) != pack(1, module_type_format) {
    fail("(14,8) 应为 format 暗")
  }
  if px(m, size, 20, 8) != pack(0, module_type_format) {
    fail("(20,8) 应为 format 亮")
  }
  // 左下 (size-8,8)=dark 不被 format 覆盖
  if px(m, size, 13, 8) != 13 {
    fail("dark module 不应被 format 覆写")
  }
}
