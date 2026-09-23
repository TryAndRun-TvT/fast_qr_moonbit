///|
/// module.mbt —— 原始字节矩阵的位布局约定与 Int 级 helper（决策 D3 收敛）
/// 对应参考：fast_qr v0.14.0 `src/module.rs`（roadmap 批次 B5；架构决策 D1/D3）
/// 决策 D3：internal/matrix 不能反向 import lib（无环），故本包**不再定义 Module 类型**，
///       而以原始字节矩阵 `FixedArray[Int]` 为工作介质：每格 packed byte = 明暗(bit0) | 类型号<<1，
///       与 lib 公共 `Module.byte()` **完全同构、可互转**。本文件收敛为：
///        1) 模块类型号常量（0..=7）；
///        2) 一组对单格 Int 值做明暗/类型读写的位级 helper。
///       矩阵各函数收发的都是 `FixedArray[Int]` + 各序号，不 import lib；lib 侧把结果逐格
///       包装回公共 `Module`（见 S4 方案 §3.1/§3.4 与 lib qr.mbt 编排入口）。
/// 不变量：
///   - 明暗：bit0（1=DARK 黑 / 0=LIGHT 白）；
///   - 类型：bit1-3 存类型号，判别值 = 类型号 << 1；类型号用 `>> 1` 还原；
///   - 掩码/评分只对 Data（type==0）翻转/计分，功能图案不动。

///|
/// 类型号常量（0..=7）。packed 判别值 = 类型号 << 1（bit1-3）。
pub let module_type_data : Int = 0

///|
pub let module_type_finder : Int = 1

///|
pub let module_type_alignment : Int = 2

///|
pub let module_type_timing : Int = 3

///|
pub let module_type_format : Int = 4

///|
pub let module_type_version : Int = 5

///|
pub let module_type_dark : Int = 6

///|
pub let module_type_empty : Int = 7

///|
/// 判定 packed byte 是否为数据区模块（类型号 == 0）。
pub fn is_data_byte(b : Int) -> Bool {
  ((b >> 1) & 7) == 0
}

///|
/// 读类型号（bit1-3）。
pub fn module_type_of(b : Int) -> Int {
  (b >> 1) & 7
}

///|
/// 读明暗位（bit0）：返回 0=LIGHT / 1=DARK。
pub fn value_of(b : Int) -> Int {
  b & 1
}

///|
/// 构造单格值：`明暗(0/1) | 类型号 << 1`。
pub fn pack(value : Int, t : Int) -> Int {
  (value & 1) | (t << 1)
}

///|
/// 置/清明暗位（保留类型号）。
pub fn set_value(b : Int, value : Int) -> Int {
  (b & 0xFE) | (value & 1)
}

///|
/// 翻转明暗位（掩码核心操作：调用方需保证只对 Data 类模块调用）。
pub fn toggle_value(b : Int) -> Int {
  b ^ 1
}
