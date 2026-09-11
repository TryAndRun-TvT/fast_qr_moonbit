# tryandrun/fast_qr_moonbit

> 基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。
> 纯 MoonBit 实现、无外部依赖，逐位对齐 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr)。

**项目状态**：功能对齐收口（M0–M3 里程碑 ✅），111 单测 + 快照全绿，仅 `wasm-gc` 后端回归通过。

`moon run cmd/main` 的真实输出（内容 `https://example.com/`）：

```text
▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
█ ▄▄▄▄▄ ██▀█  ▀ █▀█ ▄▄▄▄▄ █
█ █   █ █▀█▀█▄ ▀█▄█ █   █ █
█ █▄▄▄█ █▀  █▀█ ███ █▄▄▄█ █
█▄▄▄▄▄▄▄█ ▀ █ █ ▀ █▄▄▄▄▄▄▄█
█▀ ▄▀▀█▄█▀ ▀▄▄▀▄▀▄▀  █ █▀▀█
█▀▄▀██ ▄▀█▀██ █▀▄▀▄█▀▄ ▄█▄█
█▄█ ▄█▄▄ ▄██▀ ▄▄  █  ███▀ █
█▄▄ ▀▄▀▄▀▀ ▀▀▄██▄  ▄▀▀ ▄█▄█
█▄▄▄▄▄▄▄▄▀█▄▄▀███ ▄▄▄ ██▄▀█
█ ▄▄▄▄▄ ██▄ ██ ▀▀ █▄█ ███▄█
█ █   █ ██▀▄ ▄▄ ▄▄ ▄▄ █▀▀▄█
█ █▄▄▄█ █ ▀▄  ▄▀   ▀  ▄█▄▄█
█▄▄▄▄▄▄▄▄█████▄█▄█▄█▄██▄██▄█
```

| | |
|---|---|
| **语言** | [MoonBit](https://www.moonbitlang.cn/)（**仅 `wasm-gc`**；`wasm`(WASI)、`js` 已移除，`native` 受 `supported_targets` 限制） |
| **标准** | ISO/IEC 18004 二维码（版本 1–40，ECL L/M/Q/H，8 掩码评分择优） |
| **许可** | [Apache-2.0](./LICENSE) |
| **参考** | Rust [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 逐位移植对齐 |

---

## 目录

- [功能特性](#功能特性)
- [能力与局限](#能力与局限)
- [快速开始](#快速开始)
- [从源码构建](#从源码构建)
- [编译为 Wasm](#编译为-wasm)
- [性能速览](#性能速览)
- [文档索引](#文档索引)
- [代码放置约定](#代码放置约定方案-3模块根无包库包在-lib)
- [项目结构](#项目结构)
- [开发与 CI](#开发与-ci)
- [问题反馈与贡献](#问题反馈与贡献)
- [License](#license)

---

## 功能特性

- **纯 MoonBit 实现**，无外部依赖，可直接 `moon add` 依赖到你的项目。
- **标准合规**：遵循 ISO/IEC 18004 —— 版本 V01–V40、四种纠错级别（L/M/Q/H）、
  三模式自动编码（Numeric / Alphanumeric / Byte）+ 自动回退、8 种掩码评分择优。
- **逐字节对齐参考**：矩阵与 fast_qr v0.14.0 全量快照逐位一致，可解码读回原文。
- **单后端产物**：仅 `wasm-gc`（体积小、性能好；需支持 wasm-gc 的宿主，见「能力与局限」）。
- **两用接口**：过程式 `QRCode::build` 编排入口 + 链式 `QRBuilder` 便捷构造器。
- **多样输出**：终端字符画（`to_str`/`print`）与 SVG 字符串（`SvgBuilder`，6 种模块形状）。

## 能力与局限

| 能力 | 说明 |
|------|------|
| 编码内容 | **字节（ASCII）** 输入；自动选择 Numeric / Alphanumeric / Byte，也可强制指定模式 |
| 版本/纠错 | 自动最小适配或强制指定版本 V01–V40；ECL 缺省 Quartile(Q)，可显式 L/M/Q/H |
| 掩码 | 自动 8 轮评分择优，或指定固定掩码（走快速路径） |
| 输出 | 终端 Unicode 字符画、SVG 字符串 |

已知局限（诚实声明）：

- **编码模式**仅支持 Byte/Alphanumeric/Numeric；**Kanji 模式暂不支持**（与参考 fast_qr 一致）。
- 输入按 **ASCII 字节** 处理（非 ASCII 多字节字符的语义见 [S6 评审记录](./docs/S6-端到端对齐与公共API.md) 的优化建议）。
- 产物形态面向 **wasm**：MoonBit `Int` 32 位、纠错位流 `KEEP_LAST=33`（取 Rust wasm32 分支），
  对真实 QR 语义无差别（详见 [S9 评估记录](./docs/S9-性能基准.md) §2.4）。
- **仅支持 `wasm-gc`**：`moon.mod` 声明 `supported_targets = "+wasm-gc"`，下游 `native`/JS 消费者会被构建系统
  直接拒绝（实测 `does not support target backend 'native'`）。库本身是纯 MoonBit，此为**有意的分发范围收缩**；
  其中 `native` 另需系统 C 编译器（当前 CI/本地镜像未装）。
- **宿主需支持 wasm-gc（GC 提案）**：如 Node ≥ 22 / V8、启用 GC 的 wasmtime；CLI `println` 依赖
  `spectest.print_char` 导入（非标准 WASI）。`wasm`(WASI) 通用兜底已移除，宿主接入面相应变窄。

---

## 快速开始

在项目根目录（`moon.mod` 所在处）添加本库为依赖：

```bash
# 需本模块已发布至 mooncakes；发布前可 clone 本仓库按「从源码构建」体验
moon add tryandrun/fast_qr_moonbit
```

在 `moon.pkg` 中声明依赖并起别名（本库包路径为 `.../lib`，别名默认即目录名 `lib`）：

```toml
import {
  "tryandrun/fast_qr_moonbit/lib",
}
```

然后即可用 `QRBuilder` 生成二维码（链式设置纠错/版本/掩码）：

```moonbit
/// 由字符串输入构建 QRCode（缺省全部自动：mode 自动、ECL=Q、version 最小、mask 择优）。
fn gen() -> @lib.QRCode {
  match @lib.QRBuilder::from_string("https://example.com/").build() {
    Ok(q) => q
    Err(_) => abort("content too large")
  }
}

fn main {
  let qr = gen()
  // 输出终端 Unicode 半块字符画（含边距）
  println(qr.to_str())
  // 输出 SVG 字符串（默认黑色方块 + 白色背景、margin=4），链式定制颜色与模块形状
  let svg = @lib.SvgBuilder::default()
    .module_color("#0000ff")
    .background_color("#ffffff")
    .shape(@lib.Shape::RoundedSquare)
    .to_str(qr)
  println(svg[:200].to_owned() + "...")
}
```

主要公共类型一览（完整说明见 [文档索引](#文档索引) 各实现方案/记录）：

| 类型 | 位置/说明 |
|------|-----------|
| `ECL` / `Version` / `Mode` / `Mask` | 纠错级别（L/M/Q/H）、版本（V01–V40）、编码模式、掩码枚举 |
| `QRCode` | 生成结果容器（矩阵 + size/version/ecl/mask/mode 元数据 + `to_str`/`print`） |
| `QRCode::build` | 过程式编排入口（input/mode/ecl/version/mask → `Result[QRCode]`） |
| `QRBuilder` | 链式构造器：`from_string`/`new` + `mode/ecl/version/mask` + `build` |
| `Module` / `ModuleType` | 单像素模块（明暗 + 8 种功能归属），供读取/访问 |
| `SvgBuilder` / `Shape` | SVG 字符串输出；6 种模块形状（square/circle/rounded_square/vertical/horizontal/diamond） |
| `QRCodeError` | 构造错误（`EncodedData` 数据过大、`SpecifiedVersion` 版本过小） |

---

## 从源码构建

先安装 MoonBit 工具链：

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

模块根不设包（core 式布局）：库包在 `lib/`，CLI 在 `cmd/main/`，构建需显式给包名。

```bash
moon build lib          # 编译库包
moon build cmd/main     # 编译 CLI
moon run   cmd/main     # 运行 CLI 演示（终端字符画 + SVG）
moon test               # 运行单元/快照测试
```

提交前本地收尾检查（对齐 CI 门禁）：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon info && moon check --deny-warn && moon test
moon build lib --target wasm-gc --release
moon build cmd/main --target wasm-gc --release
moon test --target wasm-gc
```

---

## 编译为 Wasm

`supported_targets = "+wasm-gc"`，唯一后端 `preferred_target = "wasm-gc"`
（`js`、`wasm`(WASI) 均已按项目决策移除）。

> **边界**：该声明会**硬拒绝**非 wasm-gc 目标（下游 `native`/JS 构建直接报
> `does not support target backend`）；宿主须为**支持 GC 的 wasm 运行时**（Node ≥ 22 / V8、启用 GC 的 wasmtime），
> 且 CLI 打印依赖 `spectest.print_char`。取舍与复核见
> [S9n wasm-gc 收敛审计](./docs/S9n-优化方案复评与wasm-gc收敛审计.md) §1。

```bash
# 唯一后端 wasm-gc（体积最小、性能最优，宿主只需提供 spectest.print_char）
moon build cmd/main --release
moon run   cmd/main
```

产物体积（release；复跑 `bash scripts/bench-size.sh`）：

| 产物 | 后端 | raw | `-Oz`（可加载档） |
|------|------|---:|------------------:|
| **`cmd/qr-min`（纯库调用 = 库实际体积）** | **`wasm-gc`** | 41294 B | **31470 B**（30.7 KiB） |
| `cmd/bench`（基准外壳：argv/迭代/`--dump`） | **`wasm-gc`** | 47912 B（46.8 KiB） | 36296 B（35.4 KiB） |
| `cmd/main`（CLI：字符画 + SVG） | **`wasm-gc`** | 44308 B（43.3 KiB） | 33709 B |

> **引用规范**：`cmd/bench` / `cmd/main` 是「命令形态」产物，外壳不随库分发，
> **不能代表库被宿主嵌入时的实际体积**——引用库体积请用 `cmd/qr-min` 口径并注明后端与优化档。
>
> **体积金字塔**（`wasm-gc`，`-Oz`）：运行时地板（一行 `println`）**263 B** → QR 核心净增
> **+31207 B**（`cmd/qr-min`）→ 输出层（终端画 + SVG）+2239 B（`cmd/main`）→ 基准外壳
> +4826 B（`cmd/bench`）。
> **历史注记**：`wasm`(WASI) 兼容后端已移除；其体积/性能自比数据仅作历史记录
> （见 S9g/S9e），不再作为对外口径。
> 与 fast_qr 的逐口径对照见下文表格。

```bash
# -Oz 体积最优档（默认后端 wasm-gc）：
#   --all-features 会开 custom-descriptors(RTT)，其 exact heap type 在 Node/moonrun 上编译不过；
#   --disable-custom-descriptors 才产出「可被真实宿主加载」的最优档。
moon-wasm-opt _build/wasm-gc/release/build/cmd/main/main.wasm \
  --all-features --disable-custom-descriptors -Oz -o main.min.wasm   # 33709 B
```

### 与 fast_qr 的体积对照

**MoonBit 侧一律取默认后端 `wasm-gc`（实际分发形态）**；下表按形态分块，避免「库体积」与
「命令形态」混读。

#### A. 库对库（纯库调用口径 = 对外引用主口径）

两侧同为「核心-only + 一行 `println`」：MoonBit `cmd/qr-min` vs fast_qr 无胶水裸探针：

| 口径（B） | MoonBit `wasm-gc` | fast_qr 裸探针 | ours / fast |
|-----------|------------------:|---------------:|------------:|
| raw | 41294 | 59440 | **0.69×** |
| `-Oz`（可加载档） | **31470** | 45687 | **0.69×** |
| 核心净增（扣 hello 地板 263 / 20052 B） | **+31207** | +25635 | 1.22× |

> **结论**：库对库，`wasm-gc` 在 raw 与 `-Oz` 两档都约 **0.69×**；扣掉运行时地板后核心净增
> 1.22×——差距大头是两侧**运行时地板**（`wasm-gc` 263 B vs Rust 20052 B，76×），非 QR 实现差异。
> raw 档两侧元数据口径不同（fast_qr 侧含 `name`/`target_features` custom 段），以 `-Oz` 为公平档。

#### B. 命令形态 vs 库导出（参考口径）

MoonBit `cmd/bench`（含 argv/迭代/`--dump` 外壳）vs fast_qr `fast_qr_bg`（wasm-bindgen 库导出 + 胶水）：

| 口径（B） | MoonBit `wasm-gc` | fast_qr v0.14.0 | ours / fast |
|-----------|------------------:|----------------:|------------:|
| ① raw | 47912 | 61510 | **0.78×** |
| ② 剥 custom 段 | 47790 | 53476 | **0.89×** |
| ③ `-Oz` | 36296 | 49956 | **0.73×** |
| ④ ③ + 宿主胶水 | 36296（无胶水） | 58173（含 `fast_qr.js` 8217 B） | **0.62×** |

> 该块两侧形态不对称（我方含命令外壳、对方含宿主胶水），仅作参考——**引用库体积请用 A 块**。
> A 块已在 S9i 对称化（此前误用 `cmd/bench` 外壳对撞裸探针，得 0.79×）。
> **历史注记**：`wasm`(WASI) 兼容后端已移除，其体积与性能数据仅作历史记录
> （见 [S9g 确认与修正](./docs/S9g-本项目wasm产物体积-确认与修正.md) ·
> [S9f 实现记录](./docs/S9f-产物体积对比.md)），不再参与对外对比。
> 逐条口径、护栏与归因见 [S9i](./docs/S9i-纯库调用体积探针与库实际体积.md)。

---

## 性能速览

项目自带可复跑基准（`cmd/bench` + `scripts/bench*.sh`；输入 `https://example.com/`=20B、ECL H、
强制 V03/V10/V40、mask 自动择优；数字均为实测取最小）。核心结论：

| 对比 | 结果 | 出处 |
|------|------|------|
| ① vs Rust fast_qr-wasm32（**默认后端 `wasm-gc`**） | 单次 build 慢 ≈**1.8–3.4×**，逐位对齐 sha256 零差异；差距集中在 8 轮掩码择优主循环 | 明细见下表 · [S9j](./docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md) |
| ② vs moonbit 生态 `moonqr`（同宿主、完整实现可比子集） | 本仓库全程快 **2.5–4.1×**（V03H 0.318 vs 0.805、V40H 9.46 vs 38.29 ms/单次） | [S9d](./docs/S9d-与moonbit生态QR包性能对比.md) |
| ③ 产物体积 vs fast_qr | `wasm-gc` 各口径均更小（对称锚点 **0.69×**） | 对照表见 [编译为 Wasm](#编译为-wasm) · [S9i](./docs/S9i-纯库调用体积探针与库实际体积.md) |

### ① vs fast_qr-wasm32：性能明细（S9j 统一「同一 Node 进程内」口径，单次 build）

**MoonBit 侧 = `wasm-gc`（默认后端、实际分发形态）**；两侧逐位对齐 sha256 零差异。
「B 口径 = 单实例摊薄（纯算法边际）」为对外引用主口径：

| 点 | 模块数 | 本仓库 MoonBit(wasm-gc) | fast_qr-wasm32 | fast / ours | 每模块成本 ours / fast |
|----|------:|------------------------:|---------------:|------------:|------------------------|
| V03H | 841 | 0.198 ms | 0.059 ms | 0.297×（慢 ≈3.4×） | 0.235 / 0.070 µs |
| V10H | 3249 | 0.729 ms | 0.323 ms | 0.442×（慢 ≈2.3×） | 0.224 / 0.099 µs |
| V40H | 31329 | 5.329 ms | 3.021 ms | 0.567×（慢 ≈1.8×） | 0.170 / 0.096 µs |

> 口径并列：**A** 每次新建 wasm Instance（与 fast_qr「一次调用」严格同形，含宿主固定项）
> fast/ours = 0.217 / 0.406 / 0.563×；**B** 单实例摊薄如上表。护栏全绿：逐位对齐、
> Node shim vs `moonrun` 跨宿主一致、同点 checksum 互证。

> ⚠️ **绝对毫秒数绑定测量环境**（本表 Node v22.23.1 + 2026-09-11 宿主；S9e 历史口径为 Node v24.20.0）：
> 跨环境只比「同 run 成对比值」，方向性结论全环境成立——归因见
> [S9h 复测异常归因](./docs/S9h-层②性能复测异常归因-Node版本与宿主漂移.md)。
> 生态另两个 QR 包（`qrc`/`moonbitqrcode`）缺完整择优/Format 等，不可同口径对齐，仅参考口径见 S9d。
> **历史注记**：`wasm`(WASI) 兼容后端已移除，其性能/体积数字仅作历史记录（见 S9e/S9g），
> 不再参与对外对比（避免「比的是哪个后端」歧义）。

**后续优化**：经**进程级差分实测分解**（[S9k 性能瓶颈与理论上限](./docs/S9k-性能瓶颈与理论上限评估.md)）——
V40H 单次 auto 约 **68% 在 8 轮 `score`**（N1+N3 行/列 ≈37%、N2 ≈16%、N4 ≈15%）+ 11% `apply_mask`；
**V03H 约 44% 在结果容器 `wrap_packed`**（固定 31329 槽 + 逐格 `Array[Module]` 对象），8 轮评分仅 ≈28%。
优化优先级据此为 **P0 wrap/容器（利小版本）+ P1 score 减趟/掩码特化（利大版本）**。
进一步把参考库 fast_qr 的做法**移植到本仓库做受控实验**（[S9l](./docs/S9l-参考fast_qr高性能实现分析.md)）：
其 **掩码特化**（步长/对称几何、免每格 `match`）实测 **4–5.8×**、**容器逐格对象税** **≈10×**、
**字节+切片评分** **仅 ≈1.26×**——即最大杠杆是**掩码与容器**，介质宽度本身有限。
容器专项另评估了官方指定的查找表类型 `ReadOnlyArray`（[S9m](./docs/S9m-ReadOnlyArray适用性评估.md)）：
它是 `FixedArray` 的零成本封装、适合 RS/常量等**只读字面量表**；对真实 `division` 实测
**≈1.25×**（真实块长），但整 build 仅 ≈0.4–0.5%（救不了 score/wrap 两大瓶颈）。
**理论上限 ≈ fast_qr-wasm32 同执行模型数字**（V40 ≈3.0 ms）：按 S9l 叠加方案 V40 现实可收窄到
**≈3.2–3.7 ms**（fast/ours 0.57×→≈0.82–0.95×，乐观追平）；V03 因每次 build 固定成本约束，
上界 ≈0.10–0.12 ms（fast/ours 0.30×→≈0.5–0.6×，**仍慢约 1.5–2×、不追平**）。
历史路线与已否决项（T1/O1-a 就地翻转）见 [S9b 性能优化](./docs/S9b-性能优化.md)。

**已落地优化（2026-09-12，明细见 [S9n §6](./docs/S9n-优化方案复评与wasm-gc收敛审计.md)）**：按上述优先级实施
**P0 掩码特化 + P2 评分去闭包/列缓冲 + P2b N4 并入行趟**——`wasm-gc` 受控 A/B（`cmd/bench`）实测
V40H 单次 auto **5.97→4.42 ms（−26%）**、V10H **−24%**、V03H **−4%**，且 `TOTAL_CHECKSUM` 三项与基线
**完全相同**（输出逐位不变，111 测试全绿）。**ReadOnlyArray（T-R1/T-R2/T-R4）亦已落地**：RS/常量查找表
与局部只读字面量全部只读化、`get_polynomial` 等改零拷贝只读视图、`moon.mod` 启用
`prefer_readonly_array` lint 防回归——受控探针复验 `division` **≈1.30–1.34×**（真实块长，两态
checksum 逐位一致），整 build **≈0.9%**（分辨率边缘；定性「类型对齐为主、非性能杠杆」，
见 [S9n §6.6](./docs/S9n-优化方案复评与wasm-gc收敛审计.md)）。
容器 P1 受阻于 `QRCode.data` 固定容量公共契约（须 API 评审）；P2b(N2)/P3/T-R5 待做。

> 性能数字仅作选型与迭代基线，不代表对 fast_qr 的追赶承诺；逐条口径见 S9 系列文档。

---

## 文档索引

### 面向用户的文档

| 文档 | 说明 |
|------|------|
| [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md) | 目录/包/测试设置的官方依据 + 实证验证 + 落地清单 |
| [moonbit-工具链与构建-setup-分析.md](./docs/moonbit-工具链与构建-setup-分析.md) | 工具链安装、构建系统与 CI 集成；附录含仓库初始化与云原生构建配置记录 |
| [wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md) | **历史记录**：wasm 编译/运行全过程、产物结构与早期多后端对比（`wasm`(WASI) 已移除） |
| [rust-环境配置脚本与fast_qr对比-setup.md](./docs/rust-环境配置脚本与fast_qr对比-setup.md) | Rust 参考环境配置（`scripts/setup-rust.sh`）+ fast_qr 对比用法 |
| [性能测试脚本-公开评审说明.md](./docs/性能测试脚本-公开评审说明.md) | 性能测试脚本位置、参数口径与可复现路径（公开评审/审计入口；含产物体积对比 §7） |
| [S9g-本项目wasm产物体积-确认与修正.md](./docs/S9g-本项目wasm产物体积-确认与修正.md) | **历史记录**：本项目 wasm 产物体积（含已移除的 `wasm`(WASI) 后端）+ 与 fast_qr 同口径对比；现口径见 S9i |
| [S9i-纯库调用体积探针与库实际体积.md](./docs/S9i-纯库调用体积探针与库实际体积.md) | **库实际体积口径**（`cmd/qr-min` 纯库调用探针；体积金字塔 + 引用规范 + ⑤ 锚点对称化） |

### 面向维护者 / 架构文档

工程与布局：

| 文档 | 说明 |
|------|------|
| [core-仓库布局参考与目标架构.md](./docs/core-仓库布局参考与目标架构.md) | 参考 `moonbitlang/core` 得出的目标包架构与分阶段落地路线 |
| [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md) | `lib/` 公共包 + `lib/internal/` 子包的文件职责、无环依赖规则、测试规划；附录含代码放置检查与整理记录 |
| [moonbit-重写-roadmap-详细分析.md](./docs/moonbit-重写-roadmap-详细分析.md) | 重写路线图：架构要点、S1–S9 实现顺序、里程碑 M0–M3 与验证基座 |

实现系列（2026-09-11 文档整合：每阶段合并为单文档，含 实现方案 / 实现记录 / 评审与优化 等分部；按 S1–S9 顺序）：

<details>
<summary><b>S1–S9 实现系列文档（点击展开）</b></summary>

| 阶段 | 文档 | 说明 |
|------|------|------|
| **S1 数据结构** | [实现方案·记录·评审](./docs/S1-数据结构.md) | ECL/Version/Mode/Mask/Module/QRCode/CompactQR 骨架与实现 |
| **S2 常量表与 GF256** | [方案·评估核对·记录·评审](./docs/S2-常量表与GF256.md) | 容量表 + 分组/格式/生成多项式表 + GF(256) division/structure |
| **S3 数据编码** | [方案·记录·评审](./docs/S3-数据编码.md) | 三模式编码 + best_encoding 自动回退 + terminator/8 位对齐 |
| **S4 矩阵与放置** | [方案·记录](./docs/S4-矩阵与放置.md) | 功能图案绘制 + 之字形放置 + 8 掩码，M1 固定参数首码 |
| **S5 掩码评分与择优** | [方案·记录·评审](./docs/S5-掩码评分与择优.md) | N1–N4 评分 + 8 轮择优主循环 |
| **S6 端到端对齐与公共 API** | [方案·记录·评审](./docs/S6-端到端对齐与公共API.md) | 60 快照逐位对齐 + 公共 `QRBuilder`，收敛 M2 |
| **S7 输出层** | [方案·记录·评估与优化](./docs/S7-输出层to_str与SVG.md) | 终端 `to_str`/`print` + 公共 `Shape`/`SvgBuilder` SVG |
| **S8 内部结构归位** | [实现方案](./docs/S8-内部结构归位与分层.md) | 公共层文件级职责归位（qr.mbt → qr_build/qr_builder/qr_output） |
| **S9 性能基准** | [方案·记录·评估与优化](./docs/S9-性能基准.md) | `cmd/bench` 三基准点 + 宿主计时，跨生态对比，收敛 M3 |
| **S9b 性能优化** | [评估路线·再评估·O1 实施](./docs/S9b-性能优化.md) | 择优主循环逐热点优化评估与首批落地 |
| **S9c 层② fast_qr-wasm 对比** | [方案·记录·详细分析](./docs/S9c-性能测试与fast_qr-wasm对比.md) | **历史口径**：Node 调用 wasm 逐位对齐 + 同口径计时（收口 M3） |
| **S9d moonbit 生态对比** | [方案·记录·详细分析·moonbitqrcode 两篇专题](./docs/S9d-与moonbit生态QR包性能对比.md) | 与 `qrc`/`moonqr`/`moonbitqrcode` 同语言对比 |
| **S9e 统一 Node 调用** | [方案·记录](./docs/S9e-性能测试统一Node调用.md) | **历史口径**：两侧统一 Node 进程内调用（MoonBit 侧为已移除的 `wasm`(WASI)），重测并分析（issue #50） |
| **S9f 产物体积对比** | [方案·记录](./docs/S9f-产物体积对比.md) | **历史口径**：同规则口径量测两侧 wasm 体积（五档 + 基线分解 + 语义护栏，issue #50） |
| **S9g 体积确认与修正** | [确认与修正](./docs/S9g-本项目wasm产物体积-确认与修正.md) | **历史口径**：补默认后端 `wasm-gc` 全套体积；修正 ⑤ 锚点污染与全文结论（含已移除的 `wasm` 后端） |
| **S9h 性能复测异常归因** | [复测归因](./docs/S9h-层②性能复测异常归因-Node版本与宿主漂移.md) | 层②复测异常定位：Node 大版本（v22/v24 受控 A/B）与宿主漂移两因素；引用规范修订 |
| **S9i 纯库调用体积探针** | [探针与库实际体积](./docs/S9i-纯库调用体积探针与库实际体积.md) | `cmd/qr-min` 纯库调用口径：库实际体积 31470 B（wasm-gc `-Oz`）+ 修正 ⑤ 锚点不对称（0.69×） |
| **S9j 层② wasm-gc 口径收敛** | [wasm-gc vs fast_qr](./docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md) | 层② MoonBit 侧收敛为 `wasm-gc`；Node 进程内 shim 直测（fast 快 ≈1.8–3.4×） |
| **S9k 性能瓶颈与理论上限** | [差分分解·优化上限·理论模型](./docs/S9k-性能瓶颈与理论上限评估.md) | 进程级差分把 auto build 拆为 5 段：V40 瓶颈=8轮 score(68%)、V03=wrap 容器(44%)；理论上限≈fast_qr 同模型（V40≈3.0ms） |
| **S9l 参考 fast_qr 高性能分析** | [上游精读·受控实验·优化映射](./docs/S9l-参考fast_qr高性能实现分析.md) | 逐文件拆解 fast_qr 快在哪：掩码特化实测 **5×**、容器对象税 **10×**、字节+切片评分 **1.26×**；给出 P0–P4 落地与叠加预期 |
| **S9m ReadOnlyArray 适用性** | [官方定位·表示事实·受控实验](./docs/S9m-ReadOnlyArray适用性评估.md) | `ReadOnlyArray`=FixedArray 零成本封装、官方指定的**字面量查找表**类型；救不了 score/wrap 两瓶颈；真实 `division` 实测 **≈1.25×**（真实块长，整 build ≈0.4–0.5%） |
| **S9n 复评与 wasm-gc 收敛审计** | [收敛审计·漏洞复评·统一优先级·落地记录](./docs/S9n-优化方案复评与wasm-gc收敛审计.md) | 审计 wasm-gc 收敛遗漏；复评 K/P/T-R 三套编号的**重复计数/介质混杂/基线互串**等 6 漏洞；收敛为**单一优先级清单** + `supported_targets` 硬边界；含 P0/P2/P2b 与 ReadOnlyArray **落地记录**（V40 −26%） |

</details>

### 移植参考：fast_qr（Rust v0.14.0）分析

本仓库以 Rust 库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 为参考实现，
以下是对该参考库源码的深度分析（检出于环境 `/fast_qr`，不在本仓库内），作为移植输入与设计依据：

| 文档 | 说明 |
|------|------|
| [fast-qr-索引.md](docs/移植参考/fast-qr-索引.md) | 参考库文档集入口：架构 / 接口 / 开发者指南 / 核心概念 / 模块 / 跨语言重写评估 |
| [fast-qr-架构.md](docs/移植参考/fast-qr-架构.md) | 六大子系统、数据流与 7 条核心性能设计决策 |
| [fast-qr-接口.md](docs/移植参考/fast-qr-接口.md) | Rust 与 JS/WASM 公开 API、示例与性能契约数据 |
| [fast-qr-开发者指南.md](docs/移植参考/fast-qr-开发者指南.md) | 参考库环境、feature 矩阵、CI 与已知注意事项 |
| [跨语言重写评估.md](docs/移植参考/专有概念/跨语言重写评估.md) | 重写价值判定、候选语言对比与机械翻译+黄金测试路线图 |

> 完整语料另见 `docs/移植参考/` 下的 `模块/` 与 `专有概念/` 子目录（由 `fast-qr-索引.md` 统辖）。
> 更多「基础框架/实现方案」等高层分析见 [项目基础框架-详细分析.md](./docs/项目基础框架-详细分析.md)。

---

## 代码放置约定（方案 3：模块根无包，库包在 `lib/`）

本仓库模块根只放元数据（对齐 `moonbitlang/core` 形态）：库包在 `lib/`、实现子包在 `lib/internal/`
（internal 永不反向 import `lib`，依赖无环）、CLI 在 `cmd/main/`；**不要建 `src/`**（MoonBit 无此约定）。
测试放所属包目录内：`*_test.mbt` 黑盒（包外，仅 `pub` API）/ `*_wbtest.mbt` 白盒（包内，可访问私有实现），
两者不可混用；跨包依赖在使用方 `moon.pkg` 声明且声明后必须使用（否则 `unused_package` 告警致 `moon check` 失败）。

完整约定表见 [AGENTS.md](./AGENTS.md)，文件级职责详见
[moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md)。

---

## 项目结构

```
.
├── moon.mod                    # MoonBit 模块配置（模块根不建包）
├── lib/                        # 库包（公共 API，lib/moon.pkg）
│   ├── fast_qr_moonbit.mbt     #   库入口 / 公共 API 总览
│   ├── ecl / version / mode / mask.mbt  # 公共枚举（ECL/Version/Mode/Mask）
│   ├── module.mbt              #   公共 Module / ModuleType（单字节位打包）
│   ├── qr.mbt                  #   QRCode 结果容器 + QRCodeError + 访问器
│   ├── qr_build.mbt            #   编排/构造：select_capacity + build_fixed/build
│   ├── qr_builder.mbt          #   公共 QRBuilder 构造器
│   ├── qr_output.mbt           #   QRCode 输出便捷 to_str/print
│   ├── helpers.mbt / svg.mbt / shape.mbt  # 输出层：终端画 + SVG + Shape
│   ├── *_test.mbt / *_wbtest.mbt          # 黑盒测试 / 白盒测试
│   └── internal/               #   实现子包（各带 moon.pkg；不反向依赖 lib）
│       ├── constants/          #     常量表 + 容量/元数据表
│       ├── bitstream/          #     位流缓冲（CompactQR）
│       ├── reedsolomon/        #     GF(256) 除法 + 交织
│       ├── data_encoding/      #     三模式编码 + 自动回退
│       └── matrix/             #     module/matrix/placement/datamasking/score
├── cmd/main/                   # CLI 可执行入口（演示终端画 + SVG）
├── cmd/bench/                  # 性能三基准点基准（S9，含 --dump 值全集导出）
├── cmd/qr-min/                 # 纯库调用体积探针（S9i：库实际体积口径，零外壳）
├── docs/                       # 项目文档（见上文「文档索引」）
├── scripts/                    # 构建与开发辅助脚本（见下节）
├── .githooks/                  # 可选 Git 钩子（需自行启用）
├── .cnb.yml                    # 云原生构建（CNB CI）配置
├── AGENTS.md                   # AI 协作代理指南（单一真实文件）
├── README.md                   # 本文件（moon.mod 的 readme）
└── LICENSE                     # Apache-2.0
```

各文件职责的详细说明见 [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md)。

---

## 开发与 CI

- **本地校验**：`scripts/` 提供可复用的分阶段脚本（安装工具链、fmt 门禁、静态检查、
  单测、构建回归、性能基准），均由 `.cnb.yml` 在 CI（push）中按序调用。
- **代码门禁**：`moon fmt --check` + `moon check --deny-warn` + `moon test` + `wasm-gc` release
  回归（`js`、`wasm`(WASI) 均已移除；不加 `native` 阶段——需系统 C 编译器）。
- **性能基准**：`bash scripts/bench.sh`（`wasm-gc` 三基准点）；层② `bash scripts/bench-layer2.sh`
  **`wasm-gc` vs fast_qr** 同 Node 进程对比（S9j）。
- **体积基准**：`bash scripts/bench-size.sh`（**S9f/S9g 同规则口径**：raw / 剥 custom / `-Oz` / wasm+胶水 /
  同功能锚点 + hello-only 基线分解，**仅 `wasm-gc`** 一列，带语义护栏 + 探针导入面自检；见
  [S9i](./docs/S9i-纯库调用体积探针与库实际体积.md)）。
- **Git 钩子（可选）**：`git config core.hooksPath .githooks`（个人本地配置，仓库不代设）。
- **后端口径**：项目**仅支持 `wasm-gc`**（实际分发形态，对外性能/体积口径）；
  `wasm`(WASI) 已移除，其数字仅作历史记录（术语与脚本角色见
  [性能测试脚本公开评审说明 §2.1](./docs/性能测试脚本-公开评审说明.md)）。
- **编码 / 提交规范**：见 [AGENTS.md](./AGENTS.md)（密钥安全、MoonBit 布局、文档死链零容忍等硬性约定）。

常用脚本一览：

| 脚本 | 作用 |
|------|------|
| `setup-moonbit.sh` | 安装 MoonBit 工具链并校验 |
| `fmt-check.sh` / `check.sh` / `test.sh` | 格式门禁 / 静态检查门禁 / 单元测试 |
| `build-and-run.sh` | `wasm-gc` 构建 + 运行 + 测试回归 |
| `bench.sh` | S9 三基准点基准（`wasm-gc`；非 vs fast_qr） |
| `bench-layer2.sh` | 层② 同 Node 进程调用对比（**S9j `wasm-gc` vs fast_qr**） |
| `gc-compare.mjs` | 层② wasm-gc 对比驱动：Node 宿主 shim（argv/print_char）+ 逐位对齐 + 跨宿主护栏 + A/B 计时（S9j） |
| `bench-size.sh` | 产物**体积**对比入口（S9f/S9g/S9i 同规则口径 + 纯库调用探针 + 语义护栏 + 基线分解；取 `wasm-gc`） |
| `wasm-size.mjs` | 体积对比驱动：五档量测 + 段解析 + 语义护栏 + markdown/JSON（S9f/S9g，`wasm-gc`） |
| `build-fast-qr-wasm.sh` | 构建 fast_qr v0.14.0 `qr_with` nodejs 产物（外部检出，不入库） |
| `setup-fast-qr-wasm-env.sh` | 层②环境：rust wasm32 target + gcc + 预编译 wasm-bindgen-cli（幂等） |
| `setup-rust.sh` | 安装 Rust 工具链（rsproxy 镜像，供 fast_qr 参考对比，可选） |

---

## 问题反馈与贡献

- **问题与建议**：提交至仓库 [Issue](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/issues)。
- **贡献流程**：改动前请阅读 [AGENTS.md](./AGENTS.md)（密钥安全、MoonBit 布局、文档死链零容忍等
  硬性约定），并跑通[开发与 CI](#开发与-ci) 中的收尾检查后再提交。

---

## License

[Apache-2.0](./LICENSE)
