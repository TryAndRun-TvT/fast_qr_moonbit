///|
/// ecl.mbt —— 纠错级别（ECL：L / M / Q / H）
/// 对应参考：/fast_qr/src/ecl.rs（roadmap 批次 B1）
/// 职责：ECL 枚举与判别值；作为容量选择、分组与生成多项式查表的第一参数。
/// 拆包去向：lib 包公共（Version/ECL 等对调用者可见，见框架文档 §四）。
/// 待实现：枚举定义 + 与 hardcode/version 查表联动；白盒判别断言。
