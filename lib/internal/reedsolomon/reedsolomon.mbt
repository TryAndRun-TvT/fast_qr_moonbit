///|
/// reedsolomon.mbt —— GF(256) 纠错与交织
/// 对应参考：fast_qr v0.14.0 src/polynomials.rs（roadmap 批次 B4，实现记录 §4.3）
/// 职责：LOG/ANTILOG 表驱动的 division（余数 = 纠错码字）与
///       structure（分块纠错 + 数据/纠错码字交织）。
/// 关键语义：除法右对齐入 [0;255] 工作区、查表异或，余数在尾部；
///       交织数据区逐块跨字节、纠错区逐字节跨块（方向相反）。
/// 依赖：constants（get_polynomial / ecc_to_groups / data_codewords）。ecl/version 以 Int 序号入参。
/// 实现：LOG/ANTILOG 表由提取脚本从参考源码生成（禁止手抄）。

///|

///|
/// LOG[e] = α^e 的域值（e 为 α 指数，0..255）。

///|
let log_table : ReadOnlyArray[Byte] = [
  (1).to_byte(),
  (2).to_byte(),
  (4).to_byte(),
  (8).to_byte(),
  (16).to_byte(),
  (32).to_byte(),
  (64).to_byte(),
  (128).to_byte(),
  (29).to_byte(),
  (58).to_byte(),
  (116).to_byte(),
  (232).to_byte(),
  (205).to_byte(),
  (135).to_byte(),
  (19).to_byte(),
  (38).to_byte(),
  (76).to_byte(),
  (152).to_byte(),
  (45).to_byte(),
  (90).to_byte(),
  (180).to_byte(),
  (117).to_byte(),
  (234).to_byte(),
  (201).to_byte(),
  (143).to_byte(),
  (3).to_byte(),
  (6).to_byte(),
  (12).to_byte(),
  (24).to_byte(),
  (48).to_byte(),
  (96).to_byte(),
  (192).to_byte(),
  (157).to_byte(),
  (39).to_byte(),
  (78).to_byte(),
  (156).to_byte(),
  (37).to_byte(),
  (74).to_byte(),
  (148).to_byte(),
  (53).to_byte(),
  (106).to_byte(),
  (212).to_byte(),
  (181).to_byte(),
  (119).to_byte(),
  (238).to_byte(),
  (193).to_byte(),
  (159).to_byte(),
  (35).to_byte(),
  (70).to_byte(),
  (140).to_byte(),
  (5).to_byte(),
  (10).to_byte(),
  (20).to_byte(),
  (40).to_byte(),
  (80).to_byte(),
  (160).to_byte(),
  (93).to_byte(),
  (186).to_byte(),
  (105).to_byte(),
  (210).to_byte(),
  (185).to_byte(),
  (111).to_byte(),
  (222).to_byte(),
  (161).to_byte(),
  (95).to_byte(),
  (190).to_byte(),
  (97).to_byte(),
  (194).to_byte(),
  (153).to_byte(),
  (47).to_byte(),
  (94).to_byte(),
  (188).to_byte(),
  (101).to_byte(),
  (202).to_byte(),
  (137).to_byte(),
  (15).to_byte(),
  (30).to_byte(),
  (60).to_byte(),
  (120).to_byte(),
  (240).to_byte(),
  (253).to_byte(),
  (231).to_byte(),
  (211).to_byte(),
  (187).to_byte(),
  (107).to_byte(),
  (214).to_byte(),
  (177).to_byte(),
  (127).to_byte(),
  (254).to_byte(),
  (225).to_byte(),
  (223).to_byte(),
  (163).to_byte(),
  (91).to_byte(),
  (182).to_byte(),
  (113).to_byte(),
  (226).to_byte(),
  (217).to_byte(),
  (175).to_byte(),
  (67).to_byte(),
  (134).to_byte(),
  (17).to_byte(),
  (34).to_byte(),
  (68).to_byte(),
  (136).to_byte(),
  (13).to_byte(),
  (26).to_byte(),
  (52).to_byte(),
  (104).to_byte(),
  (208).to_byte(),
  (189).to_byte(),
  (103).to_byte(),
  (206).to_byte(),
  (129).to_byte(),
  (31).to_byte(),
  (62).to_byte(),
  (124).to_byte(),
  (248).to_byte(),
  (237).to_byte(),
  (199).to_byte(),
  (147).to_byte(),
  (59).to_byte(),
  (118).to_byte(),
  (236).to_byte(),
  (197).to_byte(),
  (151).to_byte(),
  (51).to_byte(),
  (102).to_byte(),
  (204).to_byte(),
  (133).to_byte(),
  (23).to_byte(),
  (46).to_byte(),
  (92).to_byte(),
  (184).to_byte(),
  (109).to_byte(),
  (218).to_byte(),
  (169).to_byte(),
  (79).to_byte(),
  (158).to_byte(),
  (33).to_byte(),
  (66).to_byte(),
  (132).to_byte(),
  (21).to_byte(),
  (42).to_byte(),
  (84).to_byte(),
  (168).to_byte(),
  (77).to_byte(),
  (154).to_byte(),
  (41).to_byte(),
  (82).to_byte(),
  (164).to_byte(),
  (85).to_byte(),
  (170).to_byte(),
  (73).to_byte(),
  (146).to_byte(),
  (57).to_byte(),
  (114).to_byte(),
  (228).to_byte(),
  (213).to_byte(),
  (183).to_byte(),
  (115).to_byte(),
  (230).to_byte(),
  (209).to_byte(),
  (191).to_byte(),
  (99).to_byte(),
  (198).to_byte(),
  (145).to_byte(),
  (63).to_byte(),
  (126).to_byte(),
  (252).to_byte(),
  (229).to_byte(),
  (215).to_byte(),
  (179).to_byte(),
  (123).to_byte(),
  (246).to_byte(),
  (241).to_byte(),
  (255).to_byte(),
  (227).to_byte(),
  (219).to_byte(),
  (171).to_byte(),
  (75).to_byte(),
  (150).to_byte(),
  (49).to_byte(),
  (98).to_byte(),
  (196).to_byte(),
  (149).to_byte(),
  (55).to_byte(),
  (110).to_byte(),
  (220).to_byte(),
  (165).to_byte(),
  (87).to_byte(),
  (174).to_byte(),
  (65).to_byte(),
  (130).to_byte(),
  (25).to_byte(),
  (50).to_byte(),
  (100).to_byte(),
  (200).to_byte(),
  (141).to_byte(),
  (7).to_byte(),
  (14).to_byte(),
  (28).to_byte(),
  (56).to_byte(),
  (112).to_byte(),
  (224).to_byte(),
  (221).to_byte(),
  (167).to_byte(),
  (83).to_byte(),
  (166).to_byte(),
  (81).to_byte(),
  (162).to_byte(),
  (89).to_byte(),
  (178).to_byte(),
  (121).to_byte(),
  (242).to_byte(),
  (249).to_byte(),
  (239).to_byte(),
  (195).to_byte(),
  (155).to_byte(),
  (43).to_byte(),
  (86).to_byte(),
  (172).to_byte(),
  (69).to_byte(),
  (138).to_byte(),
  (9).to_byte(),
  (18).to_byte(),
  (36).to_byte(),
  (72).to_byte(),
  (144).to_byte(),
  (61).to_byte(),
  (122).to_byte(),
  (244).to_byte(),
  (245).to_byte(),
  (247).to_byte(),
  (243).to_byte(),
  (251).to_byte(),
  (235).to_byte(),
  (203).to_byte(),
  (139).to_byte(),
  (11).to_byte(),
  (22).to_byte(),
  (44).to_byte(),
  (88).to_byte(),
  (176).to_byte(),
  (125).to_byte(),
  (250).to_byte(),
  (233).to_byte(),
  (207).to_byte(),
  (131).to_byte(),
  (27).to_byte(),
  (54).to_byte(),
  (108).to_byte(),
  (216).to_byte(),
  (173).to_byte(),
  (71).to_byte(),
  (142).to_byte(),
  (1).to_byte(),
]

///|
/// ANTILOG[x] = x 的 α 对数指数（x 为域值，0..255）。

///|
let antilog_table : ReadOnlyArray[Byte] = [
  (175).to_byte(),
  (0).to_byte(),
  (1).to_byte(),
  (25).to_byte(),
  (2).to_byte(),
  (50).to_byte(),
  (26).to_byte(),
  (198).to_byte(),
  (3).to_byte(),
  (223).to_byte(),
  (51).to_byte(),
  (238).to_byte(),
  (27).to_byte(),
  (104).to_byte(),
  (199).to_byte(),
  (75).to_byte(),
  (4).to_byte(),
  (100).to_byte(),
  (224).to_byte(),
  (14).to_byte(),
  (52).to_byte(),
  (141).to_byte(),
  (239).to_byte(),
  (129).to_byte(),
  (28).to_byte(),
  (193).to_byte(),
  (105).to_byte(),
  (248).to_byte(),
  (200).to_byte(),
  (8).to_byte(),
  (76).to_byte(),
  (113).to_byte(),
  (5).to_byte(),
  (138).to_byte(),
  (101).to_byte(),
  (47).to_byte(),
  (225).to_byte(),
  (36).to_byte(),
  (15).to_byte(),
  (33).to_byte(),
  (53).to_byte(),
  (147).to_byte(),
  (142).to_byte(),
  (218).to_byte(),
  (240).to_byte(),
  (18).to_byte(),
  (130).to_byte(),
  (69).to_byte(),
  (29).to_byte(),
  (181).to_byte(),
  (194).to_byte(),
  (125).to_byte(),
  (106).to_byte(),
  (39).to_byte(),
  (249).to_byte(),
  (185).to_byte(),
  (201).to_byte(),
  (154).to_byte(),
  (9).to_byte(),
  (120).to_byte(),
  (77).to_byte(),
  (228).to_byte(),
  (114).to_byte(),
  (166).to_byte(),
  (6).to_byte(),
  (191).to_byte(),
  (139).to_byte(),
  (98).to_byte(),
  (102).to_byte(),
  (221).to_byte(),
  (48).to_byte(),
  (253).to_byte(),
  (226).to_byte(),
  (152).to_byte(),
  (37).to_byte(),
  (179).to_byte(),
  (16).to_byte(),
  (145).to_byte(),
  (34).to_byte(),
  (136).to_byte(),
  (54).to_byte(),
  (208).to_byte(),
  (148).to_byte(),
  (206).to_byte(),
  (143).to_byte(),
  (150).to_byte(),
  (219).to_byte(),
  (189).to_byte(),
  (241).to_byte(),
  (210).to_byte(),
  (19).to_byte(),
  (92).to_byte(),
  (131).to_byte(),
  (56).to_byte(),
  (70).to_byte(),
  (64).to_byte(),
  (30).to_byte(),
  (66).to_byte(),
  (182).to_byte(),
  (163).to_byte(),
  (195).to_byte(),
  (72).to_byte(),
  (126).to_byte(),
  (110).to_byte(),
  (107).to_byte(),
  (58).to_byte(),
  (40).to_byte(),
  (84).to_byte(),
  (250).to_byte(),
  (133).to_byte(),
  (186).to_byte(),
  (61).to_byte(),
  (202).to_byte(),
  (94).to_byte(),
  (155).to_byte(),
  (159).to_byte(),
  (10).to_byte(),
  (21).to_byte(),
  (121).to_byte(),
  (43).to_byte(),
  (78).to_byte(),
  (212).to_byte(),
  (229).to_byte(),
  (172).to_byte(),
  (115).to_byte(),
  (243).to_byte(),
  (167).to_byte(),
  (87).to_byte(),
  (7).to_byte(),
  (112).to_byte(),
  (192).to_byte(),
  (247).to_byte(),
  (140).to_byte(),
  (128).to_byte(),
  (99).to_byte(),
  (13).to_byte(),
  (103).to_byte(),
  (74).to_byte(),
  (222).to_byte(),
  (237).to_byte(),
  (49).to_byte(),
  (197).to_byte(),
  (254).to_byte(),
  (24).to_byte(),
  (227).to_byte(),
  (165).to_byte(),
  (153).to_byte(),
  (119).to_byte(),
  (38).to_byte(),
  (184).to_byte(),
  (180).to_byte(),
  (124).to_byte(),
  (17).to_byte(),
  (68).to_byte(),
  (146).to_byte(),
  (217).to_byte(),
  (35).to_byte(),
  (32).to_byte(),
  (137).to_byte(),
  (46).to_byte(),
  (55).to_byte(),
  (63).to_byte(),
  (209).to_byte(),
  (91).to_byte(),
  (149).to_byte(),
  (188).to_byte(),
  (207).to_byte(),
  (205).to_byte(),
  (144).to_byte(),
  (135).to_byte(),
  (151).to_byte(),
  (178).to_byte(),
  (220).to_byte(),
  (252).to_byte(),
  (190).to_byte(),
  (97).to_byte(),
  (242).to_byte(),
  (86).to_byte(),
  (211).to_byte(),
  (171).to_byte(),
  (20).to_byte(),
  (42).to_byte(),
  (93).to_byte(),
  (158).to_byte(),
  (132).to_byte(),
  (60).to_byte(),
  (57).to_byte(),
  (83).to_byte(),
  (71).to_byte(),
  (109).to_byte(),
  (65).to_byte(),
  (162).to_byte(),
  (31).to_byte(),
  (45).to_byte(),
  (67).to_byte(),
  (216).to_byte(),
  (183).to_byte(),
  (123).to_byte(),
  (164).to_byte(),
  (118).to_byte(),
  (196).to_byte(),
  (23).to_byte(),
  (73).to_byte(),
  (236).to_byte(),
  (127).to_byte(),
  (12).to_byte(),
  (111).to_byte(),
  (246).to_byte(),
  (108).to_byte(),
  (161).to_byte(),
  (59).to_byte(),
  (82).to_byte(),
  (41).to_byte(),
  (157).to_byte(),
  (85).to_byte(),
  (170).to_byte(),
  (251).to_byte(),
  (96).to_byte(),
  (134).to_byte(),
  (177).to_byte(),
  (187).to_byte(),
  (204).to_byte(),
  (62).to_byte(),
  (90).to_byte(),
  (203).to_byte(),
  (89).to_byte(),
  (95).to_byte(),
  (176).to_byte(),
  (156).to_byte(),
  (169).to_byte(),
  (160).to_byte(),
  (81).to_byte(),
  (11).to_byte(),
  (245).to_byte(),
  (22).to_byte(),
  (235).to_byte(),
  (122).to_byte(),
  (117).to_byte(),
  (44).to_byte(),
  (215).to_byte(),
  (79).to_byte(),
  (174).to_byte(),
  (213).to_byte(),
  (233).to_byte(),
  (230).to_byte(),
  (231).to_byte(),
  (173).to_byte(),
  (232).to_byte(),
  (116).to_byte(),
  (214).to_byte(),
  (244).to_byte(),
  (234).to_byte(),
  (168).to_byte(),
  (80).to_byte(),
  (88).to_byte(),
  (175).to_byte(),
]

///|
/// GF(256) 除法取余（= 数据块的纠错码字）。
/// data 数据右对齐放入 255 字节工作区，对每个非零首项查 ANTILOG 得指数 alpha，
/// 逐生成项 LOG[(by[j]+alpha) % 255] 异或。返回尾部 by.length()-1 个余数字节。
/// 前置：data.length() + by.length() <= 256。

///|
pub fn division(data : Array[Byte], by : ReadOnlyArray[Byte]) -> Array[Byte] {
  let buf = Array::make(255, b'\x00')
  let start = 256 - data.length() - by.length()
  let mut i = 0
  while i < data.length() {
    buf[start + i] = data[i]
    i += 1
  }
  let mut k = start
  while k < start + data.length() {
    if buf[k] != b'\x00' {
      let alpha = antilog_table[buf[k].to_int()].to_int()
      let mut j = 0
      while j < by.length() {
        let tmp = by[j].to_int() + alpha
        buf[k + j] = (buf[k + j].to_int() ^ log_table[tmp % 255].to_int()).to_byte()
        j += 1
      }
    }
    k += 1
  }
  // 余数 = 工作区最后 by.length()-1 字节
  let rem_len = by.length() - 1
  let rem = Array::make(rem_len, b'\x00')
  let mut r = 0
  while r < rem_len {
    rem[r] = buf[256 - by.length() + r]
    r += 1
  }
  rem
}

///|
/// 拷贝 data[from..to)（返回独立数组）。
fn slice(data : Array[Byte], from : Int, to : Int) -> Array[Byte] {
  let n = to - from
  let out = Array::make(n, b'\x00')
  let mut i = 0
  while i < n {
    out[i] = data[from + i]
    i += 1
  }
  out
}

///|
/// 分块纠错 + 交织。data 为数据码字（长度应等于 data_codewords(version,ecl)）。
/// 返回 5430 字节交织缓冲：前段为交织后数据码字，之后为逐字节跨块的纠错码字。

///|
pub fn structure(
  data : Array[Byte],
  ecl_idx : Int,
  version_idx : Int,
) -> Array[Byte] {
  let gen = @constants.get_polynomial(version_idx, ecl_idx)
  let (g1c, g1s, g2c, g2s) = @constants.ecc_to_groups(ecl_idx, version_idx)
  let groups_total = g1c + g2c
  let out = Array::make(5430, b'\x00')
  let start_err = @constants.data_codewords(ecl_idx, version_idx)
  // g1 块纠错（逐块跨字节写入纠错区）
  let mut gi = 0
  while gi < g1c {
    let sidx = gi * g1s
    let block = slice(data, sidx, sidx + g1s)
    let rem = division(block, gen)
    let mut j = 0
    while j < rem.length() {
      out[start_err + j * groups_total + gi] = rem[j]
      j += 1
    }
    gi += 1
  }
  // g2 块纠错
  let mut gi2 = 0
  while gi2 < g2c {
    let sidx = g1s * g1c + gi2 * g2s
    let block = slice(data, sidx, sidx + g2s)
    let rem = division(block, gen)
    let mut j = 0
    while j < rem.length() {
      out[start_err + j * groups_total + gi2 + g1c] = rem[j]
      j += 1
    }
    gi2 += 1
  }
  // 数据交织：数据区逐块跨字节
  let mut push = 0
  let max_s = if g1s > g2s { g1s } else { g2s }
  let mut i = 0
  while i < max_s {
    if i < g1s {
      let mut j = 0
      while j < g1c {
        out[push] = data[j * g1s + i]
        push += 1
        j += 1
      }
    }
    if i < g2s {
      let mut j = 0
      while j < g2c {
        out[push] = data[j * g2s + i + g1s * g1c]
        push += 1
        j += 1
      }
    }
    i += 1
  }
  out
}
