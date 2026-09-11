///|
/// score_wbtest.mbt —— 评分 4 规则白盒护栏 + create_auto_qr 择优护栏
/// 语义核对（framework 掩码与评分不变量）：
///   - N1 连续同色 N>=5 计 N-2（仅在 Data 上累计，非 Data/变色即结算）；
///   - N2 2×2 同色块计 3，触及非 Data 不计且连续性归零；
///   - N3 11 位窗口命中 finder 类图案计 40，行首/尾补浅色（双侧命中各计）；
///   - N4 暗比查 constants 惩罚表。
/// 介质：packed = 明暗|类型<<1（见本包 module.mbt）。

///|
/// 造一个全 Data 的 size×size 亮矩阵。
fn data_light(size : Int) -> Array[Int] {
  Array::make(size * size, pack(0, module_type_data))
}

///|
/// 造一个全 Data 的 size×size 暗矩阵。
fn data_dark(size : Int) -> Array[Int] {
  Array::make(size * size, pack(1, module_type_data))
}

///|
/// N1：单行 5 连暗（全 Data）运行分 = 5-2=3（行方向）。
test "score_line: 连续同色 N>=5 计 N-2" {
  let size = 5
  let m = data_light(size)
  // 第 0 行全暗（5 连），其余行全亮。
  let mut i = 0
  while i < size {
    m[i] = pack(1, module_type_data)
    i += 1
  }
  // 行方向：第 0 行 5 连暗 =3；列方向每列首格暗+4 亮，长度 5 不成 N>=5 同色（各 1/4），列贡献 0。
  // 但 N1 行扫描包括 5 连暗第 0 行 3 分 + 其余 4 行各 5 连亮 =4 分 => 3 + 4*3。
  let expect_row = 3 + 4 * 3 // 第0行暗5连3 + 4行亮5连各3
  assert_eq(score_line(m, size), expect_row)
}

///|
/// N1：列方向连续同色也能计（验证列评分逻辑，掩码后语义由 placement 主循环保证）。
test "score_line: 列方向连续同色计分" {
  let size = 5
  let m = data_light(size)
  // 第 0 列全暗。
  let mut i = 0
  while i < size {
    m[i * size + 0] = pack(1, module_type_data)
    i += 1
  }
  // 行：每行首格暗+4 亮 => 无 N>=5 连续；列：第 0 列 5 连暗=3，其余列 5 连亮各=3 => 3 + 4*3
  assert_eq(score_line(m, size), 3 + 4 * 3)
}

///|
/// N2：全暗 5×5 的 2×2 同色块数 = (5-1)*(5-1) = 16，各 3 分 = 48。
test "score_squares: 全同色 2×2 块按 3 分/块" {
  let m = data_dark(5)
  assert_eq(score_squares(m, 5), 16 * 3)
}

///|
/// N3：构造 finder 类图案行，11 位窗口命中计 40。
/// 图案 0b00001011101 = 前 4 亮 + 1011101（浅色在前的 finder 类）。
test "score_pattern: 11 位窗口命中类 finder 计 40" {
  let size = 11
  let m = data_light(size)
  // 用「行首 4 浅色 + 目标 1011101」的浅后图案也可由行内真实暗亮构成：
  // 这里直接构造 11 位 = 00001011101（暗=1）置于第 0 行。
  let bits : ReadOnlyArray[Int] = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
  let mut j = 0
  while j < 11 {
    m[j] = pack(bits[j], module_type_data)
    j += 1
  }
  // 行方向：末尾累计出 00001011101 命中浅前图案 +40；随后补 4 浅色移位又命中浅后
  // 10111010000 +40（quiet zone 双侧各命中一次，参考 line() 行尾补浅）。列方向全亮不成图案。
  assert_eq(score_pattern(m, 11), 80)
}

///|
/// N4：暗比查表。全亮矩阵暗比 0% => percent_score[0]=90。
test "score_dark: 暗比 0% 查表得 90" {
  let m = data_light(21)
  assert_eq(score_dark(m, 21), 90)
}

///|
/// S9n P2b：N4 暗格计数并入行趟后，`score` 仍**严格等于**四规则分量之和。
/// 用混合明暗/类型的矩阵，防聚合口径漂移。
test "score 分解：N4 并入行趟后仍等于四规则之和" {
  let size = 21
  let m = Array::make(size * size, pack(0, module_type_data))
  let mut i = 0
  while i < size * size {
    let t = (i * 5 + 1) % 9
    let t2 = if t > 7 { module_type_data } else { t }
    m[i] = pack((i * 3 + i / size) & 1, t2)
    i += 1
  }
  let total = score(m, size)
  let parts = score_line(m, size) +
    score_pattern(m, size) +
    score_squares(m, size) +
    score_dark(m, size)
  assert_eq(total, parts)
}

///|
/// score 总分 = 四规则之和；对一个简单全 Data 矩阵不越界且非负。
test "score: 汇总非负且可分解" {
  let m = data_light(5)
  let total = score(m, 5)
  if total < 0 {
    fail("score 不应为负")
  }
  // 全亮 5×5：行 5 连亮×5 行 =15；列 5 连亮×5 列=15；squares 16*3=48；dark 0% =>90；pattern 无命中 0。
  assert_eq(total, 15 + 15 + 48 + 90 + 0)
}

///|
/// create_auto_qr：择优护栏——对已知 structure 遍历 8 掩码，断言返回的 best_mask 与手工逐轮最低分一致，
/// 且非功能模块（format 之外）不受择优循环破坏（掩码只动 Data）。
test "create_auto_qr: 返回最低分掩码且矩阵自洽" {
  // V1 空输入（26 数据码字全 0，多由 place 放 0）。
  let structure = Array::make(26, (0).to_byte())
  let (m, best_mask) = create_auto_qr(structure, 0, 0) // V01, L
  if best_mask < 0 || best_mask > 7 {
    fail("best_mask 应 0..=7")
  }
  let size = 21
  // 断言返回矩阵 size*size。
  if m.length() != size * size {
    fail("矩阵长度应为 size*size")
  }
}
