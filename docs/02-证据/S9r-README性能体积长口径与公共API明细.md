# S9r · README 长口径承接：性能/体积/公共 API 明细

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README.md](../README.md) §2

> 背景：ISSUE #47 多轮要求「README 去冗杂 → README 只保留索引」。
> README 原先在**正文内**保留了体积表、性能明细表、Roadmap 编号细节与公共类型表；
> 它们与 `docs/S9*`、`lib/*.mbt` 高度重复。本轮把**明细原样迁到本文档**，
> README 只留「量级结论 + 出处链接」。
> 日期：2026-09-14　｜　口径口径与复跑见 [性能测试脚本-公开评审说明](性能测试脚本-公开评审说明.md)
> ｜　权威出处：体积 [S9i](S9i-纯库调用体积探针与库实际体积.md)、性能 [S9p](S9p-宿主调用面性能口径-JS向wasm传参.md) / [S9q](S9q-性能口径统计差异与取平均评估.md)
>
> **本文不是新结论**，是 README 历史正文的**归档承接**（数字未重测，出处与离散口径以原文为准）。

---

## 1. 产物体积（release，`bash scripts/bench-size.sh`）

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

`-Oz` 体积最优档（默认后端 `wasm-gc`）：

```bash
# --all-features 会开 custom-descriptors(RTT)，其 exact heap type 在 Node/moonrun 上编译不过；
# --disable-custom-descriptors 才产出「可被真实宿主加载」的最优档。
moon-wasm-opt _build/wasm-gc/release/build/cmd/main/main.wasm \
  --all-features --disable-custom-descriptors -Oz -o main.min.wasm   # 33593 B
```

### 1.1 与 fast_qr 的体积对比（库对库主口径）

两侧同为「核心-only + 一行 `println`」（MoonBit `cmd/qr-min` vs fast_qr 无胶水裸探针）：

| 口径（B） | MoonBit `wasm-gc` | fast_qr 裸探针 | ours / fast |
|-----------|------------------:|---------------:|------------:|
| raw | 41427 | 59440 | **0.70×** |
| `-Oz`（可加载档） | **31365** | 45687 | **0.69×** |
| 核心净增（扣 hello 地板 263 / 20052 B） | **+31102** | +25635 | 1.21× |

> **结论**：库对库，`wasm-gc` 在 raw 与 `-Oz` 两档都约 **0.69–0.70×**；扣掉运行时地板后核心净增
> 1.21×——差距大头是两侧**运行时地板**（`wasm-gc` 263 B vs Rust 20052 B，76×），非 QR 实现差异。
> 命令形态（`cmd/bench` 含 argv/迭代外壳）对照与其他档位明细见 [S9i](S9i-纯库调用体积探针与库实际体积.md) ·
> [S9f](S9f-产物体积对比.md)。

---

## 2. 性能三口径（核心结论表）

> 引用的性能数字仅作选型与迭代基线，**不代表对 fast_qr 的追赶承诺**；逐条口径见 S9 系列文档。

复跑入口：`bash scripts/bench-host.sh`（宿主调用面）· `bench-host-var.sh`（统计稳定性）·
`bench-layer2.sh`（层② vs fast_qr）· `bench.sh`（层① 后端）· `bench-size.sh`（体积）。
统一口径：输入 `https://example.com/`=20B、ECL H、强制 V03/V10/V40、mask 自动择优。

| 对比 | 结果 | 出处 |
|------|------|------|
| ① vs Rust fast_qr-wasm32（**默认后端 `wasm-gc`**） | 单次 build 慢 ≈**1.3–2.5×**，逐位对齐 sha256 零差异；差距集中在 8 轮掩码择优主循环 | 明细见下表 · [S9p](S9p-宿主调用面性能口径-JS向wasm传参.md) · [S9j](S9j-层②统一Node对比-wasm-gc与fast_qr.md) |
| ② vs moonbit 生态 `moonqr`（同宿主、完整实现可比子集） | 本仓库全程快 **2.5–4.1×**（V03H 0.318 vs 0.805、V40H 9.46 vs 38.29 ms/单次，历史口径） | [S9d](S9d-与moonbit生态QR包性能对比.md) |
| ③ 产物体积 vs fast_qr | `wasm-gc` 各口径均更小（对称锚点 **0.69×**） | [§1.1](#11-与-fast_qr-的体积对比库对库主口径) · [S9i](S9i-纯库调用体积探针与库实际体积.md) |

> ① 的数据随 P0/P2/P2b 优化已刷新（2026-09-12 重测）；② 为优化前（2026-09-06）历史口径，
> 未随本轮重测，量级参考即可。

### 2.1 vs fast_qr-wasm32：性能明细（宿主调用面主口径）

**主口径 = 宿主调用面（[S9p](S9p-宿主调用面性能口径-JS向wasm传参.md)）**：宿主一次 `compile`
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
> 全部下沉到 [S9q](S9q-性能口径统计差异与取平均评估.md) · [S9p](S9p-宿主调用面性能口径-JS向wasm传参.md) §4.1 ·
> [S9h](S9h-层②性能复测异常归因-Node版本与宿主漂移.md) · [S9d](S9d-与moonbit生态QR包性能对比.md)。
> **护栏全绿**：宿主面 checksum 与 `cmd/bench <点> 1` 逐点相同 · 逐位对齐 sha256 三点相同 · 跨宿主一致。

### 2.2 后续优化 Roadmap

- **成本分解**（[S9k](S9k-性能瓶颈与理论上限评估.md)）：V40H 约 **68% 在 8 轮 `score`** + 11% `apply_mask`；
  V03H 约 **44% 在结果容器 `wrap_packed`**。优先级据此定为 **P0 容器 / P1 score 减趟与掩码特化**。
- **已落地**（[S9n §6](S9n-优化方案复评与wasm-gc收敛审计.md)）：P0 掩码特化 + P2 评分去闭包/列缓冲 + P2b N4 并入行趟，
  V40H 受控 A/B **−26%**（V10H −24%、V03H −4%），`TOTAL_CHECKSUM` 三项与基线完全相同（输出逐位不变）；
  ReadOnlyArray 只读化 + `prefer_readonly_array` lint 亦已落地（**≈0.9%**，定性「类型对齐为主、非性能杠杆」）。
- **待做与上限**：容器 P1 受阻于 `QRCode.data` 固定容量公共契约（须 API 评审）；P2b(N2)/P3/T-R5 待做。
  理论上限≈ fast_qr 同执行模型（本环境 V40 ≈3.55 ms），现实可收窄到 V40 **≈3.6–4.2 ms**；
  V03 受每次 build 固定成本约束，**仍慢约 1.1–1.4×、大概率不追平**。
  已否决项（T1/O1-a 就地翻转）见 [S9b](S9b-性能优化.md)，统一优先级清单见 [S9n §3](S9n-优化方案复评与wasm-gc收敛审计.md)。

---

## 3. 公共类型一览（README 旧正文承接）

| 类型 | 位置/说明 |
|------|-----------|
| `ECL` / `Version` / `Mode` / `Mask` | 纠错级别（L/M/Q/H）、版本（V01–V40）、编码模式、掩码枚举 |
| `QRCode` | 生成结果容器（矩阵 + size/version/ecl/mask/mode 元数据 + `to_str`/`print`） |
| `QRCode::build` / `build_fixed` | 过程式编排入口（input/mode/ecl/version/mask → `Result[QRCode]`；`build` 的 `Some(mask)` 分支委托 `build_fixed`） |
| `QRCode::empty` | **空矩阵构造**（宿主自建/改写矩阵的唯一入口） |
| `QRCode::get` / `set` / `meta` / `data`（+ `size`/`version`/`ecl`/`mask`/`mode`） | 逐格读写与元数据访问器（`set` 不可变式，返回新 `QRCode`） |
| `QRCode::select_capacity` | 容量/版本三元组解析（显式模式参与判定，供自定义编排复用） |
| `QRBuilder` | 链式构造器：`from_string`/`new` + `mode/ecl/version/mask` + `build` |
| `Module` / `ModuleType` | 单像素模块（明暗 + 8 种功能归属）；`Module::new(value, type)` 为通用构造 |
| `SvgBuilder` / `Shape` | SVG 字符串输出；6 种模块形状（square/circle/rounded_square/vertical/horizontal/diamond）；链式 `margin/module_color/background_color/shape` |
| `Shape::from_name` | 由名字（大小写不敏感）取形状枚举，未知名回退 |
| `ECL::to_char` | 纠错级别 → 显示字符（`L`/`M`/`Q`/`H`） |
| `QRCodeError` | 构造错误（`EncodedData` 数据过大、`SpecifiedVersion` 版本过小） |

### 3.1 矩阵读写与自建（宿主可拿到 `QRCode`）

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
> 上面是 `nocheck` 展示块（**不受门禁保护**，仅示意）；受门禁保护的可运行示例见
> [README 快速开始](../../README.md#快速开始) 的 `mbt check` 块与 [`cmd/main`](../../cmd/main/main.mbt)。

---

## 4. 脚本分组（README 旧正文承接）

README「开发与 CI」原本内联了一张 **12 行**逐脚本表 + 分组表。现由本节承接，
README 只留一行「`bash scripts/<name>.sh` + 指向 `scripts/` 目录」。

`scripts/` 按角色分组（**push CI 已移除**；门禁链由 `gates.sh` 本地一键触发，
环境配置与对外对比脚本仅本地/审计时手动执行）：

| 角色 | 脚本 | 执行方式 |
|------|------|:--------------:|
| 环境配置 | `setup-moonbit.sh`、`setup-rust.sh`、`setup-fast-qr-wasm-env.sh` | 手动（幂等，本地/审计） |
| **全量门禁** | **`gates.sh`**（`fmt-check` → `check` → `test` → `docs-link-check` → `test-scale` → `build-and-run` → `diff-gate` → `publish-check`） | **本地** |
| **发布** | **`publish.sh`**（默认干跑；`--publish` 才真发，需确认） | **本地（不进 CI）** |
| 门禁链单项 | `fmt-check.sh` → `check.sh` → `test.sh` → `build-and-run.sh` | 本地（亦由 `gates.sh` 串起） |
| 性能基准 | **`bench-host.sh` + `host-bench.mjs`（宿主调用面：JS 反复带参调 wasm，主口径）**、`bench-host-var.sh` + `bench-host-var.mjs`（统计稳定性）、`bench.sh`（层①）、`bench-layer2.sh` + `gc-compare.mjs`（层② vs fast_qr） | ❌ |
| 体积基准 | `bench-size.sh` + `wasm-size.mjs`（同规则口径 + 纯库探针 + 语义护栏） | ❌ |
| 外部检出 | `build-fast-qr-wasm.sh`（fast_qr 侧产物，检出副本不入库） | ❌ |
| 测试审计 | `test-audit.sh`（变异检测 + 解码回读）+ `apply-mutation.py` + `qr-decode-check.mjs`（`--points` 三点 / `--corpus` T3-d 54 组） | ❌ |
| 黄金值/规模 | `gen-goldens.sh`（钉版重建 + `--verify` 四项）+ `snapshot_gen_*.{py,rs,mjs}` + `snapshot_verify_*.py` + `test-scale.sh`（单测试文件 ≤800 行护栏） | ❌ |
| 差分门禁 | `diff-gate.sh`（vs 参考 wasm 逐位 sha256；无制品显式 skipped） | 本地（可 skipped） |
| 覆盖率 | `coverage.sh`（`moon coverage analyze` 报告）+ **`--floor` 不下降门禁（T5-b）** | ❌ |
| 文档/规模护栏 | **`docs-link-check.sh`（T6-c 相对链接死链）** + `test-scale.sh`（T7-b 单测试文件 ≤800 行） | 本地 |
| 资源生成 | `gen-readme-qr-svg.sh`（重建 `docs/assets/qr-example.svg`，临时包用完即删） | ❌ |

---

## 5. 引用纪律（从 README 迁来的原因）

1. 上述**数字与表格**是「证据与历史」，随实现漂移——放在 README 会**必然过期**；
2. README 是**落地页**，读者第一屏需要的是「能做什么 / 怎么用 / 局限」；
3. 同一结论**一处权威**：数字只留在 S9 系列（本文档仅承接 README 旧正文，不新增结论），
   README 只写「量级 + 出处」。
