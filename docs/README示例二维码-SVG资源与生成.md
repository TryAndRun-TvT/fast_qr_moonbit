# README 示例二维码：SVG 矢量资源与生成方式

> **状态**：现行　｜　日期：2026-09-12　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §6

> 面向：README 维护者 / 审阅者。
> 背景与实测：ISSUE #47 第二轮要求「将二维码换为 svg，避免 markdown 渲染导致二维码变形」。
> 日期：2026-09-12　｜　工具链：`moon 0.1.20260904`、Node 24（仅用于光栅化校验）
> 影响面：README 头部示例块 + `docs/assets/qr-example.svg` + `scripts/gen-readme-qr-svg.sh`，
> **不改 lib / 公共 API / 快照 / 用例**。

---

## 0. 结论先行

- README 头部的二维码示例已从**终端 Unicode 半块字符画**改为 **SVG 矢量图**
  （`docs/assets/qr-example.svg`，约 1.9 KB，122 个矩形合并片段）。
- 动机：字符画（`▄▀█`）在**按比例字体 / 窄屏 / 移动端**会被 Markdown 渲染器折行与重排，
  行宽不再等宽 → 二维码「变形」（走样、扫不出）；SVG 与字体、字号、视口宽度无关，
  任意缩放不失真。
- 资源可直接复现：`bash scripts/gen-readme-qr-svg.sh`（用完即删的临时 MoonBit 包生成，不留痕）。
- 资产内容与库输出**同源可核**：矩阵 = `QRBuilder::from_string("https://example.com/").build()`，
  与 `moon run cmd/main` 的字符画逐模块一致（§3 给出三方一致性核验）。

---

## 1. 为什么要换：字符画在 Markdown 里会变形

原 README 头部（2026-09-11 随 S9i 那次改动引入）是这样的：

```text
`moon run cmd/main` 的真实输出（内容 `https://example.com/`）：

```text
▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
█ ▄▄▄▄▄ ██▀█  ▀ █▀█ ▄▄▄▄▄ █
...
```
```

问题（实测与通用渲染行为）：

| 问题 | 说明 |
|------|------|
| **等宽前提被破坏** | 半块字符画依赖「每行等宽 + 行高固定」。网页/移动端 Markdown 用**按比例字体**渲染代码块时，`█ ▄ ▀` 三类字符的**内联宽度不同**，列不再对齐 → 矩阵被横向拉花 |
| **折行挤压** | 27 字符宽（V3 码）在窄屏会**软换行**，同一模块行被拆到两行 → 行列错位，二维码无法识别 |
| **缩放/深色主题** | 字符画无法缩放；深色主题下前景背景反转，静区失效（扫码失败） |
| **可访问性** | 纯字符画没有替代文本，读屏软件只能读出一串方块字符 |

SVG 则：与字体无关、与视口宽度无关、可缩放不失真、可给 `aria-label`/`title`、
体积小且**文本化可 diff**（能进 code review）。

---

## 2. 资源规格（`docs/assets/qr-example.svg`）

| 项 | 值 |
|----|----|
| 内容 | `https://example.com/`（与 CLI/性能基准同输入） |
| 版本 / 纠错 / 掩码 | V03（25×25，`qr.size()==25`）/ ECL **Q**（默认）/ mask **自动择优** |
| 边距 | 4 模块（库默认 `SvgBuilder::margin=4`）→ `viewBox="0 0 33 33"` |
| 颜色 | 背景 `#ffffff`、模块 `#000000`（库默认 `background_color`/`dot_color`） |
| path 语义 | 每个暗模块 `M{x},{y}h1v1h-{1}z`（与库 `Shape::Square` 的 `M{x},{y}h1v1h-1` 等价） |
| 压缩 | 相邻同列矩形**纵向合并**（316 个暗模块 → 122 个矩形片段），仅压缩、不改变覆盖 |
| 额外属性 | `role="img"` + `aria-label` + `<title>`（库不产出，托管资产为可访问性补上） |
| 体积 | ≈ 1.9 KB（单行 `d`） |

> **与库输出的差异（诚实声明）**：本资产**不是** `SvgBuilder::to_str` 的逐字节输出——
> 库按「每格一段」输出（示例码约 4093 B），资产做了矩形合并并补了可访问性属性。
> 两者的**几何语义完全等价**（§3 已核验逐模块一致）。若需要「库原样输出」，
> 用 `moon run cmd/main` 或直接调 `SvgBuilder`。

---

## 3. 一致性核验（三方同源）

| 侧 | 产物 | 核验方式与结果 |
|----|------|----------------|
| 库矩阵 | `QRBuilder::from_string("https://example.com/").build()` | 逐格导出暗格坐标，`n=25`、暗格 **316** 个 |
| 库终端字符画 | `QRCode::to_str()`（`moon run cmd/main`） | 按 `helpers.mbt` 的 `(真,真)=' ' / (真,假)='▄' / (假,真)='▀' / (假,假)='█'` 规则**反向重建**，与 `to_str()` 14 行**逐字符相同** |
| README 资产 | `docs/assets/qr-example.svg` | 光栅化（density 40 → 660×660，最近邻）后解码，`jsQR` 解回 **`https://example.com/`** |

---

## 4. 生成方式（可复现）

```bash
bash scripts/gen-readme-qr-svg.sh     # 重新生成 docs/assets/qr-example.svg
```

脚本做的事：

1. 在 `cmd/qr-svg-gen/` 建一个**临时可执行包**（`import @lib`），对 `https://example.com/` 构建二维码，
   按行主序导出暗格坐标（`N=<size>` 与 `DARK=r,c;...` 两行文本）；
2. 运行后**立即删除临时包**（不留入库痕迹）；
3. `python3` 侧把坐标做「连续列段 → 跨行同区间合并」压缩成矩形，拼 `d`，
   写出带 `role`/`aria-label`/`title` 的 SVG。

### 4.1 踩坑记录：`d` 属性必须单行

首版曾把 `d` 按 160 字符折行以「便于阅读」。实测：**librsvg**（rsvg-convert / sharp 等常用渲染器）
会把 `d` 属性内的换行视为无效数据而**截断路径**，图形只剩左上角一角（本地复现：
`as-is` 解码失败、去掉换行后成功）。故：

- `d` **保持单行**（标签之间可以有换行，属性值内部不行）；
- 该约束已写进脚本注释，避免回归。

### 4.2 为什么「非 ASCII 内容」按字节编码仍可扫

`https://example.com/` 是纯 ASCII，走 Byte 模式；资产的 `<title>` 用中文只是**注释**，
不参与编码，故不影响扫码结果。

---

## 5. 后续维护约定

- **改示例内容**：改脚本里的 `CONTENT`（当前 `https://example.com/`），重跑脚本；
  同时更新 README 图注文字与本文档 §2 表。
- **改库输出口径**（如默认 margin/颜色/形状）：README 图不必跟随（图只需可扫），
  但若口径变化会影响「同源」表述，需同步本节 §2/§3。
- **不要手工编辑 SVG**：该文件是生成物；手工改动会在下次重跑时被覆盖。
- README 引用方式：`<img src="./docs/assets/qr-example.svg" ... width="220" height="220">`
  （显式给 `width`/`height`，避免不同渲染器对无尺寸 SVG 的默认占位不一致）。
- **渲染核验实测**：README 头部片段经 `marked` 解析后 `<img>` 保留（未被当代码块）；
  资产在 `width=220`（README 实际显示尺寸）/ 440 / 1024 px 下均可解码为 `https://example.com/`；
  64 px 极小尺寸下多数扫码器会失败——属**显示尺寸不足**而非资产问题，故 README 固定 `width="220"`。
  深色主题下无需额外处理：资产自带白色背景 `rect`（库默认配色即白底黑码）。

---

## 6. 参考

- 输出层实现与口径：[S7 输出层 to_str 与 SVG](./S7-输出层to_str与SVG.md)
- 体积口径（`cmd/main` 含输出层的增量）：[S9i 纯库调用体积探针与库实际体积](./S9i-纯库调用体积探针与库实际体积.md)
- 本仓库实码：`scripts/gen-readme-qr-svg.sh`（生成器）、`docs/assets/qr-example.svg`（资产）、
  `cmd/main/main.mbt`（字符画 + SVG 打印演示）

---

## 4. 2026-09-14 增补：`fill-rule="evenodd"` 与「d 必须单行」

本轮（ISSUE #47 第三轮，见 [README优化-冗余清理与最佳实践.md](./README优化-冗余清理与最佳实践.md) §6.5）
给 `<path>` 补了 `fill-rule="evenodd"`，生成脚本同步注释。**口径以实测为准，勿夸大**：

| 事项 | 实测结论 |
|------|---------|
| `d` 属性**必须单行** | ✅ **已发生的实测缺陷**：librsvg（rsvg-convert / sharp）把 `d` 内换行当无效数据，路径被截断、图形只剩一角（2026-09-12 本地复现：折行解码失败、单行成功） |
| `fill-rule="evenodd"` | ⚠️ **去风险加固，非修复现存 bug**：当前合并结果 **122 子路径两两无嵌套**，加/不加渲染**逐字节相同**、jsQR 均可解 |
| 何时 `evenodd` 是必需的 | 负向对照（注入包住全图的外层矩形）：无 `fill-rule` → jsQR **解不出**；加 `evenodd` → **解回原文**。因合并出的子路径**方向一律同向**，`nonzero` 对嵌套取并集会把亮格填暗 |

**维护动作**：改动合并算法（尤其是引入「子路径方向归一化」或「矩形排序」）后，
请重跑 §3 的解码回读与本节的两条负向对照，确认资产仍可解。

> 校验命令（本环境可复现）：
> ```bash
> npm i -g @resvg/resvg-js && npm i jsqr pngjs
> # 光栅化 512px 后交给 jsQR，应解回 https://example.com/
> ```
