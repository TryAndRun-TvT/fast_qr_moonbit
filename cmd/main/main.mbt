///|
/// fast_qr_moonbit CLI 入口 —— S7 输出演示（落地 M1「CLI 调用库输出真实码」欠账）
/// 使用方式: moon run cmd/main
/// 行为：对示例内容构建一个 QRCode，先打印终端字符画（to_str），再打印其 SVG（SvgBuilder）。
///       演示两端后端的输出均可用；SVG 字符串较大，此处仅打印前若干字符示意。

///|
/// 由字符串输入构建 QRCode（自动择优 mode/ecl/version/mask）。
fn demo_qr(content : String) -> @lib.QRCode {
  match @lib.QRBuilder::from_string(content).build() {
    Ok(q) => q
    Err(_) => abort("demo content too large for V40")
  }
}

///|
fn main {
  println("fast_qr_moonbit - MoonBit QR Code Generator (S7 demo)")
  let qr = demo_qr("https://example.com/")
  println("--- QRCode.to_str() 终端字符画 ---")
  println(qr.to_str())
  println(
    "--- SvgBuilder 链式定制（module_color/background_color/shape）SVG（前 200 字符示意） ---",
  )
  // 与 README「快速开始」示例口径一致：默认 + 自定义模块色/背景/圆角形状（D3 一致性）
  let svg = @lib.SvgBuilder::default()
    .module_color("#0000ff")
    .background_color("#ffffff")
    .shape(RoundedSquare)
    .to_str(qr)
  println(svg[:200].to_owned() + "...")
}
