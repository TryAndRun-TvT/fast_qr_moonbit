///|
/// mode.mbt —— 公共编码模式枚举（Numeric / Alphanumeric / Byte）
/// 对应参考：/fast_qr/src/encode.rs 的 Mode（roadmap 批次 B7/B8）
/// 职责：对外 API 的模式枚举；进入编码时转为模式序号传给 internal/data_encoding。
/// 拆包去向：lib 包公共（进入 .mbti 的对外契约面）。
/// 待实现：枚举定义 + 与编码内部序号的映射。
