///|
/// module.mbt —— 公共 Module/ModuleType（单字节位打包）
/// 对应参考：fast_qr v0.14.0 `src/module.rs`（roadmap 批次 B5；架构决策 D1）
/// 职责：`Module` 为矩阵单像素，用 1 字节承载——bit0 存明暗（1=DARK/0=LIGHT），
///       bit1-3 存类型号（0..=7）；`ModuleType` 为 8 种功能归属。
/// 架构决策（D1）：`Module` 上移 lib 公共层作**对外呈现类型**，与 Rust crate 根导出对齐；
///       `internal/matrix` 掩码/放置等直接对原始字节做位运算（见其所在包），lib 侧
///       把字节结果包装为公共 `Module` 呈现。依赖方向保持 lib → internal，无环。

///|
/// 模块类型号（0..=7）。判别值按 `序号 << 1` 写入 bit1-3。
pub(all) enum ModuleType {
  /// 编码数据区
  Data
  /// 三个大定位方块
  FinderPattern
  /// 小定位方块（对齐图案）
  Alignment
  /// 连接定位图案的黑白线（时序图案）
  Timing
  /// 格式信息区
  Format
  /// 版本信息区（V7+）
  Version
  /// 固定暗模块
  DarkModule
  /// 分隔区（separator）
  Empty
} derive(Eq, Debug)

///|
/// 类型号 → 0..=7（供写入 bit1-3 前的位移）。
pub fn ModuleType::to_int(self : ModuleType) -> Int {
  match self {
    Data => 0
    FinderPattern => 1
    Alignment => 2
    Timing => 3
    Format => 4
    Version => 5
    DarkModule => 6
    Empty => 7
  }
}

///|
/// 由类型号还原类型；越界回退到 `Empty`。
pub fn ModuleType::from_int(i : Int) -> ModuleType {
  match i {
    0 => Data
    1 => FinderPattern
    2 => Alignment
    3 => Timing
    4 => Format
    5 => Version
    6 => DarkModule
    _ => Empty
  }
}

///|
/// QR 矩阵单像素：单字节承载明暗与类型。
pub(all) struct Module {
  byte : Byte
} derive(Eq, Debug)

///|
/// 读明暗值：1 = DARK（黑）、0 = LIGHT（白）。
pub fn Module::value(self : Module) -> Bool {
  (self.byte.to_int() & 1) == 1
}

///|
/// 读类型号（bit1-3），用于 Data 判定与类型识别。
pub fn Module::module_type(self : Module) -> ModuleType {
  ModuleType::from_int((self.byte.to_int() >> 1) & 7)
}

///|
/// 构造一个指定明暗与类型的模块。
pub fn Module::new(value : Bool, t : ModuleType) -> Module {
  let v = if value { 1 } else { 0 }
  let b = (v | (t.to_int() << 1)) & 0xFF
  Module::{ byte: b.to_byte(), }
}

///|
/// 便捷构造：明暗数据区模块。
pub fn Module::data(value : Bool) -> Module {
  Module::new(value, Data)
}

///|
/// 便捷构造：明暗定位方块模块。
pub fn Module::finder_pattern(value : Bool) -> Module {
  Module::new(value, FinderPattern)
}

///|
/// 便捷构造：明暗对齐图案模块。
pub fn Module::alignment(value : Bool) -> Module {
  Module::new(value, Alignment)
}

///|
/// 便捷构造：明暗时序图案模块。
pub fn Module::timing(value : Bool) -> Module {
  Module::new(value, Timing)
}

///|
/// 便捷构造：明暗格式信息模块。
pub fn Module::format(value : Bool) -> Module {
  Module::new(value, Format)
}

///|
/// 便捷构造：明暗版本信息模块。
pub fn Module::version(value : Bool) -> Module {
  Module::new(value, Version)
}

///|
/// 便捷构造：明暗固定暗模块。
pub fn Module::dark(value : Bool) -> Module {
  Module::new(value, DarkModule)
}

///|
/// 便捷构造：明暗分隔区模块。
pub fn Module::empty(value : Bool) -> Module {
  Module::new(value, Empty)
}

///|
/// 置/清明暗位（bit0）。
pub fn Module::set(self : Module, value : Bool) -> Module {
  let b = self.byte.to_int()
  let nb = if value { b | 1 } else { b & 0xFE }
  Module::{ byte: nb.to_byte(), }
}

///|
/// 翻转明暗位（掩码核心操作：只对 Data 类模块调用）。
pub fn Module::toggle(self : Module) -> Module {
  Module::{ byte: (self.byte.to_int() ^ 1).to_byte(), }
}

///|
/// 底层字节（供 internal/输出层直接按位读取）。
pub fn Module::byte(self : Module) -> Byte {
  self.byte
}

///|
/// 常量：暗模块值 = `true`。
pub fn module_dark() -> Bool {
  true
}

///|
/// 常量：亮模块值 = `false`。
pub fn module_light() -> Bool {
  false
}
