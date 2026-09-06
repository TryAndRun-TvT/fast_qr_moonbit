///|
/// qr.mbt —— QRCode 结果、构造与错误
/// 对应参考：fast_qr v0.14.0 `src/qr.rs`（roadmap 批次 B8 骨架）
/// 职责：`QRCode`（固定矩阵容器 + size/version/ecl/mask/mode 元数据）。
/// 关键语义：矩阵为一维按行存储的固定容量容器（177×177=31329）；大小 = 版本*4+17。
/// 架构决策（D1）：`QRCode.data` 使用公共 `Module`（lib 层呈现类型），不泄漏 internal 类型。
/// 范围说明：两类错误（`EncodedData`/`SpecifiedVersion`）随批次 B8（encode 容量判定）
///       落地时定义并构造——MoonBit `unused_constructor`（`--deny-warn`）要求枚举变体
///       在可达代码中被构造，S1 尚无产生错误的路径，故推迟其定义到 S3/B8。

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
  let data = Array::make(QR_MAX_MODULES, Module::data(module_light()))
  QRCode::{ data, size, version: None, ecl: None, mask: None, mode: None, }
}

///|
/// 以指定版本构造空 `QRCode`（矩阵边长由版本推导，元数据 `version=Some(v)`）。
pub fn QRCode::for_version(v : Version) -> QRCode {
  QRCode::default(v.width()).with_version(v)
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

///|
/// QRCode 容量/版本选择（S3/B8）：解析输入数据应使用的 mode/ecl/version 三元组（序号）。
/// - `mode=None` → `best_encoding` 自动回退（Numeric→Alnum→Byte）；`Some(m)` 用指定模式。
/// - `ecl=None` → 默认 Quartile（Q）；`Some(e)` 用指定纠错。
/// - `v=None` → 取 `version_for` 返回的最小适配版本；`Some(uv)` 且 `uv >= 最小` 用 uv。
/// - 数据过大（V40 装不下）→ `Err(EncodedData)`；指定版本 < 最小适配 → `Err(SpecifiedVersion)`。
/// 供 S4 create_matrix 与后续 QRBuilder（S6）复用：本阶段只做容量选择，矩阵放置随 S4 接入
/// 此路径产出的版本号构建完整 QRCode（见 S3 方案 §3.5/§6）。
pub fn QRCode::select_capacity(
  input : Array[Byte],
  mode : Mode?,
  ecl : ECL?,
  v : Version?,
) -> Result[(Int, Int, Int), QRCodeError] {
  // mode：None → best_encoding 自动回退
  let mode_idx = match mode {
    Some(m) => m.to_int()
    None => @data_encoding.best_encoding(input)
  }
  // ecl：None → 默认 Quartile(Q, idx 2)
  let ecl_idx = match ecl {
    Some(e) => e.to_int()
    None => ECL::Q.to_int()
  }
  // 最小适配版本：-1 → V40 也装不下（数据过大）
  let min_v = @constants.version_for(mode_idx, ecl_idx, input.length())
  if min_v < 0 {
    return Err(EncodedData)
  }
  // 指定版本约束：uv 序号 >= 最小适配才合法，否则报 SpecifiedVersion
  let version_idx = match v {
    Some(uv) =>
      if uv.to_int() >= min_v {
        uv.to_int()
      } else {
        return Err(SpecifiedVersion)
      }
    None => min_v
  }
  Ok((mode_idx, ecl_idx, version_idx))
}
