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

///|
/// M1 最小编排入口：固定 mask 下把 select_capacity→encode→structure→放置→Format→固定 mask 串成完整 QRCode。
/// 对应参考 fast_qr v0.14.0 `src/placement.rs::create_matrix`（S4 方案 §1「M1 编排」）。
/// - input 为输入字节；mode/ecl/version 为 `None` 时走 select_capacity 自动择优
///   （mode 按 best_encoding 回退、ecl 默认 Q、version 取最小适配）；
/// - mask **必填**：S4/M1 只按指定固定 mask 应用一次掩码、写真实 Format（8 轮择优评分留 S5）。
/// - 返回完整 `QRCode`（data 已含掩码后明暗、元数据 version/ecl/mask/mode 为解析值）。

///|
/// 将 packed 字节矩阵逐格包装回公共 Module，装入固定容量 QRCode（build_fixed/build 共用尾步）。
/// `mask_idx` 为最终 mask 序号；`mode_idx/ecl_idx/version_idx` 为解析值写元数据。
fn wrap_packed(
  packed : Array[Int],
  version_idx : Int,
  ecl_idx : Int,
  mask_idx : Int,
  mode_idx : Int,
) -> QRCode {
  let size = version_idx * 4 + 21
  let data = Array::make(QR_MAX_MODULES, Module::data(false))
  let mut i = 0
  while i < size * size {
    let b = packed[i]
    let value = (b & 1) == 1
    let t = ModuleType::from_int((b >> 1) & 7)
    data[i] = Module::new(value, t)
    i += 1
  }
  QRCode::{
    data,
    size,
    version: Some(Version::from_int(version_idx)),
    ecl: Some(ECL::from_int(ecl_idx)),
    mask: Some(Mask::from_int(mask_idx)),
    mode: Some(Mode::from_int(mode_idx)),
  }
}

///|
pub fn QRCode::build_fixed(
  input : Array[Byte],
  mode : Mode?,
  ecl : ECL?,
  version : Version?,
  mask : Mask,
) -> Result[QRCode, QRCodeError] {
  // 1) 容量/版本选择：返回 (mode_idx, ecl_idx, version_idx) 序号
  let (mode_idx, ecl_idx, version_idx) = match
    QRCode::select_capacity(input, mode, ecl, version) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  // 2) 编码到位流缓冲（data 前 data_codewords 字节为数据码字）
  let compact = @data_encoding.encode(input, ecl_idx, mode_idx, version_idx)
  // 3) 分块纠错 + 交织：输出 5430 缓冲，前 max_bytes(version) 字节为交织码字
  let interleaved = @reedsolomon.structure(compact.data(), ecl_idx, version_idx)
  // 4) 放置 + 覆写真实 Format + 一次固定 mask，得到 packed 字节矩阵
  let packed = @matrix.create_fixed_qr(
    interleaved,
    version_idx,
    ecl_idx,
    mask.to_int(),
  )
  // 5) 逐格包装回公共 Module
  Ok(wrap_packed(packed, version_idx, ecl_idx, mask.to_int(), mode_idx))
}

///|
/// S5 自动择优入口（mask 可 None）：`None` 走 8 轮 clone+score 择优主循环（自动 mask），
/// `Some(m)` 走固定 mask 快速路径：直接应用一次用户 mask、跳过冗余 8 轮评分（输出等价参考
/// fast_qr 的强制掩码旁路——参考虽照跑评分但用用户 mask 覆盖，本实现直接跳过为等价优化）。
/// 编排队列：select_capacity → encode → structure → （mask None→ create_auto_qr 择优 / Some→create_fixed_qr）。
/// 返回完整 `QRCode`（data 含最终明暗、mask 元数据为实际应用的那个掩码）。
pub fn QRCode::build(
  input : Array[Byte],
  mode : Mode?,
  ecl : ECL?,
  version : Version?,
  mask : Mask?,
) -> Result[QRCode, QRCodeError] {
  let (mode_idx, ecl_idx, version_idx) = match
    QRCode::select_capacity(input, mode, ecl, version) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let compact = @data_encoding.encode(input, ecl_idx, mode_idx, version_idx)
  let interleaved = @reedsolomon.structure(compact.data(), ecl_idx, version_idx)
  match mask {
    // 指定固定掩码：走 create_fixed_qr 快速路径——直接应用用户 mask、跳过冗余 8 轮评分
    // （输出等价参考 place_on_matrix 强制掩码旁路，跳过为合理优化，未改行为）
    Some(m) => {
      let packed = @matrix.create_fixed_qr(
        interleaved,
        version_idx,
        ecl_idx,
        m.to_int(),
      )
      Ok(wrap_packed(packed, version_idx, ecl_idx, m.to_int(), mode_idx))
    }
    None => {
      let (packed, best_mask) = @matrix.create_auto_qr(
        interleaved, version_idx, ecl_idx,
      )
      Ok(wrap_packed(packed, version_idx, ecl_idx, best_mask, mode_idx))
    }
  }
}
