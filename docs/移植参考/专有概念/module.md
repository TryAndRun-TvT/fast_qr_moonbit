# Module

Module 是 QR 码矩阵中的单个像素（"模块"），fast_qr 用一个字节表示它，这是整个库性能设计的基础单元。

## 什么是 Module？

Module 代表 QR 码网格中的一个最小方格，同时携带两个信息：明暗值（黑/白）与功能归属（数据区还是某个功能图案）。fast_qr 将两者打包进单个 `u8`，使矩阵总大小仅为 31329 字节（177x177），且掩码、评分操作都退化为单字节位运算。

**关键特征**:
- bit0 存明暗值：1 = DARK（黑），0 = LIGHT（白）
- bit1-3 存**类型号**（0..7：Data=0 / Finder=1 / Alignment=2 / Timing=3 / Format=4 / Version=5 / DarkModule=6 / Empty=7）；`ModuleType` 各变体的判别值按 `序号 << 1` 声明（如 `Data = 0 << 1`、`Empty = 7 << 1`），使 `new` 能直接 `value | 判别值` 写入，`module_type()` 用 `>> 1` 还原类型号
- `Copy` 语义，无堆分配，`size_of::<Module>() == 1` 有专门测试断言

## 代码位置

| 方面 | 位置 |
|------|------|
| 类型定义 | `src/module.rs:42`（`pub struct Module(pub u8)`） |
| 类型枚举 | `src/module.rs:4`（ModuleType） |
| 使用方 | `src/qr.rs`（QRCode.data）、`src/datamasking.rs`、`src/score.rs`、`src/default.rs` |
| 测试 | `src/module.rs:148-217`（含字节大小断言） |

## 结构

```rust
pub struct Module(pub u8);

pub enum ModuleType {
    Data = 0 << 1,           // 编码数据区
    FinderPattern = 1 << 1,  // 三个大定位方块
    Alignment = 2 << 1,      // 小定位方块
    Timing = 3 << 1,         // 连接定位图案的黑白线
    Format = 4 << 1,         // 格式信息区
    Version = 5 << 1,        // 版本信息区（V7+）
    DarkModule = 6 << 1,     // 固定暗模块
    Empty = 7 << 1,          // 分隔区（separator）
}
```

### 关键方法

| 方法 | 位操作 | 用途 |
|------|------|------|
| `new(value, module_type)` | `value as u8 \| type as u8`（判别值已含 `<< 1`） | 构造 |
| `value()` | `self.0 & 1 == 1` | 读明暗 |
| `module_type()` | `self.0 >> 1` | 读类型号（0..7，用于 Data 判定/类型识别） |
| `set(value)` | 置位/清位 bit0 | 写明暗 |
| `toggle()` | `self.0 ^= 1` | 翻转（掩码核心操作） |

## 不变量

1. **单字节**：Module 永远占 1 字节，测试 `byte_size` 保证
2. **类型偏移**：类型号写入 bit1-3（判别值按 `序号 << 1` 声明），`module_type()` 的 `>> 1` 解码必须与之配套，否则错位
3. **掩码只动 Data**：所有掩码与评分逻辑都通过 `module_type() == ModuleType::Data` 判断后再操作，功能图案不可被掩码翻转

## 关系

| 关联概念 | 关系 | 描述 |
|---------|------|------|
| [CompactQR](./compact-qr.md) | 上下游 | CompactQR 中的比特最终逐位写入 Module 矩阵 |
| QRCode | 容器 | QRCode.data 是 Module 的 31329 长度固定数组 |
