///|
/// placement.mbt —— 数据放置 + 总装编排（B9b，对照 fast_qr v0.14.0 `src/placement.rs`）
/// 对应参考：/fast_qr/src/placement.rs:36 `place_on_matrix_data` + :85 `place_on_matrix` 固定 mask 分支
/// 职责：之字形逐位放置交织码字（跳过第 6 列、自右往左每两列一组、行向交替）；
///       `create_fixed_qr` 编排 create_matrix → 放置 → 写真实 Format → 一次固定 mask，产出 M1 首码。
/// 介质：原始字节矩阵 `FixedArray[Int]`（D3 决策，见本包 module.mbt 位布局）。
/// 关键语义：
///   - 只对 `Data` 类模块写位并推进 idx；功能图案（finder/timing/.../format/version）一律跳过；
///   - 位序大端（MSB first）：`byte[idx/8]` 的第 `7 - idx%8` 位；
///   - 放置的是**未掩码**的原始码字位；Format 必须在放置之后、掩码之前以真实值覆写（时序铁律 §五.7）；
///   - `apply_mask` 只翻 Data 类，Format/功能图案不动。
/// 坐标约定：扁平下标 = 行 row * size + 列 col（行向下、列向右）。
/// 所在包：internal/matrix（roadmap 批次 B9 后半 / B10 用 score 前的基础）。
/// 依赖规则：不依赖 lib 公共包；依赖本包 module 位 helper 与 matrix.mbt 的
///       create_matrix / create_matrix_format_info（二者同包内）。

///|
/// 之字形逐位放置数据（就地改写 m 中 Data 类模块的明暗位）。
/// `structure` 为交织后码字字节流（reedsolomon.structure 输出），位按大端序自第 0 位起连续消费。
/// 对应参考 `placement.rs:36 place_on_matrix_data`。
pub fn place_on_matrix_data(
  m : FixedArray[Int],
  size : Int,
  structure : Array[Byte],
) -> Unit {
  let mut rev = true
  let mut idx = 0
  // 右列序列 = `(0..6)∪(7..size)` 逆序后隔项取一（即最右偶列起、隔列递减，跳第 6 列）。
  let right_cols : Array[Int] = []
  let mut c = size - 1
  while c >= 0 {
    if c != 6 {
      right_cols.push(c)
    }
    c -= 1
  }
  let mut step = 0
  while step < right_cols.length() {
    let x = right_cols[step]
    if rev {
      let mut y = size - 1
      while y >= 0 {
        idx = consume_or_skip(m, size, structure, y, x, idx)
        idx = consume_or_skip(m, size, structure, y, x - 1, idx)
        y -= 1
      }
    } else {
      let mut y = 0
      while y < size {
        idx = consume_or_skip(m, size, structure, y, x, idx)
        idx = consume_or_skip(m, size, structure, y, x - 1, idx)
        y += 1
      }
    }
    rev = !rev
    step += 2
  }
}

///|
/// 若 (y,x) 是 Data 模块则写入下一位并返回 idx+1；否则原样返回 idx。就地改写 m。
fn consume_or_skip(
  m : FixedArray[Int],
  size : Int,
  structure : Array[Byte],
  y : Int,
  x : Int,
  idx : Int,
) -> Int {
  if x < 0 || x >= size {
    return idx
  }
  let pos = y * size + x
  if is_data_byte(m[pos]) {
    // 大端取位：structure[idx/8] 的第 (7 - idx%8) 位
    let bytev = structure[idx / 8].to_int()
    let bit = (bytev >> (7 - idx % 8)) & 1
    m[pos] = pack(bit, module_type_data)
    return idx + 1
  }
  idx
}

///|
/// 固定 mask 总装：功能图案+Format 占位 → 放置码字 → 覆写真实 Format → 一次固定 mask。
/// 入参均为序号：version/ecl/mask。返回 packed 字节矩阵（明暗|类型<<1），供 lib 侧逐格包装回公共 Module。
/// 对应参考 `placement.rs place_on_matrix`（固定 mask 分支：跳过 8 轮择优，仅一次固定 mask）。
pub fn create_fixed_qr(
  structure : Array[Byte],
  version_idx : Int,
  ecl_idx : Int,
  mask_idx : Int,
) -> FixedArray[Int] {
  let size = version_idx * 4 + 21
  let m = create_matrix(version_idx)
  place_on_matrix_data(m, size, structure)
  create_matrix_format_info(m, size, ecl_idx, mask_idx)
  apply_mask(m, size, mask_idx)
}

///|
/// 自动择优总装：基础矩阵一次构建 + 放置码字后，8 轮 clone+apply_mask+score 选最低分掩码，
/// 再把真实 Format 覆写到**最优轮已掩码矩阵**上作为返回（O1-b：省末尾对 base 再 apply_mask 的整矩阵
/// copy）。返回 (packed 矩阵, 最优 mask 序号)。
/// 对照参考 `placement.rs place_on_matrix` 的自动择优分支（:85-119）。
/// 铁律：
///   - 列评分必须在掩码后做（历史 bug）：每轮对已掩码副本 score；
///   - Format 占位先写、择优循环评分用占位、选中后把真实 Format 覆写到最优轮掩码矩阵
///     （Format/功能图案非 Data，apply_mask 不翻它们，故在已掩码矩阵上覆写 Format 与
///     「base 上覆写后再 apply」逐位等价——快照已验证）；
///   - 并列取先到的低位 mask（score < best 严格小，从左到右扫描）。
pub fn create_auto_qr(
  structure : Array[Byte],
  version_idx : Int,
  ecl_idx : Int,
) -> (FixedArray[Int], Int) {
  let size = version_idx * 4 + 21
  let base = create_matrix(version_idx)
  place_on_matrix_data(base, size, structure)
  let mut best_score = 2147483647 // 参考 u32::MAX，取充分大 Int
  let mut best_mask = 0
  let mut best_masked = base // 初始占位：至少一轮会命中（score < MAX 恒真），下面必被覆盖
  let mut k = 0
  while k < 8 {
    let masked = apply_mask(base, size, k)
    let s = score(masked, size)
    if s < best_score {
      best_score = s
      best_mask = k
      best_masked = masked
    }
    k += 1
  }
  // Format/version 位非 Data，mask 未触及；在最优轮掩码矩阵上覆写真实 Format 即得最终输出。
  create_matrix_format_info(best_masked, size, ecl_idx, best_mask)
  (best_masked, best_mask)
}
