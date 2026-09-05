///|
/// hardcode.mbt —— 常量表（分组 / 格式信息 / 生成多项式）
/// 对应参考：/fast_qr/src/hardcode.rs（roadmap 批次 B3）
/// 职责：ecc_to_groups（两个 (count,size) 对打进一个 u32）、格式信息表、
///       get_polynomial 生成多项式等编译期常量表。
/// 实现方式：表由提取脚本从 /fast_qr/src/hardcode.rs 生成，禁止手抄。
/// 所在包：internal/constants（roadmap 批次 B3）。
/// 依赖规则：叶节点（无依赖），供 internal 各算法子包共享查表。
/// 待实现：表生成 + 抽测断言。
