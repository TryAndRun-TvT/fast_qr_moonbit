///|
/// s7_svg_test.mbt —— S7 SVG 输出全串字节对齐（黑盒 _test.mbt）
/// 基准：fast_qr v0.14.0 `convert/svg.rs` 对受控矩阵与真实 QR 产出的 `to_str()` 参考**全串**（Rust 生成，禁止手抄）。
/// 结构：SvgBuilder::to_str = `<svg viewBox…xmlns…><rect…/>` + N 个 `<path d="…"/>`（多 shape→多 path）
///       + `</svg>`，整串一行无分隔。坐标传给形状片段前已加 margin（对齐参考 command(y+margin,x+margin)）。
/// 覆盖：mini7 受控矩阵 × 6 形状各一全串（锁各自 path 片段/圆角描边特判/跳过亮格）+ 默认退化 Square
///       + 多 shape（Square+RoundedSquare → 双 <path>）+ 真实 V01 QR 的默认方形全串（build→svg 端到端）。

///|
/// mini7 上逐 shape 全串断言（含默认退化 Square）。
fn assert_mini_shape(want_svg : String, shapev : @lib.Shape?) -> Unit raise {
  let m = mini7()
  let got = match shapev {
    Some(s) => @lib.SvgBuilder::default().shape(s).to_str(m)
    None => @lib.SvgBuilder::default().to_str(m)
  }
  if got != want_svg {
    fail("mini svg shape mismatch")
  }
}

///|
/// mini7 默认（shapes 空）→ 退化 Square，全串对齐。
test "s7_svg_mini_default_square" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4,4h1v1h-1M5,4h1v1h-1M10,4h1v1h-1M4,5h1v1h-1M7,5h1v1h-1M9,5h1v1h-1M6,6h1v1h-1M8,6h1v1h-1M7,7h1v1h-1M10,7h1v1h-1M4,8h1v1h-1M6,8h1v1h-1M8,8h1v1h-1M10,8h1v1h-1M5,9h1v1h-1M9,9h1v1h-1M4,10h1v1h-1M7,10h1v1h-1M10,10h1v1h-1\" fill=\"#000000\"/></svg>",
    None,
  )
}

///|
/// mini7 显式 Square 全串对齐。
test "s7_svg_mini_square" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4,4h1v1h-1M5,4h1v1h-1M10,4h1v1h-1M4,5h1v1h-1M7,5h1v1h-1M9,5h1v1h-1M6,6h1v1h-1M8,6h1v1h-1M7,7h1v1h-1M10,7h1v1h-1M4,8h1v1h-1M6,8h1v1h-1M8,8h1v1h-1M10,8h1v1h-1M5,9h1v1h-1M9,9h1v1h-1M4,10h1v1h-1M7,10h1v1h-1M10,10h1v1h-1\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::Square),
  )
}

///|
/// mini7 circle 全串对齐（锁 圆形 path 片段（首坐标 x+1 整数））。
test "s7_svg_mini_circle" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M5,4.5a.5,.5 0 1,1 0,-.1M6,4.5a.5,.5 0 1,1 0,-.1M11,4.5a.5,.5 0 1,1 0,-.1M5,5.5a.5,.5 0 1,1 0,-.1M8,5.5a.5,.5 0 1,1 0,-.1M10,5.5a.5,.5 0 1,1 0,-.1M7,6.5a.5,.5 0 1,1 0,-.1M9,6.5a.5,.5 0 1,1 0,-.1M8,7.5a.5,.5 0 1,1 0,-.1M11,7.5a.5,.5 0 1,1 0,-.1M5,8.5a.5,.5 0 1,1 0,-.1M7,8.5a.5,.5 0 1,1 0,-.1M9,8.5a.5,.5 0 1,1 0,-.1M11,8.5a.5,.5 0 1,1 0,-.1M6,9.5a.5,.5 0 1,1 0,-.1M10,9.5a.5,.5 0 1,1 0,-.1M5,10.5a.5,.5 0 1,1 0,-.1M8,10.5a.5,.5 0 1,1 0,-.1M11,10.5a.5,.5 0 1,1 0,-.1\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::Circle),
  )
}

///|
/// mini7 roundedsquare 全串对齐（锁 圆角方块 + 描边特判）。
test "s7_svg_mini_roundedsquare" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4.2,4.2 4.8,4.2 4.8,4.8 4.2,4.8zM5.2,4.2 5.8,4.2 5.8,4.8 5.2,4.8zM10.2,4.2 10.8,4.2 10.8,4.8 10.2,4.8zM4.2,5.2 4.8,5.2 4.8,5.8 4.2,5.8zM7.2,5.2 7.8,5.2 7.8,5.8 7.2,5.8zM9.2,5.2 9.8,5.2 9.8,5.8 9.2,5.8zM6.2,6.2 6.8,6.2 6.8,6.8 6.2,6.8zM8.2,6.2 8.8,6.2 8.8,6.8 8.2,6.8zM7.2,7.2 7.8,7.2 7.8,7.8 7.2,7.8zM10.2,7.2 10.8,7.2 10.8,7.8 10.2,7.8zM4.2,8.2 4.8,8.2 4.8,8.8 4.2,8.8zM6.2,8.2 6.8,8.2 6.8,8.8 6.2,8.8zM8.2,8.2 8.8,8.2 8.8,8.8 8.2,8.8zM10.2,8.2 10.8,8.2 10.8,8.8 10.2,8.8zM5.2,9.2 5.8,9.2 5.8,9.8 5.2,9.8zM9.2,9.2 9.8,9.2 9.8,9.8 9.2,9.8zM4.2,10.2 4.8,10.2 4.8,10.8 4.2,10.8zM7.2,10.2 7.8,10.2 7.8,10.8 7.2,10.8zM10.2,10.2 10.8,10.2 10.8,10.8 10.2,10.8z\" stroke-width=\".3\" stroke-linejoin=\"round\" stroke=\"#000000\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::RoundedSquare),
  )
}

///|
/// mini7 vertical 全串对齐（锁 竖向 path）。
test "s7_svg_mini_vertical" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4.1,4h.8v1h-.8M5.1,4h.8v1h-.8M10.1,4h.8v1h-.8M4.1,5h.8v1h-.8M7.1,5h.8v1h-.8M9.1,5h.8v1h-.8M6.1,6h.8v1h-.8M8.1,6h.8v1h-.8M7.1,7h.8v1h-.8M10.1,7h.8v1h-.8M4.1,8h.8v1h-.8M6.1,8h.8v1h-.8M8.1,8h.8v1h-.8M10.1,8h.8v1h-.8M5.1,9h.8v1h-.8M9.1,9h.8v1h-.8M4.1,10h.8v1h-.8M7.1,10h.8v1h-.8M10.1,10h.8v1h-.8\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::Vertical),
  )
}

///|
/// mini7 horizontal 全串对齐（锁 横向 path）。
test "s7_svg_mini_horizontal" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4,4.1h1v.8h-1M5,4.1h1v.8h-1M10,4.1h1v.8h-1M4,5.1h1v.8h-1M7,5.1h1v.8h-1M9,5.1h1v.8h-1M6,6.1h1v.8h-1M8,6.1h1v.8h-1M7,7.1h1v.8h-1M10,7.1h1v.8h-1M4,8.1h1v.8h-1M6,8.1h1v.8h-1M8,8.1h1v.8h-1M10,8.1h1v.8h-1M5,9.1h1v.8h-1M9,9.1h1v.8h-1M4,10.1h1v.8h-1M7,10.1h1v.8h-1M10,10.1h1v.8h-1\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::Horizontal),
  )
}

///|
/// mini7 diamond 全串对齐（锁 菱形 path）。
test "s7_svg_mini_diamond" {
  assert_mini_shape(
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4.5,4l.5,.5l-.5,.5l-.5,-.5zM5.5,4l.5,.5l-.5,.5l-.5,-.5zM10.5,4l.5,.5l-.5,.5l-.5,-.5zM4.5,5l.5,.5l-.5,.5l-.5,-.5zM7.5,5l.5,.5l-.5,.5l-.5,-.5zM9.5,5l.5,.5l-.5,.5l-.5,-.5zM6.5,6l.5,.5l-.5,.5l-.5,-.5zM8.5,6l.5,.5l-.5,.5l-.5,-.5zM7.5,7l.5,.5l-.5,.5l-.5,-.5zM10.5,7l.5,.5l-.5,.5l-.5,-.5zM4.5,8l.5,.5l-.5,.5l-.5,-.5zM6.5,8l.5,.5l-.5,.5l-.5,-.5zM8.5,8l.5,.5l-.5,.5l-.5,-.5zM10.5,8l.5,.5l-.5,.5l-.5,-.5zM5.5,9l.5,.5l-.5,.5l-.5,-.5zM9.5,9l.5,.5l-.5,.5l-.5,-.5zM4.5,10l.5,.5l-.5,.5l-.5,-.5zM7.5,10l.5,.5l-.5,.5l-.5,-.5zM10.5,10l.5,.5l-.5,.5l-.5,-.5z\" fill=\"#000000\"/></svg>",
    Some(@lib.Shape::Diamond),
  )
}

///|
/// mini7 多 shape（Square+RoundedSquare）→ 双 <path> 全串对齐。
test "s7_svg_mini_multi" {
  let m = mini7()
  let got = @lib.SvgBuilder::default()
    .shape(@lib.Shape::Square)
    .shape(@lib.Shape::RoundedSquare)
    .to_str(m)
  if got !=
    "<svg viewBox=\"0 0 15 15\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"15px\" height=\"15px\" fill=\"#ffffff\"/><path d=\"M4,4h1v1h-1M5,4h1v1h-1M10,4h1v1h-1M4,5h1v1h-1M7,5h1v1h-1M9,5h1v1h-1M6,6h1v1h-1M8,6h1v1h-1M7,7h1v1h-1M10,7h1v1h-1M4,8h1v1h-1M6,8h1v1h-1M8,8h1v1h-1M10,8h1v1h-1M5,9h1v1h-1M9,9h1v1h-1M4,10h1v1h-1M7,10h1v1h-1M10,10h1v1h-1\" fill=\"#000000\"/><path d=\"M4.2,4.2 4.8,4.2 4.8,4.8 4.2,4.8zM5.2,4.2 5.8,4.2 5.8,4.8 5.2,4.8zM10.2,4.2 10.8,4.2 10.8,4.8 10.2,4.8zM4.2,5.2 4.8,5.2 4.8,5.8 4.2,5.8zM7.2,5.2 7.8,5.2 7.8,5.8 7.2,5.8zM9.2,5.2 9.8,5.2 9.8,5.8 9.2,5.8zM6.2,6.2 6.8,6.2 6.8,6.8 6.2,6.8zM8.2,6.2 8.8,6.2 8.8,6.8 8.2,6.8zM7.2,7.2 7.8,7.2 7.8,7.8 7.2,7.8zM10.2,7.2 10.8,7.2 10.8,7.8 10.2,7.8zM4.2,8.2 4.8,8.2 4.8,8.8 4.2,8.8zM6.2,8.2 6.8,8.2 6.8,8.8 6.2,8.8zM8.2,8.2 8.8,8.2 8.8,8.8 8.2,8.8zM10.2,8.2 10.8,8.2 10.8,8.8 10.2,8.8zM5.2,9.2 5.8,9.2 5.8,9.8 5.2,9.8zM9.2,9.2 9.8,9.2 9.8,9.8 9.2,9.8zM4.2,10.2 4.8,10.2 4.8,10.8 4.2,10.8zM7.2,10.2 7.8,10.2 7.8,10.8 7.2,10.8zM10.2,10.2 10.8,10.2 10.8,10.8 10.2,10.8z\" stroke-width=\".3\" stroke-linejoin=\"round\" stroke=\"#000000\" fill=\"#000000\"/></svg>" {
    fail("mini multi-shape mismatch")
  }
}

///|
/// 真实 V01 QR 的默认方形 SVG 全串对齐（build → SvgBuilder 端到端）。
test "s7_svg_real_v01_square" {
  let qr = match
    @lib.QRCode::build(
      hi_input(),
      Some(@lib.Mode::Byte),
      Some(@lib.ECL::L),
      Some(@lib.Version::V01),
      Some(@lib.Mask::Checkerboard),
    ) {
    Ok(q) => q
    Err(_) => abort("svg real build")
  }
  let got = @lib.SvgBuilder::default().to_str(qr)
  if got !=
    "<svg viewBox=\"0 0 29 29\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"29px\" height=\"29px\" fill=\"#ffffff\"/><path d=\"M4,4h1v1h-1M5,4h1v1h-1M6,4h1v1h-1M7,4h1v1h-1M8,4h1v1h-1M9,4h1v1h-1M10,4h1v1h-1M14,4h1v1h-1M16,4h1v1h-1M18,4h1v1h-1M19,4h1v1h-1M20,4h1v1h-1M21,4h1v1h-1M22,4h1v1h-1M23,4h1v1h-1M24,4h1v1h-1M4,5h1v1h-1M10,5h1v1h-1M16,5h1v1h-1M18,5h1v1h-1M24,5h1v1h-1M4,6h1v1h-1M6,6h1v1h-1M7,6h1v1h-1M8,6h1v1h-1M10,6h1v1h-1M12,6h1v1h-1M14,6h1v1h-1M18,6h1v1h-1M20,6h1v1h-1M21,6h1v1h-1M22,6h1v1h-1M24,6h1v1h-1M4,7h1v1h-1M6,7h1v1h-1M7,7h1v1h-1M8,7h1v1h-1M10,7h1v1h-1M16,7h1v1h-1M18,7h1v1h-1M20,7h1v1h-1M21,7h1v1h-1M22,7h1v1h-1M24,7h1v1h-1M4,8h1v1h-1M6,8h1v1h-1M7,8h1v1h-1M8,8h1v1h-1M10,8h1v1h-1M13,8h1v1h-1M15,8h1v1h-1M16,8h1v1h-1M18,8h1v1h-1M20,8h1v1h-1M21,8h1v1h-1M22,8h1v1h-1M24,8h1v1h-1M4,9h1v1h-1M10,9h1v1h-1M13,9h1v1h-1M14,9h1v1h-1M15,9h1v1h-1M18,9h1v1h-1M24,9h1v1h-1M4,10h1v1h-1M5,10h1v1h-1M6,10h1v1h-1M7,10h1v1h-1M8,10h1v1h-1M9,10h1v1h-1M10,10h1v1h-1M12,10h1v1h-1M14,10h1v1h-1M16,10h1v1h-1M18,10h1v1h-1M19,10h1v1h-1M20,10h1v1h-1M21,10h1v1h-1M22,10h1v1h-1M23,10h1v1h-1M24,10h1v1h-1M12,11h1v1h-1M14,11h1v1h-1M4,12h1v1h-1M5,12h1v1h-1M6,12h1v1h-1M8,12h1v1h-1M9,12h1v1h-1M10,12h1v1h-1M11,12h1v1h-1M12,12h1v1h-1M14,12h1v1h-1M16,12h1v1h-1M17,12h1v1h-1M18,12h1v1h-1M22,12h1v1h-1M5,13h1v1h-1M6,13h1v1h-1M11,13h1v1h-1M14,13h1v1h-1M15,13h1v1h-1M17,13h1v1h-1M19,13h1v1h-1M21,13h1v1h-1M22,13h1v1h-1M23,13h1v1h-1M24,13h1v1h-1M5,14h1v1h-1M6,14h1v1h-1M7,14h1v1h-1M8,14h1v1h-1M9,14h1v1h-1M10,14h1v1h-1M11,14h1v1h-1M12,14h1v1h-1M13,14h1v1h-1M15,14h1v1h-1M17,14h1v1h-1M18,14h1v1h-1M19,14h1v1h-1M21,14h1v1h-1M22,14h1v1h-1M23,14h1v1h-1M24,14h1v1h-1M6,15h1v1h-1M7,15h1v1h-1M15,15h1v1h-1M16,15h1v1h-1M17,15h1v1h-1M19,15h1v1h-1M20,15h1v1h-1M21,15h1v1h-1M23,15h1v1h-1M4,16h1v1h-1M7,16h1v1h-1M9,16h1v1h-1M10,16h1v1h-1M12,16h1v1h-1M14,16h1v1h-1M15,16h1v1h-1M17,16h1v1h-1M18,16h1v1h-1M19,16h1v1h-1M22,16h1v1h-1M12,17h1v1h-1M14,17h1v1h-1M18,17h1v1h-1M22,17h1v1h-1M23,17h1v1h-1M24,17h1v1h-1M4,18h1v1h-1M5,18h1v1h-1M6,18h1v1h-1M7,18h1v1h-1M8,18h1v1h-1M9,18h1v1h-1M10,18h1v1h-1M12,18h1v1h-1M13,18h1v1h-1M14,18h1v1h-1M16,18h1v1h-1M20,18h1v1h-1M23,18h1v1h-1M24,18h1v1h-1M4,19h1v1h-1M10,19h1v1h-1M12,19h1v1h-1M13,19h1v1h-1M14,19h1v1h-1M18,19h1v1h-1M22,19h1v1h-1M23,19h1v1h-1M24,19h1v1h-1M4,20h1v1h-1M6,20h1v1h-1M7,20h1v1h-1M8,20h1v1h-1M10,20h1v1h-1M12,20h1v1h-1M13,20h1v1h-1M16,20h1v1h-1M18,20h1v1h-1M20,20h1v1h-1M22,20h1v1h-1M24,20h1v1h-1M4,21h1v1h-1M6,21h1v1h-1M7,21h1v1h-1M8,21h1v1h-1M10,21h1v1h-1M13,21h1v1h-1M15,21h1v1h-1M17,21h1v1h-1M19,21h1v1h-1M21,21h1v1h-1M23,21h1v1h-1M4,22h1v1h-1M6,22h1v1h-1M7,22h1v1h-1M8,22h1v1h-1M10,22h1v1h-1M12,22h1v1h-1M13,22h1v1h-1M14,22h1v1h-1M15,22h1v1h-1M17,22h1v1h-1M18,22h1v1h-1M19,22h1v1h-1M21,22h1v1h-1M22,22h1v1h-1M24,22h1v1h-1M4,23h1v1h-1M10,23h1v1h-1M12,23h1v1h-1M13,23h1v1h-1M15,23h1v1h-1M16,23h1v1h-1M17,23h1v1h-1M19,23h1v1h-1M20,23h1v1h-1M21,23h1v1h-1M23,23h1v1h-1M4,24h1v1h-1M5,24h1v1h-1M6,24h1v1h-1M7,24h1v1h-1M8,24h1v1h-1M9,24h1v1h-1M10,24h1v1h-1M12,24h1v1h-1M15,24h1v1h-1M17,24h1v1h-1M18,24h1v1h-1M19,24h1v1h-1M21,24h1v1h-1M22,24h1v1h-1M23,24h1v1h-1M24,24h1v1h-1\" fill=\"#000000\"/></svg>" {
    fail("real v01 svg square mismatch")
  }
}

///|
/// 默认退化护栏：空 shapes 的 to_str 与显式 shape(Square) 一致。
test "s7_svg_default_guard" {
  let m = mini7()
  let a = @lib.SvgBuilder::default().to_str(m)
  let b = @lib.SvgBuilder::default().shape(@lib.Shape::Square).to_str(m)
  if a != b {
    fail("default != explicit square")
  }
}

///|
/// 自定义参数护栏：margin/背景/模块色/形状 setter 生效（改边距应改变 viewBox 尺寸与坐标起点）。
test "s7_svg_custom_params" {
  let m = mini7()
  let got = @lib.SvgBuilder::default()
    .margin(2)
    .background_color("#112233")
    .module_color("#445566")
    .shape(@lib.Shape::Diamond)
    .to_str(m)
  // 边距 2 → W=2*2+7=11；首暗格(0,0)+margin2 → 坐标从 2 起；色 #445566 / 背景 #112233
  let header = "<svg viewBox=\"0 0 11 11\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"11px\" height=\"11px\" fill=\"#112233\"/>"
  if got.has_prefix(header) == false {
    fail("custom params header wrong: " + got[:120].to_owned())
  }
  if got.contains("#445566") == false ||
    got.contains("M2.5,2l.5,.5l-.5,.5l-.5,-.5z") == false {
    fail("custom color/shape not applied")
  }
}
