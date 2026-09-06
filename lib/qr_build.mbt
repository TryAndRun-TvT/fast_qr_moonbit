///|
/// qr_build.mbt —— QRCode 编排与构造（容量/版本选择 + 矩阵装配主路径）
/// 对应参考：fast_qr v0.14.0 `src/qr.rs` / `src/placement.rs::create_matrix`（roadmap B8/B10）
/// 职责：把 lib/internal 各子包管线（data_encoding→reedsolomon→matrix）编排为两条公共入口——
///       `QRCode::select_capacity`（容量/版本三元组解析）、`QRCode::build_fixed`（固定掩码）、
///       `QRCode::build`（mask=None 自动择优 / Some 固定快速路径）；私有 `wrap_packed` 为共用尾步。
/// 架构决策（D11，S8）：从 qr.mbt 拆出「编排/构造」子关注到本文件（同包搬移、无逻辑改动），见
///       docs/S8-内部结构归位与分层-实现方案.md §3.2。QRCode 结果容器与错误在 qr.mbt，QRBuilder 在 qr_builder.mbt。
/// 依赖方向：本文件 import `@data_encoding`/`@reedsolomon`/`@matrix`/`@constants` 等 internal 子包；
///       MoonBit 同包（lib/）内非 pub 符号跨文件亦可见，故 `wrap_packed` 无需 pub 即可被本文件使用。

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
