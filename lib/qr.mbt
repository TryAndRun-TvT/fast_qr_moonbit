///|
/// qr.mbt —— QRCode 结果、构造与错误类型
/// 对应参考：/fast_qr/src/qr.rs（roadmap 批次 B8）
/// 职责：QRCode（固定矩阵容器 + size/version/ecl/mask/mode 元数据）与编码构造
///       （对外入口：bytes/str → QRCode），以及两类错误（超容量/指定版本过小）。
/// 关键语义：固定大小矩阵容器（一维按行存储）；错误面收敛为两类（框架文档 §五）。
/// 拆包去向：lib 包公共（进入 .mbti 的对外契约面）。
/// 待实现：类型定义 + 构造链路 + 黑盒行为测试。
