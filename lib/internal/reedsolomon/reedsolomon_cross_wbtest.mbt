///|
/// reedsolomon_cross_wbtest.mbt —— T1-e division ↔ structure 交叉独立证据（S10 §6 T1-e）
///
/// 思路（T1-d 语料派生，**不引入新真值**）：`structure` 的输出由「交织数据区 + 交织纠错区」构成。
/// 本用例把 `structure` 的输出**按 QR 规范逆交织**还原成各原始块（数据块 + 纠错块），
/// 再断言两件事：
///   ① **纠错区 = division(数据块)** 逐字节成立 —— 即 `structure` 写入的纠错区
///      与独立调用 `division` 的结果一致（两条路径同输入 → 同输出，互为独立证据）；
///   ② **数据区逆交织 = 原输入** 逐字节还原 —— 即交织是可逆的（锁住交织方向/列序）。
///
/// ① 的价值在 M14 型缺陷（余数长度对而值错）之外，再补一层「`structure` 的纠错区写入
/// 位置与值是否与 `division` 自洽」；② 锁住 M15 型（首块起点偏移）与交织方向反转。
///
/// **与铁律 3 的关系**：本用例的断言两端**不是同一段实现**——
///   左端 = `structure` 的**输出**（经规范定义的逆交织重排，重排逻辑独立写在测试内），
///   右端 = `division` 的**输出**。二者同为项目内实现，故它不是「独立真值来源」，
///   而是**两个算法互为独立证据**的交叉一致性检查（roadmap 明确如此定义 T1-e）。
///   真值侧仍由 T1-c/T1-d 的黄金向量（参考侧 53e8c99 实算）锁定。

///|
/// 逆交织：把 `structure` 输出还原为「按块序的数据块 + 纠错块」。
/// 返回 (data_blocks, ec_blocks)，每个元素是一块的字节数组；
/// 块序与 `ecc_to_groups` 一致：先 g1 的 g1c 块，再 g2 的 g2c 块。
/// 逆交织规则（QR 规范 / 与实现 `structure` 互逆）：
///   - 数据区：逐列（i）跨块，块内第 i 字节；g1 块长 g1s、g2 块长 g2s；
///   - 纠错区：逐行（j）跨块，块 j 字节；块总数 = g1c + g2c。

///|
fn unrestructure(
  out : Array[Byte],
  ecl : Int,
  version : Int,
) -> (Array[Array[Byte]], Array[Array[Byte]]) {
  let (g1c, g1s, g2c, g2s) = @constants.ecc_to_groups(ecl, version)
  let total = g1c + g2c
  let dcw = @constants.data_codewords(ecl, version)
  let ec_len = @constants.max_bytes(version) - dcw
  let ec_per_block = ec_len / total
  // 数据块：g1 各 g1s，g2 各 g2s
  let data_blocks : Array[Array[Byte]] = []
  let mut i = 0
  while i < total {
    let sz = if i < g1c { g1s } else { g2s }
    data_blocks.push(Array::make(sz, b'\x00'))
    i += 1
  }
  // 逆交织数据区：逐列跨块
  let max_s = if g1s > g2s { g1s } else { g2s }
  let mut ptr = 0
  let mut col = 0
  while col < max_s {
    let mut b = 0
    while b < total {
      let sz = if b < g1c { g1s } else { g2s }
      if col < sz {
        data_blocks[b][col] = out[ptr]
        ptr += 1
      }
      b += 1
    }
    col += 1
  }
  // 纠错块：逐行跨块
  let ec_blocks : Array[Array[Byte]] = []
  i = 0
  while i < total {
    ec_blocks.push(Array::make(ec_per_block, b'\x00'))
    i += 1
  }
  let mut row = 0
  while row < ec_per_block {
    let mut b = 0
    while b < total {
      ec_blocks[b][row] = out[ptr]
      ptr += 1
      b += 1
    }
    row += 1
  }
  (data_blocks, ec_blocks)
}

///|
/// T1-e：对 T1-d 的 5 组语料做交叉一致性断言（组数 ≥5，满足验收口径）。
/// 每组断言：
///   ① 逆交织数据区 == 原输入（锁交织方向/列序/首块起点）；
///   ② 每块纠错区 == `division(该块数据)`（锁纠错区值与位置）。
/// 失败信息含组名 + 块号 + 字节下标（铁律 4）。

///|
test "t1e_division_structure_cross_consistency" {
  // 语料同 T1-d（LCG 确定性输入，hex 串由 gen-goldens.sh --emit-rs 产出）。
  let cases : Array[(String, Array[Byte], Int, Int)] = [
    (
      "v05q",
      hex_bytes(
        "43554686572655c277320612066726f6f642077686f207265616c6c79206b6e6f77732077686572652068697320746f77656c206973210ec11ec11ec11ec",
      ),
      2,
      4,
    ),
    (
      "v10q",
      hex_bytes(
        "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d180a3571de14f241770bea0537b5dd78a93a16592a906bb244a8f2e6cb5a837eba11f2b0cb3609b3d85e48c5f4325cf848225fc0afc9d53e111e624a80604d4314c0b59687cb950f8f9e79e2ffc8fd789cfd0afbc080d0a0",
      ),
      2,
      9,
    ),
    (
      "v07h",
      hex_bytes(
        "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d",
      ),
      3,
      6,
    ),
    (
      "v16m",
      hex_bytes(
        "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d180a3571de14f241770bea0537b5dd78a93a16592a906bb244a8f2e6cb5a837eba11f2b0cb3609b3d85e48c5f4325cf848225fc0afc9d53e111e624a80604d4314c0b59687cb950f8f9e79e2ffc8fd789cfd0afbc080d0a0b14e83b7be0bd5741fae367b8aebce2d956336b5cf8efad19c64cf60d4ce95b01bd00b85fe7354e9d2732db74dadebe5e1473794dc9d8ad941ef664964cb5a47473bb30db7af027b26a952a2472b26106ce035d99f0ce46a8235870de78f583b2e2833a562d8170112e65d95f17ab6842dc7e6dc8ff5425b57cfea04d531c766c72f43a77606cb538fc306e7c2b5d21b1c9403f3256eda84b9554787a7cadf9f0be79b6a6b50564994d804f033f2b3ac32de4477d88fe6be9f5e56ecd471d7bef1e9f346bacff0bc1abc1108bb4a9210673e61c121729cdf0283ce8dd540e99c72cd0393db9ad1821808e487d2d5a51db14b1128772d35c1d95c69c1214c4c0f852b83aa44cb3075865334c6f1aa25ad0b9f0e0452d8e93b1d81dde031b038f1229a2be27078476c5d37bb",
      ),
      1,
      15,
    ),
    (
      "v03q",
      hex_bytes(
        "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed8",
      ),
      2,
      2,
    ),
  ]
  for c in cases {
    let (label, input, ecl, version) = c
    let out = structure(input, ecl, version)
    let (data_blocks, ec_blocks) = unrestructure(out, ecl, version)
    // ① 数据区逆交织 == 原输入
    let mut src = 0
    let mut b = 0
    while b < data_blocks.length() {
      let blk = data_blocks[b]
      let mut k = 0
      while k < blk.length() {
        if blk[k].to_int() != input[src].to_int() {
          fail(
            "t1e[" +
            label +
            "]: 数据区逆交织不符 block=" +
            b.to_string() +
            " idx=" +
            k.to_string() +
            " got=" +
            blk[k].to_int().to_string() +
            " want=" +
            input[src].to_int().to_string(),
          )
        }
        src += 1
        k += 1
      }
      b += 1
    }
    // ② 每块纠错区 == division(数据块)
    let gen = @constants.get_polynomial(version, ecl)
    b = 0
    while b < data_blocks.length() {
      let rem = division(data_blocks[b], gen)
      let ec = ec_blocks[b]
      if rem.length() != ec.length() {
        fail(
          "t1e[" +
          label +
          "]: 纠错块长度不符 block=" +
          b.to_string() +
          " got=" +
          rem.length().to_string() +
          " want=" +
          ec.length().to_string(),
        )
      }
      let mut k = 0
      while k < rem.length() {
        if rem[k].to_int() != ec[k].to_int() {
          fail(
            "t1e[" +
            label +
            "]: 纠错区 != division(数据块) block=" +
            b.to_string() +
            " idx=" +
            k.to_string() +
            " got=" +
            rem[k].to_int().to_string() +
            " want=" +
            ec[k].to_int().to_string(),
          )
        }
        k += 1
      }
      b += 1
    }
  }
}
