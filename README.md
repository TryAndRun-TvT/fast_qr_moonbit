# TryAndRun-TvT/fast_qr_moonbit

> 基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。
> 纯 MoonBit 实现、无外部依赖，逐位对齐 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr)。

[![star](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/star)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit)
[![fork](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/fork)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit)
[![latest release](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/release)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/releases)
[![license](https://cnb.cool/svg/badge/license?message=Apache-2.0&color=green)](./LICENSE)

**项目状态**：功能对齐收口（M0–M3 里程碑 ✅），`moon test` 全绿（含快照与 README 文档测试），
仅 `wasm-gc` 后端回归通过。

<img src="./docs/assets/qr-example.svg" alt="由 fast_qr_moonbit 生成的二维码：内容 https://example.com/" width="220" height="220">

示例二维码（内容 `https://example.com/`，由 `SvgBuilder` 生成、**SVG 矢量**，缩放不失真）；
复跑 `moon run cmd/main` 可同时看到终端字符画与 SVG 输出。

| | |
|---|---|
| **语言** | [MoonBit](https://www.moonbitlang.cn/)（**仅 `wasm-gc`**；边界见「能力与局限」） |
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
- [性能与体积](#性能与体积)
- [测试](#测试)
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
- **单后端产物**：仅 `wasm-gc`（体积小、性能好；宿主需支持 GC 提案）。
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
  取舍与复核见 [S9n wasm-gc 收敛审计](./docs/S9n-优化方案复评与wasm-gc收敛审计.md) §1。

---

## 快速开始

在项目根目录（`moon.mod` 所在处）添加本库为依赖：

```bash
# 需本模块已发布至 mooncakes；发布前的过渡期为 clone 本仓库按「从源码构建」体验
moon add TryAndRun-TvT/fast_qr_moonbit
```

> **发布状态**：尚未发布（`0.1.0` 待发布）。发布流程、元数据/命名核验、归档面治理
> 与发布前门禁清单见 [mooncakes-发布方案.md](./docs/mooncakes-发布方案.md)；
> 发布动作已脚本化：`bash scripts/publish.sh`（默认干跑，`--publish` 真发），
> 模块名迁移记录见 [模块名迁移与发布链路核验.md](./docs/模块名迁移与发布链路核验.md)。

在 `moon.pkg` 中声明依赖并起别名（本库包路径为 `.../lib`，别名默认即目录名 `lib`）：

```toml
import {
  "TryAndRun-TvT/fast_qr_moonbit/lib",
}
```

然后即可用 `QRBuilder` 生成二维码——下面的示例**由门禁真编译真运行**（`mbt check` 文档测试），
可运行版本另见 [`cmd/main/main.mbt`](./cmd/main/main.mbt)（`moon run cmd/main` 输出字符画 + SVG）。

```mbt check
///|
test "readme_quick_start" {
  let qr = @lib.QRBuilder::from_string("https://example.com/").build()
  match qr {
    Ok(q) => {
      // V02 → 边长 4*2+17 = 25；访问器返回 Option（手搓 QRCode 无元数据）
      assert_eq(q.size(), 25)
      assert_eq(q.version().unwrap().width(), q.size())
      assert_eq(q.ecl().unwrap(), @lib.ECL::Q)
      assert_true(q.to_str().length() > 0)
      let svg = @lib.SvgBuilder::default()
        .module_color("#0000ff")
        .background_color("#ffffff")
        .shape(@lib.Shape::RoundedSquare)
        .to_str(q)
      assert_true(svg.has_prefix("<svg"))
    }
    Err(_) => abort("README 示例内容构建失败")
  }
}
```

> 上面的 `mbt check` 块是 **document test**：`moon test` 会真编译、真运行它——
> 改公共 API 而不同步改示例，测试直接变红。机制与踩坑见
> [README优化-冗余清理与最佳实践.md](./docs/README优化-冗余清理与最佳实践.md) §6.3。

主要公共类型一览（完整说明见 [文档索引](#文档索引) 各实现方案/记录）：

| 类型 | 位置/说明 |
|------|-----------|
| `ECL` / `Version` / `Mode` / `Mask` | 纠错级别（L/M/Q/H）、版本（V01–V40）、编码模式、掩码枚举 |
| `QRCode` | 生成结果容器（矩阵 + size/version/ecl/mask/mode 元数据 + `to_str`/`print`） |
| `QRCode::build` / `build_fixed` | 过程式编排入口（input/mode/ecl/version/mask → `Result[QRCode]`；`build` 的 `Some(mask)` 分支委托 `build_fixed`） |
| `QRCode::empty` | **空矩阵构造**（宿主自建/改写矩阵的唯一入口，见下「矩阵读写」） |
| `QRCode::get` / `set` / `meta` / `data`（+ `size`/`version`/`ecl`/`mask`/`mode`） | 逐格读写与元数据访问器（`set` 不可变式，返回新 `QRCode`） |
| `QRCode::select_capacity` | 容量/版本三元组解析（显式模式参与判定，供自定义编排复用） |
| `QRBuilder` | 链式构造器：`from_string`/`new` + `mode/ecl/version/mask` + `build` |
| `Module` / `ModuleType` | 单像素模块（明暗 + 8 种功能归属）；`Module::new(value, type)` 为通用构造 |
| `SvgBuilder` / `Shape` | SVG 字符串输出；6 种模块形状（square/circle/rounded_square/vertical/horizontal/diamond）；链式 `margin/module_color/background_color/shape` |
| `Shape::from_name` | 由名字（大小写不敏感）取形状枚举，未知名回退 |
| `ECL::to_char` | 纠错级别 → 显示字符（`L`/`M`/`Q`/`H`） |
| `QRCodeError` | 构造错误（`EncodedData` 数据过大、`SpecifiedVersion` 版本过小） |

### 矩阵读写与自建（宿主可拿到 `QRCode`）

`QRCode::build` / `QRBuilder::build` 返回的**就是** `QRCode`（`pub(all) struct`），
宿主可直接读/改矩阵并交给输出层；从零自建则用 `QRCode::empty(version)` 拿一张干净画布：

```moonbit nocheck
// ① 已有编码结果：读/改单格（set 为不可变式，返回新 QRCode，不改源）
let (v, ecl, mask, mode) = qr.meta()          // 元数据快照
let dark = qr.get(0, 0).value()               // 逐格读
let qr2  = qr.set(0, 0, @lib.Module::new(true, @lib.ModuleType::Data))  // 逐格写

// ② 从零自建：空矩阵（全亮）作起点，逐格写入后输出
let canvas = @lib.QRCode::empty(@lib.Version::V05)   // 边长 = 版本*4+17
let drawn  = canvas.set(10, 10, @lib.Module::new(true, @lib.ModuleType::Data))
println(drawn.to_str())
```

> 命名/形状等辅助入口：`Shape::from_name("circle")`（按名取形状）、
> `ECL::to_char(ECL::Q)`（级别显示字符）、`SvgBuilder::default().module_color(...)`（链式配色）。


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

唯一后端 `wasm-gc`（`moon.mod`：`preferred_target`/`supported_targets`；边界见「能力与局限」）。

```bash
# 唯一后端 wasm-gc（体积最小、性能最优，宿主只需提供 spectest.print_char）
moon build cmd/main --release
moon run   cmd/main
```

产物体积（release；复跑 `bash scripts/bench-size.sh`，完整口径见
[S9i](./docs/S9i-纯库调用体积探针与库实际体积.md)）：

| 产物 | 后端 | raw | `-Oz`（可加载档） |
|------|------|---:|------------------:|
| **`cmd/qr-min`（纯库调用 = 库实际体积）** | **`wasm-gc`** | 41427 B（40.5 KiB） | **31365 B**（30.6 KiB） |
| `cmd/bench`（基准外壳：argv/迭代/`--dump`） | **`wasm-gc`** | 48038 B（46.9 KiB） | 36174 B（35.3 KiB） |
| `cmd/main`（CLI：字符画 + SVG） | **`wasm-gc`** | 44424 B（43.4 KiB） | 33593 B |

> **引用规范**：`cmd/bench` / `cmd/main` 是「命令形态」产物，外壳不随库分发，
> **不能代表库被宿主嵌入时的实际体积**——引用库体积请用 `cmd/qr-min` 口径并注明后端与优化档。
> **体积金字塔**（`wasm-gc`，`-Oz`）：运行时地板（一行 `println`）**263 B** → QR 核心净增
> **+31102 B**（`cmd/qr-min`）→ 输出层（终端画 + SVG）**+2228 B**（`cmd/main`）→ 基准外壳
> **+4809 B**（`cmd/bench`）。

```bash
# -Oz 体积最优档（默认后端 wasm-gc）：
#   --all-features 会开 custom-descriptors(RTT)，其 exact heap type 在 Node/moonrun 上编译不过；
#   --disable-custom-descriptors 才产出「可被真实宿主加载」的最优档。
moon-wasm-opt _build/wasm-gc/release/build/cmd/main/main.wasm \
  --all-features --disable-custom-descriptors -Oz -o main.min.wasm   # 33593 B
```

**与 fast_qr 的体积对比（库对库主口径）**：两侧同为「核心-only + 一行 `println`」
（MoonBit `cmd/qr-min` vs fast_qr 无胶水裸探针）：

| 口径（B） | MoonBit `wasm-gc` | fast_qr 裸探针 | ours / fast |
|-----------|------------------:|---------------:|------------:|
| raw | 41427 | 59440 | **0.70×** |
| `-Oz`（可加载档） | **31365** | 45687 | **0.69×** |
| 核心净增（扣 hello 地板 263 / 20052 B） | **+31102** | +25635 | 1.21× |

> **结论**：库对库，`wasm-gc` 在 raw 与 `-Oz` 两档都约 **0.69–0.70×**；扣掉运行时地板后核心净增
> 1.21×——差距大头是两侧**运行时地板**（`wasm-gc` 263 B vs Rust 20052 B，76×），非 QR 实现差异。
> 命令形态（`cmd/bench` 含 argv/迭代外壳）对照与其他档位明细见
> [S9i](./docs/S9i-纯库调用体积探针与库实际体积.md) · [S9f](./docs/S9f-产物体积对比.md)。

---

## 性能与体积

> 引用的性能数字仅作选型与迭代基线，**不代表对 fast_qr 的追赶承诺**；逐条口径见 S9 系列文档。

复跑入口：`bash scripts/bench-host.sh`（宿主调用面）· `bench-host-var.sh`（统计稳定性）·
`bench-layer2.sh`（层② vs fast_qr）· `bench.sh`（层① 后端）· `bench-size.sh`（体积）。
统一口径：输入 `https://example.com/`=20B、ECL H、强制 V03/V10/V40、mask 自动择优。核心结论：

| 对比 | 结果 | 出处 |
|------|------|------|
| ① vs Rust fast_qr-wasm32（**默认后端 `wasm-gc`**） | 单次 build 慢 ≈**1.3–2.5×**，逐位对齐 sha256 零差异；差距集中在 8 轮掩码择优主循环 | 明细见下表 · [S9p](./docs/S9p-宿主调用面性能口径-JS向wasm传参.md) · [S9j](./docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md) |
| ② vs moonbit 生态 `moonqr`（同宿主、完整实现可比子集） | 本仓库全程快 **2.5–4.1×**（V03H 0.318 vs 0.805、V40H 9.46 vs 38.29 ms/单次，历史口径） | [S9d](./docs/S9d-与moonbit生态QR包性能对比.md) |
| ③ 产物体积 vs fast_qr | `wasm-gc` 各口径均更小（对称锚点 **0.69×**） | 对照表见 [编译为 Wasm](#编译为-wasm) · [S9i](./docs/S9i-纯库调用体积探针与库实际体积.md) |

> ① 的数据随本轮 P0/P2/P2b 优化已刷新（2026-09-12 重测）；② 为优化前（2026-09-06）历史口径，
> 未随本轮重测，量级参考即可。

### ① vs fast_qr-wasm32：性能明细

**主口径 = 宿主调用面（[S9p](./docs/S9p-宿主调用面性能口径-JS向wasm传参.md)）**：宿主一次 `compile`
+ 一次 `Instance`，随后在同一实例上反复带参调 wasm（`cmd/host-probe` 的
`qr_generate(content, version)`），与 fast_qr `qr_with` 形态对称、逐位 sha256 零差异：

| 点 | 模块数 | 本仓库 MoonBit(wasm-gc) | fast_qr-wasm32 | fast / ours | 每模块成本 ours / fast |
|----|------:|------------------------:|---------------:|------------:|------------------------|
| V03H | 841 | 0.213 ms | 0.087 ms | 0.407×（慢 ≈2.5×） | 0.253 / 0.103 µs |
| V10H | 3249 | 0.643 ms | 0.399 ms | 0.620×（慢 ≈1.6×） | 0.198 / 0.123 µs |
| V40H | 31329 | 4.659 ms | 3.523 ms | 0.756×（慢 ≈1.3×） | 0.149 / 0.112 µs |

> 上表为「R=5 中位数」口径。**纪律**：只用「同 run 内成对比值」，不跨 run 加减绝对毫秒；
> 绝对毫秒绑定测量环境（Node v24.21.0 + 2026-09-14 宿主），跨环境只比比值。
> 统计口径与离散（V03H 比值 CV **5.98%** ≫ V10H 3.54% > V40H 0.35%；V03H 单轮最坏偏离 **+17.3%**）、
> 调度态与 Node 版本量级、旧命令形态对照、生态另两个包不可同口径的原因——
> 全部下沉到 [S9q](./docs/S9q-性能口径统计差异与取平均评估.md) · [S9p](./docs/S9p-宿主调用面性能口径-JS向wasm传参.md) §4.1 ·
> [S9h](./docs/S9h-层②性能复测异常归因-Node版本与宿主漂移.md) · [S9d](./docs/S9d-与moonbit生态QR包性能对比.md)。
> **护栏全绿**：宿主面 checksum 与 `cmd/bench <点> 1` 逐点相同 · 逐位对齐 sha256 三点相同 · 跨宿主一致。

### 后续优化 Roadmap

- **成本分解**（[S9k](./docs/S9k-性能瓶颈与理论上限评估.md)）：V40H 约 **68% 在 8 轮 `score`** + 11% `apply_mask`；
  V03H 约 **44% 在结果容器 `wrap_packed`**。优先级据此定为 **P0 容器 / P1 score 减趟与掩码特化**。
- **已落地**（[S9n §6](./docs/S9n-优化方案复评与wasm-gc收敛审计.md)）：P0 掩码特化 + P2 评分去闭包/列缓冲 + P2b N4 并入行趟，
  V40H 受控 A/B **−26%**（V10H −24%、V03H −4%），`TOTAL_CHECKSUM` 三项与基线完全相同（输出逐位不变）；
  ReadOnlyArray 只读化 + `prefer_readonly_array` lint 亦已落地（**≈0.9%**，定性「类型对齐为主、非性能杠杆」）。
- **待做与上限**：容器 P1 受阻于 `QRCode.data` 固定容量公共契约（须 API 评审）；P2b(N2)/P3/T-R5 待做。
  理论上限≈ fast_qr 同执行模型（本环境 V40 ≈3.55 ms），现实可收窄到 V40 **≈3.6–4.2 ms**；
  V03 受每次 build 固定成本约束，**仍慢约 1.1–1.4×、大概率不追平**。
  已否决项（T1/O1-a 就地翻转）见 [S9b](./docs/S9b-性能优化.md)，统一优先级清单见 [S9n §3](./docs/S9n-优化方案复评与wasm-gc收敛审计.md)。

---

## 测试

**现状**：`moon test` 全绿（含 wasm-gc 回归与 1 个 README 文档测试），测试文件按「就近式三载体」分层
（`*_test.mbt` 黑盒 / `*_wbtest.mbt` 白盒）。**用例数与文件数不写进 README**——它们随实现变动，
写死必然漂移（此处曾出现同一文件内 146/147 自相矛盾）；需要数字时以实跑为准：`moon test`。

| 层 | 覆盖 |
|----|------|
| 黑盒 | 公共枚举与 `select_capacity` 四态 + **模式/版本语义回归（4 条，v5）**、`QRBuilder` 链式等价、**择优 mask 号回归（T2-d）**、SVG 全串、终端画、**21 个**端到端全矩阵 hex 快照、**11 条固化解码向量（T3-c）** |
| 白盒 | 位流、常量表交叉不变量 + **全表值级校验（T1-f）**、**生成多项式独立推导（T1-a）**、三模式编码、GF(256) 交织 + **黄金余数/交织向量（T1-c/T1-d）+ 交叉独立证据（T1-e）**、**逐行/逐列打分明细（T2-a/T2-b）+ 结算边界（T2-b2/b3）**、8 种掩码、**放置逐格坐标（T2-c）**、**Format 双副本布局（T2-e）**、**独立数字真值（T0-c）**、**属性测试四则（T4-a）**、**枚举全量回环（T5-b）** |
| 黄金值来源 | 参考 fast_qr commit `53e8c99` 侧由脚本产出（**禁止手抄**）：`snapshot_gen_s6.rs`（全矩阵）、`snapshot_gen_tables.py`（常量表全表指纹）、`snapshot_gen_rs_vectors.rs`（division/structure）、`snapshot_gen_score.rs`（打分明细）、`snapshot_gen_placement.rs`（放置坐标）、`snapshot_gen_default.py`（Python `qrcode` 独立真值）；一键校验 `bash scripts/gen-goldens.sh --verify`（四项零差异） |

**测试完善路线**见 [S10-测试用例设计与完善roadmap.md](./docs/S10-测试用例设计与完善roadmap.md)（**测试维护入口**）。
关键结论（均已实跑）：

- **强负向对照（变异检测）**：`bash scripts/test-audit.sh mutation` 就地植入 **21 类**最小缺陷 →
  **21 类全部被检出**；历次审计共发现 **4 条真漏检**（容量表中间项、Format 非抽查点、N1 结算阈值 `5→6`、
  择优并列 `s < best`）全部已修——**分支存在 ≠ 分支被测、契约必须显式锁定**。
- **独立第三方解码回读**：`bash scripts/test-audit.sh decode` 用纯 JS `jsqr` 回读，
  三基准点 + **T3-d 全语料 54 组**全部读回原文；`--mutate` 负向组全部解码失败（证明证据链「能红、可信」）。
- **⚠️ 测试基础设施抓到一条真 bug（v5）**：T3-d 探针首跑暴露 `QRCode::select_capacity`
  显式 `mode` 未参与容量判定 → 长 Alphanumeric/Byte 输入被静默按 Numeric 选版本、矩阵不可解码。
  修复后与参考在 **83,160 组参数**上零差异，见
  [S10c](./docs/S10c-select-capacity模式语义缺陷-定位与修复.md)。
- **可复现门禁**：`gen-goldens.sh --verify`（黄金值钉版重建，四项零差异）·
  `diff-gate.sh`（与参考 wasm 逐位 sha256，无制品显式 skipped）·
  `coverage.sh --floor`（T5-b 不下降，**不设绝对百分比**——覆盖率是变异检测的补充）·
  `docs-link-check.sh`（相对链接零死链）· `test-scale.sh`（单测试文件 ≤800 行）。均已并入 `gates.sh`。

**测试铁律**（摘要，完整七条见 S10 §5）：黄金值必须有脚本出处 · 黑盒锁契约/白盒锁实现 ·
**禁止 `actual == actual`** · 断言失败必须能定位到模块/行/格 · **负向优先于正向** ·
评审看**真值集合**而非用例数 · 测试不得有破坏性副作用。

---

## 文档索引

> 面向读者的口径与结论汇总在本文；**实现细节、逐条口径、历史记录**在下列文档
> （随附代码实测与复跑方式）。文件名前缀 `S1`–`S9n` 为按实现顺序编号的阶段文档。

| 文档 | 说明 |
|------|------|
| [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md) | 目录/包/测试设置的官方依据 + 实证验证 + 落地清单 |
| [moonbit-工具链与构建-setup-分析.md](./docs/moonbit-工具链与构建-setup-分析.md) | 工具链安装、构建系统与 CI 集成 |
| [mooncakes-发布方案.md](./docs/mooncakes-发布方案.md) | **发布入口**：mooncakes.io 发布流程核验、元数据/命名/归档面评估、`.moonignore` 治理、版本策略与发布前门禁清单 |
| [mooncakes-发布阻塞项3-4-落地方案.md](./docs/mooncakes-发布阻塞项3-4-落地方案.md) | **发布落地**：归档面收敛（`.moonignore` 155→32 项）+ 发布前门禁 `publish-check.sh` 的实测与负向验证 |
| [模块名迁移与发布链路核验.md](./docs/模块名迁移与发布链路核验.md) | **迁移记录**：改为 `TryAndRun-TvT` 的全仓改名清单 + `moon publish --dry-run` 实测 |
| [性能测试脚本-公开评审说明.md](./docs/性能测试脚本-公开评审说明.md) | 性能/体积脚本的参数口径与可复现路径（**审计入口**） |
| [S9i-纯库调用体积探针与库实际体积.md](./docs/S9i-纯库调用体积探针与库实际体积.md) | **库实际体积口径**（`cmd/qr-min` 纯库调用探针；体积金字塔 + 引用规范） |
| [S9j-层②统一Node对比-wasm-gc与fast_qr.md](./docs/S9j-层②统一Node对比-wasm-gc与fast_qr.md) | 层② `wasm-gc` vs fast_qr（Node 进程内 shim 直测） |
| [S9k-性能瓶颈与理论上限评估.md](./docs/S9k-性能瓶颈与理论上限评估.md) | 进程级差分把 auto build 拆为 5 段：瓶颈定位与理论上限（**roadmap 依据**） |
| [S9n-优化方案复评与wasm-gc收敛审计.md](./docs/S9n-优化方案复评与wasm-gc收敛审计.md) | 收敛审计 + **优化优先级清单** + 已落地项记录 |
| [README示例二维码-SVG资源与生成.md](./docs/README示例二维码-SVG资源与生成.md) | README 头部示例码为何用 **SVG** + 资产规格 + 生成脚本 + 一致性核验 |
| [README优化-冗余清理与最佳实践.md](./docs/README优化-冗余清理与最佳实践.md) | README 优化总账：冗余清单、官方约定对照，**§6 徽章/文档测试/SVG**、**§7 符号链接方向回正与精简** |
| [S9o-性能与体积数据重测-与README冗余清理.md](./docs/S9o-性能与体积数据重测-与README冗余清理.md) | 性能/体积数据刷新方法与归因 |
| [S9p-宿主调用面性能口径-JS向wasm传参.md](./docs/S9p-宿主调用面性能口径-JS向wasm传参.md) | **宿主调用面主口径**：JS 反复带参调 wasm（`cmd/host-probe`） |
| [S9q-性能口径统计差异与取平均评估.md](./docs/S9q-性能口径统计差异与取平均评估.md) | **统计口径**：R 轮取最小≠真值；CV / 单跑失稳率 / 漂移判定；**主数取中位数 + 报离散** |
| [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md) | 布局规则、`lib/` + `lib/internal/` 文件级职责、无环依赖、测试规划（**维护者入口**） |
| [S10-测试用例设计与完善roadmap.md](./docs/S10-测试用例设计与完善roadmap.md) | **测试 roadmap v6**：覆盖差距矩阵 + T0–T7 路线 + 七条铁律；附录为实跑结论（**测试维护入口**） |
| [S10c-`select_capacity`模式语义缺陷-定位与修复.md](./docs/S10c-select-capacity模式语义缺陷-定位与修复.md) | **v5 真 bug 修复记录**：显式模式未参与容量判定（含与参考 83,160 组对照） |
| [S10b-测试覆盖率报告.md](./docs/S10b-测试覆盖率报告.md) | **T5-a 覆盖率报告**（行级，`scripts/coverage.sh` 产出）+ **T5-b 不下降门禁**（顶部 `coverage-floor` 机器可读标记） |
| [S11-无效代码与冗余文档清理评估.md](./docs/S11-无效代码与冗余文档清理评估.md) | **清理评估入口**：无效代码/文档的判定口径与处置队列 |
| [S11b-清理落地记录-v3-v5.md](./docs/S11b-清理落地记录-v3-v5.md) | **清理落地记录分册**：v3 删冗余符号/消双份实现、v4 文件级清理、v5 注释级过期口径巡检 |
| [AGENTS.md](./AGENTS.md) | AI/协作者硬性约定：密钥安全、MoonBit 布局、文档死链零容忍（**贡献前必读**） |
| ⤷ [S1–S9n 实现系列文档](./docs/S1-数据结构.md) | 按阶段编号的实现方案/记录/评审与性能评估全套（**按需深入，从 S1 进入**） |
| ⤷ [fast_qr 移植参考](./docs/移植参考/fast-qr-索引.md) | Rust 参考库 v0.14.0 的架构/接口/概念分析语料（**由索引统辖**） |
| ⤷ [项目基础框架-详细分析.md](./docs/项目基础框架-详细分析.md) | 立项时的资产盘点、目标架构、移植策略与分阶段路线（**历史基线**） |
| ⤷ [moonbit-重写-roadmap-详细分析.md](./docs/moonbit-重写-roadmap-详细分析.md) | fast_qr 源码级核对 + S1–S9 实现顺序与里程碑 roadmap（**历史基线**，`wasm`(WASI) 口径仅作历史留存） |
| ⤷ [core-仓库布局参考与目标架构.md](./docs/core-仓库布局参考与目标架构.md) | 借鉴 `moonbitlang/core` 的目标包架构与拆包判据（`lib/` + `lib/internal/` 布局依据） |
| ⤷ [wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md) | **历史记录**：wasm 编译/运行全过程与早期多后端对比（`wasm`(WASI) 已移除） |
| ⤷ [rust-环境配置脚本与fast_qr对比-setup.md](./docs/rust-环境配置脚本与fast_qr对比-setup.md) | Rust 参考环境配置（`scripts/setup-rust.sh`）+ fast_qr 对比用法 |

> `⤷` 行是该目录/系列的总入口（**不再逐篇平铺**，避免索引与文档本体重复）。
> S11 是**清理/收敛的评估入口**（无效代码与冗余文档的判定口径 + 处置队列），
> 不替代 S10（测试覆盖面）与 S10b（覆盖率数字）。
> 其中 S1–S9n 每篇含「实现方案 / 实现记录 / 评审与优化」等分部，按阶段顺序编号；
> 性能相关重点篇目：S9b（优化路线与已否决项）、S9d（vs moonbit 生态）、S9f/S9g（**历史**体积口径）、
> S9h（环境归因）、S9l（参考 fast_qr 拆解）、S9m（ReadOnlyArray）。

---

## 代码放置约定（方案 3：模块根无包，库包在 `lib/`）

本仓库模块根只放**元数据**（对齐 `moonbitlang/core` 形态）：库包在 `lib/`、实现子包在 `lib/internal/`
（internal 永不反向 import `lib`，依赖无环）、CLI 在 `cmd/`；**不要建 `src/`**（MoonBit 无此约定）。
测试放所属包目录内：`*_test.mbt` 黑盒（包外，仅 `pub` API）/ `*_wbtest.mbt` 白盒（包内，可访问私有实现），
两者不可混用；跨包依赖在使用方 `moon.pkg` 声明且声明后必须使用（否则 `unused_package` 告警致 `moon check` 失败）。

> **模块根唯一例外：`moon.pkg`（空包，不写库代码）**——它是 README 文档测试的宿主。
> 官方布局用 `README.mbt.md` + `README.md` 符号链接，其 `mbt check` 代码块由
> `moon check`/`moon test` 当作文档测试执行；实测模块根的 `.md` **只有归属到某个包**才会被扫描，
> 故根必须存在 `moon.pkg`。库代码/公共 API **一律不放根目录**。

完整约定表见 [AGENTS.md](./AGENTS.md)，文件级职责详见
[moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md)。

---

## 项目结构

```
.
├── moon.mod                    # MoonBit 模块配置
├── moon.pkg                    # 模块根空包：README 文档测试宿主（不写库代码）
├── lib/                        # 库包（公共 API，lib/moon.pkg）
│   ├── ecl / version / mode / mask.mbt  # 公共枚举（ECL/Version/Mode/Mask）
│   ├── module.mbt              #   公共 Module / ModuleType（单字节位打包）
│   ├── qr.mbt                  #   QRCode 结果容器 + QRCodeError + 访问器
│   ├── qr_build.mbt            #   编排/构造：select_capacity + build_fixed/build
│   ├── qr_builder.mbt          #   公共 QRBuilder 构造器
│   ├── helpers.mbt             #   输出层：终端画渲染 + QRCode::to_str/print
│   ├── svg.mbt / shape.mbt     #   输出层：SVG 渲染 + Shape 枚举
│   ├── *_test.mbt / *_wbtest.mbt          # 黑盒测试 / 白盒测试
│   └── internal/               #   实现子包（各带 moon.pkg；不反向依赖 lib）
│       ├── constants/          #     常量表 + 容量/元数据表
│       ├── bitstream/          #     位流缓冲（CompactQR）
│       ├── reedsolomon/        #     GF(256) 除法 + 交织
│       ├── data_encoding/      #     三模式编码 + 自动回退
│       └── matrix/             #     module/matrix/placement/datamasking/score
├── cmd/main/                   # CLI 可执行入口（演示终端画 + SVG）
├── cmd/bench/                  # 性能基准（含 --dump 值全集导出）
├── cmd/qr-min/                 # 纯库调用体积探针（库实际体积口径，零外壳）
├── docs/                       # 项目文档（见上文「文档索引」）
│   └── assets/                 #   文档资源（qr-example.svg = README 示例码）
├── scripts/                    # 构建与开发辅助脚本（见下节）
├── .githooks/                  # 可选 Git 钩子（需自行启用）
├── .cnb.yml                    # 云原生构建（CNB CI）配置
├── AGENTS.md                   # AI 协作代理指南
├── README.mbt.md               # 本文件正文（moon.mod 的 readme，含 mbt check 示例）
├── README.md -> README.mbt.md  # 官方布局：符号链接（平台/编辑器的兼容入口）
└── LICENSE                     # Apache-2.0
```

各文件职责的详细说明见 [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md)。

---

## 开发与 CI

- **代码门禁**：`bash scripts/gates.sh`（一键全量：`moon fmt --check` + `moon check --deny-warn` +
  `moon test` + 死链/规模护栏 + `wasm-gc` release 回归 + 差分门禁 + 发布前门禁；
  支持 `STAGES="check test"` / `SKIP_SLOW=1`）。
  **push CI 已于 2026-09-14 移除**（每次推送重复全量构建，资源收益不成比例），
  门禁脚本零改动、改为本地/发布前按需执行，故提交前跑一遍是**必须**动作。
  （不加 `native` 阶段——需系统 C 编译器。）
- **发布**：`bash scripts/publish.sh`（**默认干跑**：环境自检 + 发布前门禁 + 归档清单 +
  `moon publish --dry-run`）；真实发布 `bash scripts/publish.sh --publish`（不可逆，需确认）。
  凭据属本地私有，**发布不进 CI**。
- **基准复跑**：见[性能与体积](#性能与体积)的复跑入口；参数口径见
  [性能测试脚本-公开评审说明.md](./docs/性能测试脚本-公开评审说明.md)。
- **Git 钩子（可选）**：`git config core.hooksPath .githooks`（个人本地配置，仓库不代设）。
- **编码 / 提交规范**：见 [AGENTS.md](./AGENTS.md)（密钥安全、MoonBit 布局、文档死链零容忍等硬性约定）。

`scripts/` 按角色分组（**push CI 已移除**；门禁链由 `gates.sh` 本地一键触发，环境配置与对外对比脚本仅本地/审计时手动执行）：

| 角色 | 脚本 | 执行方式 |
|------|------|:--------------:|
| 环境配置 | `setup-moonbit.sh`、`setup-rust.sh`、`setup-fast-qr-wasm-env.sh` | 手动（幂等，本地/审计） |
| **全量门禁** | **`gates.sh`**（`fmt-check` → `check` → `test` → `docs-link-check` → `test-scale` → `build-and-run` → `diff-gate` → `publish-check`） | **本地** |
| **发布** | **`publish.sh`**（默认干跑；`--publish` 才真发，需确认） | **本地（不进 CI）** |
| 门禁链单项 | `fmt-check.sh` → `check.sh` → `test.sh` → `build-and-run.sh` | 本地（亦由 `gates.sh` 串起） |
| 性能基准 | **`bench-host.sh` + `host-bench.mjs`（宿主调用面：JS 反复带参调 wasm，主口径）**、`bench-host-var.sh` + `bench-host-var.mjs`（统计稳定性：CV / 单跑失稳率 / 漂移）、`bench.sh`（层①）、`bench-layer2.sh` + `gc-compare.mjs`（层② vs fast_qr） | ❌ |
| 体积基准 | `bench-size.sh` + `wasm-size.mjs`（同规则口径 + 纯库探针 + 语义护栏） | ❌ |
| 外部检出 | `build-fast-qr-wasm.sh`（fast_qr 侧产物，检出副本不入库） | ❌ |
| 测试审计 | `test-audit.sh`（变异检测 + 解码回读）+ `apply-mutation.py` + `qr-decode-check.mjs`（`--points` 三基准点 / **`--corpus` T3-d 54 组**） | ❌ |
| 黄金值/规模 | `gen-goldens.sh`（钉版重建 + `--verify` 四项）+ `snapshot_gen_tables.py` / `snapshot_gen_default.py` / `snapshot_gen_rs_vectors.rs` / `snapshot_gen_score.rs` / `snapshot_gen_placement.rs` + `snapshot_verify_*.py` + `test-scale.sh`（单测试文件 ≤800 行护栏） | ❌ |
| 差分门禁 | `diff-gate.sh`（vs 参考 wasm 逐位 sha256；无制品显式 skipped） | 本地（可 skipped） |
| 覆盖率 | `coverage.sh`（`moon coverage analyze` 报告）+ **`--floor` 不下降门禁（T5-b）** | ❌ |
| 文档/规模护栏 | **`docs-link-check.sh`（T6-c 相对链接死链）** + `test-scale.sh`（T7-b 单测试文件 ≤800 行） | 本地 |
| 资源生成 | `gen-readme-qr-svg.sh`（重建 `docs/assets/qr-example.svg`，临时包用完即删） | ❌ |

---

## 问题反馈与贡献

- **问题与建议**：提交至仓库 [Issue](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/issues)。
- **贡献流程**：改动前请阅读 [AGENTS.md](./AGENTS.md)（密钥安全、MoonBit 布局、文档死链零容忍等
  硬性约定），并跑通[开发与 CI](#开发与-ci) 中的收尾检查后再提交。

---

## License

[Apache-2.0](./LICENSE)
