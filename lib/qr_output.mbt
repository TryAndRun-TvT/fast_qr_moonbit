///|
/// qr_output.mbt —— QRCode 输出便捷方法
/// 对应参考：fast_qr v0.14.0 `src/qr.rs:174-185`（to_str/print → helpers）。
/// 职责：`QRCode` 上挂便捷渲染/输出方法——`to_str`（渲染终端 Unicode 半块字符画，含边距，
///       纯字符串无 IO）与 `print`（承担 stdout 副作用，走 println）。均委托 helpers.mbt 的
///       `print_matrix_with_margin`。
/// 架构决策（D8）：纯渲染函数放 helpers.mbt，`QRCode` 仅挂便捷方法委托之（对齐参考 qr.rs to_str→helpers）。
/// 架构决策（D11，S8）：从 qr.mbt 拆出「输出便捷」子关注到本文件（同包搬移、无逻辑改动），见
///       docs/S8-内部结构归位与分层-实现方案.md §3.2。

///|
/// 渲染为终端 Unicode 半块字符画（含边距），返回整串字符串。
pub fn QRCode::to_str(self : QRCode) -> String {
  print_matrix_with_margin(self)
}

///|
/// 打印终端字符画到 stdout。
pub fn QRCode::print(self : QRCode) -> Unit {
  println(self.to_str())
}
