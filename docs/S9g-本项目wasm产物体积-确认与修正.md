# S9g · 本项目 wasm 产物体积 · 确认与修正

> ⚠️ **历史记录**：MoonBit `wasm`(WASI) 后端已按项目决策移除，本项目现仅支持 `wasm-gc`；本文涉及的 `wasm` 后端数字与口径仅作历史留存，不再作为对外口径。

> 本文直接回答 issue #50 复审提出的问题：**「本项目 wasm 产物体积到底多大」**，
> 并修正 [S9f](./S9f-产物体积对比.md) 初版的两处口径错误。
> 日期：2026-09-10　｜　工具链：`moon 0.1.20260904`、Node `v24.20.0`、`moon-wasm-opt`（Binaryen 125）
> 前置：main @ `51e5092`｜**不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**

---

## 0. 结论先行（数字可直接引用）

**本项目 wasm 产物体积（release，`cmd/bench` 基准命令）：**

| 后端 | raw | 剥 custom 段 | `-Oz`（可加载档） | 说明 |
|------|---:|-------------:|------------------:|------|
| **`wasm-gc`（默认，`preferred_target`）** | **47912 B**（46.8 KiB） | 47790 B | **36296 B**（35.4 KiB） | 本库对外分发形态 |
| `wasm`（WASI 兜底） | 81666 B（79.8 KiB） | 81544 B | 53745 B（52.5 KiB） | 旧宿主兼容档 |

**`cmd/main`（演示 CLI：终端字符画 + SVG）：**

| 后端 | raw | `-Oz` |
|------|---:|------:|
| **`wasm-gc`（默认）** | **44308 B**（43.3 KiB） | **33709 B** |
| `wasm`（WASI） | 75949 B（74.2 KiB） | 51043 B |

**`lib` 公共库代码本身的体积增量**（hello-only 基线扣除法）：

| 项 | `wasm-gc` | `wasm`(WASI) |
|----|----------:|-------------:|
| 运行时地板（一行 `println`，`-Oz`） | **263 B** | 2095 B |
| 完整基准/CLI 产物（`-Oz`） | 36296 / 33709 B | 53745 / 51043 B |
| ⇒ lib 代码净增（含 `cmd` 外壳） | **≈ +33–36 KB** | **≈ +49–52 KB** |

**一句话**：**默认后端 `wasm-gc` 下，本库完整 QR 生成能力（含三基准点/`--dump`/checksum 外壳）约 36 KB；
换成纯库调用可再收窄（实测 30.7 KB，见 [S9i 纯库调用体积探针](./S9i-纯库调用体积探针与库实际体积.md)）；
`wasm-gc` 比 `wasm` 小 32.5%。**

> ⚠️ 引用规范（S9i 补充）：`cmd/bench` / `cmd/main` 是「命令形态」产物，外壳（argv/迭代/`--dump`/
> 终端画/SVG）不随库分发，**不能代表库被宿主嵌入时的实际体积**；引用本库体积请用
> `cmd/qr-min` 口径（`wasm-gc` `-Oz` = 31470 B，核心净增 +31207 B）并注明后端与优化档。
>
> ⚠️ 对外对比口径（S9j 补充）：与 fast_qr 的性能/体积对比**统一取默认后端 `wasm-gc`**；
> 本文 `wasm`(WASI) 数据仅作历史记录，不参与对外对比。

---

## 1. 为什么此前没有这个数字

S9f 初版只量了 **`wasm`(WASI) 侧**产物，原因是「与 S9e 性能对比同源」。
但 `moon.mod` 明确写着：

```toml
preferred_target = "wasm-gc"   # 默认且唯一后端 = wasm-gc
supported_targets = "+wasm-gc" # wasm(WASI)/js 已移除
```

`README`、`AGENTS.md` 也一致声明「`wasm-gc` 主推（体积小 83%、快约 33%）」。
**用一个兜底后端代表「本项目产物体积」是不对的** —— 这是本次修正的核心。

> 注：此前不量 `wasm-gc` 有一个真实的技术原因（见 §3），本次已解决。

---

## 2. 修正一：`wasm-gc` 通道已补测（默认后端）

### 2.1 两侧同规则对照（`cmd/bench`）

| 档位 | MoonBit `wasm-gc` (B) | MoonBit `wasm` (B) | fast_qr_bg (B) | gc / fast_qr |
|------|----------------------:|-------------------:|---------------:|-------------:|
| ① raw 原始产物 | **47912** | 81666 | 61510 | **0.78×** |
| ② 剥 custom 段 | 47790 | 81544 | 53476 | **0.89×** |
| ③ `-Oz`（可加载档） | **36296** | 53745 | 49956 | **0.73×** |
| ④ `-Oz` + 宿主胶水 | 36296（无胶水） | 53745（无胶水） | 58173 | **0.62×** |

- 跨后端：`wasm-gc` 比 `wasm` 小 **32.5%**（36296 vs 53745 B，`-Oz`）。
- 对 fast_qr：**四种口径下 `wasm-gc` 都更小**（0.62×–0.89×），不再有「谁更小取决于口径」的歧义。
- ✅ **没变小丑话**：`wasm-gc` 不是靠丢功能换体积 —— 同一套源码、同一份 `cmd/bench`、
  同样输出 `82000/32400/9200`（见 §4 语义护栏）。

### 2.2 `cmd/main`（另一档场景）

| 指标 | `wasm-gc` | `wasm` |
|------|----------:|-------:|
| raw | 44308 B | 75949 B |
| `-Oz` | **33709 B** | 51043 B |

---

## 3. 修正过程中的一个真实技术障碍（`--disable-custom-descriptors`）

### 3.1 现象

`moon-wasm-opt <wasm-gc 产物> --all-features -Oz` **能成功产出**（36535 B），
但产物**任何宿主都加载不了**：

```text
# Node 24
CompileError: invalid heap type 'exact', enable with --experimental-wasm-custom-descriptors
# 加 --experimental-wasm-custom-descriptors 后仍失败
CompileError: type error in constant expression (expected (ref null exact 3), got nullref)
# moonrun（MoonBit 官方运行时）
Uncaught CompileError: invalid heap type 'stringview_wtf16', enable with --experimental-wasm-stringref
```

### 3.2 根因

`--all-features` 打开了 **custom-descriptors（RTT，`exact` heap type）** 提案，
`moon-wasm-opt` 会据此**改写类型系统**（把 `(ref null $T)` 变成 `(ref null exact $T)`），
而当前 Node 24 / Binaryen 125 运行端对该提案的支持不完整（类型常量表达式校验不过）。
也就是说：**`-Oz` 越「激进」，产物越「编译得过、跑不起来」。**

### 3.3 解法（已落地为脚本默认）

```bash
moon-wasm-opt <in> --all-features --disable-custom-descriptors -Oz -o <out>
```

关掉 custom-descriptors 后，产物 **36296 B** 且 **moonrun / 真实宿主均可加载运行**。
对照各优化档（均以「moonrun 能跑通 + `--dump V03` 输出正确」为可加载判据）：

| 档 | 体积 (B) | 可加载 |
|----|--------:|:------:|
| 不优化（raw） | 47912 | ✅ |
| `-O1` | 40318 | ✅ |
| `-O2` | 36697 | ✅ |
| `-O3` | 38106 | ✅ |
| `-O4` | 37930 | ✅ |
| `-Os` | 36348 | ✅ |
| **`-Oz` + `--disable-custom-descriptors`** | **36296** | ✅ |
| `-Oz` + `--all-features`（含 RTT） | 36535 | ❌ 编译不过 |

> 结论：**可加载条件下的体积最优解 = `--all-features --disable-custom-descriptors -Oz`**。
> 顺手拿到一条副产品：`-Oz` 在该产物上仅比 `-Os` 小 52 B，但比 `-O2` 小 401 B。

---

## 4. 修正二：⑤ 同功能锚点初版结论反了（0.92× → 1.18×）

### 4.1 错在哪

S9f 初版写：

> 同功能锚点（都无胶水、都自带运行时）：fast_qr 裸探针 **58632 B** vs MoonBit bench **53745 B = 0.92×**

**58632 B 是一个「被污染」的数字。** fast_qr 检出副本一旦有 `wasm-bindgen` feature，
Cargo 会把 `wasm-bindgen` **强制链进同 crate 的全部 target（含 `bin`）**：

| 探针产物 | raw | `-Oz` | 导入面 |
|----------|----:|------:|--------|
| 干净（`--no-default-features`） | **59440 B** | **45687 B** | **0 导入** |
| 被污染（默认 features） | 74454 B | **58632 B** | `__wbindgen_placeholder__` × N |

→ 初版用了下方那行（58632 B），于是把 **1.18×** 算成了 **0.92×**。

### 4.2 修正后（`wasm`/WASI 侧同口径）

| 锚点（`-Oz`，都无胶水、都自带运行时） | (B) |
|--------------------------------------|----:|
| MoonBit `cmd/bench`（`wasm`） | 53745 |
| fast_qr 裸探针（干净） | **45687** |
| ⇒ **ours / fast_qr** | **1.18×** |

### 4.3 加固措施（把「看数字眼熟」变成**硬失败**）

`scripts/bench-size.sh` 现在在编译探针后做**导入面自检**：

```js
const imports = WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync(f)));
if (imports.length !== 0) { /* 报错退出，不输出表格 */ }
```

实测输出（幂等复跑）：

```text
>>> 探针自检 OK: s9f_size_probe.wasm = 59440 B, 0 imports
>>> 探针自检 OK: s9f_hello_probe.wasm = 28820 B, 0 imports
```

---

## 5. 完整对照总表（本次修正后，两侧同规则）

| 档位 | MoonBit `wasm-gc`（默认） | MoonBit `wasm`（兜底） | fast_qr v0.14.0 | gc / fast |
|------|--------------------------:|-----------------------:|----------------:|----------:|
| ① raw | **47912** | 81666 | 61510 | **0.78×** |
| ② 剥 custom | 47790 | 81544 | 53476 | **0.89×** |
| ③ `-Oz`（可加载） | **36296** | 53745 | 49956 | **0.73×** |
| ④ ③ + 宿主胶水 | 36296 | 53745 | 58173 | **0.62×** |
| ⑤ 同功能锚点（`-Oz`，无胶水） | 36296 | 53745 | 45687 | **0.79×** |

**基线分解（hello-only 地板 → 真实 QR 命令，均 `-Oz`）：**

| 侧 | 地板 | 真实 QR | 业务净增 |
|----|-----:|--------:|---------:|
| MoonBit `wasm-gc` | **263 B** | 36296 B | **+36033 B** |
| MoonBit `wasm` | 2095 B | 53745 B | +51650 B |
| fast_qr（Rust） | 20052 B | 45687 B | +25635 B |

---

## 6. 修正后的归因

| 差异来源 | 量级 | 说明 |
|----------|-----:|------|
| **运行时地板** | `wasm-gc` 比 Rust **少 ≈19.8 KB** | Rust 必带 core/alloc/fmt/panic；`wasm-gc` 的对象/字符串交给宿主 GC |
| 元数据 `custom` 段 | fast_qr 多 **8034 B** | wasm-bindgen 注入的 `name`（7.7 KB 级）+ `target_features` |
| 宿主胶水 | fast_qr 多 **8217 B** | `fast_qr.js` |
| QR 业务代码净增 | MoonBit gc +36.0 KB vs Rust +25.6 KB | 同量级；MoonBit 侧含 `--dump`/checksum/argv 与更宽公共面 |

**结论**：

1. 本仓库**默认分发形态 `wasm-gc` 在每一种口径下都比 fast_qr 小**（0.62×–0.89×）；
2. `wasm`(WASI) 侧则**与 fast_qr 同档**（0.92×–1.18×，取决于是否计入胶水）——
   这是因为 MoonBit 的 WASI 侧要自带线性内存运行时，与 Rust 的处境类似；
3. 真正拉开差距的是**运行时模型**：`wasm-gc` 把 GC 交给宿主，地板 263 B vs Rust 20052 B（**76×**）；
4. **引用本项目体积时，必须同时给出后端**（`wasm-gc` / `wasm`）**与口径**，否则数字没有意义。

---

## 7. 复跑方式

```bash
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
bash scripts/bench-size.sh              # 全流程（环境 + 四份产物 + 两侧探针 + 对比 + 护栏）
bash scripts/bench-size.sh --no-build   # 产物就绪时只量测（探针缺则幂等补编）
```

新增/变更的脚本能力：

- `scripts/bench-size.sh`：新增 `--moon-gc-wasm / --moon-gc-main-wasm / --moon-gc-hello-wasm / --moonrun` 参数；
  构建阶段补 `moon build cmd/{bench,main} --target wasm-gc --release`；**探针导入面自检**（非 0 导入即失败）；
  hello-only 探针两个后端都编（WASI 2095 B / wasm-gc 263 B）。
- `scripts/wasm-size.mjs`：新增 **⑤-gc 段**（默认后端口径）+ `optimizeGc()`（`--disable-custom-descriptors`）
  + `moonrunDigest()`（`wasm-gc` 语义护栏，走 `moonrun <file>`）。

护栏（全部 `--dump` 三基准点逐字节比对，不一致即 exit 1）：

| 侧 | 护栏 | 结果 |
|----|------|------|
| MoonBit `wasm` | raw / 剥 custom / `-Oz` | 一致 `d71beb98c7d2cc1a` |
| **MoonBit `wasm-gc`** | raw / 剥 custom / `-Oz`（moonrun 宿主） | 一致 `acb7b41810409c69` |
| fast_qr 库导出 | raw / 剥 custom / `-Oz`（`qr_with` 三矩阵哈希） | 一致 `88d0b6f63102ef5d` |
| fast_qr 裸探针 | raw / `-Oz`（导出符号） | 一致 `8e76ab6d79895463` |

---

## 8. 汇总

1. **问题**：S9f 初版只量 `wasm`(WASI) 兜底后端，且 ⑤ 锚点取到被 wasm-bindgen 污染的探针 → 结论偏。
2. **修正**：补 **`wasm-gc` 默认后端通道**（含 `--disable-custom-descriptors` 可加载档与 moonrun 护栏）；
   ⑤ 锚点回到干净的 45687 B → **1.18×**；并把探针污染检测升级为**硬失败**。
3. **本项目体积（release）**：`cmd/bench` **`wasm-gc` 36296 B / `wasm` 53745 B**（`-Oz`）；
   `cmd/main` **`wasm-gc` 33709 B / `wasm` 51043 B**；`wasm-gc` 比 `wasm` 小 **32.5%**。
4. **对 fast_qr**：`wasm-gc` 全口径更小（0.62×–0.89×）；`wasm` 侧同档（0.92×–1.18×）。
5. **护栏**：不改 lib/快照/`cmd/bench` 默认行为；四组语义护栏全一致；两侧探针都在外部检出副本、不入库。

---

## 9. 参考

- 上游：[S9f 实现方案](./S9f-产物体积对比.md) · [S9f 实现记录](./S9f-产物体积对比.md)（含修订注记）
- 后续：[S9i 纯库调用体积探针与库实际体积](./S9i-纯库调用体积探针与库实际体积.md)（补「库实际体积」口径并修正 ⑤ 锚点不对称）
- 同尺子：[S9e 性能统一 Node 调用](./S9e-性能测试统一Node调用.md)
- 早期三后端体积对照（骨架阶段）：[wasm-编译与运行-结果分析](./wasm-编译与运行-结果分析.md) §5.1
- 本仓库实码：`scripts/wasm-size.mjs`、`scripts/bench-size.sh`、`原 wasm/WASI Node 运行器`、`cmd/bench/main.mbt`（未改）
- 环境：moon 0.1.20260904、Node v24.20.0、moon-wasm-opt（Binaryen 125）、
  fast_qr v0.14.0（`53e8c99`）+ wasm-bindgen 0.2.100（外部检出副本，探针不入库）
