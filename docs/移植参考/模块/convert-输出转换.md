# src/convert/ 输出转换

将 QRCode 矩阵渲染为 SVG 字符串或 PNG 位图。全部位于 feature flags 之后：`svg` 独立开关，`image` 隐含 `svg` 并引入 resvg。

## 结构

```
convert/
├── mod.rs     # Shape 枚举、Color、ConvertError、rgba2hex、公共类型
├── svg.rs     # SvgBuilder（SVG 字符串/文件）
└── image.rs   # ImageBuilder（PNG 字节/文件/Pixmap）
```

## 关键文件

| 文件 | 目的 |
|------|------|
| `mod.rs` | `Shape` 枚举（WASM 与非 WASM 两套定义，非 WASM 版多出 `Command(fn)` 自定义形状）；`rgba2hex`；`ImageBackgroundShape` |
| `svg.rs` | `SvgBuilder`：margin/shape/module_color/background_color/image 等配置；`to_str(qr)`（svg.rs:308）与 `to_file(qr, path)`（svg.rs:332）；`SvgError`（IO 或 unwrap 失败） |
| `image.rs` | `ImageBuilder`：`fit_width`/`fit_height` 缩放；`to_pixmap`（image.rs:156，返回 resvg Pixmap）、`to_file`、`to_bytes`；`ImageError` |

## 依赖

**本模块依赖**:
- 核心管线的 `Module` 与 `QRCode`（只读矩阵）
- `resvg`（仅 image feature）

**依赖本模块的**:
- `src/wasm.rs`（svg feature 下暴露 qr_svg 与 SvgOptions）

## 规范

### 代码模式

**Builder 模式**：所有配置方法返回 `&mut Self`（Rust 侧）或消耗 self 的链式调用（WASM 侧 SvgOptions），最终一次性调用 `to_*`。

**形状即函数**：每种 Shape 最终归约为生成 SVG path 命令的函数（如 Square 为 `M{x},{y}h1v1h-1`），`Shape::Command` 允许用户提供 `fn(usize, usize, Module) -> String` 完全自定义。

**透明度处理**：background_color 支持 RGBA（`[255,255,255,0]` 即透明），PNG 输出保留 alpha 通道。

### 错误处理

`ConvertError` 统一枚举（mod.rs:240），SvgError/ImageError 各自覆盖 IO 与渲染失败场景。

### 测试

`src/tests/svg.rs` 对各形状做快照断言。

## 添加新形状

1. `mod.rs` 两处 Shape 枚举各加变体（WASM 版无 Command）
2. `svg.rs` 增加对应 path 生成分支
3. `wasm.rs` 导出（若需 JS 侧可见）
4. `tests/svg.rs` 加快照
