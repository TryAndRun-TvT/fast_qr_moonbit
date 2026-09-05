///|
/// reedsolomon.mbt —— GF(256) 纠错与交织
/// 对应参考：/fast_qr/src/polynomials.rs（roadmap 批次 B4）
/// 职责：LOG/ANTILOG 表驱动的 division（余数 = 纠错码字）与
///       structure（分块纠错 + 数据/纠错码字交织）。
/// 关键语义：固定上限数组（division [255]、structure [5430]）；数据区逐块跨字节、
///       纠错区逐字节跨块，交织方向相反（框架文档 §五.8）。
/// 所在包：internal/reedsolomon（roadmap 批次 B4）。
/// 依赖规则：不依赖lib 公共包；ecl/version 以序号（Int）入参，避免反向依赖lib 包枚举。
/// 待实现：查表除法/交织 + 黄金单测（期望值抄 tests/polynomials.rs、tests/structure.rs）。
