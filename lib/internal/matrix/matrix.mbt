///|
/// matrix.mbt —— 空矩阵与功能图案绘制（B9a 落地，对照 fast_qr v0.14.0 `src/default.rs`）
/// 对应参考：/fast_qr/src/default.rs（roadmap 批次 B9 前半）
/// 职责：按版本初始化矩阵容器；绘制 finder/timing/alignment/version info/
///       dark module，并为 format 区写入占位（含真实 Format 覆写 helper）。
/// 介质：原始字节矩阵 `Array[Int]`（D3 决策），每格 packed = 明暗(bit0) | 类型号<<1，
///       位布局/类型号常量/读写 helper 见本包 `module.mbt`。
/// 关键语义（框架文档 §五.7 时序铁律）：Format 先占位（浅色）、掩码择优后再覆写真实格式
///       信息，顺序不可颠倒；掩码只对 Data 类模块翻转、功能图案一律不动。
/// 坐标系约定：参考 `qr[row][col]` = 行 row、列 col ⇒ 扁平下标 `row*size + col`。
/// 坐标经 fast_qr v0.14.0 固定 mask 快照逐位对齐核验（roadmap §4.1/§4.2 B9a）。
/// 所在包：internal/matrix（roadmap 批次 B9 前半）。仅依赖 constants（alignment/information）。
/// 依赖规则：不依赖 lib 公共包；按 version 序号（Int 0..=39）创建矩阵并绘制功能图案。

///|
/// 绘制 finder 定位图案 + 三分隔区（B9a 核心）。
/// 对应参考 default.rs `create_matrix` 内 create_matrix_pattern + create_matrix_empty。
/// 结果以原始字节矩阵就地写入 m（调用方先建全 Data 亮矩阵）。

///|
/// 单个 finder 7×7 三框图案：左上角在 (oy,ox)（行 oy、列 ox）。
/// 参考 default.rs `create_matrix_pattern`。三框：外层 7 暗框、次层 5 亮框、内核 3×3 暗块。
fn draw_finder(m : Array[Int], size : Int, oy : Int, ox : Int) -> Unit {
  let mut j = 0
  while j <= 6 {
    let dark = pack(1, module_type_finder)
    m[oy * size + (j + ox)] = dark // 上边行
    m[(6 + oy) * size + (j + ox)] = dark // 下边行
    m[(j + oy) * size + ox] = dark // 左边列
    m[(j + oy) * size + (6 + ox)] = dark // 右边列
    j += 1
  }
  j = 1
  while j <= 5 {
    let light = pack(0, module_type_finder)
    m[(oy + 1) * size + (j + ox)] = light
    m[(5 + oy) * size + (j + ox)] = light
    m[(j + oy) * size + (ox + 1)] = light
    m[(j + oy) * size + (5 + ox)] = light
    j += 1
  }
  // 内核 3×3 暗块（行 oy+2..oy+4、列 ox+2..ox+4）
  let mut r = 2
  while r <= 4 {
    let dark = pack(1, module_type_finder)
    m[(r + oy) * size + (2 + ox)] = dark
    m[(r + oy) * size + (3 + ox)] = dark
    m[(r + oy) * size + (4 + ox)] = dark
    r += 1
  }
}

///|
/// 三个 finder 定位图案（左上/右上/左下）。
/// 参考 default.rs `create_matrix_pattern`：offsets 为 (y,x)。
fn create_matrix_pattern(m : Array[Int], size : Int) -> Unit {
  let n = size
  let k = 7
  let offsets = [(0, 0), (n - k, 0), (0, n - k)]
  let mut i = 0
  while i < 3 {
    let (oy, ox) = offsets[i]
    draw_finder(m, size, oy, ox)
    i += 1
  }
}

///|
/// 三个 finder 外沿的分隔浅色区。
/// 参考 default.rs `create_matrix_empty`：左上 finder 右/下沿、左下上沿/右沿、右上左沿/下沿。
fn create_matrix_empty(m : Array[Int], size : Int) -> Unit {
  let n = size
  let light = pack(0, module_type_empty)
  let mut i = 0
  while i <= 7 {
    m[i * size + 7] = light // 左上 finder 右列
    m[7 * size + i] = light // 左上 finder 下行
    m[(n - 8 + i) * size + 7] = light // 左下 finder 右列
    m[(n - 8) * size + i] = light // 左下 finder 上? → 行 n-8
    m[i * size + (n - 8)] = light // 右上 finder 左列
    m[7 * size + (n - 8 + i)] = light // 右上 finder 下行
    i += 1
  }
}

///|
/// 第 6 行/列时序图案。
/// 参考 default.rs `create_matrix_timing`：i 从 8 到 size-8（含），明暗自 i 奇偶交替，
/// 与 (POSITION_SIZE+1)%2==0 比较 ⇒ 偶数 i 置暗。
fn create_matrix_timing(m : Array[Int], size : Int) -> Unit {
  let timing = pack(0, module_type_timing)
  let mut i = 8
  while i < size - 7 {
    let val = if i % 2 == 0 { 1 } else { 0 }
    let b = set_value(timing, val)
    m[6 * size + i] = b // 第 6 行
    m[i * size + 6] = b // 第 6 列
    i += 1
  }
}

///|
/// 右下角固定暗模块 (row=size-8, col=8)。
/// 参考 default.rs `create_matrix_dark_module`。
fn create_matrix_dark_module(m : Array[Int], size : Int) -> Unit {
  m[(size - 8) * size + 8] = pack(1, module_type_dark)
}

///|
/// 对齐图案：从 constants.alignment_grid(version) 取中心点画 5×5（跳过与 finder 重叠角）。
/// 参考 default.rs `create_matrix_alignments`。
fn create_matrix_alignments(m : Array[Int], version : Int, size : Int) -> Unit {
  if version == 0 {
    return
  }
  let grid = @constants.alignment_grid(version)
  let max = grid.length() - 1
  let mut i = 0
  while i < grid.length() {
    let ay = grid[i]
    let mut j = 0
    while j < grid.length() {
      let ax = grid[j]
      // 跳过与三个 finder 重叠的对齐中心（参考源码三个角落）
      let corner = (i == 0 && (j == max || j == 0)) || (i == max && j == 0)
      if !corner {
        draw_alignment_at(m, size, ay, ax)
      }
      j += 1
    }
    i += 1
  }
}

///|
/// 在中心 (cy,cx) 画单个 5×5 对齐图案。
/// 参考 default.rs `create_matrix_alignments` 内部循环。
fn draw_alignment_at(m : Array[Int], size : Int, cy : Int, cx : Int) -> Unit {
  // 外层暗框（行 cy-2/cy+2、列 cx-2..cx+2；列 cx-2/cx+2、行 cy-2..cy+2）
  let y0 = cy - 2
  let x0 = cx - 2
  let dark = pack(1, module_type_alignment)
  let mut off = 0
  while off <= 4 {
    m[y0 * size + (x0 + off)] = dark
    m[(y0 + 4) * size + (x0 + off)] = dark
    m[(y0 + off) * size + x0] = dark
    m[(y0 + off) * size + (x0 + 4)] = dark
    off += 1
  }
  // 次层亮框（行 cy-1/cy+1、列 cx-1..cx+1）
  let y1 = cy - 1
  let x1 = cx - 1
  let light = pack(0, module_type_alignment)
  let mut off2 = 0
  while off2 <= 2 {
    m[y1 * size + (x1 + off2)] = light
    m[(y1 + 2) * size + (x1 + off2)] = light
    m[(y1 + off2) * size + x1] = light
    m[(y1 + off2) * size + (x1 + 2)] = light
    off2 += 1
  }
  // 中心暗
  m[cy * size + cx] = pack(1, module_type_alignment)
}

///|
/// 版本信息区（仅 V7+，右下 6×3 与左上 3×6 两块）。
/// 参考 default.rs `create_matrix_version_info`：用 constants.information 的 18 bit。
fn create_matrix_version_info(
  m : Array[Int],
  version : Int,
  size : Int,
) -> Unit {
  if version < 6 {
    return
  }
  let n = size
  let info = @constants.information(version)
  let mut i = 0
  while i <= 2 {
    let mut j = 0
    while j <= 5 {
      let shift = 1 << (j * 3 + i)
      let val = if (info & shift) != 0 { 1 } else { 0 }
      let b = pack(val, module_type_version)
      m[j * n + (n - 11 + i)] = b // 右下：行 j、列 n-11+i
      m[(n - 11 + i) * n + j] = b // 左上：行 n-11+i、列 j
      j += 1
    }
    i += 1
  }
}

///|
/// Format 区写浅色占位（B9a 尾步，为后续放置让出区域；真实 Format 在放置+掩码后覆写）。
/// 参考 default.rs `create_matrix` 尾部 format 占位块。
fn create_matrix_format_placeholder(m : Array[Int], size : Int) -> Unit {
  let n = size
  let light = pack(0, module_type_format)
  let mut i = 0
  while i <= 5 {
    m[8 * n + i] = light // 左上区行 8
    m[i * n + 8] = light // 左上区列 8
    m[8 * n + (n - 1 - i)] = light // 右上区行 8
    m[(n - 1 - i) * n + 8] = light // 左下区列 8
    i += 1
  }
  // 左上三格位
  m[8 * n + 7] = light
  m[8 * n + 8] = light
  m[7 * n + 8] = light
  // 右上两格
  m[8 * n + (n - 1 - 6)] = light
  m[8 * n + (n - 1 - 7)] = light
  // 左下两格
  m[(n - 1 - 6) * n + 8] = light
}

///|
/// 创建给定版本的空矩阵 + 全部功能图案（含 Format 占位），数据区为浅色 Data。
/// 参考 default.rs `create_matrix(version)`。入参 version 序号 0..=39。
pub fn create_matrix(version : Int) -> Array[Int] {
  let size = version * 4 + 21
  let light_data = pack(0, module_type_data)
  let m = Array::make(size * size, light_data)
  create_matrix_pattern(m, size)
  create_matrix_timing(m, size)
  create_matrix_dark_module(m, size)
  create_matrix_alignments(m, version, size)
  create_matrix_version_info(m, version, size)
  create_matrix_empty(m, size)
  create_matrix_format_placeholder(m, size)
  m
}

///|
/// 用真实 15 位 Format 信息覆写 format 区（含两侧位置掩码异或后的位序）。
/// 参考 default.rs `create_matrix_format_info`。入参 ecl/mask 为序号。
/// 供 placement/总装阶段在「掩码应用后」调用（时序铁律 §五.7）。
pub fn create_matrix_format_info(
  m : Array[Int],
  size : Int,
  ecl : Int,
  mask : Int,
) -> Unit {
  let n = size
  let fi = @constants.format_information(ecl, mask)
  // 位 14..9（六组：行 8 左/列 8 下）
  let mut i = 5
  while i >= 0 {
    let shift = 1 << (i + 9)
    let val = if (fi & shift) != 0 { 1 } else { 0 }
    let b = pack(val, module_type_format)
    m[8 * n + (5 - i)] = b // 左上 行 8、列 5-i
    m[(n - 6 + i) * n + 8] = b // 左下 行 n-6+i、列 8
    i -= 1
  }
  // 位 5..0
  i = 0
  while i <= 5 {
    let shift = 1 << i
    let val = if (fi & shift) != 0 { 1 } else { 0 }
    let b = pack(val, module_type_format)
    m[i * n + 8] = b // 左上 列 8、行 i
    m[8 * n + (n - i - 1)] = b // 右上 行 8、列 n-i-1
    i += 1
  }
  // 位 8：左上 (8,7) 与 左下 (n-7,8)
  m[8 * n + 7] = pack(
    if (fi & (1 << 8)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
  m[(n - 7) * n + 8] = pack(
    if (fi & (1 << 8)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
  // 位 7：左上 (8,8) 与 右上 (8,n-8)
  m[8 * n + 8] = pack(
    if (fi & (1 << 7)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
  m[8 * n + (n - 8)] = pack(
    if (fi & (1 << 7)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
  // 位 6：左上 (7,8) 与 右上 (8,n-7)
  m[7 * n + 8] = pack(
    if (fi & (1 << 6)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
  m[8 * n + (n - 7)] = pack(
    if (fi & (1 << 6)) != 0 {
      1
    } else {
      0
    },
    module_type_format,
  )
}
