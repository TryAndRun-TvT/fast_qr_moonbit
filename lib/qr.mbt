///|
/// qr.mbt —— QRCode 结果容器与错误
/// 对应参考：fast_qr v0.14.0 `src/qr.rs`（roadmap 批次 B8 骨架）
/// 职责：`QRCode` 结果容器（固定矩阵 + size/version/ecl/mask/mode 元数据）与 `QRCodeError`。
///       版本/纠错/掩码/模式等**编排与构造**已随 S8 拆至 qr_build.mbt/qr_builder.mbt（同包内
///       非 pub 符号跨文件亦可见），终端输出便捷方法拆至 qr_output.mbt。
/// 关键语义：矩阵为一维按行存储的固定容量容器（177×177=31329）；大小 = 版本*4+17。
/// 架构决策（D1）：`QRCode.data` 使用公共 `Module`（lib 层呈现类型），不泄漏 internal 类型。
/// 架构决策（D11，S8）：公共层文件级职责归位——本文件仅保留「结果容器/错误/访问器」，不涉及
///       编排（build_fixed/build/select_capacity）与 QRBuilder，见
///       docs/S8-内部结构归位与分层.md §3.2。

///|
/// 最大矩阵边长（版本 40：40*4+17 = 177）。
pub const QR_MAX_WIDTH : Int = 177

///|
/// 最大模块数：177 × 177 = 31329。
pub const QR_MAX_MODULES : Int = 31329

///|
/// QR 码结果。`data` 为一维按行存储的模块矩阵（固定容量 `QR_MAX_MODULES`，
/// 实际有效范围为 `size*size`，超出部分不参与渲染）。
pub(all) struct QRCode {
  /// 模块矩阵（一维按行存储）
  data : Array[Module]
  /// 矩阵边长（= 版本号 * 4 + 17），版本号 1..=40
  size : Int
  /// 实际版本（`None` 表示按数据自动择优）
  version : Version?
  /// 实际纠错级别（`None` 表示默认 Quartile）
  ecl : ECL?
  /// 实际掩码（`None` 表示自动择优）
  mask : Mask?
  /// 实际编码模式（`None` 表示自动择优）
  mode : Mode?
}

///|
/// 构造一个边长 `size`、矩阵全为亮色数据模块、元数据全 `None` 的空 `QRCode`。
pub fn QRCode::default(size : Int) -> QRCode {
  let data = Array::make(QR_MAX_MODULES, Module::data(false))
  QRCode::{ data, size, version: None, ecl: None, mask: None, mode: None, }
}

///|
/// 以指定版本构造**空矩阵** `QRCode`：边长由版本推导（`v.width()`），
/// 矩阵全为亮色 Data 模块，仅 `version` 元数据被置为 `Some(v)`（ecl/mask/mode 仍 `None`）。
///
/// 这是宿主「从零自建/改写矩阵再输出」（如叠加自定义图案）的**语义清晰入口**：
/// 先 `QRCode::empty(v)` 拿一张干净画布，再用 `set(row, col, m)` 逐格写入，
/// 最后交给输出层（`to_str` / `SvgBuilder::to_str`）。若已有满矩阵需改单格，
/// 用 `build()` 得到结果后直接 `set(...)` 亦可（`QRCode` 本就由 `build()` 公开返回）。
///
/// 语义对齐参考 fast_qr `QRCode::default(size)`，但把「版本」作为显式入参、
/// 避免 `default(size)` 的「边长 + 元数据全 None」双重歧义（见 docs/S11 §3.1）。
pub fn QRCode::empty(v : Version) -> QRCode {
  QRCode::default(v.width()).with_version(v)
}

///|
/// 以指定版本构造空 `QRCode`（`QRCode::empty` 的历史别名，语义完全一致）。
pub fn QRCode::for_version(v : Version) -> QRCode {
  QRCode::empty(v)
}

///|
/// 覆写版本元数据（构造/读取时为清晰表达所用版本）。
fn QRCode::with_version(self : QRCode, v : Version) -> QRCode {
  QRCode::{
    data: self.data,
    size: self.size,
    version: Some(v),
    ecl: self.ecl,
    mask: self.mask,
    mode: self.mode,
  }
}

///|
/// 读取第 `row` 行第 `col` 列模块。
pub fn QRCode::get(self : QRCode, row : Int, col : Int) -> Module {
  self.data[row * self.size + col]
}

///|
/// 覆写第 `row` 行第 `col` 列模块（不可变式：返回新 QRCode）。
pub fn QRCode::set(self : QRCode, row : Int, col : Int, m : Module) -> QRCode {
  // 不可变式写入：先拷贝数组再改，避免返回的新 QRCode 与源共享同一底层数组
  // （Array 是引用类型，直接 `data = self.data` 会原地改源，破坏不可变语义）
  let data = self.data.copy()
  data[row * self.size + col] = m
  QRCode::{
    data,
    size: self.size,
    version: self.version,
    ecl: self.ecl,
    mask: self.mask,
    mode: self.mode,
  }
}

///|
/// 矩阵边长。
pub fn QRCode::size(self : QRCode) -> Int {
  self.size
}

///|
/// 版本访问器。
pub fn QRCode::version(self : QRCode) -> Version? {
  self.version
}

///|
/// 纠错级别访问器。
pub fn QRCode::ecl(self : QRCode) -> ECL? {
  self.ecl
}

///|
/// 掩码访问器。
pub fn QRCode::mask(self : QRCode) -> Mask? {
  self.mask
}

///|
/// 编码模式访问器。
pub fn QRCode::mode(self : QRCode) -> Mode? {
  self.mode
}

///|
/// 拷贝整个模块矩阵。
pub fn QRCode::data(self : QRCode) -> Array[Module] {
  self.data.copy()
}

///|
/// 元数据快照（供黑盒测试断言 version/ecl/mask/mode 默认值）。
pub fn QRCode::meta(self : QRCode) -> (Version?, ECL?, Mask?, Mode?) {
  (self.version, self.ecl, self.mask, self.mode)
}

///|
/// QRCode 构造错误。对应参考 fast_qr v0.14.0 `src/qr.rs` 的 `QRCodeError`。
/// - `EncodedData`：数据过大，超出 V40 在该 (模式, 纠错) 下的容量上限。
/// - `SpecifiedVersion`：调用方指定的版本小于容纳该数据所需的最小版本。
/// S1 因 `unused_constructor`（`--deny-warn`）推迟其定义到 S3/B8：本阶段容量选择路径
/// （`QRCode::select_capacity`）会在可达代码真实构造这两个变体。
pub(all) enum QRCodeError {
  /// 数据过大无法编码
  EncodedData
  /// 指定版本太小无法容纳数据
  SpecifiedVersion
} derive(Eq, Debug)
