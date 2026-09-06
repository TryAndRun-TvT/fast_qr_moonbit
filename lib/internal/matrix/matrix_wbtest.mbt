///|
/// matrix 包内白盒测试：D3 原始字节矩阵位布局 helper 语义。
/// 覆盖 pack 类型号/明暗打包、module_type_of / value_of / is_data_byte 解码、
/// set_value / toggle_value 位操作（S4 方案 §6.2 白盒位级断言，放置/掩码前的基础护栏）。

///|
test "module helper: pack 类型号与明暗打包 roundtrip" {
  // 类型号写 bit1-3、明暗写 bit0
  let d0 = pack(0, module_type_data) // Data 亮
  if d0 != 0 {
    fail("Data light 应打包为 0")
  }
  let d1 = pack(1, module_type_data) // Data 暗
  if d1 != 1 {
    fail("Data dark 应打包为 1")
  }
  // finder 暗 = 1 | (1<<1) = 3
  let f = pack(1, module_type_finder)
  if f != 3 {
    fail("finder dark = 1|(1<<1) = 3，实际 \{f}")
  }
  // empty 亮 = 0 | (7<<1) = 14
  let e = pack(0, module_type_empty)
  if e != 14 {
    fail("empty light = 0|(7<<1) = 14，实际 \{e}")
  }
}

///|
test "module helper: 类型号/明暗解码" {
  let f = pack(1, module_type_finder) // 3
  if module_type_of(f) != module_type_finder {
    fail("module_type_of(finder dark) 应还原 1")
  }
  if value_of(f) != 1 {
    fail("value_of(finder dark) 应=1")
  }
  if is_data_byte(f) {
    fail("finder 不是 data，is_data_byte 应为 false")
  }
  if !is_data_byte(pack(0, module_type_data)) {
    fail("Data 模块 is_data_byte 应为 true")
  }
}

///|
test "module helper: set_value 只动明暗、toggle_value 只翻 bit0" {
  let f = pack(0, module_type_finder) // 2 = 0 | (1<<1)
  let f_light = set_value(f, 1) // 改为亮? 不：set_value 置明暗
  // set_value(f,1) -> (2 & 0xFE)|1 = 2|1 = 3
  if f_light != 3 {
    fail("set_value(f,1) 应=3，实际 \{f_light}")
  }
  if module_type_of(f_light) != module_type_finder {
    fail("set_value 不应改变类型号")
  }
  // toggle 只在明暗翻转
  let toggled = toggle_value(f_light) // 3^1 = 2
  if toggled != 2 {
    fail("toggle_value(3) 应=2，实际 \{toggled}")
  }
  if module_type_of(toggled) != module_type_finder {
    fail("toggle 不应改变类型号")
  }
}
