///|
/// lib/internal/reedsolomon/reedsolomon_structure_a_wbtest.mbt —— structure 交织黄金向量（S10 §6 T1-d，V05-Q / V10-Q）
/// 输入（LCG 确定性）与期望交织结果均由 scripts/gen-goldens.sh --emit-rs
/// 在参考侧 fast_qr 53e8c99 **实际计算**产出，严禁手抄；以 hex 串内联比对。
/// 真值点：每组的「消息区 + 纠错区」全长逐字节。

///|
test "t1d_structure_golden_v05-q__v10-q" {
  // v05q: V05-ECL2，data=62 字节，交织后 134 字节
  let got_v05q = structure(
    hex_bytes(
      "43554686572655c277320612066726f6f642077686f207265616c6c79206b6e6f77732077686572652068697320746f77656c206973210ec11ec11ec11ec",
    ),
    2,
    4,
  )
  let want_v05q = hex_ints(
    "43f6b64655f6e6f74642f77686077756577632c22686070655f27697c207863277265710325626ec0616521112c606ec06c78611679297ec2606321107ecd55794ebc7cc749f0b60b1052d3cd4ad73ca4c18f7b68593f17c4b3bdf9df221e5c8ee6af8864c289a1bc3ff7581e6ac9ad1bd526f110a0256a36c83a1a3f0206f78c0b227858dec",
  )
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
  // v10q: V10-ECL2，data=154 字节，交织后 346 字节
  let got_v10q = structure(
    hex_bytes(
      "71471d94ec8993c744bcd8cfcb3cc5a66819a8e6caa4e23b69bd418941da1edc4ed83613c682494c19e2740ea94a4f394920c6ae776db8be592551547a3428e1414d180a3571de14f241770bea0537b5dd78a93a16592a906bb244a8f2e6cb5a837eba11f2b0cb3609b3d85e48c5f4325cf848225fc0afc9d53e111e624a80604d4314c0b59687cb950f8f9e79e2ffc8fd789cfd0afbc080d0a0",
    ),
    2,
    9,
  )
  let want_v10q = hex_ints(
    "71e64925ea5a488747ca4c51058322cb1da41954377e5f9594e2e27ab5bac00fec3b7434dd11af8f89690e2878f2c99e93bda9e1a9b0d579c7414a413acb3ee244894f4d163611ffbc41391859091ec8d8da490a2ab362fdcf1e203590d84a78cbdcc6716b5e809c3c4eaedeb24860fdc5d8771444c54d0aa6366df2a8f443fb6813b841f23214c019c6be77e65cc080a882590bcbf8b5d096a05deeb61809cfe51cdb6554cfb8054b9b19710d1e817039404eda65e2820856a5ae76d582134cf813d5fbd7d6d1d6d51cfe59286421b35f8178dc63ebda1dffaa0c7ca52802a2614b81209334d6c0bebca891fd77d1027c55dcc322998bfb393389ea801a3c4df23464db291f8bb5bbaf203b4228340d2ab22ee4b975af6922076bf906a4ff1c84d1de2177855c84188c18ee9e571d4fab121ad33d79198842706403688aa49a4218f98bee6fde22e7ffe4b6c16f22fc8040d4f0b82792fa812f",
  )
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
}
