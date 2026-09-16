# fast_qr 接口文档

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README-导航与索引.md](../README-导航与索引.md) §7

fast_qr 是一个库项目（Rust crate + npm WASM 包），提供三类接口：Rust 公开 API、JavaScript/WASM API、以及基准/示例程序。

## 1. Rust 公开 API

crate 根导出（`src/lib.rs:75-80`）：

```rust
pub use crate::datamasking::Mask;
pub use crate::ecl::ECL;
pub use crate::encode::Mode;
pub use crate::module::{Module, ModuleType};
pub use crate::qr::{QRBuilder, QRCode};
pub use crate::version::Version;
```

### 1.1 QRBuilder（构造器）

定义于 `src/qr.rs:200`。

| 方法 | 签名 | 说明 |
|------|------|------|
| `new` | `fn new<I: Into<Vec<u8>>>(input: I) -> QRBuilder` | 接受 `String`/`&str`/`Vec<u8>` 等 |
| `mode` | `fn mode(&mut self, mode: Mode) -> &mut Self` | 强制编码模式 |
| `ecl` | `fn ecl(&mut self, ecl: ECL) -> &mut Self` | 强制纠错级别 |
| `version` | `fn version(&mut self, version: Version) -> &mut Self` | 强制版本（V01-V40） |
| `mask` | `fn mask(&mut self, mask: Mask) -> &mut Self` | 强制掩码（极少使用） |
| `build` | `fn build(&self) -> Result<QRCode, QRCodeError>` | 计算并返回 QRCode |

错误类型 `QRCodeError`：`EncodedData`（数据超出容量）、`SpecifiedVersion`（指定版本过小）。

### 1.2 QRCode（结果矩阵）

定义于 `src/qr.rs:25`。

| 成员 | 类型 | 说明 |
|------|------|------|
| `data` | `[Module; 177*177]` | 一维固定数组，按行存储 |
| `size` | `usize` | 矩阵边长 = version*4 + 17 |
| `version` | `Option<Version>` | 实际使用的版本 |
| `ecl` | `Option<ECL>` | 实际使用的纠错级别 |
| `mask` | `Option<Mask>` | 实际选用的掩码 |
| `mode` | `Option<Mode>` | 实际使用的编码模式 |

| 方法 | 说明 |
|------|------|
| `Index<usize>` | `qr[row]` 返回该行切片 |
| `to_str()` | 输出终端字符画（Unicode 半块字符，两行合一） |
| `print()` | 直接打印到 stdout |

### 1.3 核心枚举

**Mode**（`src/encode.rs:13`）：`Numeric`（0-9）、`Alphanumeric`（0-9 A-Z 与 9 个符号）、`Byte`（任意）。

**ECL**（`src/ecl.rs:13`）：`L`（7%）、`M`（15%）、`Q`（25%，默认）、`H`（30%）。

**Mask**（`src/datamasking.rs:11`）：8 种掩码，值 0-7：`Checkerboard`、`HorizontalLines`、`VerticalLines`、`DiagonalLines`、`LargeCheckerboard`、`Fields`、`Diamonds`、`Meadow`。

**Version**（`src/version.rs:9`）：`V01` 至 `V40`，判别值 0-39。

**Module / ModuleType**（`src/module.rs`）：单字节打包，`value()` 取 bit0，`module_type()` 取 bit1-3（8 种类型）。`Module::data/finder_pattern/alignment/timing/format/version/dark/empty(value)` 构造函数。

### 1.4 convert 模块（需 feature）

**Builder 模式**（`src/convert/svg.rs:29`、`src/convert/image.rs:39`）：

```rust
// svg feature
SvgBuilder::default()
    .shape(Shape::RoundedSquare)
    .margin(4)
    .module_color("#000000")
    .background_color("#ffffff")
    .to_str(&qrcode)            // -> String
    .to_file(&qrcode, "out.svg") // -> Result<(), SvgError>

// image feature（隐含 svg）
ImageBuilder::default()
    .shape(Shape::RoundedSquare)
    .background_color([255, 255, 255, 0])
    .fit_width(600)             // 或 fit_height
    .to_file(&qrcode, "out.png")
    .to_bytes(&qrcode)          // -> Result<Vec<u8>, ImageError>
    .to_pixmap(&qrcode)         // -> resvg Pixmap
```

**Shape**（`src/convert/mod.rs:40`）：`Square`、`Circle`、`RoundedSquare`、`Vertical`、`Horizontal`、`Diamond`；非 WASM 目标额外有 `Command(fn(usize, usize, Module) -> String)` 自定义形状。

**公共工具**（`src/convert/mod.rs`）：`rgba2hex([u8;4]) -> String`、`Color(String)`、`ImageBackgroundShape`、`ConvertError`。

### 1.5 Feature flags

| feature | 依赖 | 作用 |
|------|------|------|
| `svg` | 无 | 启用 SvgBuilder |
| `image` | `svg` + `resvg` | 启用 ImageBuilder（PNG） |
| `wasm-bindgen` | wasm32 only | 启用 JS 绑定导出 |

## 2. JavaScript / WASM API

npm 包名 `fast_qr`。构建方式见 `wasm-pack.sh`（nightly build-std + panic_immediate_abort + wasm-opt -Oz）。

### 2.1 初始化

```js
import init, { qr, qr_svg, SvgOptions, Shape } from 'fast_qr'
await init()   // WASM 加载后以下函数可任意次调用
```

### 2.2 导出函数（`src/wasm.rs`）

| 函数 | 签名 | 说明 |
|------|------|------|
| `qr` | `qr(content: string) -> Uint8Array` | 返回 size*size 的 0/1 字节数组，失败返回空数组 |
| `qr_svg` | `qr_svg(content: string, options: SvgOptions) -> string` | 返回 SVG 字符串 |

### 2.3 SvgOptions（链式配置，`src/wasm.rs:27`）

| 方法 | 说明 |
|------|------|
| `shape(shape: Shape)` | 模块形状 |
| `module_color(color: string)` | 模块颜色 `#RRGGBB[AA]` |
| `margin(n: number)` | 边距 |
| `background_color(color: string)` | 背景色 |
| `image(url: string)` | 居中嵌入图片（URL 或 base64） |
| `image_background_color(color: string)` | 图片底色 |
| `image_background_shape(shape)` | 图片底形状（Circle/Square） |
| `image_size(size: number)` | 图片尺寸比例 |
| `image_gap(gap: number)` | 图片与模块间距 |
| `image_position(pos: number[])` | 图片位置 |
| `ecl(ecl: ECL)` | 纠错级别 |
| `version(version: Version)` | 强制版本 |

### 2.4 使用示例（来自 README）

```js
const options = new SvgOptions()
  .margin(4)
  .shape(Shape.Square)
  .image("")
  .background_color("#b8a4e5")
  .module_color("#ffffff");

const svg = qr_svg("https://fast-qr.com", options);
```

## 3. 示例与基准程序

| 程序 | 运行命令 | 说明 |
|------|------|------|
| examples/simple.rs | `cargo run --example simple` | 终端字符画 QR |
| examples/svg.rs | `cargo run --example svg -F svg` | SVG 文件输出 |
| examples/image.rs | `cargo run --example image -F image` | PNG 文件输出 |
| examples/custom.rs | `cargo run --example custom -F image` | 自定义形状/颜色 |
| examples/embed.rs | `cargo run --example embed -F image` | 中央嵌入 logo |
| benches/qr.rs | `cargo bench` | criterion 基准，对比 qrcode crate（V03H/V10H/V40H） |

## 4. 性能契约

官方基准数据（`https://example.com/` 输入，criterion 200 样本 x 10s）：

| 基准点 | fast_qr | qrcode crate | 倍率 |
|------|------|------|------|
| V03H | 82.2us | 535.0us | 6.51x |
| V10H | 269.3us | 2114.5us | 7.85x |
| V40H | 2436.2us | 18037us | 7.40x |
