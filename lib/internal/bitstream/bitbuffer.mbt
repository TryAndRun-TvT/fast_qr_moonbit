///|
/// bitbuffer.mbt —— 位流缓冲（CompactQR 的 MoonBit 对应）
/// 对应参考：fast_qr v0.14.0 `src/compact.rs`（roadmap 批次 B6）
/// 职责：按任意位宽推进的大端序比特流；容量按需增长；填充补位 [236, 17]。
/// 关键语义：跨字节/位数拆分用 `KEEP_LAST` 掩码表。MoonBit `Int` 为 32 位，
///       故 `KEEP_LAST` 取 Rust wasm32 分支规模（index 0..=31，值 `(1<<k)-1`），
///       单次 `push_bits` 的位数上界与 32 位 Int 位宽一致（roadmap §3.2）。
/// 依赖规则：不依赖 lib 公共包（纯缓冲，无外部类型）。

///|
/// 保留低 `k` 位掩码：`KEEP_LAST[k] = (1<<k) - 1`（k = 0..=31，适配 32 位 Int）。
let keep_last : Array[Int] = [
  0, 1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383, 32767, 65535,
  131071, 262143, 524287, 1048575, 2097151, 4194303, 8388607, 16777215, 33554431,
  67108863, 134217727, 268435455, 536870911, 1073741823, 2147483647,
]

///|
/// 位流缓冲：`len` 为已写入比特数，`data` 为大端序字节容器。
pub struct CompactQR {
  mut len : Int
  data : Array[Byte]
}

///|
/// 空缓冲。
pub fn CompactQR::new() -> CompactQR {
  CompactQR::{ len: 0, data: Array::make(0, b'\x00'), }
}

///|
/// 从初始容量（比特数，向上取整到字节）构造缓冲。
pub fn from_bits(capacity_bits : Int) -> CompactQR {
  let nbytes = (capacity_bits + 7) / 8
  CompactQR::{ len: 0, data: Array::make(nbytes, b'\x00'), }
}

///|
/// 确保缓冲能容纳 `need_bits` 位（按需扩容，零拷贝前追加）。
fn ensure_capacity(q : CompactQR, need_bits : Int) -> Unit {
  let need_bytes = (need_bits + 7) / 8
  while q.data.length() < need_bytes {
    q.data.push(b'\x00')
  }
}

///|
/// 已写入比特数。
pub fn CompactQR::len(self : CompactQR) -> Int {
  self.len
}

///|
/// 数据字节（拷贝）。
pub fn CompactQR::data(self : CompactQR) -> Array[Byte] {
  self.data.copy()
}

///|
/// 逐字节写入一个 `u8`（可能跨字节拆分，参考 `compact.rs::push_u8`）。
pub fn CompactQR::push_u8(self : CompactQR, bits : Byte) -> Unit {
  ensure_capacity(self, self.len + 8)
  let b = bits.to_int()
  let right = self.len % 8
  let first = self.len / 8
  if right == 0 {
    self.data[first] = bits
  } else {
    let left = 8 - right
    let v0 = self.data[first].to_int() | ((b >> right) & keep_last[left])
    self.data[first] = (v0 & 0xFF).to_byte()
    let v1 = self.data[first + 1].to_int() | ((b & keep_last[right]) << left)
    self.data[first + 1] = (v1 & 0xFF).to_byte()
  }
  self.len += 8
}

///|
/// 逐字节写入一段 `u8`。
pub fn CompactQR::push_u8_slice(self : CompactQR, slice : Array[Byte]) -> Unit {
  for b in slice {
    self.push_u8(b)
  }
}

///|
/// 写入低 `len` 位（`bits` 超出部分由 `KEEP_LAST` 截断）。大端序。
pub fn CompactQR::push_bits(self : CompactQR, bits : Int, len : Int) -> Unit {
  ensure_capacity(self, self.len + len)
  let cap_bits = bits & keep_last[len]
  let rem_space = (8 - self.len % 8) % 8
  let first = self.len / 8

  if rem_space > len {
    let v = self.data[first].to_int() | (cap_bits << (rem_space - len))
    self.data[first] = (v & 0xFF).to_byte()
    self.len += len
    return
  }

  if rem_space != 0 {
    let v = self.data[first].to_int() |
      ((cap_bits >> (len - rem_space)) & keep_last[rem_space])
    self.data[first] = (v & 0xFF).to_byte()
    self.len += rem_space
  }

  // 整字节段：每次切出高 8 位写一个字节
  let hi = len - rem_space
  let mut sh = hi - 8
  while sh >= 0 {
    self.push_u8(((cap_bits >> sh) & 0xFF).to_byte())
    sh -= 8
  }

  let remaining = (len - rem_space) % 8
  if remaining == 0 {
    return
  }
  let v = self.data[self.len / 8].to_int() +
    (((cap_bits & keep_last[remaining]) << (8 - remaining)) & 0xFF)
  self.data[self.len / 8] = (v & 0xFF).to_byte()
  self.len += remaining
}

///|
/// 用 `[236, 17]` 交替填充剩余空间。前置条件：`len % 8 == 0`。
pub fn CompactQR::fill(self : CompactQR) -> Unit {
  let pad = [(0b1110_1100).to_byte(), (0b0001_0001).to_byte()]
  let mut i = 0
  let total_bytes = (self.data.length() * 8 - self.len) / 8
  while i < total_bytes {
    self.push_u8(pad[i % 2])
    i += 1
  }
}
