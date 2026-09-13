///|
/// constants_wbtest.mbt —— capacity/hardcode 白盒黄金测试
/// 期望值来自 fast_qr v0.14.0 参考源码（Version::get 分段 / hardcode 表）。

///|
test "version_for_numeric_l" {
  // Numeric(0)-L(0)：41→V01，42→V02，… 7090→V40，超界→-1
  assert_eq(version_for(0, 0, 0), 0)
  assert_eq(version_for(0, 0, 41), 0)
  assert_eq(version_for(0, 0, 42), 1)
  assert_eq(version_for(0, 0, 7089), 39)
  assert_eq(version_for(0, 0, 10000), -1)
}

///|
test "version_for_byte_h" {
  // Byte(2)-H(3)：V01 上限 7
  assert_eq(version_for(2, 3, 7), 0)
  assert_eq(version_for(2, 3, 8), 1)
}

///|
test "capacity_bytes_lookup" {
  // Numeric-L-V01 = 41；Byte-L-V01 = 17；Alphanumeric-M-V40 = 3391
  assert_eq(capacity_bytes(0, 0, 0), 41)
  assert_eq(capacity_bytes(2, 0, 0), 17)
  assert_eq(capacity_bytes(1, 1, 39), 3391)
}

///|
test "max_bytes_and_data_codewords" {
  assert_eq(max_bytes(0), 26) // V1
  assert_eq(max_bytes(39), 3706) // V40
  // data_codewords L-V1=19, Q-V5=62, H-V40=1276
  assert_eq(data_codewords(0, 0), 19)
  assert_eq(data_codewords(2, 4), 62)
  assert_eq(data_codewords(3, 39), 1276)
  assert_eq(data_bits(0, 0), 19 * 8)
}

///|
test "information_alignment_missing" {
  assert_eq(information(0), 0) // V1
  assert_eq(information(6), 31892) // V7 版本信息
  assert_eq(alignment_grid(0).length(), 0) // V1 无对齐
  let v7 = alignment_grid(6)
  assert_eq(v7, [6, 22, 38])
  assert_eq(missing_bits(1), 7) // V2
  assert_eq(missing_bits(13), 3) // V14
  assert_eq(missing_bits(20), 4) // V21
}

///|
test "ecc_to_groups_and_polynomial" {
  // ecc_to_groups L-V1 = (1,19,0,0)
  assert_eq(ecc_to_groups(0, 0), (1, 19, 0, 0))
  // ecc_to_groups L-V10 = (2,68,2,69)
  assert_eq(ecc_to_groups(0, 9), (2, 68, 2, 69))
  // get_polynomial V01-L = [0,87,229,146,149,238,102,21]（度 7）
  let p = get_polynomial(0, 0)
  assert_eq(p, [
    (0).to_byte(),
    (87).to_byte(),
    (229).to_byte(),
    (146).to_byte(),
    (149).to_byte(),
    (238).to_byte(),
    (102).to_byte(),
    (21).to_byte(),
  ])
  // V40-H 度 30（长 31）
  assert_eq(get_polynomial(39, 3).length(), 31)
}

///|
test "format_information" {
  // L-mask0 期望 0b111_0111_1100_0100 = 30660
  assert_eq(format_information(0, 0), 30660)
  // H-mask7 期望 0b000_1000_0011_1011 = 2107
  assert_eq(format_information(3, 7), 2107)
}

///|
/// 表间不变量交叉自检（全 4×40 项）：防「脚本生成 / 日后手改」导致的表漂移。
/// ① 分组自洽：ecc_to_groups 的 (g1c*g1s + g2c*g2s) 恒等于 data_codewords。
/// ② 度自洽：生成多项式度 = (max_bytes - data_codewords) / (g1c+g2c)，且恒为整数、
///    与 get_polynomial 返回长度-1 一致（等价 generator_index 选表）。
/// ③ 容量最小性：version_for 返回的版本恰好是首个容量 ≥ len 的版本（前一版本装不下）。
test "table_cross_consistency_160" {
  let mut v = 0
  while v < 40 {
    let mut e = 0
    while e < 4 {
      let (g1c, g1s, g2c, g2s) = ecc_to_groups(e, v)
      // ① 分组覆盖 = 数据码字数
      if g1c * g1s + g2c * g2s != data_codewords(e, v) {
        fail(
          "group sum mismatch e=" + e.to_string() + " v=" + (v + 1).to_string(),
        )
      }
      // ② 度 = 总纠错码字 / 分组总数，须为整数并等于 get_polynomial 度
      let ec_total = max_bytes(v) - data_codewords(e, v)
      let groups = g1c + g2c
      if ec_total % groups != 0 {
        fail(
          "degree not integer e=" + e.to_string() + " v=" + (v + 1).to_string(),
        )
      }
      let degree = ec_total / groups
      if get_polynomial(v, e).length() - 1 != degree {
        fail(
          "poly degree mismatch e=" +
          e.to_string() +
          " v=" +
          (v + 1).to_string(),
        )
      }
      e += 1
    }
    v += 1
  }
  // ③ capacity 最小性：对每个 (mode,ecl) 抽若干 len 断前版本装不下
  // Numeric-L：V1 上限 41，V2 上限 77
  assert_eq(capacity_bytes(0, 0, 0), 41)
  assert_eq(capacity_bytes(0, 0, 1), 77)
  // version_for 单调：len 越大不返回更小版本
  let mut m = 0
  while m < 3 {
    let mut e2 = 0
    while e2 < 4 {
      let mut len = 0
      while len < 100 {
        let vf = version_for(m, e2, len)
        if vf != -1 {
          if capacity_bytes(m, e2, vf) < len {
            fail(
              "version_for undersize m=" +
              m.to_string() +
              " e=" +
              e2.to_string() +
              " len=" +
              len.to_string(),
            )
          }
          if vf > 0 {
            if capacity_bytes(m, e2, vf - 1) >= len {
              fail(
                "version_for not minimal m=" +
                m.to_string() +
                " e=" +
                e2.to_string() +
                " len=" +
                len.to_string(),
              )
            }
          }
        }
        len += 1
      }
      e2 += 1
    }
    m += 1
  }
}

///|
/// cci_bits 分段边界（决策 D1 验收点）：跨 V9/V10/V26/V27 三模式取值断言。
/// version_idx：V9=8、V10=9、V26=25、V27=26。
test "cci_bits_boundaries" {
  // V1-V9（idx 0..=8）
  assert_eq(cci_bits(0, 0), 10) // Numeric V1
  assert_eq(cci_bits(8, 0), 10) // Numeric V9
  assert_eq(cci_bits(0, 1), 9) // Alnum V1
  assert_eq(cci_bits(8, 1), 9) // Alnum V9
  assert_eq(cci_bits(0, 2), 8) // Byte V1
  assert_eq(cci_bits(8, 2), 8) // Byte V9
  // V10-V26（idx 9..=25）
  assert_eq(cci_bits(9, 0), 12) // Numeric V10
  assert_eq(cci_bits(25, 0), 12) // Numeric V26
  assert_eq(cci_bits(9, 1), 11) // Alnum V10
  assert_eq(cci_bits(25, 1), 11) // Alnum V26
  assert_eq(cci_bits(9, 2), 16) // Byte V10 升 16
  assert_eq(cci_bits(25, 2), 16) // Byte V26
  // V27-V40（idx 26..=39）
  assert_eq(cci_bits(26, 0), 14) // Numeric V27
  assert_eq(cci_bits(39, 0), 14) // Numeric V40
  assert_eq(cci_bits(26, 1), 13) // Alnum V27
  assert_eq(cci_bits(39, 1), 13) // Alnum V40
  assert_eq(cci_bits(26, 2), 16) // Byte V27 不再涨
  assert_eq(cci_bits(39, 2), 16) // Byte V40
  // 越界护栏
  assert_eq(cci_bits(-1, 0), 10) // 回退 V1
  assert_eq(cci_bits(40, 0), 14) // 回退 V40
  assert_eq(cci_bits(0, 5), 8) // mode 越界按 Byte V1
}

///|
/// T1-f 全表值级校验（S10 §6 T1-f）：对**数值型常量表**逐项断言，
/// 覆盖「非抽查点」（附录 E M11/M12 实测漏检：中间项改值全程无感）。
/// 期望值由 scripts/snapshot_gen_tables.py 在参考侧 fast_qr 53e8c99 生成，
/// 严禁手改（`python3 scripts/snapshot_gen_tables.py --ref <fast_qr> --verify`）。
/// 说明：这里直接读私有表本身（白盒），逐行比对，任何单点改动都会失败。
test "t1f_full_table_values" {
  // ① capacity_table：3×4×40，按 (mode,ecl) 行展开，共 12 行
  let mut idx = 0
  let mut m = 0
  while m < 3 {
    let mut e = 0
    while e < 4 {
      let row = capacity_table[m][e]
      let want = exp_capacity_rows[idx]
      let mut v = 0
      while v < 40 {
        if row[v] != want[v] {
          fail(
            "capacity_table drift mode=" +
            m.to_string() +
            " ecl=" +
            e.to_string() +
            " V" +
            (v + 1).to_string() +
            " got=" +
            row[v].to_string() +
            " want=" +
            want[v].to_string(),
          )
        }
        v += 1
      }
      idx += 1
      e += 1
    }
    m += 1
  }
  // ② data_codewords_table：4×40
  let mut e2 = 0
  while e2 < 4 {
    let row = data_codewords_table[e2]
    let want = exp_data_codewords_rows[e2]
    let mut v = 0
    while v < 40 {
      if row[v] != want[v] {
        fail(
          "data_codewords drift ecl=" +
          e2.to_string() +
          " V" +
          (v + 1).to_string() +
          " got=" +
          row[v].to_string() +
          " want=" +
          want[v].to_string(),
        )
      }
      v += 1
    }
    e2 += 1
  }
  // ③ format_information_table：4×8（M12 漏检即此表中间项）
  let mut e3 = 0
  while e3 < 4 {
    let row = format_information_table[e3]
    let want = exp_format_rows[e3]
    let mut msk = 0
    while msk < 8 {
      if row[msk] != want[msk] {
        fail(
          "format_information drift ecl=" +
          e3.to_string() +
          " mask=" +
          msk.to_string() +
          " got=" +
          row[msk].to_string() +
          " want=" +
          want[msk].to_string(),
        )
      }
      msk += 1
    }
    e3 += 1
  }
  // ④ ecc_to_groups_table：4×40 四元组
  let mut e4 = 0
  while e4 < 4 {
    let row = ecc_to_groups_table[e4]
    let want = exp_ecc_groups_rows[e4]
    let mut v = 0
    while v < 40 {
      let (a1, b1, c1, d1) = row[v]
      let (a2, b2, c2, d2) = want[v]
      if (a1, b1, c1, d1) != (a2, b2, c2, d2) {
        fail(
          "ecc_to_groups drift ecl=" +
          e4.to_string() +
          " V" +
          (v + 1).to_string() +
          " got=(" +
          a1.to_string() +
          "," +
          b1.to_string() +
          "," +
          c1.to_string() +
          "," +
          d1.to_string() +
          ") want=(" +
          a2.to_string() +
          "," +
          b2.to_string() +
          "," +
          c2.to_string() +
          "," +
          d2.to_string() +
          ")",
        )
      }
      v += 1
    }
    e4 += 1
  }
  // ⑤ percent_score_table：100（N4 查表，同样属数值型常量表）
  let mut p = 0
  while p < 100 {
    if percent_score_table[p] != exp_percent_score[p] {
      fail(
        "percent_score drift percent=" +
        p.to_string() +
        " got=" +
        percent_score_table[p].to_string() +
        " want=" +
        exp_percent_score[p].to_string(),
      )
    }
    p += 1
  }
}

///|
/// BEGIN GENERATED: snapshot_gen_tables.py
/// 来源 fast_qr commit 53e8c99 (v0.14.0)；禁止手改，重跑 --verify 核对。
/// capacity_table[mode][ecl][version] 全表（3×4×40，逐行 40 项）
let exp_capacity_rows : Array[Array[Int]] = [
  [
    41, 77, 127, 187, 255, 322, 370, 461, 552, 652, 772, 883, 1022, 1101, 1250, 1408,
    1548, 1725, 1903, 2061, 2232, 2409, 2620, 2812, 3057, 3283, 3517, 3669, 3909,
    4158, 4417, 4686, 4965, 5253, 5529, 5836, 6153, 6479, 6743, 7089,
  ],
  [
    34, 63, 101, 149, 202, 255, 293, 365, 432, 513, 604, 691, 796, 871, 991, 1082,
    1212, 1346, 1500, 1600, 1708, 1872, 2059, 2188, 2395, 2544, 2701, 2857, 3035,
    3289, 3486, 3693, 3909, 4134, 4343, 4588, 4775, 5039, 5313, 5596,
  ],
  [
    27, 48, 77, 111, 144, 178, 207, 259, 312, 364, 427, 489, 580, 621, 703, 775,
    876, 948, 1063, 1159, 1224, 1358, 1468, 1588, 1718, 1804, 1933, 2085, 2181, 2358,
    2473, 2670, 2805, 2949, 3081, 3244, 3417, 3599, 3791, 3993,
  ],
  [
    17, 34, 58, 82, 106, 139, 154, 202, 235, 288, 331, 374, 427, 468, 530, 602, 674,
    746, 813, 919, 969, 1056, 1108, 1228, 1286, 1425, 1501, 1581, 1677, 1782, 1897,
    2022, 2157, 2301, 2361, 2524, 2625, 2735, 2927, 3057,
  ],
  [
    25, 47, 77, 114, 154, 195, 224, 279, 335, 395, 468, 535, 619, 667, 758, 854,
    938, 1046, 1153, 1249, 1352, 1460, 1588, 1704, 1853, 1990, 2132, 2223, 2369,
    2520, 2677, 2840, 3009, 3183, 3351, 3537, 3729, 3927, 4087, 4296,
  ],
  [
    20, 38, 61, 90, 122, 154, 178, 221, 262, 311, 366, 419, 483, 528, 600, 656, 734,
    816, 909, 970, 1035, 1134, 1248, 1326, 1451, 1542, 1637, 1732, 1839, 1994, 2113,
    2238, 2369, 2506, 2632, 2780, 2894, 3054, 3220, 3391,
  ],
  [
    16, 29, 47, 67, 87, 108, 125, 157, 189, 221, 259, 296, 352, 376, 426, 470, 531,
    574, 644, 702, 742, 823, 890, 963, 1041, 1094, 1172, 1263, 1322, 1429, 1499,
    1618, 1700, 1787, 1867, 1966, 2071, 2181, 2298, 2420,
  ],
  [
    10, 20, 35, 50, 64, 84, 93, 122, 143, 174, 200, 227, 259, 283, 321, 365, 408,
    452, 493, 557, 587, 640, 672, 744, 779, 864, 910, 958, 1016, 1080, 1150, 1226,
    1307, 1394, 1431, 1530, 1591, 1658, 1774, 1852,
  ],
  [
    17, 32, 53, 78, 106, 134, 154, 192, 230, 271, 321, 367, 425, 458, 520, 586, 644,
    718, 792, 858, 929, 1003, 1091, 1171, 1273, 1367, 1465, 1528, 1628, 1732, 1840,
    1952, 2068, 2188, 2303, 2431, 2563, 2699, 2809, 2953,
  ],
  [
    14, 26, 42, 62, 84, 106, 122, 152, 180, 213, 251, 287, 331, 362, 412, 450, 504,
    560, 624, 666, 711, 779, 857, 911, 997, 1059, 1125, 1190, 1264, 1370, 1452, 1538,
    1628, 1722, 1809, 1911, 1989, 2099, 2213, 2331,
  ],
  [
    11, 20, 32, 46, 60, 74, 86, 108, 130, 151, 177, 203, 241, 258, 292, 322, 364,
    394, 442, 482, 509, 565, 611, 661, 715, 751, 805, 868, 908, 982, 1030, 1112,
    1168, 1228, 1283, 1351, 1423, 1499, 1579, 1663,
  ],
  [
    7, 14, 24, 34, 44, 58, 64, 84, 98, 119, 137, 155, 177, 194, 220, 250, 280, 310,
    338, 382, 403, 439, 461, 511, 535, 593, 625, 658, 698, 742, 790, 842, 898, 958,
    983, 1051, 1093, 1139, 1219, 1273,
  ],
]

///|
/// data_codewords_table[ecl][version] 全表（4×40）
let exp_data_codewords_rows : Array[Array[Int]] = [
  [
    19, 34, 55, 80, 108, 136, 156, 194, 232, 274, 324, 370, 428, 461, 523, 589, 647,
    721, 795, 861, 932, 1006, 1094, 1174, 1276, 1370, 1468, 1531, 1631, 1735, 1843,
    1955, 2071, 2191, 2306, 2434, 2566, 2702, 2812, 2956,
  ],
  [
    16, 28, 44, 64, 86, 108, 124, 154, 182, 216, 254, 290, 334, 365, 415, 453, 507,
    563, 627, 669, 714, 782, 860, 914, 1000, 1062, 1128, 1193, 1267, 1373, 1455,
    1541, 1631, 1725, 1812, 1914, 1992, 2102, 2216, 2334,
  ],
  [
    13, 22, 34, 48, 62, 76, 88, 110, 132, 154, 180, 206, 244, 261, 295, 325, 367,
    397, 445, 485, 512, 568, 614, 664, 718, 754, 808, 871, 911, 985, 1033, 1115,
    1171, 1231, 1286, 1354, 1426, 1502, 1582, 1666,
  ],
  [
    9, 16, 26, 36, 46, 60, 66, 86, 100, 122, 140, 158, 180, 197, 223, 253, 283, 313,
    341, 385, 406, 442, 464, 514, 538, 596, 628, 661, 701, 745, 793, 845, 901, 961,
    986, 1054, 1096, 1142, 1222, 1276,
  ],
]

///|
/// format_information_table[ecl][mask] 全表（4×8）
let exp_format_rows : Array[Array[Int]] = [
  [30660, 29427, 32170, 30877, 26159, 25368, 27713, 26998],
  [21522, 20773, 24188, 23371, 17913, 16590, 20375, 19104],
  [13663, 12392, 16177, 14854, 9396, 8579, 11994, 11245],
  [5769, 5054, 7399, 6608, 1890, 597, 3340, 2107],
]

///|
/// ecc_to_groups_table[ecl][version] 全表（4×40 四元组）
let exp_ecc_groups_rows : Array[Array[(Int, Int, Int, Int)]] = [
  [
    (1, 19, 0, 0),
    (1, 34, 0, 0),
    (1, 55, 0, 0),
    (1, 80, 0, 0),
    (1, 108, 0, 0),
    (2, 68, 0, 0),
    (2, 78, 0, 0),
    (2, 97, 0, 0),
    (2, 116, 0, 0),
    (2, 68, 2, 69),
    (4, 81, 0, 0),
    (2, 92, 2, 93),
    (4, 107, 0, 0),
    (3, 115, 1, 116),
    (5, 87, 1, 88),
    (5, 98, 1, 99),
    (1, 107, 5, 108),
    (5, 120, 1, 121),
    (3, 113, 4, 114),
    (3, 107, 5, 108),
    (4, 116, 4, 117),
    (2, 111, 7, 112),
    (4, 121, 5, 122),
    (6, 117, 4, 118),
    (8, 106, 4, 107),
    (10, 114, 2, 115),
    (8, 122, 4, 123),
    (3, 117, 10, 118),
    (7, 116, 7, 117),
    (5, 115, 10, 116),
    (13, 115, 3, 116),
    (17, 115, 0, 0),
    (17, 115, 1, 116),
    (13, 115, 6, 116),
    (12, 121, 7, 122),
    (6, 121, 14, 122),
    (17, 122, 4, 123),
    (4, 122, 18, 123),
    (20, 117, 4, 118),
    (19, 118, 6, 119),
  ],
  [
    (1, 16, 0, 0),
    (1, 28, 0, 0),
    (1, 44, 0, 0),
    (2, 32, 0, 0),
    (2, 43, 0, 0),
    (4, 27, 0, 0),
    (4, 31, 0, 0),
    (2, 38, 2, 39),
    (3, 36, 2, 37),
    (4, 43, 1, 44),
    (1, 50, 4, 51),
    (6, 36, 2, 37),
    (8, 37, 1, 38),
    (4, 40, 5, 41),
    (5, 41, 5, 42),
    (7, 45, 3, 46),
    (10, 46, 1, 47),
    (9, 43, 4, 44),
    (3, 44, 11, 45),
    (3, 41, 13, 42),
    (17, 42, 0, 0),
    (17, 46, 0, 0),
    (4, 47, 14, 48),
    (6, 45, 14, 46),
    (8, 47, 13, 48),
    (19, 46, 4, 47),
    (22, 45, 3, 46),
    (3, 45, 23, 46),
    (21, 45, 7, 46),
    (19, 47, 10, 48),
    (2, 46, 29, 47),
    (10, 46, 23, 47),
    (14, 46, 21, 47),
    (14, 46, 23, 47),
    (12, 47, 26, 48),
    (6, 47, 34, 48),
    (29, 46, 14, 47),
    (13, 46, 32, 47),
    (40, 47, 7, 48),
    (18, 47, 31, 48),
  ],
  [
    (1, 13, 0, 0),
    (1, 22, 0, 0),
    (2, 17, 0, 0),
    (2, 24, 0, 0),
    (2, 15, 2, 16),
    (4, 19, 0, 0),
    (2, 14, 4, 15),
    (4, 18, 2, 19),
    (4, 16, 4, 17),
    (6, 19, 2, 20),
    (4, 22, 4, 23),
    (4, 20, 6, 21),
    (8, 20, 4, 21),
    (11, 16, 5, 17),
    (5, 24, 7, 25),
    (15, 19, 2, 20),
    (1, 22, 15, 23),
    (17, 22, 1, 23),
    (17, 21, 4, 22),
    (15, 24, 5, 25),
    (17, 22, 6, 23),
    (7, 24, 16, 25),
    (11, 24, 14, 25),
    (11, 24, 16, 25),
    (7, 24, 22, 25),
    (28, 22, 6, 23),
    (8, 23, 26, 24),
    (4, 24, 31, 25),
    (1, 23, 37, 24),
    (15, 24, 25, 25),
    (42, 24, 1, 25),
    (10, 24, 35, 25),
    (29, 24, 19, 25),
    (44, 24, 7, 25),
    (39, 24, 14, 25),
    (46, 24, 10, 25),
    (49, 24, 10, 25),
    (48, 24, 14, 25),
    (43, 24, 22, 25),
    (34, 24, 34, 25),
  ],
  [
    (1, 9, 0, 0),
    (1, 16, 0, 0),
    (2, 13, 0, 0),
    (4, 9, 0, 0),
    (2, 11, 2, 12),
    (4, 15, 0, 0),
    (4, 13, 1, 14),
    (4, 14, 2, 15),
    (4, 12, 4, 13),
    (6, 15, 2, 16),
    (3, 12, 8, 13),
    (7, 14, 4, 15),
    (12, 11, 4, 12),
    (11, 12, 5, 13),
    (11, 12, 7, 13),
    (3, 15, 13, 16),
    (2, 14, 17, 15),
    (2, 14, 19, 15),
    (9, 13, 16, 14),
    (15, 15, 10, 16),
    (19, 16, 6, 17),
    (34, 13, 0, 0),
    (16, 15, 14, 16),
    (30, 16, 2, 17),
    (22, 15, 13, 16),
    (33, 16, 4, 17),
    (12, 15, 28, 16),
    (11, 15, 31, 16),
    (19, 15, 26, 16),
    (23, 15, 25, 16),
    (23, 15, 28, 16),
    (19, 15, 35, 16),
    (11, 15, 46, 16),
    (59, 16, 1, 17),
    (22, 15, 41, 16),
    (2, 15, 64, 16),
    (24, 15, 46, 16),
    (42, 15, 32, 16),
    (10, 15, 67, 16),
    (20, 15, 61, 16),
  ],
]

///|
/// percent_score_table[percent] 全表（100）
let exp_percent_score : Array[Int] = [
  90, 90, 90, 90, 90, 80, 80, 80, 80, 80, 70, 70, 70, 70, 70, 60, 60, 60, 60, 60,
  50, 50, 50, 50, 50, 40, 40, 40, 40, 40, 30, 30, 30, 30, 30, 20, 20, 20, 20, 20,
  10, 10, 10, 10, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 20, 20, 20,
  20, 20, 30, 30, 30, 30, 30, 40, 40, 40, 40, 40, 50, 50, 50, 50, 50, 60, 60, 60,
  60, 60, 70, 70, 70, 70, 70, 80, 80, 80, 80, 80, 90, 90, 90, 90, 90,
]
/// END GENERATED
