# S9i · 纯库调用体积探针与「库实际体积」口径

> **状态**：现行　｜　日期：2026-09-23　｜　索引：[docs/README.md](../README.md) §2

> 背景与动机：[S9g](S9g-本项目wasm产物体积-确认与修正.md) 的体积口径只有 `cmd/bench`
> （性能基准外壳）与 `cmd/main`（CLI 演示外壳）两档**可执行包**——它们度量的是「命令形态」
> 的产物体积，**不能代表本库被宿主嵌入时的实际体积**：外壳代码（argv 解析、迭代循环、
> `--dump` 导出、终端字符画、SVG）不随库分发，宿主按需裁剪。
> S9g §0 已预告「换成纯库调用可再收窄」，本文补齐这一口径，并修正 ⑤ 同功能锚点的**不对称**问题。
> 日期：2026-09-11　｜　工具链：`moon 0.1.20260904`、Node `v24.20.0`、`moon-wasm-opt`（Binaryen 125）
> 前置：main @ `e5569ad` 附近｜**不改 lib / 公共 API / 快照 / `cmd/bench` / `cmd/main` 默认行为**
>
> ⚠️ **2026-09-12 重测更新**：本文 2026-09-11 首测数字随工具链/构建环境有 ±0.2–0.4% 的正常漂移，
> 且 `cmd/qr-min` 在 P0/P2/P2b 优化后代码规模微调。**09-12 重测值为**
> `raw 41427 B` / `-Oz **31365 B**`（净增 **+31102 B**），与 README「编译为 Wasm」表一致；
> 重测详见 [S9o](S9o-性能与体积数据重测-与README冗余清理.md)。下表保留首测原始记录以便对照。
>
> ⚠️ **2026-09-23 再测（工具链 `moon 0.1.20260920`）**：`cmd/qr-min` raw **41778 B** / `-Oz` **31629 B**
> （净增 **+31366 B**，较 09-12 基线 +0.84%）；`cmd/main` `-Oz` **33841 B**（+0.74%）；
> `cmd/bench` `-Oz` **39706 B**（**+9.8%**，argv/`@env` 外壳随工具链膨胀，不影响库分发体积）。
> fast_qr 参考侧产物逐字节未变（裸探针 `-Oz` 45687 B）。**本节 §0 数字已更新为再测值**；
> 末次明细与结论见 [S9r](S9r-README性能体积长口径与公共API明细.md) §1，§3 各表保留 09-11 首测原值。

---

## 0. 结论先行（数字可直接引用）

**「库实际体积」= `cmd/qr-min` 纯库调用探针（release，`-Oz` 可加载档）：**

| 产物 | 后端 | raw | `-Oz`（可加载档） |
|------|------|----:|------------------:|
| **`cmd/qr-min`（纯库调用）** | **`wasm-gc`（默认）** | 41294 B → **41778 B** | **31470 B → 31629 B**（30.9 KiB） |
| `cmd/qr-min` | `wasm`（WASI） | 72227 B | 47878 B（46.8 KiB） |

**体积金字塔（`wasm-gc`，`-Oz`，同场实测）：**

| 层 | 产物 | `-Oz` (B) | 说明 |
|----|------|----------:|------|
| 运行时地板 | hello-only 探针 | **263** | 一行 `println`，对象交给宿主 GC |
| **QR 核心管线（库实际体积）** | **`cmd/qr-min`** | **31629**（09-12 为 31365） | 仅 build 路径 + 一行 `println`；净增 **+31366 B** |
| + 输出层 | `cmd/main` | 33841（09-12 为 33593） | 终端字符画 + SVG + Shape 共 **+2212 B**（2.2 KB） |
| + 基准外壳 | `cmd/bench` | 39706（09-12 为 36174） | argv/env/迭代/`--dump`/checksum 共 **+8077 B**（7.9 KB） |

**一句话**：作为库被嵌入时，本库 QR 核心在默认后端 `wasm-gc` 下约 **30.9 KB**（净增 **+31366 B**），
此前以 `cmd/bench`/`cmd/main` 引用的 33–39 KB 是「命令形态」上限；输出层只占 2.2 KB，
基准外壳占 7.9 KB。**引用本库体积时请用 `cmd/qr-min` 口径并注明后端与优化档。**

> ⚠️ 对外对比口径（S9j 补充）：与 fast_qr 的体积对比**统一取默认后端 `wasm-gc`**；
> 本文表中的 `wasm`(WASI) 数据仅作兜底记录，不参与对外对比。

---

## 1. 问题：命令形态 ≠ 库体积，且锚点对比不对称

### 1.1 MoonBit 侧从未测过「纯库调用」

S9f/S9g 的 MoonBit 侧数字全部来自两个可执行包：

| 产物 | 外壳内容（不随库分发的部分） |
|------|------------------------------|
| `cmd/bench` | `@env` argv 解析、版本选择/迭代数解析、N 次循环、`--dump` 值全集文本导出、checksum 累加 |
| `cmd/main` | 终端字符画渲染（`helpers.mbt`）、SVG 渲染（`svg.mbt` + 6 种 `Shape`）、演示编排 |

宿主集成（如 JS 宿主调 wasm 生成二维码）通常只需要 build 路径（可选输出层），
用命令形态数字对外承诺库体积**系统性偏高**（wasm-gc 侧偏高 ≈2.2–7.9 KB，见 §2 归因）。

### 1.2 ⑤ 同功能锚点两侧不对称

S9f/S9g 的 ⑤ 锚点对比：

| 侧 | 产物 | 形态 |
|----|------|------|
| fast_qr | `s9f_size_probe`（45687 B） | **核心-only**：`QRBuilder::build` + 返回矩阵长度，无胶水 |
| MoonBit | `cmd/bench`（53745/36296 B） | **基准外壳**：argv + 迭代 + `--dump` + checksum |

Rust 侧早有「核心-only 裸探针」，MoonBit 侧却拿全外壳对撞——MoonBit 侧被**高估**，
该口径不满足「同形对撞」。本文的 `cmd/qr-min` 即 MoonBit 侧的对称探针。

---

## 2. 探针设计（`cmd/qr-min`，已入库）

### 2.1 形态约束（对齐 fast_qr `s9f_size_probe`）

- **语义**：对三基准点（V03/V10/V40；输入 `https://example.com/`=20B、ECL=H、mask 自动择优）
  各 build **一次**，把 `size` 与代表性模块字节（`get(0,0)` / `get(sz-1,sz-1)` / `get(sz/2,sz/2)`）
  累加进校验总量，末尾 `println` 一行 `QR_MIN_CHECKSUM=<定值>`。
- **防死代码消除**：build 结果被真实读取消费（口径同 `cmd/bench` 单点采样），无空循环风险。
- **最小宿主面**：除 `println`（与 hello 地板同面，地板扣除自洽）外零依赖——
  不 import `@env`、不读 argv、不含 `--dump`、不含终端画/SVG。
- **语义护栏**：两后端输出恒为 `QR_MIN_CHECKSUM=283`
  （= 三点 size 之和 263 + 6 个模块字节 20），跨后端/跨优化档必须一致。

### 2.2 为什么探针必须是仓内 `cmd/` 包

fast_qr 侧探针是外部检出副本里的临时 `bin`（不入库）；MoonBit 侧探针必须 `import @lib`
（同模块内包引用），只能在仓内建 `cmd/qr-min`（`pkgtype(kind: "executable")`）。
副作用是**任何人可一键复跑**：`moon build cmd/qr-min --release` 即得产物，比外部探针更可审计。
代价：`cmd/qr-min` 源码本身不入产物体积（体积只统计 wasm 产物字节），无口径污染。

### 2.3 量测与护栏规则（沿用 S9f/S9g 同尺子）

- 优化档：`wasm-gc` 用 `moon-wasm-opt --all-features --disable-custom-descriptors -Oz`
  （可加载条件下的体积最优解，见 S9g §3）；`wasm`(WASI) 用 `--all-features -Oz`。
- 护栏：原始 / `-Oz` 产物在 moonrun（wasm-gc）/ Node WASI runner（wasm）下输出逐字节一致，
  不一致即 exit 1（体积优化不得悄悄改语义）。
- 脚本已接入：`scripts/bench-size.sh` 新增 `MOON_QRMIN_WASM` / `MOON_GC_QRMIN_WASM` 通道并
  构建 `cmd/qr-min`；`scripts/wasm-size.mjs` 新增 `--moon-qrmin-wasm` / `--moon-gc-qrmin-wasm`
  参数、⑤ 锚点行、⑤b 纯库调用行与结论项 ⑥（JSON 输出同步新增 `moonQrmin` / `moonGcQrmin`）。

---

## 3. 实测结果（2026-09-11，同场实测）

### 3.1 体积金字塔（`wasm-gc` 默认后端，`-Oz`）

| 层 | 产物 | raw (B) | `-Oz` (B) | 相邻增量 |
|----|------|--------:|----------:|---------:|
| 运行时地板 | hello-only | — | 263 | — |
| **QR 核心管线** | **`cmd/qr-min`** | 41294 | **31470** | **+31207** |
| + 输出层（终端画 + SVG） | `cmd/main` | 44308 | 33709 | +2239 |
| + 基准外壳（argv/迭代/`--dump`） | `cmd/bench` | 47912 | 36296 | +4826 |

> 输出层只占 **2.2 KB**——对完整公共面（含 6 种 Shape 的 SVG）而言出乎意料地小；
> 基准外壳占 **4.8 KB**，其中 `--dump` 文本导出与 argv/迭代解析是大头。

### 3.2 `wasm`(WASI) 兜底侧

| 产物 | raw (B) | `-Oz` (B) | 净增（扣 hello 地板 2095 B） |
|------|--------:|----------:|---------------------------:|
| `cmd/qr-min` | 72227 | 47878 | +45783 |
| `cmd/main` | 75949 | 51043 | +48948 |
| `cmd/bench` | 81666 | 53745 | +51650 |

### 3.3 修正后的对称锚点（纯库调用 vs 裸探针，`-Oz`）

| 口径 | MoonBit 侧 | fast_qr 侧 | ours / fast | S9g 旧值（不对称） |
|------|-----------:|-----------:|------------:|------------------:|
| `wasm-gc`（默认） | `cmd/qr-min` **31470** | 裸探针 45687 | **0.69×** | 0.79×（bench 36296） |
| `wasm`（WASI） | `cmd/qr-min` **47878** | 裸探针 45687 | **1.05×** | 1.18×（bench 53745） |
| 核心净增（`wasm-gc`） | +31207 | +25635（45687−20052） | 1.22× | 1.41×（+36033） |
| 核心净增（`wasm`） | +45783 | +25635 | 1.79× | 2.01×（+51650） |

**修正结论**：

1. `wasm-gc` 侧「对称锚点」从 0.79× 收窄到 **0.69×**——此前 MoonBit 侧被 bench 外壳高估约 1.5 KB；
2. `wasm`(WASI) 侧从 1.18× 收窄到 **1.05×**——**纯算法产物两侧基本同档**，
   此前 1.18× 里的差距主要是 MoonBit WASI 运行时之上又叠了外壳，而非 QR 实现；
3. 运行时地板结论不变（`wasm-gc` 263 B vs Rust 20052 B）；
4. S9g 的 ①–④ 口径（vs `fast_qr_bg` 含胶水面）不受影响，仍按原文引用。

---

## 4. 语义护栏（本次实测）

| 侧 | 护栏 | 结果 |
|----|------|------|
| MoonBit `wasm-gc` `cmd/qr-min` | raw / `-Oz` 输出逐字节一致（moonrun） | 一致 `QR_MIN_CHECKSUM=283` |
| MoonBit `wasm` `cmd/qr-min` | raw / `-Oz` 输出逐字节一致（Node WASI runner） | 一致 `QR_MIN_CHECKSUM=283` |
| MoonBit `wasm-gc` bench/main | 复跑 `-Oz` = 36296 / 33709 B | 与 S9g 完全一致（工具链未漂移） |
| 既存四组护栏 | `bash scripts/bench-size.sh --no-build` | 全部通过（sha256 与 S9g 记录一致） |

---

## 5. 复跑方式

```bash
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
bash scripts/bench-size.sh              # 全流程（含 cmd/qr-min wasm-gc 构建 + 五组护栏）
bash scripts/bench-size.sh --no-build   # 产物就绪时只量测
```

单测探针本体（输出必须为 `QR_MIN_CHECKSUM=283`）：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon run cmd/qr-min                                  # 唯一后端 wasm-gc
```

---

## 6. 汇总

1. **问题**：`cmd/bench`/`cmd/main` 是「命令形态」产物，外壳（argv/迭代/`--dump`/终端画/SVG）
   不随库分发，其体积不能代表库实际体积；且 ⑤ 同功能锚点两侧形态不对称（Rust 裸探针 vs MoonBit 全外壳）。
2. **方案**：新增仓内探针 `cmd/qr-min`（语义对齐 fast_qr `s9f_size_probe`：三基准点各 build 一次 +
   消费结果 + 一行 `println`，零外壳），并接入 `bench-size.sh` / `wasm-size.mjs` 同尺子流水线。
3. **数字**：库实际体积（`wasm-gc`，`-Oz`）= **31470 B**，扣 263 B 地板后核心净增 **+31207 B**；
   输出层 +2239 B、基准外壳 +4826 B。对称锚点：`wasm-gc` **0.69×**、`wasm` **1.05×**。
4. **引用规范**：本库体积一律用 `cmd/qr-min` 口径并注明后端与优化档；`cmd/bench`/`cmd/main`
   数字仅代表「命令形态」，须显式说明。
5. **护栏**：不改 lib / 公共 API / 快照 / 既有 `cmd` 默认行为；五组语义护栏全绿；
   `.mbti` 零漂移（探针为可执行包，不涉公共接口）。

---

## 7. 参考

- 前序口径：[S9f 产物体积对比](S9f-产物体积对比.md) · [S9g 确认与修正](S9g-本项目wasm产物体积-确认与修正.md)
- 同尺子性能口径：[S9e 性能统一 Node 调用](S9e-性能测试统一Node调用.md)
- 本仓库实码：`cmd/qr-min/`（探针本体）、`scripts/bench-size.sh`（构建 + 通道）、
  `scripts/wasm-size.mjs`（量测 + 护栏）、`scripts/build-and-run.sh`（CI 覆盖探针编译）
- 环境：moon 0.1.20260904、Node v24.20.0、moon-wasm-opt（Binaryen 125）、
  fast_qr v0.14.0（`53e8c99`）+ wasm-bindgen 0.2.100（外部检出副本，探针不入库）
