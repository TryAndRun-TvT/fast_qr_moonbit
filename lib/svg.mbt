///|
/// svg.mbt —— SVG 输出（公共 `SvgBuilder`，S7 输出层 B11）
/// 对应参考：fast_qr v0.14.0 `src/convert/{mod,svg}.rs`（B11 子集）。
/// 架构决策（D9）：纯库无 Cargo feature 机制，SVG 作为 lib 公共面**常驻**（轻、纯字符串）。
/// 范围裁剪：不落 `shape_color`/`image`/`image_*`（wasm 宿主嵌图子集，S7 明确不做，见方案 §1.2）。
/// 语义逐字符对齐参考 `SvgBuilder`/`path`/`to_str`（含 viewBox 的 xmlns、单行无分隔、坐标已含 margin）。
/// 值语义：对齐 S6 `QRBuilder` 惯例，setter 返回新 `SvgBuilder`（参考为 &mut 链式）。

///|
/// 单个模块的 SVG path 片段。`y`/`x` 为**加过 margin 的坐标**（= row+margin / col+margin），
/// 逐字符对齐参考 `src/convert/mod.rs` `Shape::square/circle/...`。
/// rounded_square 的额外描边不在此处，由 `to_str` 的 path 收尾特判补充。
fn svg_shape_path(shape : Shape, y : Int, x : Int) -> String {
  match shape {
    Square => "M" + x.to_string() + "," + y.to_string() + "h1v1h-1"
    Circle =>
      "M" + (x + 1).to_string() + "," + y.to_string() + ".5a.5,.5 0 1,1 0,-.1"
    RoundedSquare =>
      "M" +
      x.to_string() +
      ".2," +
      y.to_string() +
      ".2 " +
      x.to_string() +
      ".8," +
      y.to_string() +
      ".2 " +
      x.to_string() +
      ".8," +
      y.to_string() +
      ".8 " +
      x.to_string() +
      ".2," +
      y.to_string() +
      ".8z"
    Vertical => "M" + x.to_string() + ".1," + y.to_string() + "h.8v1h-.8"
    Horizontal => "M" + x.to_string() + "," + y.to_string() + ".1h1v.8h-1"
    Diamond =>
      "M" + x.to_string() + ".5," + y.to_string() + "l.5,.5l-.5,.5l-.5,-.5z"
  }
}

///|
/// SVG 构造器（builder 模式，值语义）。持边距、背景/模块色、形状数组。
pub(all) struct SvgBuilder {
  /// 外边距（模块数），默认 4
  margin : Int
  /// 背景色（hex 字符串），默认 `#ffffff`
  background_color : String
  /// 模块填充色（hex 字符串），默认 `#000000`
  dot_color : String
  /// 形状数组；空数组在渲染时退化默认 `Square`
  shapes : Array[Shape]
}

///|
/// 默认 `SvgBuilder`：margin=4、背景 `#ffffff`、模块色 `#000000`、shapes 空（=Square）。
pub fn SvgBuilder::new() -> SvgBuilder {
  SvgBuilder::default()
}

///|
/// 默认值构造（对齐参考 `Default for SvgBuilder`）。
pub fn SvgBuilder::default() -> SvgBuilder {
  SvgBuilder::{
    margin: 4,
    background_color: "#ffffff",
    dot_color: "#000000",
    shapes: [],
  }
}

///|
/// 设置外边距（不可变式：返回新 `SvgBuilder`）。
pub fn SvgBuilder::margin(self : SvgBuilder, m : Int) -> SvgBuilder {
  SvgBuilder::{
    margin: m,
    background_color: self.background_color,
    dot_color: self.dot_color,
    shapes: self.shapes,
  }
}

///|
/// 设置模块填充色（hex 字符串，不可变式）。
pub fn SvgBuilder::module_color(
  self : SvgBuilder,
  color : String,
) -> SvgBuilder {
  SvgBuilder::{
    margin: self.margin,
    background_color: self.background_color,
    dot_color: color,
    shapes: self.shapes,
  }
}

///|
/// 设置背景色（hex 字符串，不可变式）。
pub fn SvgBuilder::background_color(
  self : SvgBuilder,
  color : String,
) -> SvgBuilder {
  SvgBuilder::{
    margin: self.margin,
    background_color: color,
    dot_color: self.dot_color,
    shapes: self.shapes,
  }
}

///|
/// 追加一个形状到形状数组（不可变式；可多次调用实现多 shape → 多 `<path>`）。
pub fn SvgBuilder::shape(self : SvgBuilder, s : Shape) -> SvgBuilder {
  let shapes = self.shapes.copy()
  shapes.push(s)
  SvgBuilder::{
    margin: self.margin,
    background_color: self.background_color,
    dot_color: self.dot_color,
    shapes,
  }
}

///|
/// 渲染一个 `<path d="…"/>`：遍历 `qr` 所有暗格，按该 shape 逐格拼片段。
/// `rounded_square` 额外收尾补描边属性（对齐参考 svg.rs `path` 特判）。
fn svg_render_path(
  shape : Shape,
  qr : QRCode,
  margin : Int,
  color : String,
) -> String {
  let n = qr.size()
  let sb = StringBuilder()
  sb.write_string("<path d=\"")
  let mut r = 0
  while r < n {
    let mut c = 0
    while c < n {
      if qr.get(r, c).value() {
        sb.write_string(svg_shape_path(shape, r + margin, c + margin))
      }
      c += 1
    }
    r += 1
  }
  if shape == RoundedSquare {
    sb.write_string(
      "\" stroke-width=\".3\" stroke-linejoin=\"round\" stroke=\"",
    )
    sb.write_string(color)
    sb.write_string("\" fill=\"")
    sb.write_string(color)
    sb.write_string("\"/>")
  } else {
    sb.write_string("\" fill=\"")
    sb.write_string(color)
    sb.write_string("\"/>")
  }
  sb.to_string()
}

///|
/// 渲染整串 SVG。`W = margin*2 + n`；结构：`<svg viewBox…xmlns…><rect…/>{paths}</svg>`，
/// 无任何空格/换行分隔（整串一行，对齐参考 `to_str`）。
/// 空 shapes 时退化默认 `[Square]`（对齐参考 `DEFAULT_COMMAND`）。
pub fn SvgBuilder::to_str(self : SvgBuilder, qr : QRCode) -> String {
  let n = qr.size()
  let w = self.margin * 2 + n
  let shapes = if self.shapes.is_empty() {
    let a : Array[Shape] = [Square]
    a
  } else {
    self.shapes
  }
  let sb = StringBuilder()
  sb.write_string("<svg viewBox=\"0 0 ")
  sb.write_string(w.to_string())
  sb.write_string(" ")
  sb.write_string(w.to_string())
  sb.write_string("\" xmlns=\"http://www.w3.org/2000/svg\">")
  sb.write_string("<rect width=\"")
  sb.write_string(w.to_string())
  sb.write_string("px\" height=\"")
  sb.write_string(w.to_string())
  sb.write_string("px\" fill=\"")
  sb.write_string(self.background_color)
  sb.write_string("\"/>")
  for s in shapes {
    sb.write_string(svg_render_path(s, qr, self.margin, self.dot_color))
  }
  sb.write_string("</svg>")
  sb.to_string()
}
