///|
/// fast_qr_moonbit.mbt —— 库入口 / 顶层公共 API 组装层（lib 公共包）
/// 职责：把 lib/internal 各子包（constants/bitstream/reedsolomon/data_encoding/matrix）
///       的管线封装为对外的「字节/字符串 → QRCode」便捷入口；公共枚举（ECL/Version/
///       Mode/Mask）与 QRCode 等在 lib 公共层定义并随入口暴露给调用者。
/// 依赖规则：lib 可 import lib/internal 子包，internal 永不反向依赖 lib（无环约束，实测确认）。
/// 当前状态：项目骨架——各文件已按设计落地为**注释骨架**（无逻辑代码），真实实现按
///       roadmap 批次 B1-B11 逐个替换注释（见
///       [moonbit-实现布局与文件职责](../docs/moonbit-实现布局与文件职责.md)）。
