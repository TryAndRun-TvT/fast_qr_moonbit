///|
/// shape.mbt —— SVG 模块形状枚举（S7 输出层，B11）
/// 对应参考：fast_qr v0.14.0 `src/convert/mod.rs` `Shape`（WASM 目标 6 变体；本仓库纯库无 wasm-bindgen，
///       按 S7 方案 §3.2 只落 6 固定形状，不落函数字段变体 `Command`，`derive(Eq)` 无碍）。
/// 职责：声明 SVG 每个模块可用的 6 种形状；`shape_path` 按 (row+margin, col+margin) 产出该形状
///       的单个模块 SVG path 片段（逐字符对齐参考 `Shape::{square,circle,...}` 整串常量）。
/// 优化（S7 评估 §3.2）：6 形状 path 片段集中为「含坐标占位」常量定义在 svg.mbt `svg_shape_path`，
///       本文件只承载枚举与名字 ↔ 枚举 双向轻量映射，供 CLI/宿主按字符串名选形状复用。

///|
/// SVG 模块形状（6 固定变体）。
pub(all) enum Shape {
  /// 方块（参考 `M{x},{y}h1v1h-1`）
  Square
  /// 圆形（参考 `M{x+1},{y}.5a.5,.5 0 1,1 0,-.1`，首坐标 x+1 为整数、次坐标带 .5）
  Circle
  /// 圆角方块（参考 `M{x}.2,{y}.2 {x}.8,{y}.2 {x}.8,{y}.8 {x}.2,{y}.8z`，SVG 端额外加描边）
  RoundedSquare
  /// 竖向椭圆（参考 `M{x}.1,{y}h.8v1h-.8`）
  Vertical
  /// 横向椭圆（参考 `M{x},{y}.1h1v.8h-1`）
  Horizontal
  /// 菱形（参考 `M{x}.5,{y}l.5,.5l-.5,.5l-.5,-.5z`）
  Diamond
} derive(Eq, Debug)

///|
/// 形状 → 名字符串（对齐参考 `From<Shape> for &str`）。
pub fn Shape::name(self : Shape) -> String {
  match self {
    Square => "square"
    Circle => "circle"
    RoundedSquare => "rounded_square"
    Vertical => "vertical"
    Horizontal => "horizontal"
    Diamond => "diamond"
  }
}

///|
/// 名字符串 → 形状（大小写不敏感；未知名字回退 `Square`，对齐参考 `From<String> for Shape`）。
pub fn Shape::from_name(s : String) -> Shape {
  match shape_lower_ascii(s) {
    "square" => Square
    "circle" => Circle
    "rounded_square" => RoundedSquare
    "vertical" => Vertical
    "horizontal" => Horizontal
    "diamond" => Diamond
    _ => Square
  }
}

///|
/// ASCII 全小写（名字对照用；MoonBit String 无内置 to_lowercase，此处手工实现 ASCII 折叠）。
fn shape_lower_ascii(s : String) -> String {
  let b = StringBuilder()
  for ch in s {
    let v = ch.to_int()
    if v >= 65 && v <= 90 {
      b.write_char(Int::unsafe_to_char(v + 32))
    } else {
      b.write_char(ch)
    }
  }
  b.to_string()
}
