///|
/// 黑盒测试（_test.mbt）
/// 在包**外**运行，只能访问 `pub` 导出的公共 API。
/// 通过 `@fast_qr_moonbit` 别名引用本包（包级别名自动可用，无需在 moon.pkg 中声明）。
/// 内部实现细节的测试请放 `fast_qr_moonbit_wbtest.mbt`。
test "module_smoke" {
  // 骨架阶段：验证测试包可编译并成功加载本包
  // 实现公共 API 后，替换为针对公共行为的断言
  assert_true(true)
}
