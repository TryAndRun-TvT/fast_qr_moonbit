///|
/// lib/internal/reedsolomon/reedsolomon_structure_b_wbtest.mbt —— structure 交织黄金向量（S10 §6 T1-d，V07-H / V16-M / V03-Q）
/// 输入（LCG 确定性）与期望交织结果均由 scripts/gen-goldens.sh --emit-rs
/// 在参考侧 fast_qr 53e8c99 **实际计算**产出，严禁手抄；以 hex 串内联比对。
/// 真值点：每组的「消息区 + 纠错区」全长逐字节。

///|
test "t1d_structure_golden_v07-h__v16-m__v03-q" {
  // v07h: V07-ECL3，data=66 字节，交织后 196 字节
  let got_v07h = structure(
    hex_bytes(
      "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d",
    ),
    3,
    6,
  )
  let want_v07h = hex_ints(
    "713c414c7747c589196d1da641e2b89468da74beec191e0e5989a8dca92593e64e4a51c7cad84f5444a436397abce2134934d83bc62028cf6982c6e1cbbd49ae414d2cf07c0e62db2936a26748424a7662a5c3aa249124d186b3ae20d75339bca0f31cb76511aac41acd82410f6b2a6778072549ad516e4f4b4780871f440db1cd80871aed126fd35f369633d24f51c49c9297c02a27b7ebc60181f76bfc36ad9ba2323a1e7c14aee8e2484ac4758040be10f10b4e9af3f32ee7b5f6909ce17760cc103d",
  )
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
  // v16m: V16-ECL1，data=453 字节，交织后 733 字节
  let got_v16m = structure(
    hex_bytes(
      "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d180a3571de14f241770bea0537b5dd78a93a16592a906bb244a8f2e6cb5a837eba11f2b0cb3609b3d85e48c5f4325cf848225fc0afc9d53e111e624a80604d4314c0b59687cb950f8f9e79e2ffc8fd789cfd0afbc080d0a0b14e83b7be0bd5741fae367b8aebce2d956336b5cf8efad19c64cf60d4ce95b01bd00b85fe7354e9d2732db74dadebe5e1473794dc9d8ad941ef664964cb5a47473bb30db7af027b26a952a2472b26106ce035d99f0ce46a8235870de78f583b2e2833a562d8170112e65d95f17ab6842dc7e6dc8ff5425b57cfea04d531c766c72f43a77606cb538fc306e7c2b5d21b1c9403f3256eda84b9554787a7cadf9f0be79b6a6b50564994d804f033f2b3ac32de4477d88fe6be9f5e56ecd471d7bef1e9f346bacff0bc1abc1108bb4a9210673e61c121729cdf0283ce8dd540e99c72cd0393db9ad1821808e487d2d5a51db14b1128772d35c1d95c69c1214c4c0f852b83aa44cb3075865334c6f1aa25ad0b9f0e0452d8e93b1d81dde031b038f1229a2be27078476c5d37bb",
    ),
    1,
    15,
  )
  let want_v16m = hex_ints(
    "714a44cbcf7b8fe7104c474fa8956026f59b674c1d39f20fd4a9426a3e0f9449e68fce525b6b6185ec20cb9e95a25750c12b89c65a79b047cf56218393ae83e21b2bea4972aac7777effd02604949c44446dbac80b10d5d8dfcbbcb811fd856c31040230d8bef278fee0c7f08375cf59b09c73356633ce86cb25cbfd54d9c7f28d533c51360ae99f2fb3d534c55409fbd20c43ac40c6a67ab3c073e4a732e9f16834d8802d6a76de9caa19285ed0b78206447225a8e148a04d35cb77cdade641c5b1ad8753d8030bca4df44eeb0d8f8f939fa4183283e5e7c3e6db0ee20a5cb7e18f06be9a043b35f8be4758e79fd1526971480b373bc25e82d8bdde22d5942eb55618e941145f74dc28d2ec083b89f2c01f9d331bd4e41d4141afae8aa51c718781da77c936d96294d7d2dd1e0bd57b41d803bed5e0dcea3e8aef17f3f1a5314e0511eb660125e91db0d8371ece49126ef3b13836b5622d64e6da464bf113dd4a95cb5d84ba1122c67880635a95b9cf289a82a9603647f155f0772b493a4db5477a47bc2de24c1643cf3bb6871a35701959148eb384a7bcc178e22ac0fa0d2dca11d9477490b5d1b7c7df085c6c0e6b969cafe69fbb695da9b2876402dc0b4ac1379221bb02ebebd8d31e272484253cf1f8641e3b2ba53bca7198e8b24f1925bfdd321f40ee4b47d68f45c8f098d6fcca757e65724769a0bd89a2239f6a79d7d86c7d2bc670cb48b8bf77d5e580d7d977292d5395127dd2cb2a399aa235e3f614870bb585ae836e15d6f619c4dcb4fe4060cfa131347123bf210f345aa87ea96f8e2c0128008f8ab50088484089b35ee33c2aad9798037fdcc7f909050101db89a5c0f8ad0c49680aa09bcf1ba75ac7a8d9db591515c4a41665808420ec03fb0a7cc278d39f20a9e23389cffd5801d3d41186118b17ce09514341589d4bce17228e823d7587c968d5bcc60b23f1020d3b3c1fccbc7dcde072631128ac8c341094a9ac82716d905bd6c2d1e46423d87832a9b91a477f3eaea490aa4d81",
  )
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
  // v03q: V03-ECL2，data=34 字节，交织后 70 字节
  let got_v03q = structure(
    hex_bytes(
      "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed8",
    ),
    2,
    2,
  )
  let want_v03q = hex_ints(
    "711947a81de694caeca489e2933bc76944bdbc41d889cf41cbda3c1ec5dca64e68d8e2fc452de26bc91dee5d401cd2262b549d29258d6bf59bff38162e8d14a909a02f522ac9",
  )
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
