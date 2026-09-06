///|
/// hardcode.mbt —— 常量表（分组 / 格式信息 / 生成多项式 / 暗比惩罚）
/// 对应参考：fast_qr v0.14.0 src/hardcode.rs（roadmap 批次 B3/B10，实现记录 §4.2）
/// 职责：ecc_to_groups（两个 (count,size) 分组对）、get_polynomial（生成多项式选择）、
///       format_information（纠错×掩码 → 15 位格式信息字，S5 写真实 Format 用）、
///       percent_score_table（N4 暗比惩罚表，S5 评分用）。
/// 实现：表由提取脚本从参考源码 src/hardcode.rs 生成（禁止手抄）。
/// 依赖规则：叶节点（无依赖）；ecl/version/mask 以 Int 序号入参。

///|

///|
/// ecc_to_groups_table[ecl][version] = (g1_count, g1_size, g2_count, g2_size)。
/// 源码以 u32 位打包，此处解码为四元组直接存储。

///|
let ecc_to_groups_table : Array[Array[(Int, Int, Int, Int)]] = [
  [ // ecl 0 = L
    (1, 19, 0, 0), // V01
    (1, 34, 0, 0), // V02
    (1, 55, 0, 0), // V03
    (1, 80, 0, 0), // V04
    (1, 108, 0, 0), // V05
    (2, 68, 0, 0), // V06
    (2, 78, 0, 0), // V07
    (2, 97, 0, 0), // V08
    (2, 116, 0, 0), // V09
    (2, 68, 2, 69), // V10
    (4, 81, 0, 0), // V11
    (2, 92, 2, 93), // V12
    (4, 107, 0, 0), // V13
    (3, 115, 1, 116), // V14
    (5, 87, 1, 88), // V15
    (5, 98, 1, 99), // V16
    (1, 107, 5, 108), // V17
    (5, 120, 1, 121), // V18
    (3, 113, 4, 114), // V19
    (3, 107, 5, 108), // V20
    (4, 116, 4, 117), // V21
    (2, 111, 7, 112), // V22
    (4, 121, 5, 122), // V23
    (6, 117, 4, 118), // V24
    (8, 106, 4, 107), // V25
    (10, 114, 2, 115), // V26
    (8, 122, 4, 123), // V27
    (3, 117, 10, 118), // V28
    (7, 116, 7, 117), // V29
    (5, 115, 10, 116), // V30
    (13, 115, 3, 116), // V31
    (17, 115, 0, 0), // V32
    (17, 115, 1, 116), // V33
    (13, 115, 6, 116), // V34
    (12, 121, 7, 122), // V35
    (6, 121, 14, 122), // V36
    (17, 122, 4, 123), // V37
    (4, 122, 18, 123), // V38
    (20, 117, 4, 118), // V39
    (19, 118, 6, 119), // V40
  ],
  [ // ecl 1 = M
    (1, 16, 0, 0), // V01
    (1, 28, 0, 0), // V02
    (1, 44, 0, 0), // V03
    (2, 32, 0, 0), // V04
    (2, 43, 0, 0), // V05
    (4, 27, 0, 0), // V06
    (4, 31, 0, 0), // V07
    (2, 38, 2, 39), // V08
    (3, 36, 2, 37), // V09
    (4, 43, 1, 44), // V10
    (1, 50, 4, 51), // V11
    (6, 36, 2, 37), // V12
    (8, 37, 1, 38), // V13
    (4, 40, 5, 41), // V14
    (5, 41, 5, 42), // V15
    (7, 45, 3, 46), // V16
    (10, 46, 1, 47), // V17
    (9, 43, 4, 44), // V18
    (3, 44, 11, 45), // V19
    (3, 41, 13, 42), // V20
    (17, 42, 0, 0), // V21
    (17, 46, 0, 0), // V22
    (4, 47, 14, 48), // V23
    (6, 45, 14, 46), // V24
    (8, 47, 13, 48), // V25
    (19, 46, 4, 47), // V26
    (22, 45, 3, 46), // V27
    (3, 45, 23, 46), // V28
    (21, 45, 7, 46), // V29
    (19, 47, 10, 48), // V30
    (2, 46, 29, 47), // V31
    (10, 46, 23, 47), // V32
    (14, 46, 21, 47), // V33
    (14, 46, 23, 47), // V34
    (12, 47, 26, 48), // V35
    (6, 47, 34, 48), // V36
    (29, 46, 14, 47), // V37
    (13, 46, 32, 47), // V38
    (40, 47, 7, 48), // V39
    (18, 47, 31, 48), // V40
  ],
  [ // ecl 2 = Q
    (1, 13, 0, 0), // V01
    (1, 22, 0, 0), // V02
    (2, 17, 0, 0), // V03
    (2, 24, 0, 0), // V04
    (2, 15, 2, 16), // V05
    (4, 19, 0, 0), // V06
    (2, 14, 4, 15), // V07
    (4, 18, 2, 19), // V08
    (4, 16, 4, 17), // V09
    (6, 19, 2, 20), // V10
    (4, 22, 4, 23), // V11
    (4, 20, 6, 21), // V12
    (8, 20, 4, 21), // V13
    (11, 16, 5, 17), // V14
    (5, 24, 7, 25), // V15
    (15, 19, 2, 20), // V16
    (1, 22, 15, 23), // V17
    (17, 22, 1, 23), // V18
    (17, 21, 4, 22), // V19
    (15, 24, 5, 25), // V20
    (17, 22, 6, 23), // V21
    (7, 24, 16, 25), // V22
    (11, 24, 14, 25), // V23
    (11, 24, 16, 25), // V24
    (7, 24, 22, 25), // V25
    (28, 22, 6, 23), // V26
    (8, 23, 26, 24), // V27
    (4, 24, 31, 25), // V28
    (1, 23, 37, 24), // V29
    (15, 24, 25, 25), // V30
    (42, 24, 1, 25), // V31
    (10, 24, 35, 25), // V32
    (29, 24, 19, 25), // V33
    (44, 24, 7, 25), // V34
    (39, 24, 14, 25), // V35
    (46, 24, 10, 25), // V36
    (49, 24, 10, 25), // V37
    (48, 24, 14, 25), // V38
    (43, 24, 22, 25), // V39
    (34, 24, 34, 25), // V40
  ],
  [ // ecl 3 = H
    (1, 9, 0, 0), // V01
    (1, 16, 0, 0), // V02
    (2, 13, 0, 0), // V03
    (4, 9, 0, 0), // V04
    (2, 11, 2, 12), // V05
    (4, 15, 0, 0), // V06
    (4, 13, 1, 14), // V07
    (4, 14, 2, 15), // V08
    (4, 12, 4, 13), // V09
    (6, 15, 2, 16), // V10
    (3, 12, 8, 13), // V11
    (7, 14, 4, 15), // V12
    (12, 11, 4, 12), // V13
    (11, 12, 5, 13), // V14
    (11, 12, 7, 13), // V15
    (3, 15, 13, 16), // V16
    (2, 14, 17, 15), // V17
    (2, 14, 19, 15), // V18
    (9, 13, 16, 14), // V19
    (15, 15, 10, 16), // V20
    (19, 16, 6, 17), // V21
    (34, 13, 0, 0), // V22
    (16, 15, 14, 16), // V23
    (30, 16, 2, 17), // V24
    (22, 15, 13, 16), // V25
    (33, 16, 4, 17), // V26
    (12, 15, 28, 16), // V27
    (11, 15, 31, 16), // V28
    (19, 15, 26, 16), // V29
    (23, 15, 25, 16), // V30
    (23, 15, 28, 16), // V31
    (19, 15, 35, 16), // V32
    (11, 15, 46, 16), // V33
    (59, 16, 1, 17), // V34
    (22, 15, 41, 16), // V35
    (2, 15, 64, 16), // V36
    (24, 15, 46, 16), // V37
    (42, 15, 32, 16), // V38
    (10, 15, 67, 16), // V39
    (20, 15, 61, 16), // V40
  ],
]

///|
/// 31 条生成多项式：generator_polys[i]（i = 度 = 纠错码字数/块）。
/// 每条首元素 0，按 α 指数存储。

///|
let generator_polys : Array[Array[Byte]] = [
  [ // 度 0，长 1
    (0).to_byte(),
  ],
  [ // 度 1，长 2
    (0).to_byte(),
    (0).to_byte(),
  ],
  [ // 度 2，长 3
    (0).to_byte(),
    (25).to_byte(),
    (1).to_byte(),
  ],
  [ // 度 3，长 4
    (0).to_byte(),
    (198).to_byte(),
    (199).to_byte(),
    (3).to_byte(),
  ],
  [ // 度 4，长 5
    (0).to_byte(),
    (75).to_byte(),
    (249).to_byte(),
    (78).to_byte(),
    (6).to_byte(),
  ],
  [ // 度 5，长 6
    (0).to_byte(),
    (113).to_byte(),
    (164).to_byte(),
    (166).to_byte(),
    (119).to_byte(),
    (10).to_byte(),
  ],
  [ // 度 6，长 7
    (0).to_byte(),
    (166).to_byte(),
    (0).to_byte(),
    (134).to_byte(),
    (5).to_byte(),
    (176).to_byte(),
    (15).to_byte(),
  ],
  [ // 度 7，长 8
    (0).to_byte(),
    (87).to_byte(),
    (229).to_byte(),
    (146).to_byte(),
    (149).to_byte(),
    (238).to_byte(),
    (102).to_byte(),
    (21).to_byte(),
  ],
  [ // 度 8，长 9
    (0).to_byte(),
    (175).to_byte(),
    (238).to_byte(),
    (208).to_byte(),
    (249).to_byte(),
    (215).to_byte(),
    (252).to_byte(),
    (196).to_byte(),
    (28).to_byte(),
  ],
  [ // 度 9，长 10
    (0).to_byte(),
    (95).to_byte(),
    (246).to_byte(),
    (137).to_byte(),
    (231).to_byte(),
    (235).to_byte(),
    (149).to_byte(),
    (11).to_byte(),
    (123).to_byte(),
    (36).to_byte(),
  ],
  [ // 度 10，长 11
    (0).to_byte(),
    (251).to_byte(),
    (67).to_byte(),
    (46).to_byte(),
    (61).to_byte(),
    (118).to_byte(),
    (70).to_byte(),
    (64).to_byte(),
    (94).to_byte(),
    (32).to_byte(),
    (45).to_byte(),
  ],
  [ // 度 11，长 12
    (0).to_byte(),
    (220).to_byte(),
    (192).to_byte(),
    (91).to_byte(),
    (194).to_byte(),
    (172).to_byte(),
    (177).to_byte(),
    (209).to_byte(),
    (116).to_byte(),
    (227).to_byte(),
    (10).to_byte(),
    (55).to_byte(),
  ],
  [ // 度 12，长 13
    (0).to_byte(),
    (102).to_byte(),
    (43).to_byte(),
    (98).to_byte(),
    (121).to_byte(),
    (187).to_byte(),
    (113).to_byte(),
    (198).to_byte(),
    (143).to_byte(),
    (131).to_byte(),
    (87).to_byte(),
    (157).to_byte(),
    (66).to_byte(),
  ],
  [ // 度 13，长 14
    (0).to_byte(),
    (74).to_byte(),
    (152).to_byte(),
    (176).to_byte(),
    (100).to_byte(),
    (86).to_byte(),
    (100).to_byte(),
    (106).to_byte(),
    (104).to_byte(),
    (130).to_byte(),
    (218).to_byte(),
    (206).to_byte(),
    (140).to_byte(),
    (78).to_byte(),
  ],
  [ // 度 14，长 15
    (0).to_byte(),
    (199).to_byte(),
    (249).to_byte(),
    (155).to_byte(),
    (48).to_byte(),
    (190).to_byte(),
    (124).to_byte(),
    (218).to_byte(),
    (137).to_byte(),
    (216).to_byte(),
    (87).to_byte(),
    (207).to_byte(),
    (59).to_byte(),
    (22).to_byte(),
    (91).to_byte(),
  ],
  [ // 度 15，长 16
    (0).to_byte(),
    (8).to_byte(),
    (183).to_byte(),
    (61).to_byte(),
    (91).to_byte(),
    (202).to_byte(),
    (37).to_byte(),
    (51).to_byte(),
    (58).to_byte(),
    (58).to_byte(),
    (237).to_byte(),
    (140).to_byte(),
    (124).to_byte(),
    (5).to_byte(),
    (99).to_byte(),
    (105).to_byte(),
  ],
  [ // 度 16，长 17
    (0).to_byte(),
    (120).to_byte(),
    (104).to_byte(),
    (107).to_byte(),
    (109).to_byte(),
    (102).to_byte(),
    (161).to_byte(),
    (76).to_byte(),
    (3).to_byte(),
    (91).to_byte(),
    (191).to_byte(),
    (147).to_byte(),
    (169).to_byte(),
    (182).to_byte(),
    (194).to_byte(),
    (225).to_byte(),
    (120).to_byte(),
  ],
  [ // 度 17，长 18
    (0).to_byte(),
    (43).to_byte(),
    (139).to_byte(),
    (206).to_byte(),
    (78).to_byte(),
    (43).to_byte(),
    (239).to_byte(),
    (123).to_byte(),
    (206).to_byte(),
    (214).to_byte(),
    (147).to_byte(),
    (24).to_byte(),
    (99).to_byte(),
    (150).to_byte(),
    (39).to_byte(),
    (243).to_byte(),
    (163).to_byte(),
    (136).to_byte(),
  ],
  [ // 度 18，长 19
    (0).to_byte(),
    (215).to_byte(),
    (234).to_byte(),
    (158).to_byte(),
    (94).to_byte(),
    (184).to_byte(),
    (97).to_byte(),
    (118).to_byte(),
    (170).to_byte(),
    (79).to_byte(),
    (187).to_byte(),
    (152).to_byte(),
    (148).to_byte(),
    (252).to_byte(),
    (179).to_byte(),
    (5).to_byte(),
    (98).to_byte(),
    (96).to_byte(),
    (153).to_byte(),
  ],
  [ // 度 19，长 20
    (0).to_byte(),
    (67).to_byte(),
    (3).to_byte(),
    (105).to_byte(),
    (153).to_byte(),
    (52).to_byte(),
    (90).to_byte(),
    (83).to_byte(),
    (17).to_byte(),
    (150).to_byte(),
    (159).to_byte(),
    (44).to_byte(),
    (128).to_byte(),
    (153).to_byte(),
    (133).to_byte(),
    (252).to_byte(),
    (222).to_byte(),
    (138).to_byte(),
    (220).to_byte(),
    (171).to_byte(),
  ],
  [ // 度 20，长 21
    (0).to_byte(),
    (17).to_byte(),
    (60).to_byte(),
    (79).to_byte(),
    (50).to_byte(),
    (61).to_byte(),
    (163).to_byte(),
    (26).to_byte(),
    (187).to_byte(),
    (202).to_byte(),
    (180).to_byte(),
    (221).to_byte(),
    (225).to_byte(),
    (83).to_byte(),
    (239).to_byte(),
    (156).to_byte(),
    (164).to_byte(),
    (212).to_byte(),
    (212).to_byte(),
    (188).to_byte(),
    (190).to_byte(),
  ],
  [ // 度 21，长 22
    (0).to_byte(),
    (240).to_byte(),
    (233).to_byte(),
    (104).to_byte(),
    (247).to_byte(),
    (181).to_byte(),
    (140).to_byte(),
    (67).to_byte(),
    (98).to_byte(),
    (85).to_byte(),
    (200).to_byte(),
    (210).to_byte(),
    (115).to_byte(),
    (148).to_byte(),
    (137).to_byte(),
    (230).to_byte(),
    (36).to_byte(),
    (122).to_byte(),
    (254).to_byte(),
    (148).to_byte(),
    (175).to_byte(),
    (210).to_byte(),
  ],
  [ // 度 22，长 23
    (0).to_byte(),
    (210).to_byte(),
    (171).to_byte(),
    (247).to_byte(),
    (242).to_byte(),
    (93).to_byte(),
    (230).to_byte(),
    (14).to_byte(),
    (109).to_byte(),
    (221).to_byte(),
    (53).to_byte(),
    (200).to_byte(),
    (74).to_byte(),
    (8).to_byte(),
    (172).to_byte(),
    (98).to_byte(),
    (80).to_byte(),
    (219).to_byte(),
    (134).to_byte(),
    (160).to_byte(),
    (105).to_byte(),
    (165).to_byte(),
    (231).to_byte(),
  ],
  [ // 度 23，长 24
    (0).to_byte(),
    (171).to_byte(),
    (102).to_byte(),
    (146).to_byte(),
    (91).to_byte(),
    (49).to_byte(),
    (103).to_byte(),
    (65).to_byte(),
    (17).to_byte(),
    (193).to_byte(),
    (150).to_byte(),
    (14).to_byte(),
    (25).to_byte(),
    (183).to_byte(),
    (248).to_byte(),
    (94).to_byte(),
    (164).to_byte(),
    (224).to_byte(),
    (192).to_byte(),
    (1).to_byte(),
    (78).to_byte(),
    (56).to_byte(),
    (147).to_byte(),
    (253).to_byte(),
  ],
  [ // 度 24，长 25
    (0).to_byte(),
    (229).to_byte(),
    (121).to_byte(),
    (135).to_byte(),
    (48).to_byte(),
    (211).to_byte(),
    (117).to_byte(),
    (251).to_byte(),
    (126).to_byte(),
    (159).to_byte(),
    (180).to_byte(),
    (169).to_byte(),
    (152).to_byte(),
    (192).to_byte(),
    (226).to_byte(),
    (228).to_byte(),
    (218).to_byte(),
    (111).to_byte(),
    (0).to_byte(),
    (117).to_byte(),
    (232).to_byte(),
    (87).to_byte(),
    (96).to_byte(),
    (227).to_byte(),
    (21).to_byte(),
  ],
  [ // 度 25，长 26
    (0).to_byte(),
    (231).to_byte(),
    (181).to_byte(),
    (156).to_byte(),
    (39).to_byte(),
    (170).to_byte(),
    (26).to_byte(),
    (12).to_byte(),
    (59).to_byte(),
    (15).to_byte(),
    (148).to_byte(),
    (201).to_byte(),
    (54).to_byte(),
    (66).to_byte(),
    (237).to_byte(),
    (208).to_byte(),
    (99).to_byte(),
    (167).to_byte(),
    (144).to_byte(),
    (182).to_byte(),
    (95).to_byte(),
    (243).to_byte(),
    (129).to_byte(),
    (178).to_byte(),
    (252).to_byte(),
    (45).to_byte(),
  ],
  [ // 度 26，长 27
    (0).to_byte(),
    (173).to_byte(),
    (125).to_byte(),
    (158).to_byte(),
    (2).to_byte(),
    (103).to_byte(),
    (182).to_byte(),
    (118).to_byte(),
    (17).to_byte(),
    (145).to_byte(),
    (201).to_byte(),
    (111).to_byte(),
    (28).to_byte(),
    (165).to_byte(),
    (53).to_byte(),
    (161).to_byte(),
    (21).to_byte(),
    (245).to_byte(),
    (142).to_byte(),
    (13).to_byte(),
    (102).to_byte(),
    (48).to_byte(),
    (227).to_byte(),
    (153).to_byte(),
    (145).to_byte(),
    (218).to_byte(),
    (70).to_byte(),
  ],
  [ // 度 27，长 28
    (0).to_byte(),
    (79).to_byte(),
    (228).to_byte(),
    (8).to_byte(),
    (165).to_byte(),
    (227).to_byte(),
    (21).to_byte(),
    (180).to_byte(),
    (29).to_byte(),
    (9).to_byte(),
    (237).to_byte(),
    (70).to_byte(),
    (99).to_byte(),
    (45).to_byte(),
    (58).to_byte(),
    (138).to_byte(),
    (135).to_byte(),
    (73).to_byte(),
    (126).to_byte(),
    (172).to_byte(),
    (94).to_byte(),
    (216).to_byte(),
    (193).to_byte(),
    (157).to_byte(),
    (26).to_byte(),
    (17).to_byte(),
    (149).to_byte(),
    (96).to_byte(),
  ],
  [ // 度 28，长 29
    (0).to_byte(),
    (168).to_byte(),
    (223).to_byte(),
    (200).to_byte(),
    (104).to_byte(),
    (224).to_byte(),
    (234).to_byte(),
    (108).to_byte(),
    (180).to_byte(),
    (110).to_byte(),
    (190).to_byte(),
    (195).to_byte(),
    (147).to_byte(),
    (205).to_byte(),
    (27).to_byte(),
    (232).to_byte(),
    (201).to_byte(),
    (21).to_byte(),
    (43).to_byte(),
    (245).to_byte(),
    (87).to_byte(),
    (42).to_byte(),
    (195).to_byte(),
    (212).to_byte(),
    (119).to_byte(),
    (242).to_byte(),
    (37).to_byte(),
    (9).to_byte(),
    (123).to_byte(),
  ],
  [ // 度 29，长 30
    (0).to_byte(),
    (156).to_byte(),
    (45).to_byte(),
    (183).to_byte(),
    (29).to_byte(),
    (151).to_byte(),
    (219).to_byte(),
    (54).to_byte(),
    (96).to_byte(),
    (249).to_byte(),
    (24).to_byte(),
    (136).to_byte(),
    (5).to_byte(),
    (241).to_byte(),
    (175).to_byte(),
    (189).to_byte(),
    (28).to_byte(),
    (75).to_byte(),
    (234).to_byte(),
    (150).to_byte(),
    (148).to_byte(),
    (23).to_byte(),
    (9).to_byte(),
    (202).to_byte(),
    (162).to_byte(),
    (68).to_byte(),
    (250).to_byte(),
    (140).to_byte(),
    (24).to_byte(),
    (151).to_byte(),
  ],
  [ // 度 30，长 31
    (0).to_byte(),
    (41).to_byte(),
    (173).to_byte(),
    (145).to_byte(),
    (152).to_byte(),
    (216).to_byte(),
    (31).to_byte(),
    (179).to_byte(),
    (182).to_byte(),
    (50).to_byte(),
    (48).to_byte(),
    (110).to_byte(),
    (86).to_byte(),
    (239).to_byte(),
    (96).to_byte(),
    (222).to_byte(),
    (125).to_byte(),
    (42).to_byte(),
    (173).to_byte(),
    (226).to_byte(),
    (193).to_byte(),
    (224).to_byte(),
    (130).to_byte(),
    (156).to_byte(),
    (37).to_byte(),
    (251).to_byte(),
    (216).to_byte(),
    (238).to_byte(),
    (40).to_byte(),
    (192).to_byte(),
    (180).to_byte(),
  ],
]

///|
/// get_polynomial 选择索引：generator_index[ecl][version] = 生成多项式序号（度）。
/// 由 (max_bytes - data_codewords) / 分组总数 求得，与源码 get_polynomial 分组一致。

///|
let generator_index : Array[Array[Int]] = [
  [ // ecl 0 = L
    7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
    28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
  ],
  [ // ecl 1 = M
    10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
    26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
  ],
  [ // ecl 2 = Q
    13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30,
    28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
  ],
  [ // ecl 3 = H
    17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28,
    30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
  ],
]

///|
/// format_information[ecl][mask]：15 位格式信息字。S5 用。

///|
let format_information_table : Array[Array[Int]] = [
  [ // ecl 0 = L
    30660, 29427, 32170, 30877, 26159, 25368, 27713, 26998,
  ],
  [ // ecl 1 = M
    21522, 20773, 24188, 23371, 17913, 16590, 20375, 19104,
  ],
  [ // ecl 2 = Q
    13663, 12392, 16177, 14854, 9396, 8579, 11994, 11245,
  ],
  [ // ecl 3 = H
    5769, 5054, 7399, 6608, 1890, 597, 3340, 2107,
  ],
]

///|
/// 分组信息：ecc_to_groups(ecl_idx, version_idx) -> (g1_count, g1_size, g2_count, g2_size)。
/// reedsolomon.structure 依赖。

///|
pub fn ecc_to_groups(ecl_idx : Int, version_idx : Int) -> (Int, Int, Int, Int) {
  ecc_to_groups_table[if ecl_idx < 0 || ecl_idx > 3 { 3 } else { ecl_idx }][if version_idx <
    0 ||
    version_idx > 39 {
    39
  } else {
    version_idx
  }]
}

///|
/// 生成多项式：get_polynomial(version_idx, ecl_idx) -> 生成多项式（拷贝）。
/// 入参顺序 (version, ecl) 对齐源码。供 reedsolomon.division/structure 用。

///|
pub fn get_polynomial(version_idx : Int, ecl_idx : Int) -> Array[Byte] {
  let v = if version_idx < 0 || version_idx > 39 { 39 } else { version_idx }
  let e = if ecl_idx < 0 || ecl_idx > 3 { 3 } else { ecl_idx }
  generator_polys[generator_index[e][v]].copy()
}

///|
/// 格式信息字：format_information(ecl_idx, mask_idx)。S5 用。

///|
pub fn format_information(ecl_idx : Int, mask_idx : Int) -> Int {
  let e = if ecl_idx < 0 || ecl_idx > 3 { 3 } else { ecl_idx }
  let m = if mask_idx < 0 || mask_idx > 7 { 0 } else { mask_idx }
  format_information_table[e][m]
}

///|
/// percent_score_table[percent(0..=99)] = 暗模块占比惩罚分（N4 评分用）。
/// 对应参考 fast_qr v0.14.0 `hardcode.rs:406 PERCENT_SCORE`（roadmap 铁律：脚本提取、禁止手抄）。
/// 每偏离 50% 一档（5% 步长）给固定惩罚分；percent 取整为 `暗模块数*100 // 总模块数`（0..=99）。
/// S5 落：N4 `score_dark` 查此表。
pub let percent_score_table : Array[Int] = [
  90, 90, 90, 90, 90, 80, 80, 80, 80, 80, 70, 70, 70, 70, 70, 60, 60, 60, 60, 60,
  50, 50, 50, 50, 50, 40, 40, 40, 40, 40, 30, 30, 30, 30, 30, 20, 20, 20, 20, 20,
  10, 10, 10, 10, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 20, 20, 20,
  20, 20, 30, 30, 30, 30, 30, 40, 40, 40, 40, 40, 50, 50, 50, 50, 50, 60, 60, 60,
  60, 60, 70, 70, 70, 70, 70, 80, 80, 80, 80, 80, 90, 90, 90, 90, 90,
]

///|
/// N4 暗比查表：percent_score(percent) -> 惩罚分。percent 需 0..=99。
pub fn percent_score(percent : Int) -> Int {
  if percent < 0 {
    percent_score_table[0]
  } else if percent > 99 {
    percent_score_table[99]
  } else {
    percent_score_table[percent]
  }
}
