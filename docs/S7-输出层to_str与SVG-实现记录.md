# S7 · 输出层 to_str 终端画 + SVG · 实现记录

> 承接 [S7-输出层to_str与SVG-实现方案](./S7-输出层to_str与SVG-实现方案.md)（PR #36）与
> [S7-输出层to_str与SVG-实现评估与优化-记录](./S7-输出层to_str与SVG-实现评估与优化-记录.md)（PR #37）
> 落地 S7 两块交付：**终端画 `to_str`/`print`**（对齐 `helpers.rs`，补 M1「CLI 输出」欠账）+
> **公共 `SvgBuilder`/`Shape` SVG 字符串输出**（对齐 `convert/svg.rs` 纯字符串子集）。属 roadmap
> §4.4「输出面补齐」非 M 里程碑，纯确定性字符串渲染，参考**全串逐字节快照**对齐（比 tests/svg.rs 的
> contains 更严）。
>
> 日期：2026-09-06　｜　基线：main（PR #37 已合，**94 个 test 块**）　｜　落地后测试 **94 → 109（净 +15）**，
> wasm-gc / wasm 双后端 release 全绿；无构建产物入库；参考数据由 Rust fast_qr v0.14.0（`53e8c99`）一次生成
> （本记录配套 `/tmp/fast_qr` 检出，不入库）。

---

## 0. 一句话结论

S7 两块交付全部达成：
- **S7-1（终端画）**：`helpers.mbt` 落地 `print_matrix_with_margin`（四态映射 / 上边距两行合一 / 末行合并，
  逐字符对齐 `helpers.rs`）+ `QRCode::to_str`/`print`（委托，对齐 `qr.rs:174-185`）。
- **S7-2（SVG）**：`lib/shape.mbt` 公共 `Shape` 枚举 + 名字↔枚举双向映射；`lib/svg.mbt` 公共 `SvgBuilder`
  （margin/shape/module_color/background_color 值语义 setter + `to_str(qr)`）纯字符串 SVG，6 形状 path 片段
  集中常量定义、rounded 描边特判、多 shape → 多 `<path>`、坐标已含 margin（对齐 `convert/{mod,svg}.rs` 子集）。
- 用参考**全串字节对齐**快照 + CLI 真码输出收口，**未发现正确性 bug**。

---

## 1. 交付清单（对照方案 §3.3/§6）

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

## 2. 关键实现语义（逐字符对照参考源码核验）

### 2.1 终端画（`helpers.rs` `print_matrix_with_margin`）
- 四态映射（真 = Module DARK）：`(真,真)→' '`、`(真,假)→'▄'`、`(假,真)→'▀'`、`(假,假)→'█'`；
  上边距两行合一实为整行 `▄`（`(empty(true),empty(false))→'▄'`），**非「白底实块」直观视觉**——快照锁定。
- 结构：首行 `▄`+size×`▄`+`▄`+`\n`；中间 `(0..size-1).step_by(2)` 两行合一每行左/右 `█`+换行；
  末行（size 恒奇数）`qr[size-1]` 与全亮 `empty(false)` 合并，右缘 `█` **无末尾换行**（对齐参考）。

### 2.2 SVG（`convert/{mod,svg}.rs` 子集）
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

## 3. 验证与对齐

### 3.1 参考全串字节对齐快照
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

### 3.2 CLI 冒烟（补 M1 欠账）
`cmd/main` 现 `QRBuilder::from_string("https://example.com/").build()` 真码，先 `println(to_str())` 打印终端画，
再 `SvgBuilder::default().to_str()` 打印 SVG（截前 200 字符示意）；wasm-gc 后端运行正常。

### 3.3 门禁（AGENTS §二.4）
`moon fmt`、`moon info`、`moon check --deny-warn`、`moon test` 全绿（测试 94 → **109**，净 +15）；
wasm-gc / wasm 双后端 release 构建 + `moon test --target` 通过；`git status` 无 `.mbti`/`_build` 产物入库。
`.mbti` 护栏：lib 新增 `Shape`/`SvgBuilder`/`to_str`/`print` 公共 API 属预期变更；internal 各 `.mbti` 不变。

---

## 4. 遗留（后续批次）

- **S8（internal 拆包）**：roadmap §4.2 下一步（文件过多/分层信号时做）。
- **S9（性能）**：移植三基准点 V03H/V10H/V40H（`https://example.com/` 输入）透明对比。
- **SVG `image`/`shape_color` 嵌图子集**、**PNG（image.rs）**、**wasm 宿主导出面**：S7 明确不做 / 按需二期。

---

## 5. 参考
- [S7-输出层to_str与SVG-实现方案.md](./S7-输出层to_str与SVG-实现方案.md)、
  [S7-输出层to_str与SVG-实现评估与优化-记录.md](./S7-输出层to_str与SVG-实现评估与优化-记录.md)、
  [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) §4.2/§4.4
- [fast-qr-接口.md](./移植参考/fast-qr-接口.md) §1.2/§1.4、[convert-输出转换.md](./移植参考/模块/convert-输出转换.md)
- 参考源码 fast_qr v0.14.0（`53e8c99`）：`src/helpers.rs`、`src/qr.rs:174-185`、`src/convert/{mod,svg}.rs`
