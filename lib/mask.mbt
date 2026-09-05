///|
/// mask.mbt —— 公共掩码枚举（0-7）
/// 对应参考：/fast_qr/src/datamasking.rs 的 Mask（roadmap 批次 B10）
/// 职责：对外 API 的掩码枚举；进入择优/强制掩码时转为掩码序号传给 internal/matrix。
/// 拆包去向：lib 包公共（进入 .mbti 的对外契约面）。
/// 待实现：枚举定义 + 与矩阵层掩码序号的映射。
