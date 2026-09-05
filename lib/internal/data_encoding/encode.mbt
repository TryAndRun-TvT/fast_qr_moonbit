///|
/// encode.mbt —— 数据编码（Numeric / Alphanumeric / Byte）
/// 对应参考：/fast_qr/src/encode.rs（roadmap 批次 B7）
/// 职责：三模式编码写入位流缓冲；best_encoding 自动回退（Numeric→Alnum→Byte）；
///       terminator + 8 位对齐。
/// 关键语义：Numeric 3 位一组 10 bit、Alnum 2 字符 11 bit、Byte 直拷（框架文档 §五.9）。
/// 所在包：internal/data_encoding（roadmap 批次 B7）。
/// 依赖规则：不依赖lib 公共包；mode/ecl 以序号（Int）入参；容量查 internal/constants。
/// 待实现：先 Byte 模式最小路径（配合固定版本/掩码出首码，M1），再补三模式与自动回退；
///       黄金单测期望值抄 tests/encode.rs。
