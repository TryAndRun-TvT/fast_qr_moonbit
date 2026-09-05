# src/wasm.rs WASM 绑定

将核心能力以最小接口暴露给 JavaScript：两个函数 + 一个配置类。仅在 `wasm32` 目标且启用 `wasm-bindgen` feature 时编译。

## 结构

```
src/wasm.rs   # 全部绑定逻辑（236 行）
wasm-pack.sh  # 发布级构建脚本
pkg/          # 构建产物（fast_qr.js / fast_qr_bg.wasm）
```

## 关键导出

| 导出 | 目的 |
|------|------|
| `qr(content: &str) -> Vec<u8>` | 矩阵的 0/1 扁平字节数组；失败返回空数组（wasm.rs:18） |
| `qr_svg(content: &str, options: SvgOptions) -> String` | 直接产出 SVG 字符串（wasm.rs:202） |
| `SvgOptions` | 链式配置：shape/margin/颜色/嵌入图片/ecl/version（wasm.rs:27） |
| `Shape` / `ECL` / `Version` | 枚举经 `#[wasm_bindgen]` 转发给 JS |

内部辅助 `bool_to_u8`（wasm.rs:7）把 QRCode 矩阵压成 0/1 字节，丢弃类型信息。

## 依赖

**本模块依赖**:
- 核心 `QRCode::new`
- `convert`（svg feature）—— SvgOptions 的字段直接复用 convert 类型

**依赖本模块的**:
- npm 包 `fast_qr` 的全部消费者

## 规范

### 构建链（wasm-pack.sh）

```bash
cargo +nightly build --release \
  --target wasm32-unknown-unknown \
  -Z build-std=std,panic_abort \
  -Z build-std-features=panic_immediate_abort \
  --features svg,wasm-bindgen
# 再经 wasm-bindgen CLI --web 生成胶水，wasm-opt -Oz 二次瘦身
```

体积优化三板斧：`panic_immediate_abort`（panic 字符串归零）+ `opt-level='s'` + `wasm-opt -Oz`。

### 错误处理

JS 侧无异常：`qr()` 失败返回空数组。这是刻意的简化（WASM 边界不做 Result 提升到异常）。

### 配置校验

颜色解析（`color_to_code`，wasm.rs:48）容错：非法输入静默忽略（保持默认），`#RRGGBB` 自动补 alpha=255。
