///|
/// datamasking.mbt —— 8 种掩码图案
/// 对应参考：/fast_qr/src/datamasking.rs（roadmap 批次 B10 前半）
/// 职责：8 个掩码函数，只翻转 Data 类模块；掩码 5/6 共用 6x6 网格 + 固定
///       OFFSETS 偏移表技巧（Fields 4 项 / Diamonds 12 项）。
/// 所在包：internal/matrix（roadmap 批次 B10 前半）。
/// 依赖规则：不依赖lib 公共包；掩码以序号（Int）选择。
/// 待实现：掩码函数 + 白盒/快照测试。
