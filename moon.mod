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
// wasm(WASI) 为兼容兜底，仅作历史记录，不参与对外对比

supported_targets = "+wasm+wasm-gc"

description = "Fast QR code generator library written in MoonBit"
