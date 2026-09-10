# tryandrun/fast_qr_moonbit

> 基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。
> 纯 MoonBit 实现、无外部依赖，逐位对齐 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr)。

**项目状态**：功能对齐收口（M0–M3 里程碑 ✅），109 单测 + 快照全绿，`wasm-gc` / `wasm` 双后端回归通过。

| | |
|---|---|
| **语言** | [MoonBit](https://www.moonbitlang.cn/)（`wasm-gc` 主推 + `wasm`/WASI 兼容；`js` 已移除，`native` 需系统 C 编译器） |
| **标准** | ISO/IEC 18004 二维码（版本 1–40，ECL L/M/Q/H，8 掩码评分择优） |
| **许可** | [Apache-2.0](./LICENSE) |
| **参考** | Rust [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 逐位移植对齐 |

---

## 目录

- [功能特性](#功能特性)
- [能力与局限](#能力与局限)
- [在项目中作为依赖使用](#在项目中作为依赖使用)
- [从源码构建](#从源码构建)
- [编译为 Wasm](#编译为-wasm)
- [性能速览](#性能速览)
- [文档索引](#文档索引)
- [性能测试脚本公开评审说明](./docs/性能测试脚本-公开评审说明.md)
- [代码放置约定](#代码放置约定方案-3模块根无包库包在-lib)
- [项目结构](#项目结构)
- [开发与 CI](#开发与-ci)
- [License](#license)

---

## 功能特性

- **纯 MoonBit 实现**，无外部依赖，可直接 `moon add` 依赖到你的项目。
- **标准合规**：遵循 ISO/IEC 18004 —— 版本 V01–V40、四种纠错级别（L/M/Q/H）、
  三模式自动编码（Numeric / Alphanumeric / Byte）+ 自动回退、8 种掩码评分择优。
- **逐字节对齐参考**：矩阵与 fast_qr v0.14.0 全量快照逐位一致，可解码读回原文。
- **双后端产物**：`wasm-gc`（默认，体积小、性能好）+ `wasm`（WASI，宿主接入灵活）。
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
- 输入按 **ASCII 字节** 处理（非 ASCII 多字节字符的语义见 [S6 评审记录](./docs/S6-实现评审与优化-记录.md) 的优化建议）。
- 产物形态面向 **wasm**：MoonBit `Int` 32 位、纠错位流 `KEEP_LAST=33`（取 Rust wasm32 分支），
  对真实 QR 语义无差别（详见 [S9 评估记录](./docs/S9-性能基准-实现评估与优化-记录.md) §2.4）。
- `native` 后端需系统 C 编译器，当前 CI/本地镜像未安装，暂不可用。

---

## 在项目中作为依赖使用

在你的 MoonBit 项目里添加本库作为依赖：

```toml
# 项目 moon.mod 所在目录执行
# moon add tryandrun/fast_qr_moonbit
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
  // 输出 SVG 字符串（默认黑色方块 + 白色背景、margin=4）
  let svg = @lib.SvgBuilder::default()
    .module_color("#0000ff")
    .background_color("#ffffff")
    .shape(@lib.Shape::RoundedSquare)
    .to_str(qr)
  println(svg[:200] + "...")
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
for t in wasm-gc wasm; do
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon test --target "$t"
done
```

---

## 编译为 Wasm

`supported_targets = "+wasm+wasm-gc"`，默认后端 `preferred_target = "wasm-gc"`。

```bash
# 默认后端 wasm-gc（体积最小、性能最优，宿主只需提供 spectest.print_char）
moon build cmd/main --release
moon run   cmd/main

# 兼容后端 wasm（WASI preview1，可被 node / wasmtime 等标准宿主加载）
moon build cmd/main --target wasm --release
moon run   cmd/main --target wasm
```

产物位置与体积（release，`cmd/main` 骨架）：

| 后端 | 产物 | 体积 | 特点 |
|------|------|-----:|------|
| **`wasm-gc`**（默认） | `_build/wasm-gc/release/build/cmd/main/main.wasm` | **440 B** | 仅 1 个 `spectest.print_char` 导入，宿主集成成本最低 |
| `wasm` | `_build/wasm/release/build/cmd/main/main.wasm` | 2598 B | 符合 WASI preview1，可被 node / wasmtime 等标准宿主加载 |

默认选 `wasm-gc` 的依据：体积比 `wasm` 小 **83%**、计算密集基准快约 **33%**。
详细分析见 [wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md)。

---

## 性能速览

项目自带可复跑基准（`cmd/bench` + `scripts/bench.sh`，输入 `https://example.com/`=20B、ECL H、
强制 V03/V10/V40、mask 自动择优）。以下汇总**跨库性能对比**（vs Rust 参考 fast_qr + moonbit 生态 QR 包）
与**后续优化路线**。完整口径、原始表与归因见所链文档（数字均为 R 取最小的实测，可 `scripts/bench*.sh`
复跑）。

### 跨库对比全景

**① 层① 跨后端（同源码互证）**：`wasm-gc` 全程比 `wasm` 快约 **1.2–1.4×**，两后端
`TOTAL_CHECKSUM` 完全一致。见 [S9 实现记录](./docs/S9-性能基准-实现记录.md)。

**② 层② vs Rust 参考 fast_qr-wasm32**：自 **S9e 起两侧统一为「同一 Node 进程内」调用**（此前
fast_qr 进程内 / MoonBit `moonrun` 子进程，MoonBit 侧被多计 12–20% 进程启动）。
下表为**单次 build**，逐位对齐 sha256 零差异（见 [S9e 实现记录](./docs/S9e-性能测试统一Node调用-实现记录.md)）：

| 点 | 模块数 | 本仓库 MoonBit(wasm) 单次(B 纯边际) | fast_qr-wasm32 单次 | fast/ours | 每模块成本 ours / fast |
|----|------:|-----------------------------------:|--------------------:|----------:|------------------------:|
| V03H | 841 | 0.314 ms | 0.085 ms | 0.27×（慢≈3.7×） | 0.374 / 0.101 µs |
| V10H | 3249 | 1.257 ms | 0.401 ms | 0.32×（慢≈3.1×） | 0.387 / 0.123 µs |
| V40H | 31329 | 9.66 ms | 3.554 ms | 0.37×（慢≈2.7×） | 0.308 / 0.113 µs |

> 两口径并列（S9e §4）：**A** 每次都新建 wasm Instance（与 fast_qr「一次调用」严格同形、含 Node 托管
> 固定项 ≈83µs/次）fast/ours = 0.18/0.27/0.33×；**B** 单实例摊薄（纯算法边际）如上表。
> 旧 S9c 口径（MoonBit 侧含子进程启动）为 0.20/0.29/0.35× —— 量级结论一致，S9e 只是把尺子统一干净。

**③ 同语言 vs moonbit 生态**（moonrun 同宿主、整程最小/N；见 [S9d 详细分析](./docs/S9d-与moonbit生态QR包性能对比-详细分析.md)）：
同尺寸、同语义（强制 V + ECL H + **自动择优** + 完整 Format/版本）可比子集 = 本仓库 vs `moonqr`，
本仓库全程快 **2.5–4.1×**（V03H 0.318 vs 0.805、V40H 9.46 vs 38.29ms/单次）。

- `qrc` / `moonbitqrcode` **不可同口径对齐**（仅参考口径）：`moonbitqrcode` lib 固定 mask0、仅 L/M/Q
  且只自动小版本（0.046ms = 跳过择优的**下限**，不代表完整质量）；`qrc` 自动版本疑似容量单位 bug、
  强制路径无 mask/Format（低值不代表完整 QR 成本）。

> **评估结论**：① 相对 Rust 参考 fast_qr 的 ~2.7–3.7×（S9e 统一口径）差距集中在「8 轮择优主循环」且可优化收窄；
> ② 相对 moonbit 生态完整实现（moonqr）本仓库**不落后且领先 2.5–4.1×**，完整「自动择优 + 可强制 ECL +
> 多版本」实现尚少、本库有生态价值；③ 数字仅作选型/迭代基线，不对齐追平 fast_qr 作硬承诺。

### 后续性能优化 Roadmap（详见 S9b 三篇）

**头号热点** = 自动择优 8 轮掩码评分主循环（V40H 占单次 auto 成本 ≈**86%**，随版本超线性放大）。
差分实测：V40H 单次 auto ≈7.99ms vs 固定 mask ≈1.13ms。

| 优先级 | 项 | 内容 | 状态 / 预期 |
|--------|----|------|-------------|
| **P1 已试** | T1（O1-a 就地翻转） | 免 8 轮全量 copy | ⛔ **实测否决**（+~8%，copy 非大头、score 多趟扫描才是） |
| **P1 已落地** | T2（O1-b 复用最优轮矩阵） | 省末尾第 9 次 copy | ✅ V40H 边际 9.007→8.874ms（≈−1.5%），快照/sha256/109 全绿 |
| **P1 主攻（下一步）** | T3（O2 score 减趟） | score 4 趟→3 趟（N4 dark 并入已有趟） | 预期 V40H 择优 −10–20%；对齐敏感区需逐步独立提交 |
| **P1** | T4（mask 判定特化） | 消除每格 `match mask_idx` | 预期 −5–10%；建议与 T3 同批、独立提交 |
| **P2** | T5（wrap 按 size² 分配） | 改善小版本固定开销 | 需先评估公共 `QRCode.data` 固定容量容器语义 |
| **P2/实验** | T6（表示宽度 Int→Byte） | 收窄 4B/格搬运 | 高风险大改面，先独立微基准再定 |
| — | — | — | **明确不追平** fast 每模块 0.07–0.10µs（Rust release+u8+LLVM 系数底） |

- **组合预期**（不承诺）：T3+T4 落地后 V40H 边际 ≈9 → **≈4–5ms**（fast 3.18ms 的 1.25–1.6×）。
- **验收统一**：每步快照逐位 diff 零差异 + 109 测试 + 双后端 checksum + `bash scripts/bench-layer2.sh`
  同尺子复跑（对照 S9c/S9d 总表观察差距收窄）。
- 落地约束：改代码需另立实施任务并遵守 roadmap「S5 O1 主循环重构单列 P2」；本文档仅给路线与现状。
- 入口：[S9b 评估与路线](./docs/S9b-性能优化-评估与路线.md) · [再评估与实施建议](./docs/S9b-性能优化-再评估与实施建议.md) ·
  [O1 实施记录](./docs/S9b-性能优化-O1实施记录.md)。

> 性能数字仅作选型与迭代基线，不代表对 fast_qr 的追赶承诺；逐条口径见 S9 系列文档。

---

## 文档索引

### 面向用户的文档

| 文档 | 说明 |
|------|------|
| [moonbit-项目目录设置-最佳实践.md](./docs/moonbit-项目目录设置-最佳实践.md) | 目录/包/测试设置的官方依据 + 实证验证 + 落地清单 |
| [moonbit-工具链与构建-setup-分析.md](./docs/moonbit-工具链与构建-setup-分析.md) | 工具链安装、构建系统与 CI 集成 |
| [wasm-编译与运行-结果分析.md](./docs/wasm-编译与运行-结果分析.md) | wasm 编译/运行全过程、产物结构、多后端对比与选型 |
| [rust-环境配置脚本与fast_qr对比-setup.md](./docs/rust-环境配置脚本与fast_qr对比-setup.md) | Rust 参考环境配置（`scripts/setup-rust.sh`）+ fast_qr 对比用法 |
| [性能测试脚本-公开评审说明.md](./docs/性能测试脚本-公开评审说明.md) | 性能测试脚本位置、参数口径与可复现路径（公开评审/审计入口） |

### 面向维护者 / 架构文档

工程与布局：

| 文档 | 说明 |
|------|------|
| [repo-初始化配置说明.md](./docs/repo-初始化配置说明.md) | 仓库初始化与云原生构建配置 |
| [core-仓库布局参考与目标架构.md](./docs/core-仓库布局参考与目标架构.md) | 参考 `moonbitlang/core` 得出的目标包架构与分阶段落地路线 |
| [moonbit-实现布局与文件职责.md](./docs/moonbit-实现布局与文件职责.md) | `lib/` 公共包 + `lib/internal/` 子包的文件职责、无环依赖规则、测试规划 |
| [代码布局检查与整理.md](./docs/代码布局检查与整理.md) | 代码放置位置检查、MoonBit 文件/测试约定与整理记录 |
| [moonbit-重写-roadmap-详细分析.md](./docs/moonbit-重写-roadmap-详细分析.md) | 重写路线图：架构要点、S1–S9 实现顺序、里程碑 M0–M3 与验证基座 |

实现系列（方案 → 记录 → 评审，按 S1–S9 顺序）：

<details>
<summary><b>S1–S9 实现系列文档（点击展开）</b></summary>

| 阶段 | 文档 | 说明 |
|------|------|------|
| **S1 数据结构** | [实现方案](./docs/S1-数据结构-实现方案.md) · [实现记录](./docs/S1-数据结构-实现记录.md) · [评审与优化](./docs/S1-实现评审与优化-记录.md) | ECL/Version/Mode/Mask/Module/QRCode/CompactQR 骨架与实现 |
| **S2 常量表与 GF256** | [实现方案](./docs/S2-常量表与GF256-实现方案.md) · [评估与源码核对](./docs/S2-实现评估与源码核对-记录.md) · [实现记录](./docs/S2-实现记录.md) · [评审与优化](./docs/S2-实现评审与优化-记录.md) | 容量表 + 分组/格式/生成多项式表 + GF(256) division/structure |
| **S3 数据编码** | [实现方案](./docs/S3-数据编码-实现方案.md) · [实现记录](./docs/S3-数据编码-实现记录.md) · [评审与优化](./docs/S3-实现评审与优化-记录.md) | 三模式编码 + best_encoding 自动回退 + terminator/8 位对齐 |
| **S4 矩阵与放置** | [实现方案](./docs/S4-矩阵与放置-实现方案.md) · [实现记录](./docs/S4-矩阵与放置-实现记录.md) | 功能图案绘制 + 之字形放置 + 8 掩码，M1 固定参数首码 |
| **S5 掩码评分与择优** | [实现方案](./docs/S5-掩码评分与择优-实现方案.md) · [实现记录](./docs/S5-掩码评分与择优-实现记录.md) · [评审与优化](./docs/S5-实现评审与优化-记录.md) | N1–N4 评分 + 8 轮择优主循环 |
| **S6 端到端对齐与公共 API** | [实现方案](./docs/S6-端到端对齐与公共API-实现方案.md) · [实现记录](./docs/S6-端到端对齐与公共API-实现记录.md) · [评审与优化](./docs/S6-实现评审与优化-记录.md) | 60 快照逐位对齐 + 公共 `QRBuilder`，收敛 M2 |
| **S7 输出层** | [实现方案](./docs/S7-输出层to_str与SVG-实现方案.md) · [评估与优化](./docs/S7-输出层to_str与SVG-实现评估与优化-记录.md) · [实现记录](./docs/S7-输出层to_str与SVG-实现记录.md) | 终端 `to_str`/`print` + 公共 `Shape`/`SvgBuilder` SVG |
| **S8 内部结构归位** | [实现方案](./docs/S8-内部结构归位与分层-实现方案.md) | 公共层文件级职责归位（qr.mbt → qr_build/qr_builder/qr_output） |
| **S9 性能基准** | [实现方案](./docs/S9-性能基准-实现方案.md) · [评估与优化](./docs/S9-性能基准-实现评估与优化-记录.md) · [实现记录](./docs/S9-性能基准-实现记录.md) | `cmd/bench` 三基准点 + 宿主计时，跨后端/生态对比，收敛 M3 |
| **S9b 性能优化** | [评估与路线](./docs/S9b-性能优化-评估与路线.md) · [再评估与实施建议](./docs/S9b-性能优化-再评估与实施建议.md) · [O1 实施记录](./docs/S9b-性能优化-O1实施记录.md) | 择优主循环逐热点优化评估与首批落地 |
| **S9c 层② fast_qr-wasm 对比** | [实现方案](./docs/S9c-性能测试与fast_qr-wasm对比-实现方案.md) · [实现记录](./docs/S9c-性能测试与fast_qr-wasm对比-实现记录.md) · [详细分析](./docs/S9c-性能测试与fast_qr-wasm对比-详细分析.md) | Node 调用 wasm 逐位对齐 + 同口径计时（收口 M3） |
| **S9d moonbit 生态对比** | [方案](./docs/S9d-与moonbit生态QR包性能对比-方案.md) · [实现记录](./docs/S9d-与moonbit生态QR包性能对比-实现记录.md) · [详细分析](./docs/S9d-与moonbit生态QR包性能对比-详细分析.md) · [moonbitqrcode 快速原因分析](./docs/S9d-moonbitqrcode快速原因与产物对比-分析.md) · [固定 mask0 缺陷与主流对比](./docs/S9d-moonbitqrcode固定mask0缺陷与主流对比.md) | 与 `qrc`/`moonqr`/`moonbitqrcode` 同语言对比 |
| **S9e 统一 Node 调用** | [实现方案](./docs/S9e-性能测试统一Node调用-实现方案.md) · [实现记录](./docs/S9e-性能测试统一Node调用-实现记录.md) | 两侧统一 Node 进程内调用 MoonBit/fast_qr wasm，重测并分析（issue #50） |

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

本仓库模块根只放元数据（对齐 `moonbitlang/core` 形态），按下列约定放置代码：

| 文件 / 目录 | 放置位置 | 约定 |
|-------------|---------|------|
| 模块配置 | 根目录 `moon.mod` | 声明 `name` / `preferred_target` / `supported_targets`；**根目录不建包**（无 `moon.pkg`） |
| 库包 | `lib/` + `lib/moon.pkg` | 库源码全部在 `lib/`；公共类型/入口在 `lib/` 根文件，实现子包在 `lib/internal/` |
| 库入口 | `lib/fast_qr_moonbit.mbt` | 文件名沿用模块名便于识别 |
| 黑盒测试 | `lib/<模块名>_test.mbt` | **包外**运行，只能访问 `pub` API；用 `@lib` 别名引用本包（别名 = 目录名 `lib`） |
| 白盒测试 | `lib/<模块名>_wbtest.mbt` | **包内**运行，可直接访问私有实现 |
| CLI 入口 | `cmd/main/` | `moon.pkg` 需写 `pkgtype(kind: "executable")` |
| 跨包依赖 | 使用方的 `moon.pkg` | `import { "tryandrun/fast_qr_moonbit/lib" @lib }`；声明后必须使用，否则触发 `unused_package` |

> **不要建 `src/`**：MoonBit 无 `src/` 约定；本仓库用 `lib/` 承载库包、`lib/internal/`
> 承载实现细节（与 core 的 feature 包 + internal 形态一致）。
> 包名由目录名决定且不可配置；目录内 `.mbt` 文件名则可自由命名。弃用代码放各目录的 `deprecated.mbt`。

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
  单测、多后端构建回归、性能基准），均由 `.cnb.yml` 在 CI（push）中按序调用。
- **代码门禁**：`moon fmt --check` + `moon check --deny-warn` + `moon test` + 双后端
  `wasm-gc`/`wasm` release 回归（`js` 已移除，不加 `native` 阶段——需系统 C 编译器）。
- **性能基准**：`bash scripts/bench.sh`（层①跨后端）；层② fast_qr-wasm 对比见
  `bash scripts/bench-layer2.sh`（**S9e 起两侧统一 Node 进程内调用**，见
  [S9e 实现记录](./docs/S9e-性能测试统一Node调用-实现记录.md)）。
- **Git 钩子（可选）**：`git config core.hooksPath .githooks`（个人本地配置，仓库不代设）。
- **编码 / 提交规范**：见 [AGENTS.md](./AGENTS.md)（密钥安全、MoonBit 布局、文档死链零容忍等硬性约定）。

常用脚本一览：

| 脚本 | 作用 |
|------|------|
| `setup-moonbit.sh` | 安装 MoonBit 工具链并校验 |
| `fmt-check.sh` / `check.sh` / `test.sh` | 格式门禁 / 静态检查门禁 / 单元测试 |
| `build-and-run.sh` | 双后端（wasm-gc/wasm）构建 + 运行 + 测试回归 |
| `bench.sh` | S9 层① 宿主计时（多次取最小） |
| `bench-layer2.sh` | 层② Node（S9e：**同一进程内**）调用 wasm 与 fast_qr 对比 |
| `moonbit-wasm-runner.mjs` | Node 进程内托管 MoonBit WASI 产物的运行器（S9e 统一宿主） |
| `wasm-compare.mjs` | 层② 对比驱动：逐位对齐 + A/B 双口径计时（S9e 统一 Node 调用） |
| `build-fast-qr-wasm.sh` | 构建 fast_qr v0.14.0 `qr_with` nodejs 产物（外部检出，不入库） |
| `setup-fast-qr-wasm-env.sh` | 层②环境：rust wasm32 target + gcc + 预编译 wasm-bindgen-cli（幂等） |
| `setup-rust.sh` | 安装 Rust 工具链（rsproxy 镜像，供 fast_qr 参考对比，可选） |

---

## License

[Apache-2.0](./LICENSE)
