///|
/// bitbuffer.mbt —— 位流缓冲（CompactQR 的 MoonBit 对应）
/// 对应参考：/fast_qr/src/compact.rs（roadmap 批次 B6）
/// 职责：按任意位宽推进的大端序比特流；按版本容量预分配，编码期零扩容；
///       填充补位 [236, 17]。
/// 关键语义：跨字节截断用 KEEP_LAST 表，需与后端位宽一致（wasm32 33 项 / 64 位 65 项，
///       见框架文档 §五.3）。
/// 所在包：internal/bitstream（roadmap 批次 B6）。
/// 依赖规则：不依赖lib 公共包（纯缓冲，无外部类型）。
/// 待实现：写入/截断/填充逻辑 + 黄金单测（期望值抄 /fast_qr/src/tests/compact.rs）。
