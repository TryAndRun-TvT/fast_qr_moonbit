///|
/// reedsolomon_wbtest.mbt —— division / structure 白盒黄金测试
/// 黄金来源：fast_qr v0.14.0 src/tests/structure.rs（V05-Q 用例）。

///|
/// Int 列表 → Array[Byte]（低位截断）。
fn b(l : Array[Int]) -> Array[Byte] {
  let out : Array[Byte] = []
  for x in l {
    out.push((x & 0xFF).to_byte())
  }
  out
}

///|
/// data_codewords 输入（V05-Q，62 字节）。
fn data_v05q() -> Array[Byte] {
  b([
    67, 85, 70, 134, 87, 38, 85, 194, 119, 50, 6, 18, 6, 103, 38, 246, 246, 66, 7,
    118, 134, 242, 7, 38, 86, 22, 198, 199, 146, 6, 182, 230, 247, 119, 50, 7, 118,
    134, 87, 38, 82, 6, 134, 151, 50, 7, 70, 247, 118, 86, 194, 6, 151, 50, 16, 236,
    17, 236, 17, 236, 17, 236,
  ])
}

///|
/// 读取 out 前 n 个字节为 Int 列表。
fn head(out : Array[Byte], n : Int) -> Array[Int] {
  let r : Array[Int] = []
  let mut i = 0
  while i < n {
    r.push(out[i].to_int())
    i += 1
  }
  r
}

///|
/// structure 数据区交织结果（V05-Q 前 62 字节）。
test "structure_message_v05_q" {
  let out = structure(data_v05q(), 2, 4) // ecl=Q(2), version=V05(4)
  let expect = b([
    67, 246, 182, 70, 85, 246, 230, 247, 70, 66, 247, 118, 134, 7, 119, 86, 87, 118,
    50, 194, 38, 134, 7, 6, 85, 242, 118, 151, 194, 7, 134, 50, 119, 38, 87, 16,
    50, 86, 38, 236, 6, 22, 82, 17, 18, 198, 6, 236, 6, 199, 134, 17, 103, 146, 151,
    236, 38, 6, 50, 17, 7, 236,
  ])
  let got = head(out, 62)
  let mut i = 0
  while i < 62 {
    if got[i] != expect[i].to_int() {
      fail(
        "message mismatch at " +
        i.to_string() +
        ": got " +
        got[i].to_string() +
        " want " +
        expect[i].to_string(),
      )
    }
    i += 1
  }
}

///|
/// structure 纠错区交织结果（V05-Q，structure[62..134]，72 字节）。
test "structure_error_v05_q" {
  let out = structure(data_v05q(), 2, 4)
  let expect = b([
    213, 87, 148, 235, 199, 204, 116, 159, 11, 96, 177, 5, 45, 60, 212, 173, 115,
    202, 76, 24, 247, 182, 133, 147, 241, 124, 75, 59, 223, 157, 242, 33, 229, 200,
    238, 106, 248, 134, 76, 40, 154, 27, 195, 255, 117, 129, 230, 172, 154, 209,
    189, 82, 111, 17, 10, 2, 86, 163, 108, 131, 161, 163, 240, 32, 111, 120, 192,
    178, 39, 133, 141, 236,
  ])
  let mut i = 0
  while i < 72 {
    let got = out[62 + i].to_int()
    if got != expect[i].to_int() {
      fail(
        "error mismatch at " +
        i.to_string() +
        ": got " +
        got.to_string() +
        " want " +
        expect[i].to_string(),
      )
    }
    i += 1
  }
}

///|
/// division 单元自检：V01-L 数据块 19 字节 → 余数应等于 structure 中首块纠错（此处仅验证长度与零行为）。
test "division_len" {
  let gen = @constants.get_polynomial(0, 0) // V01-L：度 7，长 8
  assert_eq(gen.length(), 8)
  let data = data_v05q() // 用 62 字节做除法（非分块），仅验证余数长度 = gen.len-1
  let rem = division(data, gen)
  assert_eq(rem.length(), gen.length() - 1)
}

///|
/// T1-c division 黄金余数（S10 §6 T1-c）：8 组（值级，非仅长度）。
/// 覆盖缺口 G3：此前仅断言「余数长度」；M5 已证长度断言有效，此补「长度对而值错」这一窄类。
/// 黄金值由 scripts/gen-goldens.sh --emit-rs 在参考侧 fast_qr 53e8c99 **实际计算**产出，
/// 严禁手抄（重跑该命令可重建）。
/// 每组失败信息含组号与首个不一致字节下标，满足铁律 4「可定位」。
test "t1c_division_golden_remainders" {
  // v05q_01: V05-ECL2，余数 18 字节
  let gen_v05q_01 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_01.length(), 19)
  let data_v05q_01 : Array[Byte] = [
    (67).to_byte(),
    (85).to_byte(),
    (70).to_byte(),
    (134).to_byte(),
    (87).to_byte(),
    (38).to_byte(),
    (85).to_byte(),
    (194).to_byte(),
    (119).to_byte(),
    (50).to_byte(),
    (6).to_byte(),
    (18).to_byte(),
    (6).to_byte(),
    (103).to_byte(),
    (38).to_byte(),
  ]
  let rem_v05q_01 = division(data_v05q_01, gen_v05q_01)
  let want_v05q_01 : Array[Int] = [
    213, 199, 11, 45, 115, 247, 241, 223, 229, 248, 154, 117, 154, 111, 86, 161,
    111, 39,
  ]
  if rem_v05q_01.length() != want_v05q_01.length() {
    fail(
      "v05q_01: remainder length got=" +
      rem_v05q_01.length().to_string() +
      " want=" +
      want_v05q_01.length().to_string(),
    )
  }
  let mut i_v05q_01 = 0
  while i_v05q_01 < want_v05q_01.length() {
    if rem_v05q_01[i_v05q_01].to_int() != want_v05q_01[i_v05q_01] {
      fail(
        "v05q_01: remainder byte " +
        i_v05q_01.to_string() +
        " got=" +
        rem_v05q_01[i_v05q_01].to_int().to_string() +
        " want=" +
        want_v05q_01[i_v05q_01].to_string(),
      )
    }
    i_v05q_01 += 1
  }
  // v05q_02: V05-ECL2，余数 18 字节
  let gen_v05q_02 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_02.length(), 19)
  let data_v05q_02 : Array[Byte] = [
    (246).to_byte(),
    (246).to_byte(),
    (66).to_byte(),
    (7).to_byte(),
    (118).to_byte(),
    (134).to_byte(),
    (242).to_byte(),
    (7).to_byte(),
    (38).to_byte(),
    (86).to_byte(),
    (22).to_byte(),
    (198).to_byte(),
    (199).to_byte(),
    (146).to_byte(),
    (6).to_byte(),
  ]
  let rem_v05q_02 = division(data_v05q_02, gen_v05q_02)
  let want_v05q_02 : Array[Int] = [
    87, 204, 96, 60, 202, 182, 124, 157, 200, 134, 27, 129, 209, 17, 163, 163, 120,
    133,
  ]
  if rem_v05q_02.length() != want_v05q_02.length() {
    fail(
      "v05q_02: remainder length got=" +
      rem_v05q_02.length().to_string() +
      " want=" +
      want_v05q_02.length().to_string(),
    )
  }
  let mut i_v05q_02 = 0
  while i_v05q_02 < want_v05q_02.length() {
    if rem_v05q_02[i_v05q_02].to_int() != want_v05q_02[i_v05q_02] {
      fail(
        "v05q_02: remainder byte " +
        i_v05q_02.to_string() +
        " got=" +
        rem_v05q_02[i_v05q_02].to_int().to_string() +
        " want=" +
        want_v05q_02[i_v05q_02].to_string(),
      )
    }
    i_v05q_02 += 1
  }
  // v05q_03: V05-ECL2，余数 18 字节
  let gen_v05q_03 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_03.length(), 19)
  let data_v05q_03 : Array[Byte] = [
    (182).to_byte(),
    (230).to_byte(),
    (247).to_byte(),
    (119).to_byte(),
    (50).to_byte(),
    (7).to_byte(),
    (118).to_byte(),
    (134).to_byte(),
    (87).to_byte(),
    (38).to_byte(),
    (82).to_byte(),
    (6).to_byte(),
    (134).to_byte(),
    (151).to_byte(),
    (50).to_byte(),
    (7).to_byte(),
  ]
  let rem_v05q_03 = division(data_v05q_03, gen_v05q_03)
  let want_v05q_03 : Array[Int] = [
    148, 116, 177, 212, 76, 133, 75, 242, 238, 76, 195, 230, 189, 10, 108, 240, 192,
    141,
  ]
  if rem_v05q_03.length() != want_v05q_03.length() {
    fail(
      "v05q_03: remainder length got=" +
      rem_v05q_03.length().to_string() +
      " want=" +
      want_v05q_03.length().to_string(),
    )
  }
  let mut i_v05q_03 = 0
  while i_v05q_03 < want_v05q_03.length() {
    if rem_v05q_03[i_v05q_03].to_int() != want_v05q_03[i_v05q_03] {
      fail(
        "v05q_03: remainder byte " +
        i_v05q_03.to_string() +
        " got=" +
        rem_v05q_03[i_v05q_03].to_int().to_string() +
        " want=" +
        want_v05q_03[i_v05q_03].to_string(),
      )
    }
    i_v05q_03 += 1
  }
  // v05q_04: V05-ECL2，余数 18 字节
  let gen_v05q_04 = @constants.get_polynomial(4, 2)
  assert_eq(gen_v05q_04.length(), 19)
  let data_v05q_04 : Array[Byte] = [
    (70).to_byte(),
    (247).to_byte(),
    (118).to_byte(),
    (86).to_byte(),
    (194).to_byte(),
    (6).to_byte(),
    (151).to_byte(),
    (50).to_byte(),
    (16).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
  ]
  let rem_v05q_04 = division(data_v05q_04, gen_v05q_04)
  let want_v05q_04 : Array[Int] = [
    235, 159, 5, 173, 24, 147, 59, 33, 106, 40, 255, 172, 82, 2, 131, 32, 178, 236,
  ]
  if rem_v05q_04.length() != want_v05q_04.length() {
    fail(
      "v05q_04: remainder length got=" +
      rem_v05q_04.length().to_string() +
      " want=" +
      want_v05q_04.length().to_string(),
    )
  }
  let mut i_v05q_04 = 0
  while i_v05q_04 < want_v05q_04.length() {
    if rem_v05q_04[i_v05q_04].to_int() != want_v05q_04[i_v05q_04] {
      fail(
        "v05q_04: remainder byte " +
        i_v05q_04.to_string() +
        " got=" +
        rem_v05q_04[i_v05q_04].to_int().to_string() +
        " want=" +
        want_v05q_04[i_v05q_04].to_string(),
      )
    }
    i_v05q_04 += 1
  }
  // struct_31_0: V05-ECL2，余数 18 字节
  let gen_struct_31_0 = @constants.get_polynomial(4, 2)
  assert_eq(gen_struct_31_0.length(), 19)
  let data_struct_31_0 : Array[Byte] = [
    (28).to_byte(),
    (195).to_byte(),
    (100).to_byte(),
    (36).to_byte(),
    (175).to_byte(),
    (11).to_byte(),
    (35).to_byte(),
    (243).to_byte(),
    (28).to_byte(),
    (137).to_byte(),
    (59).to_byte(),
    (182).to_byte(),
    (193).to_byte(),
  ]
  let rem_struct_31_0 = division(data_struct_31_0, gen_struct_31_0)
  let want_struct_31_0 : Array[Int] = [
    100, 125, 151, 135, 174, 245, 238, 245, 29, 25, 213, 169, 45, 206, 189, 118,
    163, 136,
  ]
  if rem_struct_31_0.length() != want_struct_31_0.length() {
    fail(
      "struct_31_0: remainder length got=" +
      rem_struct_31_0.length().to_string() +
      " want=" +
      want_struct_31_0.length().to_string(),
    )
  }
  let mut i_struct_31_0 = 0
  while i_struct_31_0 < want_struct_31_0.length() {
    if rem_struct_31_0[i_struct_31_0].to_int() !=
      want_struct_31_0[i_struct_31_0] {
      fail(
        "struct_31_0: remainder byte " +
        i_struct_31_0.to_string() +
        " got=" +
        rem_struct_31_0[i_struct_31_0].to_int().to_string() +
        " want=" +
        want_struct_31_0[i_struct_31_0].to_string(),
      )
    }
    i_struct_31_0 += 1
  }
  // struct_31_1: V05-ECL2，余数 18 字节
  let gen_struct_31_1 = @constants.get_polynomial(4, 2)
  assert_eq(gen_struct_31_1.length(), 19)
  let data_struct_31_1 : Array[Byte] = [
    (35).to_byte(),
    (37).to_byte(),
    (251).to_byte(),
    (189).to_byte(),
    (8).to_byte(),
    (169).to_byte(),
    (15).to_byte(),
    (34).to_byte(),
    (59).to_byte(),
    (137).to_byte(),
    (187).to_byte(),
    (114).to_byte(),
    (134).to_byte(),
  ]
  let rem_struct_31_1 = division(data_struct_31_1, gen_struct_31_1)
  let want_struct_31_1 : Array[Int] = [
    104, 119, 14, 38, 28, 163, 246, 77, 44, 194, 8, 121, 183, 161, 174, 157, 174,
    22,
  ]
  if rem_struct_31_1.length() != want_struct_31_1.length() {
    fail(
      "struct_31_1: remainder length got=" +
      rem_struct_31_1.length().to_string() +
      " want=" +
      want_struct_31_1.length().to_string(),
    )
  }
  let mut i_struct_31_1 = 0
  while i_struct_31_1 < want_struct_31_1.length() {
    if rem_struct_31_1[i_struct_31_1].to_int() !=
      want_struct_31_1[i_struct_31_1] {
      fail(
        "struct_31_1: remainder byte " +
        i_struct_31_1.to_string() +
        " got=" +
        rem_struct_31_1[i_struct_31_1].to_int().to_string() +
        " want=" +
        want_struct_31_1[i_struct_31_1].to_string(),
      )
    }
    i_struct_31_1 += 1
  }
  // small_1: V01-ECL0，余数 7 字节
  let gen_small_1 = @constants.get_polynomial(0, 0)
  assert_eq(gen_small_1.length(), 8)
  let data_small_1 : Array[Byte] = [(32).to_byte(), (9).to_byte()]
  let rem_small_1 = division(data_small_1, gen_small_1)
  let want_small_1 : Array[Int] = [16, 70, 12, 200, 52, 106, 229]
  if rem_small_1.length() != want_small_1.length() {
    fail(
      "small_1: remainder length got=" +
      rem_small_1.length().to_string() +
      " want=" +
      want_small_1.length().to_string(),
    )
  }
  let mut i_small_1 = 0
  while i_small_1 < want_small_1.length() {
    if rem_small_1[i_small_1].to_int() != want_small_1[i_small_1] {
      fail(
        "small_1: remainder byte " +
        i_small_1.to_string() +
        " got=" +
        rem_small_1[i_small_1].to_int().to_string() +
        " want=" +
        want_small_1[i_small_1].to_string(),
      )
    }
    i_small_1 += 1
  }
}

///|
/// T1-d structure 交织黄金值（S10 §6 T1-d）：5 组（V05-Q / V10-Q / V07-H / V16-M / V03-Q）。
/// 覆盖缺口 G4：此前仅 V05-Q 1 组。输入为确定性 LCG（可复现、非手抄），
/// 期望交织结果由 scripts/gen-goldens.sh --emit-rs 在参考侧 fast_qr 53e8c99 **实际计算**产出。
/// 每组断言消息区 / 纠错区全长，失败信息含组号与首个不一致下标（铁律 4）。
test "t1d_structure_golden" {
  // v05q: V05-ECL2，data=62 字节，out=134 字节
  let data_v05q : Array[Byte] = [
    (67).to_byte(),
    (85).to_byte(),
    (70).to_byte(),
    (134).to_byte(),
    (87).to_byte(),
    (38).to_byte(),
    (85).to_byte(),
    (194).to_byte(),
    (119).to_byte(),
    (50).to_byte(),
    (6).to_byte(),
    (18).to_byte(),
    (6).to_byte(),
    (103).to_byte(),
    (38).to_byte(),
    (246).to_byte(),
    (246).to_byte(),
    (66).to_byte(),
    (7).to_byte(),
    (118).to_byte(),
    (134).to_byte(),
    (242).to_byte(),
    (7).to_byte(),
    (38).to_byte(),
    (86).to_byte(),
    (22).to_byte(),
    (198).to_byte(),
    (199).to_byte(),
    (146).to_byte(),
    (6).to_byte(),
    (182).to_byte(),
    (230).to_byte(),
    (247).to_byte(),
    (119).to_byte(),
    (50).to_byte(),
    (7).to_byte(),
    (118).to_byte(),
    (134).to_byte(),
    (87).to_byte(),
    (38).to_byte(),
    (82).to_byte(),
    (6).to_byte(),
    (134).to_byte(),
    (151).to_byte(),
    (50).to_byte(),
    (7).to_byte(),
    (70).to_byte(),
    (247).to_byte(),
    (118).to_byte(),
    (86).to_byte(),
    (194).to_byte(),
    (6).to_byte(),
    (151).to_byte(),
    (50).to_byte(),
    (16).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
    (17).to_byte(),
    (236).to_byte(),
  ]
  let want_v05q : Array[Int] = [
    67, 246, 182, 70, 85, 246, 230, 247, 70, 66, 247, 118, 134, 7, 119, 86, 87, 118,
    50, 194, 38, 134, 7, 6, 85, 242, 118, 151, 194, 7, 134, 50, 119, 38, 87, 16,
    50, 86, 38, 236, 6, 22, 82, 17, 18, 198, 6, 236, 6, 199, 134, 17, 103, 146, 151,
    236, 38, 6, 50, 17, 7, 236, 213, 87, 148, 235, 199, 204, 116, 159, 11, 96, 177,
    5, 45, 60, 212, 173, 115, 202, 76, 24, 247, 182, 133, 147, 241, 124, 75, 59,
    223, 157, 242, 33, 229, 200, 238, 106, 248, 134, 76, 40, 154, 27, 195, 255, 117,
    129, 230, 172, 154, 209, 189, 82, 111, 17, 10, 2, 86, 163, 108, 131, 161, 163,
    240, 32, 111, 120, 192, 178, 39, 133, 141, 236,
  ]
  let got_v05q = structure(data_v05q, 2, 4)
  let mut i_v05q = 0
  while i_v05q < want_v05q.length() {
    if got_v05q[i_v05q].to_int() != want_v05q[i_v05q] {
      fail(
        "v05q: structure byte " +
        i_v05q.to_string() +
        " got=" +
        got_v05q[i_v05q].to_int().to_string() +
        " want=" +
        want_v05q[i_v05q].to_string(),
      )
    }
    i_v05q += 1
  }
  // v10q: V10-ECL2，data=154 字节，out=346 字节
  let data_v10q : Array[Byte] = [
    (113).to_byte(),
    (71).to_byte(),
    (29).to_byte(),
    (148).to_byte(),
    (236).to_byte(),
    (137).to_byte(),
    (147).to_byte(),
    (199).to_byte(),
    (68).to_byte(),
    (188).to_byte(),
    (216).to_byte(),
    (207).to_byte(),
    (203).to_byte(),
    (60).to_byte(),
    (197).to_byte(),
    (166).to_byte(),
    (104).to_byte(),
    (25).to_byte(),
    (168).to_byte(),
    (230).to_byte(),
    (202).to_byte(),
    (164).to_byte(),
    (226).to_byte(),
    (59).to_byte(),
    (105).to_byte(),
    (189).to_byte(),
    (65).to_byte(),
    (137).to_byte(),
    (65).to_byte(),
    (218).to_byte(),
    (30).to_byte(),
    (220).to_byte(),
    (78).to_byte(),
    (216).to_byte(),
    (54).to_byte(),
    (19).to_byte(),
    (198).to_byte(),
    (130).to_byte(),
    (73).to_byte(),
    (76).to_byte(),
    (25).to_byte(),
    (226).to_byte(),
    (116).to_byte(),
    (14).to_byte(),
    (169).to_byte(),
    (74).to_byte(),
    (79).to_byte(),
    (57).to_byte(),
    (73).to_byte(),
    (32).to_byte(),
    (198).to_byte(),
    (174).to_byte(),
    (119).to_byte(),
    (109).to_byte(),
    (184).to_byte(),
    (190).to_byte(),
    (89).to_byte(),
    (37).to_byte(),
    (81).to_byte(),
    (84).to_byte(),
    (122).to_byte(),
    (52).to_byte(),
    (40).to_byte(),
    (225).to_byte(),
    (65).to_byte(),
    (77).to_byte(),
    (24).to_byte(),
    (10).to_byte(),
    (53).to_byte(),
    (113).to_byte(),
    (222).to_byte(),
    (20).to_byte(),
    (242).to_byte(),
    (65).to_byte(),
    (119).to_byte(),
    (11).to_byte(),
    (234).to_byte(),
    (5).to_byte(),
    (55).to_byte(),
    (181).to_byte(),
    (221).to_byte(),
    (120).to_byte(),
    (169).to_byte(),
    (58).to_byte(),
    (22).to_byte(),
    (89).to_byte(),
    (42).to_byte(),
    (144).to_byte(),
    (107).to_byte(),
    (178).to_byte(),
    (68).to_byte(),
    (168).to_byte(),
    (242).to_byte(),
    (230).to_byte(),
    (203).to_byte(),
    (90).to_byte(),
    (131).to_byte(),
    (126).to_byte(),
    (186).to_byte(),
    (17).to_byte(),
    (242).to_byte(),
    (176).to_byte(),
    (203).to_byte(),
    (54).to_byte(),
    (9).to_byte(),
    (179).to_byte(),
    (216).to_byte(),
    (94).to_byte(),
    (72).to_byte(),
    (197).to_byte(),
    (244).to_byte(),
    (50).to_byte(),
    (92).to_byte(),
    (248).to_byte(),
    (72).to_byte(),
    (34).to_byte(),
    (95).to_byte(),
    (192).to_byte(),
    (175).to_byte(),
    (201).to_byte(),
    (213).to_byte(),
    (62).to_byte(),
    (17).to_byte(),
    (30).to_byte(),
    (98).to_byte(),
    (74).to_byte(),
    (128).to_byte(),
    (96).to_byte(),
    (77).to_byte(),
    (67).to_byte(),
    (20).to_byte(),
    (192).to_byte(),
    (181).to_byte(),
    (150).to_byte(),
    (135).to_byte(),
    (203).to_byte(),
    (149).to_byte(),
    (15).to_byte(),
    (143).to_byte(),
    (158).to_byte(),
    (121).to_byte(),
    (226).to_byte(),
    (255).to_byte(),
    (200).to_byte(),
    (253).to_byte(),
    (120).to_byte(),
    (156).to_byte(),
    (253).to_byte(),
    (10).to_byte(),
    (251).to_byte(),
    (192).to_byte(),
    (128).to_byte(),
    (208).to_byte(),
    (160).to_byte(),
  ]
  let want_v10q : Array[Int] = [
    113, 230, 73, 37, 234, 90, 72, 135, 71, 202, 76, 81, 5, 131, 34, 203, 29, 164,
    25, 84, 55, 126, 95, 149, 148, 226, 226, 122, 181, 186, 192, 15, 236, 59, 116,
    52, 221, 17, 175, 143, 137, 105, 14, 40, 120, 242, 201, 158, 147, 189, 169, 225,
    169, 176, 213, 121, 199, 65, 74, 65, 58, 203, 62, 226, 68, 137, 79, 77, 22, 54,
    17, 255, 188, 65, 57, 24, 89, 9, 30, 200, 216, 218, 73, 10, 42, 179, 98, 253,
    207, 30, 32, 53, 144, 216, 74, 120, 203, 220, 198, 113, 107, 94, 128, 156, 60,
    78, 174, 222, 178, 72, 96, 253, 197, 216, 119, 20, 68, 197, 77, 10, 166, 54,
    109, 242, 168, 244, 67, 251, 104, 19, 184, 65, 242, 50, 20, 192, 25, 198, 190,
    119, 230, 92, 192, 128, 168, 130, 89, 11, 203, 248, 181, 208, 150, 160, 93, 238,
    182, 24, 9, 207, 229, 28, 219, 101, 84, 207, 184, 5, 75, 155, 25, 113, 13, 30,
    129, 112, 57, 64, 78, 218, 101, 226, 130, 8, 86, 165, 174, 118, 213, 130, 19,
    76, 248, 19, 213, 251, 215, 214, 209, 214, 213, 28, 254, 89, 40, 100, 33, 179,
    95, 129, 120, 220, 99, 235, 218, 29, 255, 170, 12, 124, 165, 40, 2, 162, 97,
    75, 129, 32, 147, 52, 214, 192, 190, 188, 168, 145, 253, 119, 209, 2, 124, 85,
    220, 195, 34, 153, 139, 251, 57, 51, 137, 234, 128, 26, 60, 77, 242, 52, 100,
    219, 41, 31, 139, 181, 187, 175, 32, 59, 66, 40, 52, 13, 42, 178, 46, 228, 185,
    117, 175, 105, 34, 7, 107, 249, 6, 164, 255, 28, 132, 209, 222, 33, 119, 133,
    92, 132, 24, 140, 24, 238, 158, 87, 29, 79, 171, 18, 26, 211, 61, 121, 25, 136,
    66, 112, 100, 3, 104, 138, 164, 154, 66, 24, 249, 139, 238, 111, 222, 34, 231,
    255, 228, 182, 193, 111, 34, 252, 128, 64, 212, 240, 184, 39, 146, 250, 129,
    47,
  ]
  let got_v10q = structure(data_v10q, 2, 9)
  let mut i_v10q = 0
  while i_v10q < want_v10q.length() {
    if got_v10q[i_v10q].to_int() != want_v10q[i_v10q] {
      fail(
        "v10q: structure byte " +
        i_v10q.to_string() +
        " got=" +
        got_v10q[i_v10q].to_int().to_string() +
        " want=" +
        want_v10q[i_v10q].to_string(),
      )
    }
    i_v10q += 1
  }
  // v07h: V07-ECL3，data=66 字节，out=196 字节
  let data_v07h : Array[Byte] = [
    (113).to_byte(),
    (71).to_byte(),
    (29).to_byte(),
    (148).to_byte(),
    (236).to_byte(),
    (137).to_byte(),
    (147).to_byte(),
    (199).to_byte(),
    (68).to_byte(),
    (188).to_byte(),
    (216).to_byte(),
    (207).to_byte(),
    (203).to_byte(),
    (60).to_byte(),
    (197).to_byte(),
    (166).to_byte(),
    (104).to_byte(),
    (25).to_byte(),
    (168).to_byte(),
    (230).to_byte(),
    (202).to_byte(),
    (164).to_byte(),
    (226).to_byte(),
    (59).to_byte(),
    (105).to_byte(),
    (189).to_byte(),
    (65).to_byte(),
    (137).to_byte(),
    (65).to_byte(),
    (218).to_byte(),
    (30).to_byte(),
    (220).to_byte(),
    (78).to_byte(),
    (216).to_byte(),
    (54).to_byte(),
    (19).to_byte(),
    (198).to_byte(),
    (130).to_byte(),
    (73).to_byte(),
    (76).to_byte(),
    (25).to_byte(),
    (226).to_byte(),
    (116).to_byte(),
    (14).to_byte(),
    (169).to_byte(),
    (74).to_byte(),
    (79).to_byte(),
    (57).to_byte(),
    (73).to_byte(),
    (32).to_byte(),
    (198).to_byte(),
    (174).to_byte(),
    (119).to_byte(),
    (109).to_byte(),
    (184).to_byte(),
    (190).to_byte(),
    (89).to_byte(),
    (37).to_byte(),
    (81).to_byte(),
    (84).to_byte(),
    (122).to_byte(),
    (52).to_byte(),
    (40).to_byte(),
    (225).to_byte(),
    (65).to_byte(),
    (77).to_byte(),
  ]
  let want_v07h : Array[Int] = [
    113, 60, 65, 76, 119, 71, 197, 137, 25, 109, 29, 166, 65, 226, 184, 148, 104,
    218, 116, 190, 236, 25, 30, 14, 89, 137, 168, 220, 169, 37, 147, 230, 78, 74,
    81, 199, 202, 216, 79, 84, 68, 164, 54, 57, 122, 188, 226, 19, 73, 52, 216, 59,
    198, 32, 40, 207, 105, 130, 198, 225, 203, 189, 73, 174, 65, 77, 44, 240, 124,
    14, 98, 219, 41, 54, 162, 103, 72, 66, 74, 118, 98, 165, 195, 170, 36, 145, 36,
    209, 134, 179, 174, 32, 215, 83, 57, 188, 160, 243, 28, 183, 101, 17, 170, 196,
    26, 205, 130, 65, 15, 107, 42, 103, 120, 7, 37, 73, 173, 81, 110, 79, 75, 71,
    128, 135, 31, 68, 13, 177, 205, 128, 135, 26, 237, 18, 111, 211, 95, 54, 150,
    51, 210, 79, 81, 196, 156, 146, 151, 192, 42, 39, 183, 235, 198, 1, 129, 247,
    107, 252, 54, 173, 155, 162, 50, 58, 30, 124, 20, 174, 232, 226, 72, 74, 196,
    117, 128, 64, 190, 16, 241, 11, 78, 154, 243, 243, 46, 231, 181, 246, 144, 156,
    225, 119, 96, 204, 16, 61,
  ]
  let got_v07h = structure(data_v07h, 3, 6)
  let mut i_v07h = 0
  while i_v07h < want_v07h.length() {
    if got_v07h[i_v07h].to_int() != want_v07h[i_v07h] {
      fail(
        "v07h: structure byte " +
        i_v07h.to_string() +
        " got=" +
        got_v07h[i_v07h].to_int().to_string() +
        " want=" +
        want_v07h[i_v07h].to_string(),
      )
    }
    i_v07h += 1
  }
  // v16m: V16-ECL1，data=453 字节，out=733 字节
  let data_v16m : Array[Byte] = [
    (113).to_byte(),
    (71).to_byte(),
    (29).to_byte(),
    (148).to_byte(),
    (236).to_byte(),
    (137).to_byte(),
    (147).to_byte(),
    (199).to_byte(),
    (68).to_byte(),
    (188).to_byte(),
    (216).to_byte(),
    (207).to_byte(),
    (203).to_byte(),
    (60).to_byte(),
    (197).to_byte(),
    (166).to_byte(),
    (104).to_byte(),
    (25).to_byte(),
    (168).to_byte(),
    (230).to_byte(),
    (202).to_byte(),
    (164).to_byte(),
    (226).to_byte(),
    (59).to_byte(),
    (105).to_byte(),
    (189).to_byte(),
    (65).to_byte(),
    (137).to_byte(),
    (65).to_byte(),
    (218).to_byte(),
    (30).to_byte(),
    (220).to_byte(),
    (78).to_byte(),
    (216).to_byte(),
    (54).to_byte(),
    (19).to_byte(),
    (198).to_byte(),
    (130).to_byte(),
    (73).to_byte(),
    (76).to_byte(),
    (25).to_byte(),
    (226).to_byte(),
    (116).to_byte(),
    (14).to_byte(),
    (169).to_byte(),
    (74).to_byte(),
    (79).to_byte(),
    (57).to_byte(),
    (73).to_byte(),
    (32).to_byte(),
    (198).to_byte(),
    (174).to_byte(),
    (119).to_byte(),
    (109).to_byte(),
    (184).to_byte(),
    (190).to_byte(),
    (89).to_byte(),
    (37).to_byte(),
    (81).to_byte(),
    (84).to_byte(),
    (122).to_byte(),
    (52).to_byte(),
    (40).to_byte(),
    (225).to_byte(),
    (65).to_byte(),
    (77).to_byte(),
    (24).to_byte(),
    (10).to_byte(),
    (53).to_byte(),
    (113).to_byte(),
    (222).to_byte(),
    (20).to_byte(),
    (242).to_byte(),
    (65).to_byte(),
    (119).to_byte(),
    (11).to_byte(),
    (234).to_byte(),
    (5).to_byte(),
    (55).to_byte(),
    (181).to_byte(),
    (221).to_byte(),
    (120).to_byte(),
    (169).to_byte(),
    (58).to_byte(),
    (22).to_byte(),
    (89).to_byte(),
    (42).to_byte(),
    (144).to_byte(),
    (107).to_byte(),
    (178).to_byte(),
    (68).to_byte(),
    (168).to_byte(),
    (242).to_byte(),
    (230).to_byte(),
    (203).to_byte(),
    (90).to_byte(),
    (131).to_byte(),
    (126).to_byte(),
    (186).to_byte(),
    (17).to_byte(),
    (242).to_byte(),
    (176).to_byte(),
    (203).to_byte(),
    (54).to_byte(),
    (9).to_byte(),
    (179).to_byte(),
    (216).to_byte(),
    (94).to_byte(),
    (72).to_byte(),
    (197).to_byte(),
    (244).to_byte(),
    (50).to_byte(),
    (92).to_byte(),
    (248).to_byte(),
    (72).to_byte(),
    (34).to_byte(),
    (95).to_byte(),
    (192).to_byte(),
    (175).to_byte(),
    (201).to_byte(),
    (213).to_byte(),
    (62).to_byte(),
    (17).to_byte(),
    (30).to_byte(),
    (98).to_byte(),
    (74).to_byte(),
    (128).to_byte(),
    (96).to_byte(),
    (77).to_byte(),
    (67).to_byte(),
    (20).to_byte(),
    (192).to_byte(),
    (181).to_byte(),
    (150).to_byte(),
    (135).to_byte(),
    (203).to_byte(),
    (149).to_byte(),
    (15).to_byte(),
    (143).to_byte(),
    (158).to_byte(),
    (121).to_byte(),
    (226).to_byte(),
    (255).to_byte(),
    (200).to_byte(),
    (253).to_byte(),
    (120).to_byte(),
    (156).to_byte(),
    (253).to_byte(),
    (10).to_byte(),
    (251).to_byte(),
    (192).to_byte(),
    (128).to_byte(),
    (208).to_byte(),
    (160).to_byte(),
    (177).to_byte(),
    (78).to_byte(),
    (131).to_byte(),
    (183).to_byte(),
    (190).to_byte(),
    (11).to_byte(),
    (213).to_byte(),
    (116).to_byte(),
    (31).to_byte(),
    (174).to_byte(),
    (54).to_byte(),
    (123).to_byte(),
    (138).to_byte(),
    (235).to_byte(),
    (206).to_byte(),
    (45).to_byte(),
    (149).to_byte(),
    (99).to_byte(),
    (54).to_byte(),
    (181).to_byte(),
    (207).to_byte(),
    (142).to_byte(),
    (250).to_byte(),
    (209).to_byte(),
    (156).to_byte(),
    (100).to_byte(),
    (207).to_byte(),
    (96).to_byte(),
    (212).to_byte(),
    (206).to_byte(),
    (149).to_byte(),
    (176).to_byte(),
    (27).to_byte(),
    (208).to_byte(),
    (11).to_byte(),
    (133).to_byte(),
    (254).to_byte(),
    (115).to_byte(),
    (84).to_byte(),
    (233).to_byte(),
    (210).to_byte(),
    (115).to_byte(),
    (45).to_byte(),
    (183).to_byte(),
    (77).to_byte(),
    (173).to_byte(),
    (235).to_byte(),
    (229).to_byte(),
    (225).to_byte(),
    (71).to_byte(),
    (55).to_byte(),
    (148).to_byte(),
    (220).to_byte(),
    (157).to_byte(),
    (138).to_byte(),
    (217).to_byte(),
    (65).to_byte(),
    (239).to_byte(),
    (102).to_byte(),
    (73).to_byte(),
    (100).to_byte(),
    (203).to_byte(),
    (90).to_byte(),
    (71).to_byte(),
    (71).to_byte(),
    (59).to_byte(),
    (179).to_byte(),
    (13).to_byte(),
    (183).to_byte(),
    (175).to_byte(),
    (2).to_byte(),
    (123).to_byte(),
    (38).to_byte(),
    (169).to_byte(),
    (82).to_byte(),
    (162).to_byte(),
    (71).to_byte(),
    (43).to_byte(),
    (38).to_byte(),
    (16).to_byte(),
    (108).to_byte(),
    (224).to_byte(),
    (53).to_byte(),
    (217).to_byte(),
    (159).to_byte(),
    (12).to_byte(),
    (228).to_byte(),
    (106).to_byte(),
    (130).to_byte(),
    (53).to_byte(),
    (135).to_byte(),
    (13).to_byte(),
    (231).to_byte(),
    (143).to_byte(),
    (88).to_byte(),
    (59).to_byte(),
    (46).to_byte(),
    (40).to_byte(),
    (51).to_byte(),
    (165).to_byte(),
    (98).to_byte(),
    (216).to_byte(),
    (23).to_byte(),
    (1).to_byte(),
    (18).to_byte(),
    (230).to_byte(),
    (93).to_byte(),
    (149).to_byte(),
    (241).to_byte(),
    (122).to_byte(),
    (182).to_byte(),
    (132).to_byte(),
    (45).to_byte(),
    (199).to_byte(),
    (230).to_byte(),
    (220).to_byte(),
    (143).to_byte(),
    (245).to_byte(),
    (66).to_byte(),
    (91).to_byte(),
    (87).to_byte(),
    (207).to_byte(),
    (234).to_byte(),
    (4).to_byte(),
    (213).to_byte(),
    (49).to_byte(),
    (199).to_byte(),
    (102).to_byte(),
    (199).to_byte(),
    (47).to_byte(),
    (67).to_byte(),
    (167).to_byte(),
    (118).to_byte(),
    (6).to_byte(),
    (203).to_byte(),
    (83).to_byte(),
    (143).to_byte(),
    (195).to_byte(),
    (6).to_byte(),
    (231).to_byte(),
    (194).to_byte(),
    (181).to_byte(),
    (210).to_byte(),
    (27).to_byte(),
    (28).to_byte(),
    (148).to_byte(),
    (3).to_byte(),
    (243).to_byte(),
    (37).to_byte(),
    (110).to_byte(),
    (218).to_byte(),
    (132).to_byte(),
    (185).to_byte(),
    (85).to_byte(),
    (71).to_byte(),
    (135).to_byte(),
    (167).to_byte(),
    (202).to_byte(),
    (223).to_byte(),
    (159).to_byte(),
    (11).to_byte(),
    (231).to_byte(),
    (155).to_byte(),
    (106).to_byte(),
    (107).to_byte(),
    (80).to_byte(),
    (86).to_byte(),
    (73).to_byte(),
    (148).to_byte(),
    (216).to_byte(),
    (4).to_byte(),
    (240).to_byte(),
    (51).to_byte(),
    (242).to_byte(),
    (179).to_byte(),
    (172).to_byte(),
    (50).to_byte(),
    (222).to_byte(),
    (68).to_byte(),
    (119).to_byte(),
    (216).to_byte(),
    (143).to_byte(),
    (230).to_byte(),
    (190).to_byte(),
    (159).to_byte(),
    (94).to_byte(),
    (86).to_byte(),
    (236).to_byte(),
    (212).to_byte(),
    (113).to_byte(),
    (215).to_byte(),
    (190).to_byte(),
    (241).to_byte(),
    (233).to_byte(),
    (243).to_byte(),
    (70).to_byte(),
    (186).to_byte(),
    (207).to_byte(),
    (240).to_byte(),
    (188).to_byte(),
    (26).to_byte(),
    (188).to_byte(),
    (17).to_byte(),
    (8).to_byte(),
    (187).to_byte(),
    (74).to_byte(),
    (146).to_byte(),
    (16).to_byte(),
    (103).to_byte(),
    (62).to_byte(),
    (97).to_byte(),
    (193).to_byte(),
    (33).to_byte(),
    (114).to_byte(),
    (156).to_byte(),
    (223).to_byte(),
    (2).to_byte(),
    (131).to_byte(),
    (206).to_byte(),
    (141).to_byte(),
    (213).to_byte(),
    (64).to_byte(),
    (233).to_byte(),
    (156).to_byte(),
    (114).to_byte(),
    (205).to_byte(),
    (3).to_byte(),
    (147).to_byte(),
    (219).to_byte(),
    (154).to_byte(),
    (209).to_byte(),
    (130).to_byte(),
    (24).to_byte(),
    (8).to_byte(),
    (228).to_byte(),
    (135).to_byte(),
    (210).to_byte(),
    (213).to_byte(),
    (165).to_byte(),
    (29).to_byte(),
    (177).to_byte(),
    (75).to_byte(),
    (17).to_byte(),
    (40).to_byte(),
    (119).to_byte(),
    (45).to_byte(),
    (53).to_byte(),
    (193).to_byte(),
    (217).to_byte(),
    (92).to_byte(),
    (105).to_byte(),
    (193).to_byte(),
    (33).to_byte(),
    (76).to_byte(),
    (76).to_byte(),
    (15).to_byte(),
    (133).to_byte(),
    (43).to_byte(),
    (131).to_byte(),
    (170).to_byte(),
    (68).to_byte(),
    (203).to_byte(),
    (48).to_byte(),
    (117).to_byte(),
    (134).to_byte(),
    (83).to_byte(),
    (52).to_byte(),
    (198).to_byte(),
    (241).to_byte(),
    (170).to_byte(),
    (37).to_byte(),
    (173).to_byte(),
    (11).to_byte(),
    (159).to_byte(),
    (14).to_byte(),
    (4).to_byte(),
    (82).to_byte(),
    (216).to_byte(),
    (233).to_byte(),
    (59).to_byte(),
    (29).to_byte(),
    (129).to_byte(),
    (221).to_byte(),
    (224).to_byte(),
    (49).to_byte(),
    (176).to_byte(),
    (56).to_byte(),
    (241).to_byte(),
    (34).to_byte(),
    (154).to_byte(),
    (43).to_byte(),
    (226).to_byte(),
    (112).to_byte(),
    (120).to_byte(),
    (71).to_byte(),
    (108).to_byte(),
    (93).to_byte(),
    (55).to_byte(),
    (187).to_byte(),
  ]
  let want_v16m : Array[Int] = [
    113, 74, 68, 203, 207, 123, 143, 231, 16, 76, 71, 79, 168, 149, 96, 38, 245,
    155, 103, 76, 29, 57, 242, 15, 212, 169, 66, 106, 62, 15, 148, 73, 230, 143,
    206, 82, 91, 107, 97, 133, 236, 32, 203, 158, 149, 162, 87, 80, 193, 43, 137,
    198, 90, 121, 176, 71, 207, 86, 33, 131, 147, 174, 131, 226, 27, 43, 234, 73,
    114, 170, 199, 119, 126, 255, 208, 38, 4, 148, 156, 68, 68, 109, 186, 200, 11,
    16, 213, 216, 223, 203, 188, 184, 17, 253, 133, 108, 49, 4, 2, 48, 216, 190,
    242, 120, 254, 224, 199, 240, 131, 117, 207, 89, 176, 156, 115, 53, 102, 51,
    206, 134, 203, 37, 203, 253, 84, 217, 199, 242, 141, 83, 60, 81, 54, 10, 233,
    159, 47, 179, 213, 52, 197, 84, 9, 251, 210, 12, 67, 172, 64, 198, 166, 122,
    179, 192, 115, 228, 167, 50, 233, 241, 104, 52, 216, 128, 45, 106, 118, 222,
    156, 170, 25, 40, 94, 208, 183, 130, 6, 68, 114, 37, 168, 225, 72, 160, 77, 53,
    203, 119, 205, 173, 230, 65, 197, 177, 173, 135, 83, 216, 3, 11, 202, 77, 244,
    78, 235, 13, 143, 143, 147, 159, 164, 24, 50, 131, 229, 231, 195, 230, 219, 14,
    226, 10, 92, 183, 225, 143, 6, 190, 154, 4, 59, 53, 248, 190, 71, 88, 231, 159,
    209, 82, 105, 113, 72, 11, 55, 59, 194, 94, 130, 216, 189, 222, 34, 213, 148,
    46, 181, 86, 24, 233, 65, 20, 95, 116, 220, 40, 210, 236, 8, 59, 137, 242, 192,
    31, 157, 51, 27, 212, 228, 29, 65, 65, 175, 174, 138, 165, 28, 113, 135, 129,
    218, 119, 201, 54, 217, 98, 148, 215, 210, 221, 30, 11, 213, 123, 65, 216, 3,
    190, 213, 224, 220, 234, 62, 138, 239, 23, 243, 241, 165, 49, 78, 5, 17, 235,
    102, 1, 37, 233, 29, 176, 216, 55, 30, 206, 73, 18, 110, 243, 177, 56, 54, 181,
    98, 45, 100, 230, 218, 70, 75, 241, 19, 221, 74, 149, 203, 93, 132, 186, 17,
    34, 198, 120, 128, 99, 90, 149, 185, 207, 40, 154, 130, 169, 96, 54, 71, 241,
    85, 240, 119, 43, 73, 58, 77, 181, 71, 122, 71, 188, 45, 226, 76, 22, 67, 207,
    59, 182, 135, 26, 53, 112, 25, 89, 20, 142, 179, 132, 167, 188, 193, 120, 226,
    42, 192, 250, 13, 45, 202, 17, 217, 71, 116, 144, 181, 209, 183, 199, 223, 8,
    92, 108, 14, 107, 150, 156, 175, 230, 159, 187, 105, 93, 169, 178, 135, 100,
    2, 220, 11, 74, 193, 55, 146, 33, 187, 2, 235, 235, 216, 211, 30, 39, 36, 132,
    37, 60, 241, 248, 100, 30, 59, 43, 165, 59, 202, 113, 152, 232, 178, 79, 25,
    37, 191, 221, 50, 31, 64, 238, 75, 71, 214, 143, 69, 200, 240, 152, 214, 252,
    202, 117, 126, 101, 114, 71, 105, 160, 189, 137, 162, 35, 159, 106, 121, 215,
    216, 108, 125, 43, 198, 112, 203, 72, 184, 191, 119, 213, 229, 128, 215, 217,
    119, 41, 45, 83, 149, 18, 125, 210, 203, 42, 57, 154, 162, 53, 227, 246, 20,
    135, 11, 181, 133, 174, 131, 110, 21, 214, 246, 25, 196, 220, 180, 254, 64, 96,
    207, 161, 49, 52, 113, 35, 191, 33, 15, 52, 90, 168, 126, 169, 111, 142, 44,
    1, 40, 0, 143, 138, 181, 0, 136, 72, 64, 137, 179, 94, 227, 60, 42, 173, 151,
    152, 3, 127, 220, 199, 249, 9, 5, 1, 1, 219, 137, 165, 192, 248, 173, 12, 73,
    104, 10, 160, 155, 207, 27, 167, 90, 199, 168, 217, 219, 89, 21, 21, 196, 164,
    22, 101, 128, 132, 32, 236, 3, 251, 10, 124, 194, 120, 211, 159, 32, 169, 226,
    51, 137, 207, 253, 88, 1, 211, 212, 17, 134, 17, 139, 23, 206, 9, 81, 67, 65,
    88, 157, 75, 206, 23, 34, 142, 130, 61, 117, 135, 201, 104, 213, 188, 198, 11,
    35, 241, 2, 13, 59, 60, 31, 204, 188, 125, 205, 224, 114, 99, 17, 40, 172, 140,
    52, 16, 148, 169, 172, 130, 113, 109, 144, 91, 214, 194, 209, 228, 100, 35, 216,
    120, 50, 169, 185, 26, 71, 127, 62, 174, 164, 144, 170, 77, 129,
  ]
  let got_v16m = structure(data_v16m, 1, 15)
  let mut i_v16m = 0
  while i_v16m < want_v16m.length() {
    if got_v16m[i_v16m].to_int() != want_v16m[i_v16m] {
      fail(
        "v16m: structure byte " +
        i_v16m.to_string() +
        " got=" +
        got_v16m[i_v16m].to_int().to_string() +
        " want=" +
        want_v16m[i_v16m].to_string(),
      )
    }
    i_v16m += 1
  }
  // v03q: V03-ECL2，data=34 字节，out=70 字节
  let data_v03q : Array[Byte] = [
    (113).to_byte(),
    (71).to_byte(),
    (29).to_byte(),
    (148).to_byte(),
    (236).to_byte(),
    (137).to_byte(),
    (147).to_byte(),
    (199).to_byte(),
    (68).to_byte(),
    (188).to_byte(),
    (216).to_byte(),
    (207).to_byte(),
    (203).to_byte(),
    (60).to_byte(),
    (197).to_byte(),
    (166).to_byte(),
    (104).to_byte(),
    (25).to_byte(),
    (168).to_byte(),
    (230).to_byte(),
    (202).to_byte(),
    (164).to_byte(),
    (226).to_byte(),
    (59).to_byte(),
    (105).to_byte(),
    (189).to_byte(),
    (65).to_byte(),
    (137).to_byte(),
    (65).to_byte(),
    (218).to_byte(),
    (30).to_byte(),
    (220).to_byte(),
    (78).to_byte(),
    (216).to_byte(),
  ]
  let want_v03q : Array[Int] = [
    113, 25, 71, 168, 29, 230, 148, 202, 236, 164, 137, 226, 147, 59, 199, 105, 68,
    189, 188, 65, 216, 137, 207, 65, 203, 218, 60, 30, 197, 220, 166, 78, 104, 216,
    226, 252, 69, 45, 226, 107, 201, 29, 238, 93, 64, 28, 210, 38, 43, 84, 157, 41,
    37, 141, 107, 245, 155, 255, 56, 22, 46, 141, 20, 169, 9, 160, 47, 82, 42, 201,
  ]
  let got_v03q = structure(data_v03q, 2, 2)
  let mut i_v03q = 0
  while i_v03q < want_v03q.length() {
    if got_v03q[i_v03q].to_int() != want_v03q[i_v03q] {
      fail(
        "v03q: structure byte " +
        i_v03q.to_string() +
        " got=" +
        got_v03q[i_v03q].to_int().to_string() +
        " want=" +
        want_v03q[i_v03q].to_string(),
      )
    }
    i_v03q += 1
  }
}
