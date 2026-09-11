///|
/// fast_qr_moonbit.mbt —— 库入口 / 顶层公共 API 总览（lib 公共包）
/// 本文件为**库入口文档头**：MoonBit 同包（lib/）内所有 .mbt 共享同一命名空间，公共 API 由
/// 各职责文件直接提供，无需在此显式 re-export。真实公共契约散布于下列文件：
///   - 公共枚举/呈现：ecl.mbt（ECL）、version.mbt（Version）、mode.mbt（Mode）、
///     mask.mbt（Mask）、module.mbt（Module/ModuleType）、shape.mbt（Shape）
///   - 结果容器与错误：qr.mbt（QRCode + QRCodeError）
///   - 编排/构造：qr_build.mbt（QRCode::select_capacity/build_fixed/build，装配 internal 管线）、
///     qr_builder.mbt（QRBuilder 便捷构造器）
///   - 输出：qr_output.mbt（QRCode::to_str/print）、helpers.mbt（终端渲染）、svg.mbt（SvgBuilder）
/// 编排入口：`QRCode::build`（字节/模式/纠错/版本/掩码 → Result[QRCode]）或 `QRBuilder`
///       （链式 setter → build）。internal 管线单向链：
///       constants → bitstream / reedsolomon / data_encoding → matrix → lib（无环，实测确认）。
/// 结构约定（AGENTS / 方案 3）：lib 可 import lib/internal 子包，internal 永不反向依赖 lib。
/// 历史：S1-S7 已将「注释骨架」替换为真实实现（现测试 109 全绿、wasm-gc/wasm 双后端）；S8
///       完成公共层文件级职责归位（qr.mbt → qr_build/qr_builder/qr_output），见
///       [S8-内部结构归位与分层](../docs/S8-内部结构归位与分层.md)。
