# CompactQR

CompactQR 是 fast_qr 的比特流缓冲区，在"用户字节"与"QR 矩阵"之间承担位级中间表示：编码器往里推任意长度的比特，纠错与放置阶段按字节读出。

## 什么是 CompactQR？

CompactQR 用一个 `Vec<u8>` 存储比特流（大端序，高位在前），外加一个 `len: usize` 记录当前比特数。它存在的原因是 QR 规范的编码单位极不规整——模式标识 4 bit、计数器 8-16 bit、Numeric 10 bit/组、Alphanumeric 11 bit/组——必须有一个能按任意位宽推进的缓冲区。

**关键特征**:
- 预分配：`from_version` 按版本最大码字数一次分配 `len*8` 字节，编码期零扩容
- 大端序：`push_bits` 从高位写起，跨字节时用 `KEEP_LAST` 掩码表拆分
- 双语义：`len` 是"已用比特数"，`data.len()` 是"容量字节数"，`fill()` 依赖两者差值补填充字节

## 代码位置

| 方面 | 位置 |
|------|------|
| 结构体 | `src/compact.rs:61` |
| KEEP_LAST 掩码表 | `src/compact.rs:34`（64 位平台 65 项）与 `src/compact.rs:53`（wasm32 33 项） |
| 写入核心 | `push_bits`（compact.rs:177）、`push_u8`（compact.rs:146） |
| 填充 | `fill()`（compact.rs:213，交替写入 [236, 17]） |
| 测试 | `src/tests/compact.rs`（200 行） |

## 结构

```rust
pub struct CompactQR {
    pub len: usize,      // 当前已写入的比特数
    pub data: Vec<u8>,   // 预分配的比特容器
}
```

### 关键方法契约

| 方法 | 契约 |
|------|------|
| `from_version(v)` | 容量 = `v.max_bytes() * 8` 比特 |
| `push_bits(bits, len)` | `bits` 超出 `len` 位的高位被 `KEEP_LAST[len]` 截断 |
| `push_u8_slice(s)` | 逐字节调用 `push_u8`，注意此路径无跨字节合并优化 |
| `fill()` | 前置条件：`len % 8 == 0`（debug 断言），用 0b1110_1100 / 0b0001_0001 交替填充 |

## 不变量

1. **容量足够**：由 `Version::get` 保证选出的版本容量 >= 数据需求，`increase_len` 只是兜底
2. **fill 前对齐**：`add_terminator` + `pad_to_8` 保证调用 `fill()` 时比特数已 8 对齐
3. **平台位宽一致**：wasm32 下 usize 为 32 位，KEEP_LAST 截断到 33 项；64 位平台为 65 项，两者必须与目标位宽匹配

## 生命周期

```mermaid
flowchart LR
    A["from_version 预分配"] --> B["encode 按位写入"]
    B --> C["add_terminator 截止符"]
    C --> D["pad_to_8 对齐"]
    D --> E["fill 填充 236/17"]
    E --> F["polynomials::structure 按字节消费"]
    F --> G["CompactQR::from_array 包装结构数组"]
    G --> H["place_on_matrix_data 逐位读出"]
```

## 关系

| 关联概念 | 关系 | 描述 |
|---------|------|------|
| [Module](./module.md) | 下游 | 比特流最终落入 Module 矩阵的数据区 |
| GF(256) 纠错 | 中间消费方 | `structure()` 以 `&[u8]` 形式消费 data 字节 |
