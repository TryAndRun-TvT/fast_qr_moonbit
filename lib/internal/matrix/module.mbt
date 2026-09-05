///|
/// module.mbt —— 模块单元（单字节位打包）
/// 对应参考：/fast_qr/src/module.rs（roadmap 批次 B5）
/// 职责：Module 单字节单元——bit0 明暗 + bit1-3 类型号；明暗/类型读写、置位与翻转。
/// 关键语义：类型判别值 = 类型号 << 1；掩码/评分只对 Data 类模块操作。
/// 所在包：internal/matrix（roadmap 批次 B5）。
/// 依赖规则：不依赖lib 公共包；Module 字节类型在本包定义并供本包算法使用。
/// 待实现：Byte 打包与位级读写 + 白盒断言。
