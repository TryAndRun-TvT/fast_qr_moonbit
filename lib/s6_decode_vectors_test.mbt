///|
/// s6_decode_vectors_test.mbt —— T3-c 固化解码向量（黑盒）；**由脚本生成，禁止手改**。
///
/// 生成器：`node scripts/snapshot_gen_decode_vectors.mjs --write`
/// 前置：`moon build cmd/bench --target wasm-gc --release`
/// 参考 commit：fast_qr v0.14.0 `53e8c99`（旁证；期望原文由输入决定，不来自参考）
///
/// 这些向量是**独立正确性证据的固定形态**：`scripts/qr-decode-check.mjs`（jsqr）已证明
/// 下列矩阵「能被第三方解码器读回原文」，本文件把该结论固化为**无 npm 依赖可回归**的指纹。
///
/// 指纹 = **FNV-1a 64** over `0/1` 行主序拼接串（16 位小写 hex）。任何矩阵输出漂移都会变红。
/// 期望内容同样固化：`content` 必须是该矩阵交给第三方解码器后**读回的原文**
///   （Numeric→全 `9`、Alphanumeric→全 `A`、Byte→全 `z`，长度见 `content`）。
///
/// 复跑路径（矩阵漂移时）：
///   1) `bash scripts/test-audit.sh decode` —— 用 jsqr 重新验证语义（需 `npm i jsqr`）
///   2) `node scripts/snapshot_gen_decode_vectors.mjs --write` —— 确认语义无误后刷新指纹
/// 铁律：**语义未重新验证前，禁止直接刷新指纹**（否则把回归洗成「新基线」）。

///|
/// 单条固化向量：`--dump-case index` 的矩阵指纹 + 期望读回内容 + 参数指纹。
struct DecodeVector {
  index : Int
  kind : String
  mode : String
  ecl : String
  version : String
  size : Int
  content : String
  fnv : String
}

///|
/// 固化向量表（脚本生成，见文件头复跑路径）。
fn decode_vectors() -> Array[DecodeVector] {
  [
    DecodeVector::{
      index: 0,
      kind: "grid",
      mode: "Numeric",
      ecl: "L",
      version: "V1",
      size: 21,
      content: "9999999999999999",
      fnv: "0c2dead0427fb2bf",
    },
    DecodeVector::{
      index: 3,
      kind: "grid",
      mode: "Numeric",
      ecl: "L",
      version: "V40",
      size: 177,
      content: "999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999",
      fnv: "b77591ca5ca6cb11",
    },
    DecodeVector::{
      index: 15,
      kind: "grid",
      mode: "Numeric",
      ecl: "H",
      version: "V40",
      size: 177,
      content: "999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999",
      fnv: "0a24973f0caae02d",
    },
    DecodeVector::{
      index: 32,
      kind: "grid",
      mode: "Byte",
      ecl: "L",
      version: "V1",
      size: 21,
      content: "zzzzzz",
      fnv: "0e72c40688c410bf",
    },
    DecodeVector::{
      index: 47,
      kind: "grid",
      mode: "Byte",
      ecl: "H",
      version: "V40",
      size: 177,
      content: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      fnv: "259bb6bee13d28cc",
    },
    DecodeVector::{
      index: 48,
      kind: "auto",
      mode: "Numeric",
      ecl: "H",
      version: "auto",
      size: 29,
      content: "9999999999999999999999999999999999999999",
      fnv: "08155c53c6ba97cc",
    },
    DecodeVector::{
      index: 49,
      kind: "auto",
      mode: "Numeric",
      ecl: "Q",
      version: "auto",
      size: 25,
      content: "9999999999999999999999999999999999999999",
      fnv: "4ad30106bbbeb160",
    },
    DecodeVector::{
      index: 50,
      kind: "auto",
      mode: "Alphanumeric",
      ecl: "H",
      version: "auto",
      size: 33,
      content: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      fnv: "08bd483e2c246a4f",
    },
    DecodeVector::{
      index: 51,
      kind: "auto",
      mode: "Alphanumeric",
      ecl: "Q",
      version: "auto",
      size: 29,
      content: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      fnv: "90ee1495f176d7bc",
    },
    DecodeVector::{
      index: 52,
      kind: "auto",
      mode: "Byte",
      ecl: "H",
      version: "auto",
      size: 37,
      content: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      fnv: "14c3ab99ea97364f",
    },
    DecodeVector::{
      index: 53,
      kind: "auto",
      mode: "Byte",
      ecl: "Q",
      version: "auto",
      size: 33,
      content: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      fnv: "87ef9560b7a81e77",
    },
  ]
}

///|
/// UInt64 → 16 位小写 hex（core 无现成实现，本文件自持）。
fn decode_hex16(v : UInt64) -> String {
  let sb = StringBuilder()
  let mut shift = 60
  while shift >= 0 {
    // 每 4 位取一个 nibble
    let nib = (v >> shift).to_int() & 0xF
    sb.write_char(
      if nib < 10 {
        (nib + 48).unsafe_to_char()
      } else {
        (nib - 10 + 97).unsafe_to_char()
      },
    )
    shift -= 4
  }
  sb.to_string()
}

///|
/// FNV-1a 64 位（与生成器 Node 侧同算法；16 位小写 hex 输出）。
fn decode_fnv1a64(s : String) -> String {
  let mut h : UInt64 = 0xCBF29CE484222325UL
  // s.to_bytes() 已 deprecated；FNV 只需**确定性地**逐字节迭代，
  // 用 char 的低 8 位 UTF-8 等价位（本向量内容全为 ASCII，无编码歧义）。
  for c in s {
    h = h ^ (c.to_int() & 0xFF).to_uint64()
    h = h * 0x100000001B3UL
  }
  decode_hex16(h)
}

///|
/// 版本短名（`V1`..`V40`）→ 公共 `Version` 枚举（`V01`..`V40`）。
fn decode_version(name : String) -> Version {
  match name {
    "V1" => Version::V01
    "V5" => Version::V05
    "V10" => Version::V10
    _ => Version::V40
  }
}

///|
/// 按向量参数**重新构建** QR 码，只用 pub API 逐格取明暗拼出矩阵串。
fn decode_rebuild(v : DecodeVector) -> String {
  let mode = match v.mode {
    "Numeric" => Mode::Numeric
    "Alphanumeric" => Mode::Alphanumeric
    _ => Mode::Byte
  }
  let ecl = match v.ecl {
    "L" => ECL::L
    "M" => ECL::M
    "Q" => ECL::Q
    _ => ECL::H
  }
  let b = QRBuilder::from_string(v.content).mode(mode).ecl(ecl)
  // kind 决定是否强制版本：`grid` 强制定长版本，`auto` 走自动最小适配（bug 靶点）。
  // 注：`version` 字符串已固化了实际选中版本，仅供失败信息定位用。
  // grid 语料强制其固化版本；auto 语料走自动最小适配（`select_capacity` 的 bug 靶点）。
  let r = if v.kind == "auto" {
    b.build()
  } else {
    b.version(decode_version(v.version)).build()
  }
  match r {
    Ok(q) => {
      let sb = StringBuilder()
      let mut row = 0
      while row < q.size() {
        let mut col = 0
        while col < q.size() {
          sb.write_char(if q.get(row, col).value() { '1' } else { '0' })
          col += 1
        }
        row += 1
      }
      sb.to_string()
    }
    Err(_) => ""
  }
}

///|
/// T3-c：对每条固化向量重建矩阵并断言 FNV-1a 指纹 + 尺寸一致（模块.函数 + 参数指纹）。
/// 说明：本测试**不依赖第三方解码器**（那是 `test-audit.sh decode` 的角色）；
/// 它锁的是「修复 `select_capacity` 模式语义后，矩阵输出保持稳定」，
/// 防止未来改动静默改回旧行为（旧行为下 auto 靶点语料**不可解码**）。
test "s6_decode_vectors_frozen" {
  let vs = decode_vectors()
  assert_eq(vs.length(), 11)
  for v in vs {
    let got = decode_rebuild(v)
    if got.length() != v.size * v.size {
      fail(
        "s6_decode_vectors_frozen case \{v.index} \{v.mode}/\{v.ecl}/\{v.version}: 矩阵长度 \{got.length()} != size^2 \{v.size * v.size}",
      )
    }
    let got_fnv = decode_fnv1a64(got)
    if got_fnv != v.fnv {
      fail(
        "s6_decode_vectors_frozen case \{v.index} \{v.mode}/\{v.ecl}/\{v.version} size=\{v.size} content_len=\{v.content.length()}: fnv=\{got_fnv} want=\{v.fnv}（矩阵漂移；先跑 bash scripts/test-audit.sh decode 复核语义）",
      )
    }
  }
}
