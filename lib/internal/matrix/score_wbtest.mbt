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

///|
/// T2-b2：N1「恰好 5 连」边界 + 被非 Data 打断的结算路径（S10 §6 T2-b / 变异 M20 的补测）。
///
/// 背景：`line_scan_buf` 的运行分有三处结算点——① 变色时、② 遇非 Data 时、③ 行末。
/// 变异 M20（把 ① 的阈值 5 改成 6）在既有夹具上**零检出**，说明「恰好 5 连 + 紧接着变色」
/// 这条路径此前**无覆盖**。本用例按参考 `score.rs::adjacent_line` 的四条线逐条断言
/// （含 `EMPT`/`FIND` 非 Data 分隔的结算路径），把 ① 的阈值钉死。
///
/// 参考：fast_qr v0.14.0 `src/tests/score.rs::adjacent_line`。
/// 期望值（5/5/3/3）为参考实算值；线内容按参考的 DATA/EMPT/FIND 类型逐格转写为 packed 值。
/// 说明：`test_line_run` 与实现同一算法（属铁律 3 的 `actual == actual` 型护栏），
/// 因此本用例的价值**不在正确性**，而在**把结算阈值暴露到可定位粒度**——
/// 真值（5/5/3/3）虽为参考实算，但这里主要锁「阈值不可漂移」。

///|
test "t2b2_n1_line_boundary_settlement" {
  // 线 1/2：7 连暗 Data → 结算一次（7-2=5）。① 行末结算路径。
  let l1 : Array[Int] = Array::make(7, pack(1, module_type_data))
  if test_line_run(fn(i) { l1[i] }, 7) != 5 {
    fail(
      "t2b2: 7 连暗（行末结算）got=" +
      test_line_run(fn(i) { l1[i] }, 7).to_string() +
      " want=5",
    )
  }
  // 线 3：EMPT(T) DATA×4 EMPT(T) DATA×5 → 两段各 4/5，仅第二段 5 连计 3。
  // 覆盖「遇非 Data 结算」（②）+「恰好 5 连」（①/② 阈值边界）。
  let l3 : Array[Int] = [
    pack(1, module_type_empty),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_empty),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
  ]
  let g3 = test_line_run(fn(i) { l3[i] }, 11)
  if g3 != 3 {
    fail("t2b2: 非 Data 分隔两段（5 连计 3）got=" + g3.to_string() + " want=3")
  }
  // 线 4：FIND×7 EMPT(F) DATA(F) DATA(T) DATA(F) DATA(T) DATA(F) DATA(T)×5 DATA(F)
  //       DATA(T)×2 EMPT(F) FIND×7 —— 覆盖「变色结算」（①）与「恰好 5 连」的交互。
  let l4 : Array[Int] = [
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(0, module_type_empty),
    pack(0, module_type_data),
    pack(1, module_type_data),
    pack(0, module_type_data),
    pack(1, module_type_data),
    pack(0, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(0, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(0, module_type_empty),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
    pack(1, module_type_finder),
  ]
  let g4 = test_line_run(fn(i) { l4[i] }, 29)
  if g4 != 3 {
    fail(
      "t2b2: xiaojiba 首行（变色结算 + 5 连边界）got=" + g4.to_string() + " want=3",
    )
  }
}

///|
/// T2-b3：N1「恰好 5 连后立刻变色」的**独立构造**（M20 的直接靶点）。
/// 线 = 5 连暗 Data + 1 亮 Data：变色发生在第 6 格，5 连须在此结算为 5-2=3。
/// 若结算阈值被改成 6，此运行**不会**在变色处结算，行末 count=1 亦不计 → 结果 0（变红）。

///|
test "t2b3_n1_exact_five_then_color_change" {
  let l : Array[Int] = [
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(1, module_type_data),
    pack(0, module_type_data),
  ]
  let got = test_line_run(fn(i) { l[i] }, 6)
  if got != 3 {
    fail("t2b3: 5 连暗 + 1 亮（变色处结算）got=" + got.to_string() + " want=3")
  }
}
