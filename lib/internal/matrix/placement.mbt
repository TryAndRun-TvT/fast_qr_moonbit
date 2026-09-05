///|
/// placement.mbt —— 数据放置 + 掩码择优 + 总装
/// 对应参考：/fast_qr/src/placement.rs（roadmap 批次 B9 后半 / B10 择优）
/// 职责：之字形放置数据（跳过第 6 列、y 方向交替）；create_matrix 总装；
///       基础矩阵只建一次，8 轮 clone+掩码+评分择优后写真实 Format。
/// 关键语义：列评分必须在掩码后进行（真实修复过的 bug 决策，框架文档 §五.6）。
/// 所在包：internal/matrix（roadmap 批次 B9 后半 / B10 择优）。
/// 依赖规则：不依赖lib 公共包；version/mask 以序号（Int）入参，结果以字节矩阵交回lib 包。
/// 待实现：放置与择优主循环；固定 mask 首码快照对齐（M1）→ 全量快照对齐（M2）。
