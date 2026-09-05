///|
/// capacity.mbt —— 版本容量与矩阵元数据表（internal 叶节点）
/// 对应参考：/fast_qr/src/version.rs（roadmap 批次 B2）
/// 职责：40 版本 × 4 ECL × 3 模式的容量表；size / 版本信息 / alignment 网格等元数据；
///       按 (mode 序号, ecl 序号, len) 返回最小可用版本。
/// 实现方式：大表由提取脚本从 /fast_qr/src/version.rs 生成（禁止手抄）；
///       期望值抄 /fast_qr/src/tests/version.rs 黄金数据。
/// 依赖规则：本包是叶节点（无依赖），供lib 包与 internal/data_encoding、internal/matrix 查表。
/// 待实现：表生成 + 查表函数 + 黄金单测。
