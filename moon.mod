// MoonBit 模块配置文件
// 参考: https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html

name = "tryandrun/fast_qr_moonbit"

version = "0.1.0"

readme = "README.md"

repository = "https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit"

license = "Apache-2.0"

keywords = [ "qr", "qrcode", "fast-qr" ]

// 默认/主推后端 = 实际分发形态，也是对外性能/体积对比的口径（见 docs/S9j-…、docs/S9i-…）

preferred_target = "wasm-gc"

// 显式声明实际支持的后端（native 需系统 C 编译器，当前不纳入）；
// wasm(WASI)、js 后端均已按项目决策移除，只保留 wasm-gc

supported_targets = "+wasm-gc"

// 启用「只读数组字面量」lint（S9m T-R4）：只读字面量提示改用 ReadOnlyArray，防回归。
// 现仓库已零命中（RS 表/常量表/局部字面量均已只读化，见 docs/S9m/S9n）。

warnings = "+prefer_readonly_array"

description = "Fast QR code generator library written in MoonBit"
