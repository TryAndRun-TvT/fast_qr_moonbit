///|
/// qr_build.mbt —— QRCode 编排与构造（容量/版本选择 + 矩阵装配主路径）
/// 对应参考：fast_qr v0.14.0 `src/qr.rs` / `src/placement.rs::create_matrix`（roadmap B8/B10）
/// 职责：把 lib/internal 各子包管线（data_encoding→reedsolomon→matrix）编排为两条公共入口——
///       `QRCode::select_capacity`（容量/版本三元组解析）、`QRCode::build_fixed`（固定掩码）、
///       `QRCode::build`（mask=None 自动择优 / Some 固定快速路径）；私有 `wrap_packed` 为共用尾步。
/// 架构决策（D11，S8）：从 qr.mbt 拆出「编排/构造」子关注到本文件（同包搬移、无逻辑改动），见
///       docs/S8-内部结构归位与分层.md §3.2。QRCode 结果容器与错误在 qr.mbt，QRBuilder 在 qr_builder.mbt。
/// 依赖方向：本文件 import `@data_encoding`/`@reedsolomon`/`@matrix`/`@constants` 等 internal 子包；
///       MoonBit 同包（lib/）内非 pub 符号跨文件亦可见，故 `wrap_packed` 无需 pub 即可被本文件使用。

///|
/// QRCode 容量/版本选择（S3/B8）：解析输入数据应使用的 mode/ecl/version 三元组（序号）。
/// - `mode=None` → `best_encoding` 自动回退（Numeric→Alnum→Byte）；`Some(m)` 用指定模式。
/// - `ecl=None` → 默认 Quartile（Q）；`Some(e)` 用指定纠错。
/// - `v=None` → 取 `version_for` 返回的最小适配版本；`Some(uv)` 且 `uv >= 最小` 用 uv。
/// - 数据过大（V40 装不下）→ `Err(EncodedData)`；指定版本 < 最小适配 → `Err(SpecifiedVersion)`。
/// 容量选择是 `build`/`build_fixed` 的公共前置步：二者以本函数产出的版本号接入矩阵装配
/// （S4 `create_matrix` → 放置 → Format 覆写），QRBuilder 亦经 `QRCode::build` 复用本路径。
///
/// **两类容量校验（对齐参考 fast_qr `Version::get` + `QRCode::new` 的两段式判定）**：
/// ① 无显式版本（`v=None`）：按**声明模式**求最小适配版本，直接查 `version_for(mode_idx, …)`。
/// 这条链必须与「该模式实际会被交给哪个编码器」一致——否则较长输入会被静默按 Numeric
/// 预算通过、随后用 Alnum/Byte 编码器写入超出数据区的位流（见下方 T3-d 回归 note）。
/// ② 显式版本（`Some(uv)`）：参考 `Version::get` 的 `mode` 分支覆盖**全部三种模式**
/// （含 Byte，V01-L=17 / V01-H=7），故「Byte 18 字节 + 强制 V01-H」在参考侧即
/// `Err(SpecifiedVersion)`；同版本下 Byte 的容量严格小于 Numeric，只有按声明模式判定
/// 才能复现该错误面。此外显式版本下还需用 uv **自身的 CCI 档位**复算
/// （`fits_at_version`，覆盖 V20→V27 这类跨档边界）。
///
/// 回归 note（T3-d 探针发现，v5 修复）：旧实现把 mode 序号算好后**从未传给容量判定**
/// （`version_for` 恒按 Numeric 预算），导致
///   - `Some(Alphanumeric)` / `Some(Byte)` + `v=None` 时按 Numeric 求最小版本；
///   - `Some(mode)` + `Some(uv)` 时丢弃模式、只查 Numeric 容量，`SpecifiedVersion` 基本失效。
/// 表现为「静默错数据」（下游解码器读回与输入不同），而非报错。
pub fn QRCode::select_capacity(
  input : Array[Byte],
  mode : Mode?,
  ecl : ECL?,
  v : Version?,
) -> Result[(Int, Int, Int), QRCodeError] {
  let len = input.length()
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
  match v {
    None => {
      // 按声明模式（或自动回退出的模式）求最小适配版本；-1 → V40 也装不下
      let min_v = @constants.version_for(mode_idx, ecl_idx, len)
      if min_v < 0 {
        return Err(EncodedData)
      }
      Ok((mode_idx, ecl_idx, min_v))
    }
    Some(uv) => {
      // ① 全局上界：该模式在全谱系内是否装得下（对照参考 `Version::get` → None → EncodedData）
      if @constants.version_for(mode_idx, ecl_idx, len) < 0 {
        return Err(EncodedData)
      }
      // ② 指定版本容纳性：按**声明模式** + **指定版本自身 CCI 档位**判定
      //    （对照参考 `QRCode::new` 中 `user_version >= version` 的比较；
      //     `fits_at_version` 用位流口径复算，比容量表更紧且覆盖 CCI 跨档）
      if !@constants.fits_at_version(mode_idx, ecl_idx, uv.to_int(), len) {
        return Err(SpecifiedVersion)
      }
      Ok((mode_idx, ecl_idx, uv.to_int()))
    }
  }
}

///|
/// 将 packed 字节矩阵逐格包装回公共 Module，装入固定容量 QRCode（build_fixed/build 共用尾步）。
/// `mask_idx` 为最终 mask 序号；`mode_idx/ecl_idx/version_idx` 为解析值写元数据。
fn wrap_packed(
  packed : FixedArray[Int],
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
/// `Some(m)` **委托 `QRCode::build_fixed`** 走固定 mask 快速路径（消双份实现，S11 §3.2）。
/// 编排队列：select_capacity → encode → structure → （mask None→ create_auto_qr 择优 / Some→build_fixed）。
/// 返回完整 `QRCode`（data 含最终明暗、mask 元数据为实际应用的那个掩码）。
pub fn QRCode::build(
  input : Array[Byte],
  mode : Mode?,
  ecl : ECL?,
  version : Version?,
  mask : Mask?,
) -> Result[QRCode, QRCodeError] {
  match mask {
    // 指定固定掩码：**委托 `build_fixed`**，避免「select_capacity → encode → structure →
    // create_fixed_qr → wrap_packed」两处逐字重复导致的静默漂移（S11 §3.2 / §10.6 P0-3）。
    // 快速路径语义不变：直接应用用户 mask、跳过冗余 8 轮评分（等价参考 place_on_matrix 的强制掩码旁路）。
    Some(m) => QRCode::build_fixed(input, mode, ecl, version, m)
    None => {
      let (mode_idx, ecl_idx, version_idx) = match
        QRCode::select_capacity(input, mode, ecl, version) {
        Ok(t) => t
        Err(e) => return Err(e)
      }
      let compact = @data_encoding.encode(input, ecl_idx, mode_idx, version_idx)
      let interleaved = @reedsolomon.structure(
        compact.data(),
        ecl_idx,
        version_idx,
      )
      let (packed, best_mask) = @matrix.create_auto_qr(
        interleaved, version_idx, ecl_idx,
      )
      Ok(wrap_packed(packed, version_idx, ecl_idx, best_mask, mode_idx))
    }
  }
}
