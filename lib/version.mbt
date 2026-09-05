///|
/// version.mbt —— 公共版本枚举（V01-V40）
/// 对应参考：/fast_qr/src/version.rs 的 Version（roadmap 批次 B2）
/// 职责：对外 API 的版本枚举与序号映射。
/// 容量/矩阵元数据等大表放 internal/constants/capacity.mbt（internal 需查表且不能反向依赖lib 包）。
/// 拆包去向：lib 包公共（进入 .mbti 的对外契约面）。
/// 待实现：枚举定义 + 序号映射；容量表联动见 internal/constants。
