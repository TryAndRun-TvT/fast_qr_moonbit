///|
/// matrix.mbt —— 空矩阵与功能图案绘制
/// 对应参考：/fast_qr/src/default.rs（roadmap 批次 B9 前半）
/// 职责：按版本初始化矩阵容器；绘制 finder/timing/alignment/version info/
///       dark module，并为 format 区写入占位。
/// 关键语义：Format 先占位、掩码择优后再覆写真实格式信息，时序不可颠倒
///       （框架文档 §五.7）。
/// 所在包：internal/matrix（roadmap 批次 B9 前半）。
/// 依赖规则：不依赖lib 公共包；按 version 序号创建矩阵并绘制功能图案。
/// 待实现：各功能图案坐标逻辑 + 快照对照。
