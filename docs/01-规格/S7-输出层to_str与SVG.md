# S7 · 输出层 to_str 与 SVG

> **状态**：现行　｜　日期：2026-09-06　｜　索引：[docs/README.md](../README.md) §7

> 本文件由原 S7-输出层to_str与SVG-实现方案 / S7-输出层to_str与SVG-实现记录 / S7-输出层to_str与SVG-实现评估与优化-记录 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接 [moonbit-重写-roadmap-详细分析](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.3 的 **S7 / B11
> 输出层**：在 S6 已收敛里程碑 **M2（功能对齐）**、公共 API（`QRCode`/`QRBuilder`/`Mode`/`ECL`/
> `Version`/`Mask`/`Module`）已对齐 fast_qr 导出面的前提下，落地把 `QRCode` 渲染为**终端字符画**（`to_str`/
> `print`）与 **SVG 字符串**（`SvgBuilder`）的输出层，对齐 fast_qr v0.14.0 `src/helpers.rs` 与
> `src/convert/svg.rs`，用参考**字符串级快照**逐字节对齐。
>
> 日期：2026-09-06　｜　前置：S6 已合入 main（PR #33/#34，94 测试绿，`QRBuilder` + 快照端到端收口达成
> M2）；本阶段为**方案评估文档**：不写实现代码，只做「读代码/文档 + 参考源码核验 + 逐文件落地清单 +
> 关键架构决策与验收策略」，供 S7 实现阶段直接执行。参考源码于本容器检出 `/tmp/fast_qr_src`
> （fast_qr v0.14.0，master `53e8c99`）供核对，不入库。

---

### 0. 一句话结论

S7 两块交付，属 **M2 之后的「输出面补齐」（roadmap §4.2 S7，非 M 里程碑，无硬性能门槛）**：

1. **终端字符画**：在 lib 公共层给 `QRCode` 加 `to_str()`（返回含边距的 Unicode 半块字符画）与 `print()`
   （打印到 stdout），移植 fast_qr `src/helpers.rs` 的 `print_matrix_with_margin`（**约 30 行**，纯逻辑，
   无 IO 副作用由 `print` 承担）；并把 M1/M4 早前约定「CLI 输出依赖 to_str」的欠账一并补上。
2. **SVG 输出**：落地公共 `SvgBuilder` 构造器（`margin`/`shape`/`module_color`/`background_color` +
   `to_str(qr)`，纯字符串拼接），移植 fast_qr `src/convert/svg.rs` 中**不依赖 resvg / 不依赖文件 IO 的
   子集**（6 种形状 + 边距 + 颜色），对齐 `tests/svg.rs` 风格**字符串快照**逐字节对齐。

**S7 不做**：`image.rs`（PNG，依赖 resvg，纯 MoonBit 库无该依赖链，roadmap §3.2/跨语言评估建议直接位图
绘制 + PNG 编码，属二期/独立阶段）；SVG 的 `shape_color`/`image`/`image_*` 图片嵌入子集（wasm/宿主专用，
本仓库纯库无 wasm-bindgen 对应物，列为「按需」扩展）。**输出层不触碰、不改动 S1-S6 已锁定的编码管线**。

---

### 1. 范围界定（对照 roadmap §4.2/§4.3 / S6 遗留）

来自 roadmap §4.2：

> **S7** | 输出层：`to_str` 终端画 + SVG（按需）| `helpers.rs` / `convert/svg.rs` | `tests/svg.rs` 快照

对应 §4.3 批次表 B11：

> | B11 | `helpers.rs` / `convert/svg.rs` → 输出层 | `to_str` / SVG（按需）| `tests/svg.rs` 风格快照 |

并承接 S6 方案 §1.2 的明确划出：

> - **`to_str` 终端画 / `print`**（helpers.mbt）→ **S7（B11 输出层）**；当前 helpers.mbt 仍是注释骨架。
> - **SVG / image convert**（`SvgBuilder`/`ImageBuilder`）→ **S7+**（需 feature 语义，本仓库为纯库无 Cargo
>   feature，是否按需实现以 roadmap S7 为准）。

#### 1.1 S7 分两块，逐条对照

| 子项 | 内容 | 参考锚点 | 对应快照/API |
|:---:|------|---------|-------------|
| S7-1 | `QRCode::to_str()`（终端半块字符画）+ `print()` | `src/helpers.rs:1-74`、`src/qr.rs:174-185` | 终端字符串快照逐字节对齐 |
| S7-2 | 公共 `SvgBuilder`（`margin`/`shape`/`module_color`/`background_color` + `to_str(qr)`）| `src/convert/svg.rs`（`SvgBuilder`/`to_str`/`path`）+ `src/convert/mod.rs`（`Shape`/`rgba2hex`）| `tests/svg.rs` 风格 SVG 字符串快照 |

#### 1.2 不属于 S7（由后续/按需承接）
- **`image.rs`（PNG）**：依赖 resvg，纯 MoonBit 库不引入；跨语言评估建议直接位图绘制 + PNG 编码，列为
  二期独立阶段（roadmap §3.2「不做的事」/跨语言评估 §4-5.6 裁剪）。
- **SVG 图片嵌入子集**（`image`/`shape_color`/`image_background_*`/`image_size/gap/position`）：wasm 宿主侧
  才用的 logo/嵌图能力；本仓库无 wasm-bindgen 对应物，S7 默认**不做**，仅留 `SvgBuilder` 结构预留字段位
  （不实现逻辑），实现时按需评估。
- **wasm 导出面**（`qr(content) -> u8[]`、`qr_svg`）：沿用 S6 方案 §7「wasm 导出面是否随 S6/S7」的结论——
  无宿主侧 JS 绑定需求则降级/单列后续阶段，S7 不扩。
- **文件 IO**（`to_file`）：纯库不做 `File::create`；CLI（`cmd/main`）层若需写文件再自管，S7 只出字符串。

---

### 2. 现状盘点与参考源码核验（动手前已核验）

#### 2.1 已就绪、S7 将直接消费的公共面（S1-S6 全绿，94 测试）
| 层 | 位置 | S7 将消费的 API | 状态 |
|------|------|---------------|:---:|
| 模块单像素 | lib `module.mbt` | `Module::value() -> Bool`（bit0 明暗）、`Module::module_type()`、`Module::data/empty/...` 构造 | ✅ S1 |
| 结果容器 | lib `qr.mbt` | `QRCode::size()`、`QRCode::get(row,col)`、`QRCode` 元数据访问器 | ✅ S1/S3/S6 |
| 端到端产码 | lib `qr.mbt` | `QRBuilder::build()` / `QRCode::build` | ✅ S5/S6 |
| 终端输出骨架 | lib `helpers.mbt` | 当前仅注释骨架（见 §2.2） | ⏳ S7 |
| 公共枚举 | lib `ecl/version/mode/mask.mbt` | 供 SVG 示例/测试 | ✅ S1 |

#### 2.2 现状缺口（本次要落地）
1. **`helpers.mbt` 仍是注释骨架**：无 `to_str`/`print`/`print_matrix_with_margin` 任何逻辑。
2. **`QRCode` 无终端/SVG 渲染方法**：参考在 `QRCode` 上提供 `to_str()`/`print()`；MoonBit 侧当前只有
   `get/set/data/meta/size/version/ecl/mask/mode`，无行切片索引（S7 用 `get(row,col)` 逐格等价即可，
   不必加切片）。
3. **无任何 SVG 相关文件/类型**：`Shape`/`SvgBuilder`/`rgba2hex`/`Color` 均未落地（本仓库从 S1-S6 一直
   聚焦编码管线，convert 输出层从未进入）。
4. **README 文档索引 / roadmap** 无 S7 方案链接；CLI（`cmd/main/main.mbt`）仍只打印字面量、未调库
   （M1 记录里「CLI 输出依赖 to_str」的欠账顺延至今，见 §4.5/§6）。

#### 2.3 参考源码核验（对照 `/tmp/fast_qr_src`，fast_qr v0.14.0 `53e8c99`）

**`helpers.rs`（74 行）——终端画算法**：常量 `EMPTY=' '`、`BLOCK='█'`、`TOP='▀'`、`BOTTOM='▄'`；
`print_line(line1,line2,size)` 两行合一：对每列 `i` 按 `(line1[i].value(), line2[i].value())` 四态映射
`(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'`；`print_matrix_with_margin(qr)` 在**上/下/左/右
各补一条明暗全白/全黑边**（边距用 `Module::empty`），奇数行末单行补 `BLOCK`。**逐字符语义已在源码第
32-56 行核验**（含 `for i in (0..size-1).step_by(2)` 只处理偶数对、末奇数行单独处理、首行 `out.push(BOTTOM)`
的左边距 = `BOTTOM` 而非 `BLOCK` 的细节）。`qr.rs:174-185` 上 `to_str()` 直接委托 `print_matrix_with_margin`，
`print()` 走 `println!("{}", ...)`。

**`convert/mod.rs`（381 行）+ `convert/svg.rs`（343 行）——SVG 子集**：
- `Shape` 6 种：`Square`/`Circle`/`RoundedSquare`/`Vertical`/`Horizontal`/`Diamond`（`Command` 自定义形状
  仅非 WASM 目标，S7 可按需省略）；各形状为 `fn(y,x,module)->String` 返回单格 path 片段：
  `square`=`M{x},{y}h1v1h-1`、`circle`=`M{},{}…a.5,…`、`rounded_square`=`M{x}.2,…z`、`vertical`=`M{x}.1,…`、
  `horizontal`=`M{x},{y}.1h1v.8h-1`、`diamond`=`M{x}.5,{y}l.5,.5…z`。
- `Color`/`rgba2hex`：`[r,g,b,a]` → `#rrggbb`（alpha=255 省略），支持 3/4 字节数组入参。
- `SvgBuilder` 字段默认：`margin=4`、`background_color="#ffffff"`、`dot_color="#000000"`、`commands` 空
  （空则用 `[Shape::square]`）。`path(qr)`：遍历 `qr.size²`，跳过 `value()==false`（非暗）格，把每个暗格的
  path 片段拼进 `<path d="…"/>`（`rounded_square` 额外带 `.3` 描边）；`to_str(qr)` 输出
  `<svg viewBox="0 0 {W} {W}" …><rect width="{W}px" …/><path …/>{image}</svg>`（`W = margin*2+n`）。
- `tests/svg.rs`（51 行）只做「包含性」断言（`svg.contains(expected)`，非全串快照），但 S7 建议比参考更严的
  **全串逐字节快照**（参考输出确定，可直接比）。

> 结论：S7 的 to_str/SVG 都是**纯确定性字符串渲染**（无随机、无 IO、无外部依赖），输出完全由 `QRCode`
> 矩阵与少量参数决定——因此可复用 S4-S6 已验证的「**具备 Rust 环境一次生成参考输出 JSON → 转 MoonBit
> 常量 → 逐字节比对**」快照链路，做**全串对齐**（比参考自身 tests 的 contains 断言更严）。

---

### 3. 关键架构决策与逐文件落地清单

#### 3.1 决策 D8：`to_str`/`print` 落在 lib 公共层 `helpers.mbt`，给 `QRCode` 加方法
- **问题**：参考在 `QRCode` 上直接提供 `to_str()`/`print()`（`qr.rs:174-185`），底层 `helpers.rs` 提供
  `print_matrix_with_margin`。MoonBit 侧 `helpers.mbt` 已作为 lib 公共层文件占位（注释骨架）。
- **方案**：在 `helpers.mbt` 实现 `print_matrix_with_margin(qr : QRCode) -> String`（顶层函数，仅读
  `Module::value`），并给 `QRCode` 加两个**实例方法**（`to_str` / `print`）委托它：
  ```
  pub fn QRCode::to_str(self : QRCode) -> String
  pub fn QRCode::print(self : QRCode) -> Unit
  ```
  - `to_str` 返回值 = `helpers::print_matrix_with_margin(self)`（与参考 `to_str` 委托 `helpers` 同构）；
  - `print` = `println(to_str())`（MoonBit 终端打印；`wasm-gc` 后端的 `println` 走
    `spectest.print_char` 已在 README「编译为 Wasm」验证，S7 沿用）。
  - 只依赖 `Module::value()`（公共），无需 internal 访问。
- 可选拆分：`helpers.mbt` 保持为「终端渲染」单职责文件（对齐 roadmap B11「helpers.rs → 输出层」），
  `to_str`/`print` 方法也可直接内联在 `qr.mbt`（参考即在 qr.rs 上），实现时二选一——推荐**方法放 qr.mbt、
  纯渲染函数放 helpers.mbt**（对齐参考：helpers 供打印、qr 供便捷方法）。

#### 3.2 决策 D9：`Shape`/`SvgBuilder` 落 lib 公共层，SVG 渲染为纯字符串拼接、无 feature 门
- **问题**：参考 SVG 在 `feature="svg"` 后（Cargo feature）；本仓库为**纯 MoonBit 库，无 Cargo feature 机制**
  （AGENTS §二.3「js 已移除，保留 wasm-gc/wasm 双后端」），且无 `wasm-bindgen`。
- **方案**：不引入 feature 门，SVG 作为 lib 公共面常驻提供（轻、纯字符串）。新增公共文件/结构：
  - **`Shape` 枚举**：`Square`/`Circle`/`RoundedSquare`/`Vertical`/`Horizontal`/`Diamond` 6 变体，放
    `lib/shape.mbt`（或 `helpers` 内）；`Command`（fn 字段）S7 默认不落（或按需加一个接受
    `(Int,Int,Module)->String` 的函数字段变体）——需注意 MoonBit 枚举带函数字段的可比较/derive 限制
    （参考因函数指针比较 lint 手动实现 Eq/Ord），S7 若只做 6 固定形状可 `derive(Eq)` 简化。
  - **`SvgBuilder` struct**：字段 `margin=4`、`background_color:String="#ffffff"`、`dot_color:String="#000000"`、
    `shapes:Array[Shape]`（空则默认 Square）；不可变链式 setter `margin`/`shape`/`module_color`/
    `background_color` 返回新 `SvgBuilder`（对齐 S6 已确立的 MoonBit 值语义惯例，参考为 `&mut` 可变借用）。
  - **`to_str(qr) -> String`**：纯拼接 `viewBox/rect/path`（按参考 §2.3 逐字生成），逐格
    `if not cell.value(): continue` → 每暗格拼 shape path → `<path d="…"/>`。
  - **颜色入参简化**：参考支持 `Color`（String/字节数组多态 via `From`）。MoonBit 无 trait 多态，
    S7 用 `String` 直接收色（`module_color("#000000")`、`background_color("#ffffff")`），不做 `[u8;4]`
    入参重载（如需 `rgba2hex` 可作为公共工具函数单列，供调用方自行转 hex）。
- 位置：SVG 相关放 `lib/svg.mbt`（新增），与 `helpers.mbt`（终端）并列，均 lib 公共包内，零 internal 依赖。

#### 3.3 逐文件落地清单

| 文件 | 改动 | 目的 |
|------|------|------|
| `lib/helpers.mbt` | 用真实逻辑替换注释骨架：`print_matrix_with_margin(qr)->String`（含 EMPTY/BLOCK/TOP/BOTTOM 常量 + 四态映射 + 边距两行合一）| 终端画渲染（B11）|
| `lib/qr.mbt` | 给 `QRCode` 加 `to_str()` / `print()` 实例方法（委托 helpers）| 对齐参考 `qr.rs:174-185` 便捷方法 |
| `lib/svg.mbt`（新增）| `Shape` 枚举 + `SvgBuilder`（margin/shape/module_color/background_color 值语义 setter）+ `to_str(qr)`（viewBox/rect/path 纯拼接）；可选公共 `rgba2hex` | SVG 输出（B11 子集）|
| `lib/helpers_wbtest.mbt` / `lib/svg_wbtest.mbt`（新增或并入测试）| 终端画 / SVG 的**全串快照**逐字节对齐 test（含 V01 短码 + 有边界 V 的复现码）| 输出对齐（§5）|
| `README.md` | 文档索引表 + S7 方案链接；功能特性/快速开始补「输出」一行 | 文档索引收口 |
| （可选）`cmd/main/main.mbt` | 调 `QRBuilder` + `.to_str()` 打印一个真实码（M1「CLI 输出」欠账落地）| 端到端可运行示例 |

- **不改动** internal 任何层（S7 是纯输出壳，编码管线 S1-S6 已锁；`to_str`/SVG 只消费 `Module::value` 与
  `QRCode::size/get`）。
- `Shape`/`SvgBuilder` 用 `pub` 暴露；`Shape` 6 固定变体 `derive(Eq, Debug)`；字段内部化经构造 + setter
  （对齐 S6 `QRBuilder` `pub(all)` 惯例，实现时定）。

#### 3.4 错误面
- 终端画 / SVG `to_str` 均**无错误返回**（纯字符串），沿用 `pub fn … -> String`，无需新增错误类型。
- SVG 的 `to_file`（文件 IO）S7 不做；`Shape` 自定义 `Command` 若不落则无 `panic` 面。

---

### 4. 关键实现语义核对清单（写代码前须对照参考源码核验）

| # | 语义 | 参考锚点 | 落地要点 |
|:-:|------|---------|---------|
| 1 | 终端画四态映射 | `helpers.rs` `print_line` | `(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'`——**勿弄反 TOP/BOTTOM** |
| 2 | 终端画边距构成 | `helpers.rs` `print_matrix_with_margin` | 上边距用 `[empty(true);177]`+`[empty(false);177]`（明暗对）；每 `BLOCK` 左/右边距；首行 `out.push(BOTTOM)` 是左边距；`step_by(2)` 只处理偶数对行、末奇数行单独补 |
| 3 | 矩阵行读取 | `qr.rs` 行切片 vs MoonBit `QRCode::get` | MoonBit 无行切片，用双层 `for row/col` + `get(row,col)` 等价读取，结果逐字符一致 |
| 4 | SVG 跳过亮格 | `svg.rs` `if !cell.value() { continue; }` | 只对 `value()==true`（暗）格拼 path；`module_color` 填充暗格 |
| 5 | SVG 默认参数 | `svg.rs` `Default` | `margin=4`、`background="#ffffff"`、`dot="#000000"`、空 shapes → Square |
| 6 | SVG path 形状片段 | `mod.rs` `Shape::square/circle/…` | 各形状 `format` 参数顺序为 `(y,x)`：`square(y,x,…)` 输出 `M{x},{y}h1v1h-1`；**shape→path 用 `(row= y, col= x)` 展开，勿 x/y 颠倒** |
| 7 | rounded_square 描边特判 | `svg.rs` `path()` | 仅 rounded_square 额外加 `stroke-width=".3" stroke-linejoin="round" stroke="{color}"` |
| 8 | `viewBox`/`rect` 尺寸 | `svg.rs` `to_str` | `W = margin*2 + qr.size`；`viewBox="0 0 {W} {W}"`、`<rect width="{W}px" height="{W}px" fill="{bg}"/>` |
| 9 | 空 shapes 退化为 Square | `svg.rs` `path()` `DEFAULT_COMMAND` | 未调 `shape()` 时用 `[Shape::square]`（即默认方形 SVG） |
| 10 | 全串快照 vs contains | `tests/svg.rs` 风格 | S7 建议比参考更严的**全串逐字节**快照（参考输出确定可复现）|
| 11 | `.mbti` 契约：新增公共 `Shape`/`SvgBuilder`/`to_str` 属预期 | AGENTS §二.4 | `moon info` 应体现新增公共 API，属预期变更非破坏 |
| 12 | wasm-gc `println` 可用性 | README「编译为 Wasm」 | `print` 走 `spectest.print_char`，wasm-gc 后端已验证可打印；`wasm` 后端走 WASI stdout |

---

### 5. 测试与验收

#### 5.1 前提：一次具备 Rust 环境生成终端画 + SVG 参考输出快照（复用 S4-S6 工具链）
- `scripts/setup-rust.sh` 已在仓库（供开发环境做 MoonBit↔Rust 对比，不入 push CI）。
- 在 `/fast_qr` 新增/扩展生成器（如 `snapshot_gen_s7.rs`）：对一组 (content, ecl?, version?, mask?) 输入，
  用参考 `QRCode::to_str()`（helpers）与 `SvgBuilder::default().shape(…).to_str(qr)` 各产出**完整输出串**，
  写成 JSON 常量。
- 产出入库为 MoonBit 测试常量数组（终端画一组 + SVG 一组），比对 test 逐字节 diff。

#### 5.2 快照用例构成（roadmap `tests/svg.rs` 风格扩展）
- **终端画**：短码（V01 "Hello World!"）+ 中码（V05 含 finder/对齐/时序的多图案）+ 一个较长码
  （覆盖满行、对齐图案、版本信息区触发 V14+ 的 to_str 视觉）；断言 `to_str()` 全串与参考一致。
- **SVG**：同输入 × `SvgBuilder::default()`（默认方形）+ `shape(Shape::Square/Circle/RoundedSquare/
  Vertical/Horizontal/Diamond)` 各一条，断言 `<svg>` 全串与参考逐字节一致（比参考 contains 更严）。
- 可选：`rgba2hex` 边界（alpha=255 省略 / alpha≠255 追加两位）。

#### 5.3 公共面黑盒用例
- `QRCode::to_str()` == `helpers::print_matrix_with_margin(qr)`（委托等值护栏）；
- `SvgBuilder::default().to_str(qr)`（空 shapes）== 显式 `shape(Square)` 结果（默认退化护栏）；
- `print()` 无副作用（返回 Unit，仅走 stdout）——黑盒只测 `to_str`，`print` 人工目测/CLI 冒烟。

#### 5.4 门禁（沿用 AGENTS §二.4）
```bash
moon fmt && moon info && moon check --deny-warn && moon test   # 预期 94 → 更多（随快照条数）
for t in wasm-gc wasm; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done
```
- `.mbti` 护栏：`Shape`/`SvgBuilder`/`to_str`/`print` 新增公共 API 属预期；internal 层零改动则 internal
  各 `.mbti` 不变。
- 不得入库构建产物（`_build/`、`*.wasm`、`*.mbti` 已 gitignore）；参考源码 `/tmp/fast_qr_src` 不入库。

#### 5.5 验收 = S7 输出面达成
终端画与 SVG 全串快照逐字节对齐（含 6 形状 + 多版本码）+
门禁全绿（wasm-gc / wasm 双后端）+ README 索引更新 = S7 达成。S7 属 roadmap §4.4 的「输出面补齐」，
不新增 M 里程碑；达成为后续 S8（internal 拆包信号）/ S9（性能，三基准点）铺平。

---

### 6. 提交切分（每批一提交，消息 `feat(qr): …`）
1. **终端画 to_str/print**：`lib/helpers.mbt` 真实实现 + `lib/qr.mbt` 加 `to_str`/`print` + 终端画全串快照
   test（提交：`feat(qr): S7 QRCode to_str/print 终端画输出（对齐 helpers.rs）`）。
2. **SVG 输出**：`lib/svg.mbt`（`Shape` + `SvgBuilder` + `to_str`）+ SVG 全串快照 test
   （提交：`feat(qr): S7 公共 SvgBuilder 输出（对齐 convert/svg.rs 子集）`）。
3. **收尾**：README / roadmap 状态更新（S7 记为完成、S8/S9 下一步）、文档索引；可选 CLI 示例。

---

### 7. 风险与评估

| 风险/难点 | 评估与对策 |
|-----------|-----------|
| 终端画 Unicode 半块视觉难人工核对 | 不靠目测，靠**全串逐字节参考快照**对齐（参考输出确定）；快照生成禁止手抄 |
| SVG path 片段 x/y 易颠倒、形状参数易错 | §4 核对清单 #4/#6/#7 铁律 + 6 形状各一条全串快照兜底（fast_qr tests/svg.rs 已有 contains 佐证，S7 用全串更严）|
| to_str 需逐行逐格遍历 `QRCode`，无行切片 | MoonBit `get(row,col)` 双层循环即可，纯读取零 internal 依赖；性能非本阶段目标 |
| SVG feature / resvg / image / wasm 依赖缺失 | 范围裁剪：纯库无 feature 门，SVG 常驻公共面；image（resvg）与 wasm 宿主嵌图子集明确不做/按需（§1.2）|
| MoonBit `println` 在 wasm 后端可用性 | `to_str` 与 `print` 分离：快照只测 `to_str`（纯字符串，全后端一致）；`print` 走 `println`，wasm-gc 已验证（README），wasm 走 WASI——CLI/人工冒烟即可 |
| `Shape::Command`（fn 字段）derive 限制 | S7 默认只落 6 固定形状（`derive(Eq)` 无碍）；`Command` 若需扩展再按函数字段枚举单独处理比较 |
| M1「CLI 输出」欠账 | 顺延多年的「CLI 调用库输出真实码」在本 S7 落地：to_str 就绪后 CLI 可 `QRBuilder` + `.to_str()` 打印，属可选项 |

> 一句话评估：S7 是**纯确定性字符串渲染**（终端画 + SVG），逻辑量小（helpers ~30 行、SVG 子集 ~150 行）、
> 零 internal 依赖、无外部运行时依赖；工作量集中在「生成参考输出快照（需一次 Rust 环境）+ 落逐字节比对
> test + 两个输出 API」。最大不确定性是 SVG path 片段的精确复刻与终端画边距的细节——均用**参考全串快照**
> 一次性锁死。S7 达成即补齐 roadmap 输出面，为 S8/S9 收尾。

---

### 8. 参考
- [moonbit-重写-roadmap-详细分析.md](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.3/§4.4 — roadmap S7 / B11 / 输出面
- [跨语言重写评估.md](../移植参考/专有概念/跨语言重写评估.md) §4-5 — PNG（image.rs）裁剪为位图绘制建议、
  输出层纯字符串直译
- [fast-qr-接口.md](../移植参考/fast-qr-接口.md) §1.2/§1.4 — QRCode `to_str`/`print`、`SvgBuilder`/`Shape` API
- [fast-qr-架构.md](../移植参考/fast-qr-架构.md) §转换输出子系统 — convert 只读矩阵、feature 关系
- [convert-输出转换.md](../移植参考/模块/convert-输出转换.md) — SvgBuilder 结构/形状/透明度语义
- [S6-端到端对齐与公共API.md](S6-端到端对齐与公共API.md) §1.2 — S7 划出（to_str/SVG 非 S6）
- [S1-数据结构.md](S1-数据结构.md) — helpers.to_str 输出归属 S7（B11）
- 参考源码 fast_qr v0.14.0：`src/helpers.rs`、`src/qr.rs:174-185`、`src/convert/{mod,svg}.rs`、`src/tests/svg.rs`

---

## 实现记录

> 承接 本文件「实现方案」部分（PR #36）与
> 本文件「评估与优化」部分（PR #37）
> 落地 S7 两块交付：**终端画 `to_str`/`print`**（对齐 `helpers.rs`，补 M1「CLI 输出」欠账）+
> **公共 `SvgBuilder`/`Shape` SVG 字符串输出**（对齐 `convert/svg.rs` 纯字符串子集）。属 roadmap
> §4.4「输出面补齐」非 M 里程碑，纯确定性字符串渲染，参考**全串逐字节快照**对齐（比 tests/svg.rs 的
> contains 更严）。
>
> 日期：2026-09-06　｜　基线：main（PR #37 已合，**94 个 test 块**）　｜　落地后测试 **94 → 109（净 +15）**，
> wasm-gc / wasm 双后端 release 全绿；无构建产物入库；参考数据由 Rust fast_qr v0.14.0（`53e8c99`）一次生成
> （本记录配套 `/tmp/fast_qr` 检出，不入库）。

---

### 0. 一句话结论

S7 两块交付全部达成：
- **S7-1（终端画）**：`helpers.mbt` 落地 `print_matrix_with_margin`（四态映射 / 上边距两行合一 / 末行合并，
  逐字符对齐 `helpers.rs`）+ `QRCode::to_str`/`print`（委托，对齐 `qr.rs:174-185`）。
- **S7-2（SVG）**：`lib/shape.mbt` 公共 `Shape` 枚举 + 名字↔枚举双向映射；`lib/svg.mbt` 公共 `SvgBuilder`
  （margin/shape/module_color/background_color 值语义 setter + `to_str(qr)`）纯字符串 SVG，6 形状 path 片段
  集中常量定义、rounded 描边特判、多 shape → 多 `<path>`、坐标已含 margin（对齐 `convert/{mod,svg}.rs` 子集）。
- 用参考**全串字节对齐**快照 + CLI 真码输出收口，**未发现正确性 bug**。

---

### 1. 交付清单（对照方案 §3.3/§6）

| 批次 | 落点 | 交付 | 验证 |
|:---:|------|------|------|
| 1 S7-1 | lib `helpers.mbt` | `print_matrix_with_margin(qr)->String`（EMPTY/BLOCK/TOP/BOTTOM 四态 + 边距两行合一 + 末行）| 终端全串快照（真实 V01/V05 + 受控 7×7）|
| 1 S7-1 | lib `qr.mbt` | `QRCode::to_str()` / `QRCode::print()`（委托 helpers）| 委托护栏 + 终端全串 |
| 2 S7-2 | lib `shape.mbt`（新增）| `Shape` 6 变体（derive Eq）+ `Shape::name` / `Shape::from_name`（ASCII 折叠）| 名字↔枚举映射 |
| 2 S7-2 | lib `svg.mbt`（新增）| `SvgBuilder`（margin/shape/module_color/background_color 值语义）+ `to_str(qr)` | 受控矩阵 ×6 形状 + 多 shape + 真实 V01 全串 |
| 3 收尾 | `cmd/main/main.mbt` | 真码终端画 + SVG 输出（补 M1 CLI 欠账）| `moon run cmd/main` 冒烟 |
| 3 收尾 | README / roadmap | S7 记完成、下一步 S8/S9；本记录 + README 索引 | 无死链 |

依赖：`lib/svg.mbt`/`lib/shape.mbt` 零 internal 依赖（只消费 `QRCode::size/get` 与 `Module::value` 公共 API）；
新增测试文件在 lib 公共包内；`cmd/main` 新增对 `lib` 的 `@lib` import。internal 层零改动。

---

### 2. 关键实现语义（逐字符对照参考源码核验）

#### 2.1 终端画（`helpers.rs` `print_matrix_with_margin`）
- 四态映射（真 = Module DARK）：`(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'`；
  上边距两行合一实为整行 `▄`（`(empty(true),empty(false))→'▄'`），**非「白底实块」直观视觉**——快照锁定。
- 结构：首行 `▄`+size×`▄`+`▄`+`\n`；中间 `(0..size-1).step_by(2)` 两行合一每行左/右 `█`+换行；
  末行（size 恒奇数）`qr[size-1]` 与全亮 `empty(false)` 合并，右缘 `█` **无末尾换行**（对齐参考）。

#### 2.2 SVG（`convert/{mod,svg}.rs` 子集）
- `Shape` 6 形状 path 片段集中为常量（对齐 `mod.rs` `Shape::square/circle/...`，坐标 `(y,x)` 已含 margin）：
  `Square=M{x},{y}h1v1h-1`、`Circle=M{x+1},{y}.5a.5,.5 0 1,1 0,-.1`（首坐标 x+1 整数）、
  `RoundedSquare=M{x}.2,{y}.2 {x}.8,{y}.2 {x}.8,{y}.8 {x}.2,{y}.8z`、`Vertical=M{x}.1,{y}h.8v1h-.8`、
  `Horizontal=M{x},{y}.1h1v.8h-1`、`Diamond=M{x}.5,{y}l.5,.5l-.5,.5l-.5,-.5z`。
- `to_str` 结构：`<svg viewBox="0 0 {W} {W}" xmlns=…><rect width="{W}px"…/>` + N 个 `<path d="…"/>` +
  `</svg>`，整串一行无分隔（W = margin*2+n）。**rounded 的 `<path>` 尾部为
  `…z" stroke-width=".3" stroke-linejoin="round" stroke="{color}" fill="{color}"/>`**（含 d 收尾引号与描边，
  不复加第二个 `"`）；非 rounded 为 `…" fill="{color}"/>`。默认 shapes 空 → 退化 `[Square]`。
- 只渲染 `value()==true`（暗）格，跳过亮格；`shape_color`/`image` 子集 S7 明确不做。

---

### 3. 验证与对齐

#### 3.1 参考全串字节对齐快照
参考数据由 Rust fast_qr v0.14.0 例程一次生成（禁止手抄），覆盖：
| 覆盖 | 条数 | 说明 |
|------|:---:|------|
| 终端真实 V01（"hi" Byte/L/V01/mask0）| 1 | 短码 to_str 全串 |
| 终端真实 V05（"HELLO WORLD…" Byte/L/V05/mask3）| 1 | 含对齐/时序/finder 多图案 |
| 终端受控 7×7 小矩阵 | 1 | 锁边距/末行/四态细节 |
| SVG 受控 7×7 × 6 形状 + 默认退化 + 多 shape | 8 | 锁各 path 片段/圆角描边/多 `<path>`/跳过亮格 |
| SVG 真实 V01 默认方形 | 1 | build→SvgBuilder 端到端 |
| **合计净增** | **12 test** | 全部 0 差异 |

另含 3 个护栏（委托 `to_str`==`print_matrix_with_margin`、默认退化==显式 Square、自定义参数生效）。

#### 3.2 CLI 冒烟（补 M1 欠账）
`cmd/main` 现 `QRBuilder::from_string("https://example.com/").build()` 真码，先 `println(to_str())` 打印终端画，
再 `SvgBuilder::default().to_str()` 打印 SVG（截前 200 字符示意）；wasm-gc 后端运行正常。

#### 3.3 门禁（AGENTS §二.4）
`moon fmt`、`moon info`、`moon check --deny-warn`、`moon test` 全绿（测试 94 → **109**，净 +15）；
wasm-gc / wasm 双后端 release 构建 + `moon test --target` 通过；`git status` 无 `.mbti`/`_build` 产物入库。
`.mbti` 护栏：lib 新增 `Shape`/`SvgBuilder`/`to_str`/`print` 公共 API 属预期变更；internal 各 `.mbti` 不变。

---

### 4. 遗留（后续批次）

- **S8（internal 拆包）**：roadmap §4.2 下一步（文件过多/分层信号时做）。
- **S9（性能）**：移植三基准点 V03H/V10H/V40H（`https://example.com/` 输入）透明对比。
- **SVG `image`/`shape_color` 嵌图子集**、**PNG（image.rs）**、**wasm 宿主导出面**：S7 明确不做 / 按需二期。

---

### 5. 参考
- 本文件「实现方案」部分、
  本文件「评估与优化」部分、
  [moonbit-重写-roadmap-详细分析.md](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.4
- [fast-qr-接口.md](../移植参考/fast-qr-接口.md) §1.2/§1.4、[convert-输出转换.md](../移植参考/模块/convert-输出转换.md)
- 参考源码 fast_qr v0.14.0（`53e8c99`）：`src/helpers.rs`、`src/qr.rs:174-185`、`src/convert/{mod,svg}.rs`

---

## 评估与优化

> 复核已合入的 本文件「实现方案」部分（PR #36），
> 目标：**独立重读仓库代码与既有文档 + 检出 fast_qr v0.14.0 参考源码（commit `53e8c99`）逐行核对**，
> 找出方案中「与参考源码不一致 / 语义清单缺漏 / 可优化点」，供 S7 实现阶段直接执行前兜底。
> 结论：**方案方向正确、无致命漏洞**；但发现 **4 处值得补进语义清单/落地清单的核对缺口** 与
> 若干优化建议（详见 §2/§3）。
>
> 日期：2026-09-06　｜　复核基线：main（PR #36 已合，S7 方案 270 行为权威前向计划）。
> 参考源码复核介质：本评审临时 `git clone --depth 1 https://github.com/erwanvivien/fast_qr`
> 于 `/tmp/fast_qr`（v0.14.0，`53e8c99`），与方案 §0 所述介质一致，不入库。

---

### 0. 一句话结论

S7 两块交付（终端 `to_str`/`print` + SVG `SvgBuilder`）定位为「输出面补齐」、纯确定性字符串渲染的判定准确；
复用 S4-S6「Rust 一次生成参考全串快照 → 逐字节对齐」链路**比参考 tests/svg.rs 的 contains 更严**的策略正确。
本评审**独立检出参考源码逐行复核**，确认方案 §2.3/§4 的核心语义转述**基本准确**，但可**补 4 处易翻车的精确
核对点**（circle 形状特例、`<svg>` 的 `xmlns`、多 shape → 多 `<path>`、坐标已含 margin 的语义），并给出若干
实现/测试层面的优化建议。方案无需重写，建议把本记录 §2 清单并入实现时的最终核对表。

---

### 1. 复核范围与基线（独立重读 + 参考源码逐行核对）

| 对象 | 复核点 | 复核结论 |
|------|--------|---------|
| `lib/module.mbt` / `lib/qr.mbt` | `Module::value()`（true=DARK）、`QRCode::size/get` 是否满足输出层只读消费 | ✅ 一致（`value()` bit0 明暗、`get(row,col)` 行主序） |
| `lib/helpers.mbt` | 当前确为注释骨架（方案 §2.2 缺口 1 属实） | ✅ 属实 |
| `cmd/main/main.mbt` | 当前仅 `println` 字面量、未调库（方案 §1「补 M1 CLI 输出欠账」属实） | ✅ 属实 |
| README / roadmap | S7 方案链接、§4.2 指引、M2/M3 里程碑定位 | ✅ 已收口 |
| fast_qr `src/helpers.rs` | 四态映射 / 边距构成 / 末行处理 | ✅ 转述准确（见 §2.1） |
| fast_qr `src/qr.rs:174-185` | `to_str` 委托 `helpers`、`print` 走 `println` | ✅ 转述准确 |
| fast_qr `src/convert/{mod,svg}.rs` | Shape 6 path 片段 / `SvgBuilder` 默认值 / `to_str`/`path` 结构 | ⚠️ 大体准确，4 处需补精确核对点（见 §2） |
| fast_qr `src/tests/svg.rs` | 确为 `contains`（非全串） | ✅ 方案比参考更严的判定属实 |

---

### 2. 发现：与参考源码核对后需补进 S7 方案的精确核对点

以下均为**逐行读参考源码**得到、方案 §2.3/§4 语义清单**未显式列出或转述略粗**、且易在手写时翻车、
但**全串快照都能兜底**的点。建议实现前并入最终核对表（补进 §4 核对清单或作为本记录引用）。

#### 2.1 终端画：四态映射转述正确，但补充「非白底视觉」观察
- 方案 §4 #1 的 `(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'` **与源码 `print_line` 完全一致**（真=DARK）。
- **补充观察**：参考 `Module::DARK=true`，但该映射把「两行皆暗」打成空格、把「全亮」打成 `█`，**并非直观的
  「黑模块→实块」白底画**；顶边距 `[empty(true);177]` + `[empty(false);177]` 两行合一实际整行输出 `▄`
  （`(真,假)→'▄'`）。因此**勿凭视觉臆测，务必用参考工具生成全串快照锁定**；方案 §7「不靠目测、靠全串快照」
  是对的，此处仅为强化该风险提示。
- 奇数边长（QR 尺寸恒为 `version*4+17`，恒奇数）下 `(0..size-1).step_by(2)` 覆盖除末行外所有行，末行单独与
  `[empty(false);177]`（全亮下行）合并；**偶数尺寸分支在真实 QR 上不可达**，无需特判。

#### 2.2 SVG：`<svg>` 起始标签含 `xmlns`，方案 §4 #8 清单未显式列出
- 参考 `svg.rs::to_str` 起始标签是 `<svg viewBox="0 0 {W} {W}" xmlns="http://www.w3.org/2000/svg">`——
  **`viewBox` 之外还有 `xmlns`**。方案 §4 #8 只写了 `viewBox`/`<rect>` 尺寸与色，未列出 `xmlns`；
  且**各元素间无任何空格/换行分隔**，整个 SVG 是一整行（`<svg …><rect …/><path …/></svg>`）。
- 全串快照能兜底，但清单补这两点（xmlns + 单行无分隔）可让手写先一次到位。

#### 2.3 SVG：`circle` 形状 path 是全部 6 个中最易抄错的特例
- 参考 `circle(y, x, _) = format!("M{},{y}.5a.5,.5 0 1,1 0,-.1", x + 1)`，即实际输出为
  `M{x+1},{y}.5a.5,.5 0 1,1 0,-.1`——**第一个坐标是 `x+1` 且为整数无小数**、第二个是 `{y}.5`（带 `.5`），
  不是直观的 `M{x},{y}...`。
- 方案 §2.3 对 circle 只写了 `M{},{}…a.5,…`，过于粗。建议实现时以「整串常量格式串 + 占位」照抄，快照仍为最终兜底。

#### 2.4 SVG：多 shape → 多个 `<path>`；坐标传给 shape 时**已含 margin**
- 参考 `path()`：commands 为空用 `[square]`（方案 §4 #9 正确）；用户调 `shape(A).shape(B)` 时**每个 command
  各产一个 `<path>`**，最后 `join("")` 串联（`<path d="…"/><path d="…"/>`）。方案把字段设计为
  `shapes:Array[Shape]`，实现须还原「N 个 shape → N 个顺序 `<path>`」。
- 且 shape 被调用为 `command(y + margin, x + margin, cell)`——**传入 shape 的 y/x 已是 row+margin / col+margin**。
  方案 §4 #6「勿 x/y 颠倒」方向对，但需再强调：写进 shape 片段的是**加过 margin 的坐标**，不是原始 row/col
  （快照会精确校验）。
- 每命令取色：无 `shape_color`（S7 已裁）时全部落到 `dot_color`；仅 rounded_square 的 `<path>` 额外加
  `stroke-width=".3" stroke-linejoin="round" stroke="{color}"`（方案 §4 #7 正确）。

---

### 3. 优化 / 待办建议（非阻断）

| # | 建议 | 理由 |
|:-:|------|------|
| 1 | **补 `Shape` ↔ 名字符串的双向映射工具**（`square/circle/.../rounded_square` ↔ 枚举），对齐参考 `From<Shape> for &str` / `From<String> for Shape`。 | S7 现只落 6 固定枚举、无 `Command`；但参考/未来 wasm `qr_svg` 都按字符串名选形状，先补一个轻量映射即可让 CLI/宿主后续无需再造轮子。 |
| 2 | **把 6 形状 path 片段定义为「含占位符的整串常量」集中放一处**（`circle` 等最易抄错的放最醒目位置），集中 + 注释里贴参考原文。 | 降低手抄风险；快照兜底虽稳，集中常量更易 review 对照。 |
| 3 | **快照用例建议加一条「多 shape + rounded_square」**（如 `shape(Square).shape(RoundedSquare)`）以覆盖 §2.4 的「多 `<path>` + rounded 描边特判」。 | 方案 §5.2 的 6 形状各一条是单 shape；多 shape 是参考支持的独立行为，值得单独锁一条。 |
| 4 | **SVG `to_str` 尺寸建议复用 `QRCode::size` 一次取好**、避免循环里反复读；参考 `path` 里 `qr.size` 每次外层 `for y` 现算，MoonBit 逐格遍历可把 `size` 提局部变量。 | 纯微优化，非本阶段（S7 无性能门槛）目标，列作提示。 |
| 5 | 方案 §4 #12 的 `print`/`println` 双后端说明正确；补充一句：**快照只测 `to_str`，`print` 归 CLI/人工冒烟**，与 S6「不把手写视觉当验收」口径一致。 | 已基本覆盖，仅强化。 |

---

### 4. 门禁与收尾（沿用 AGENTS §二.4 / 方案 §5.4）

本记录为**纯文档变更**，未触 MoonBit 代码；不改动 S7 方案已锁定的范围（无 PNG/image、无 wasm 嵌图子集、
无 feature 门、`to_str`/`print` 落 lib 公共层、SVG 常驻）。S7 实现阶段仍按方案 §5.4 门禁执行。

---

### 5. 参考
- 本文件「实现方案」部分 — 被复核的 S7 详细方案（PR #36）
- 参考源码 fast_qr v0.14.0（`53e8c99`）：`src/helpers.rs`、`src/qr.rs:174-185`、`src/convert/{mod,svg}.rs`、`src/tests/svg.rs`
- [moonbit-重写-roadmap-详细分析.md](../03-过程/moonbit-重写-roadmap-详细分析.md) §4.2/§4.4 — S7 / 输出面 / M2-M3

---
