// MoonBit 模块配置文件
// 参考: https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html

name = "tryandrun/fast_qr_moonbit"

version = "0.1.0"

readme = "README.md"

repository = "https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit"

license = "Apache-2.0"

keywords = [ "qr", "qrcode", "fast-qr" ]

preferred_target = "wasm-gc"

// 显式声明实际支持的后端（native 需系统 C 编译器，当前不纳入）

supported_targets = "+wasm+wasm-gc+js"

description = "Fast QR code generator library written in MoonBit"
