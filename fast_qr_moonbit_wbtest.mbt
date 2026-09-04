///|
/// 白盒测试（_wbtest.mbt）
/// 在包**内**运行，可直接访问私有函数与内部实现（无需 `pub` 导出）。
/// 面向公共行为的断言请放 `fast_qr_moonbit_test.mbt`。
test "internal_smoke" {
  // 骨架阶段：验证包内测试可编译
  // 实现内部 helper 后，在此直接调用以覆盖不对外暴露的逻辑
  assert_true(true)
}
