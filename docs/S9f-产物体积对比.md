# S9f · 产物体积对比

> 本文件由原 S9f-产物体积对比-实现方案 / S9f-产物体积对比-实现记录 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接 [S9e 统一 Node 调用性能口径](./S9e-性能测试统一Node调用.md) 与
> [S9c 层② fast_qr-wasm 对比](./S9c-性能测试与fast_qr-wasm对比.md)。
> 本文回应 issue #50 追加要求「**增加 wasm 体积对比**」：先**读代码与文档**盘清两侧产物形态，
> 再定**统一口径**（不是拿两个 `.wasm` 文件大小直接相除），最后给出可复跑脚本与重测记录。
> 日期：2026-09-10　｜　性质：方案 + 实现（脚本层，不改 lib / 快照 / `cmd/bench` 默认行为）
> 前置：main @ `a09b58b`（测试 109 全绿）；环境脚本见 `scripts/`。

---

> ### ⚠️ 修订（2026-09-10）
> 本文初版的体积数字有两处偏差（⑤ 锚点取到被 wasm-bindgen 污染的探针 → 0.92× 实为 **1.18×**；
> 且**漏掉默认后端 `wasm-gc`**）。修正与补测见
> [S9g 本项目 wasm 产物体积-确认与修正](./S9g-本项目wasm产物体积-确认与修正.md)
> 与 本文件「实现记录」部分。

### 0. 一句话结论

- **体积同样不是「同一把尺子」**：MoonBit 侧是 `_start` 可执行包（自带 MoonBit 运行时、无宿主胶水）；
  fast_qr 侧是 wasm-bindgen 库导出（自带 Rust core/alloc/fmt、带 8.2 KB JS 胶水、
  多 8 KB 级 `name`/`target_features` 元数据）。**raw 直接相除 = 拿两种包装比**。
- **统一口径**：两侧按**同一套规则**出五档 —— ① raw ② 剥 custom 段 ③ `moon-wasm-opt --all-features -Oz`
  （同一优化器）④ 单次调用 wasm+胶水 ⑤ **同功能锚点**（对 fast_qr 另编「无胶水单文件 + 打印」裸探针，
  与 MoonBit `cmd/bench` 同形）。
- **量测结论**：
  - raw：81666 vs 61514 B（**1.33×**）——不可比（包装不同）。
  - `-Oz`：53745 vs 49956 B（**1.08×**）；把 fast_qr 胶水计入 → 58173 B（**0.92×**）。
  - 同功能锚点（都无胶水、都自带运行时）：fast_qr 裸探针 **45687 B** vs MoonBit bench 53745 B → **1.18×**
    （**修正**：初版 58632 B / 0.92× 用了被 wasm-bindgen 污染的探针）。
  - **默认后端 `wasm-gc`**（`preferred_target`）：raw 47912 B / `-Oz` **36296 B** → 对 fast_qr **0.73×**（含胶水 0.62×）。
  - 基线分解（hello-only —— 一行 `println`）：MoonBit **2095 B** vs Rust **20052 B**（**9.57×**）。
  - **即：两侧总差主要是「运行时地板 + 宿主面」的选择差异，QR 业务净增量同量级（+51.6 KB vs +38.6 KB）。**

---

### 1. 范围界定

#### 1.1 本文做

1. 读代码/文档，盘清**两侧产物形态差异**（§2）；
2. 定义**五档同规则口径**与两个基线锚点（§3）；
3. 落地 `scripts/wasm-size.mjs`（新）+ `scripts/bench-size.sh`（新）：量测 + **语义护栏** + markdown 表；
4. 重跑出数字，产出 本文件「实现记录」部分；
5. README / 文档索引 / 脚本表 / 性能段同步。

#### 1.2 本文不做

- **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；
- **不改两侧任何源码**：fast_qr 侧探针只存在于**外部检出副本**（`$FAST_QR_WASM_DIR`），不入库；
- **不把 Rust / 层② / 体积对比接入 `.cnb.yml` push CI**（沿用既有决策：外部参考构建拖慢 CI）；
- **不追平 fast_qr 的绝对数字**（S9b 已声明不设硬门槛）。

---

### 2. 读代码与文档：两侧产物形态盘点

| 维度 | 本仓库 MoonBit（`cmd/bench`） | fast_qr v0.14.0（wasm-bindgen nodejs） |
|------|------------------------------|----------------------------------------|
| 入口 | **`_start`**（可执行包，argv 驱动） | `qr_with` / `qr` **库导出**（由 JS 胶水调用） |
| 导入面 | `wasi_snapshot_preview1.fd_write` + `__moonbit_fs_unstable.*`（argv/字符串） | `__wbindgen_placeholder__.` + `__wbindgen_externref_xform__.` |
| 自带运行时 | MoonBit 运行时（分配/字符串/格式）；`wasm-gc` 侧交宿主 GC | Rust core / alloc / fmt / panic |
| 宿主胶水 | **无**（`moonrun` / 本仓库 runner 直接跑 `_start`） | **`fast_qr.js` ≈ 8.2 KB**（wasm-bindgen 生成） |
| 元数据（custom 段） | **122 B**（`name`、`producers`） | **8038 B**（`name` 7.7 KB 级、`producers`、`target_features`） |
| 功能面 | 三基准点 + `--dump` 文本矩阵 + checksum | `qr_with` 返回 `Vec<u8>` 0/1 矩阵 |

**由表得两条硬约束**：

1. **「文件大小」不可直接比** —— 一侧的产物是「可执行 + 运行时」，另一侧是「库 + 胶水 + 元数据」。
2. **必须同规则、且要看组成** —— 于是本方案给「多档 + 分解」而非单一数字（§3）。

> 参考：S9c 层②方案 §2 已盘过 fast_qr 侧 `qr_with` 的构建链路（`cargo` + `wasm-bindgen --target nodejs`），
> S9e 统一了**性能**侧的宿主形态。本文只补**体积**侧的形态差异。

---

### 3. 统一口径定义（五档 + 两基线）

| 档位 | 规则（两侧一致） | 回答什么问题 |
|------|------------------|--------------|
| ① raw | 构建产物原样字节数 | 「文件多大」（最直观，但不可比） |
| ② 剥 custom | 统一剥离 wasm `custom` 段（纯元数据） | 「代码+数据」多大 |
| ③ `-Oz` | `moon-wasm-opt --all-features -Oz`（**两侧同一优化器**，Rust 侧另加 `--strip-debug --strip-producers`） | 发布档多大 |
| ④ wasm + 胶水 | ③ + 宿主胶水（fast_qr `fast_qr.js`；MoonBit 侧无） | **一次真实调用**要搬多少字节 |
| ⑤ 同功能锚点 | 两侧都编「**无胶水单文件 + 一行打印**、且真实走 QR 核心路径」的探针 | 排除胶水/依赖面后谁更小 |
| ⑤b 基线分解 | 两侧各编一个 **hello-only**（一行 `println`）探针 | 运行时**地板** vs QR **业务净增** |

**⑤ 的探针设计（关键）**：

- fast_qr 侧：外部检出副本新增 `src/bin/s9f_size_probe.rs` —— `#[no_mangle] pub extern "C" fn s9f_size_probe(sel: i32) -> usize`，
  内部走 `QRBuilder::new(...).ecl(H).version(Vxx).build()`（= `qr_with` 同语义），返回矩阵长度；
  `main()` 再 `println!` 一次（对齐 MoonBit `cmd/bench` 的「打印 + 退出」形态）。
  构建用 `--no-default-features`（**不带 wasm-bindgen**）→ 单文件、零导入。
- MoonBit 侧：直接用 `cmd/bench --target wasm --release`（本身即无胶水单文件）。
- ⑤b：fast_qr 侧 `s9f_hello_probe`（`String` 拼接 + 长度）、MoonBit 侧临时模块一行 `println`
  （`$FAST_QR_WASM_DIR/moonbit_hello_probe/`，**不入库**）。

**为什么 ⑤ 才公平**：`-Oz`（③）已经把两侧拉到同一优化器，但 fast_qr 的库导出仍带 wasm-bindgen 注入的
描述/ref 表 shim，MoonBit 的 `_start` 仍带 argv/checksum 路径 —— **功能面仍不同**；⑤ 用「最小同形探针」
把两侧压到「运行时 + QR 核心」的同一比较面。

---

### 4. 语义护栏（体积优化不得悄悄改语义）

| 侧 | 护栏方式 | 判据 |
|----|---------|------|
| MoonBit（`_start` 可执行包） | Node 进程内（`scripts/moonbit-wasm-runner.mjs`）跑 `--dump V03/V10/V40`，**逐字节**比对原始产物 | 剥 custom / `-Oz` 后**输出完全一致** |
| fast_qr（胶水后产物无 `_start`） | 把改写后 `.wasm` 拷进临时目录（胶水不变），`require` 后 `qr_with` 出三矩阵 → sha256 | 与原始产物哈希**一致** |
| fast_qr 裸探针 | 直接 `WebAssembly.Instance` 调 `s9f_size_probe(0/1/2)`（最小 shim 兜底） | `-Oz` 前后**一致** |

不一致即**退出码 1**，不输出表格 —— 与 S9e §4 的「对齐零差异」同一护栏思路。

---

### 5. 落地文件

| 文件 | 内容 |
|------|------|
| `scripts/wasm-size.mjs`（新） | 五档 + 基线分解量测；wasm 段解析（LEB128）；语义护栏；markdown 报告；`--json` |
| `scripts/bench-size.sh`（新） | 环境 → 两侧产物 → 两侧探针（幂等，不入库）→ 调 `wasm-size.mjs` |

不接受新依赖：只用 Node 内建（`node:fs/crypto/child_process/module`）+ `moon-wasm-opt`（moon 自带）。

---

### 6. 验收策略

| 层级 | 验收项 | 通过标准 |
|------|--------|---------|
| 量测 | 一条命令出表 | `bash scripts/bench-size.sh` 产出可复跑 markdown |
| 护栏 | 改写后语义 | 三侧护栏**全一致**（不一致即 exit 1） |
| 幂等 | 重跑 | 重复执行结果一致；探针缺失自动补编 |
| 回归 | AGENTS §二.4 | `moon fmt --check` / `moon check --deny-warn` / `moon test` **109 全绿**；双后端 release 通过；`cmd/bench` 默认数字不变（82000/32400/9200） |
| 文档 | README/索引 | 新增 S9f 两篇并回链、无死链 |

---

### 7. 汇总

1. **问题**：体积对比此前没有被统一口径，raw 直接相除会得到「1.33×」这种**包装差**。
2. **方案**：五档同规则 + hello-only 基线分解 + 三侧语义护栏，全部脚本化可复跑。
3. **结论**：**默认后端 `wasm-gc`** 在每种口径下都比 fast_qr 小（`-Oz` 0.73×、含胶水 0.62×）；
   `wasm`(WASI) 兜底侧与 fast_qr **同档**（`-Oz` 1.08×、同功能锚点 1.18×）；
   差主要来自**运行时地板**（Rust 2 万 B vs `wasm-gc` 263 B / `wasm` 2095 B）与**宿主胶水**（fast_qr 8.2 KB）。
4. **护栏**：lib/快照/`cmd/bench` 默认行为零改动，109 测试全绿；探针导入面自检（非 0 即失败）。

**后续**：见 本文件「实现记录」部分（数字、踩坑、复跑命令）。

---

### 8. 参考

- issue #50（本任务来源）；[S9e 方案](./S9e-性能测试统一Node调用.md)（性能侧同尺子）、
  [S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比.md)（层②构建链路）、
  [wasm-编译与运行-结果分析](./wasm-编译与运行-结果分析.md)（早期三后端产物体积对照）。
- 本仓库实码：`cmd/bench/main.mbt`（未改）、`scripts/wasm-size.mjs`、`scripts/bench-size.sh`、
  `scripts/moonbit-wasm-runner.mjs`、`scripts/build-fast-qr-wasm.sh`。
- 参考 fast_qr v0.14.0（`53e8c99`）：`src/wasm.rs`（`qr`/`qr_with`）、`Cargo.toml`（`opt-level='s'`+`lto`+`panic=abort`）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 14.2.0（wasm-bindgen 宿主宏所需）、`moon-wasm-opt`（moon 自带 Binaryen）。

---

## 实现记录

> 承接 本文件「实现方案」部分。
> 本文记录**落地实现 + 重跑数字 + 踩坑**，回应 issue #50 追加要求「增加 wasm 体积对比」：
> 体积也必须**同一把尺子**（承接 S9e 统一性能计时口径的思路）。
> 日期：2026-09-10　｜　前置：main @ `a09b58b`（109 全绿）。
> **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；fast_qr 侧探针只在**外部检出副本**，不入库。

---

> ### ⚠️ 修订（2026-09-10，本次复审）
> 本文初版的 ⑤ 同功能锚点行取到了**被 wasm-bindgen 污染**的裸探针（58632 B），
> 由此得出的 **「0.92×（MoonBit 更小）」是错的**；同时本文**漏掉了本仓库默认后端 `wasm-gc`**
> （`moon.mod: preferred_target = "wasm-gc"`），只量了 `wasm`(WASI) 侧。
> 两处均已修正，并已在脚本层加**探针导入面自检**防止再次踩坑。
> 修正后的完整结论另见 [S9g 本项目 wasm 产物体积-确认与修正](./S9g-本项目wasm产物体积-确认与修正.md)。

### 0. 一句话结论（已按修正后数字更新）

- **体积口径已统一**：新增 `scripts/wasm-size.mjs` + `scripts/bench-size.sh`，两侧按**同一套规则**出
  五档（raw / 剥 custom / `-Oz` / wasm+胶水 / 同功能锚点）+ **hello-only 基线分解**，
  并带**四组语义护栏**（含新增的 `wasm-gc` 通道）。
- **raw 直接相除不可比**：81666 vs 61510 B（1.33×）——Rust 侧多 8034 B 元数据、MoonBit 侧把运行时编在 code 段。
- **同规则下（`wasm`/WASI 侧）**：
  - `-Oz`：**53745 vs 49956 B = 1.08×**
  - 计入 fast_qr 宿主胶水（8217 B）：**58173 B → 0.92×**（这一条口径正确、数字未变）
  - 同功能锚点（都无胶水、都自带运行时）：fast_qr 裸探针 **45687 B** vs MoonBit bench **53745 B = 1.18×**
    —— **修正**：初版写 58632 B / 0.92×，那是被 wasm-bindgen 污染的探针（见 §3.1 / §5③）。
- **差距的来源被分解清楚**：hello-only 基线 MoonBit **2095 B** vs Rust **20052 B**（9.57×），
  即**运行时地板差 ≈18 KB**；QR 业务净增 MoonBit +51.6 KB vs fast_qr +25.6 KB（同量级）。

---

### 1. 落地清单与验收

| # | 文件/动作 | 内容 | 验收 | 状态 |
|---|-----------|------|------|------|
| 1 | `scripts/wasm-size.mjs`（新） | 五档量测 + 段解析（LEB128）+ 语义护栏 + markdown/`--json` | 一条命令出表；护栏不一致 exit 1 | ✅ |
| 2 | `scripts/bench-size.sh`（新） | 环境 → fast_qr 产物 → 两侧探针（幂等） → 调 `wasm-size.mjs` | 全流程可复跑；`--no-build` 可只量测 | ✅ |
| 3 | fast_qr 侧探针（外部检出副本，不入库） | `src/bin/s9f_size_probe.rs`（真实 QR 路径、无胶水）+ `src/bin/s9f_hello_probe.rs`（hello-only 地板） | 单文件零导入、`-Oz` 前后语义一致 | ✅ |
| 4 | MoonBit 侧基线探针（临时模块，不入库） | `$FAST_QR_WASM_DIR/moonbit_hello_probe/`（一行 `println`） | 量出 MoonBit 运行时地板 | ✅ |
| 5 | 重跑 | 本容器执行（`bash scripts/bench-size.sh`） | §3/§4 表 | ✅ |
| 5b | **修订（本次）** | 补 `wasm-gc` 默认后端通道 + 探针导入面自检；修正 ⑤ 锚点与全文结论 | §0 修订注记 / §3.1b / §5⑦⑧ | ✅ |
| 6 | 收尾回归 | fmt/check/test + 双后端 + 默认 checksum | §6 | ✅ |
| 7 | 文档治理 | S9f 方案 + 本记录 + README/索引/脚本表回链 | 无死链 | ✅ |

> **接口护栏**：新增的两个脚本都在 `scripts/`，不触 lib 公共 `.mbti`；`cmd/bench` 只被「调用」，源码未改。
> 回归维持 **109 全绿**，层① 默认数字逐字不变。

---

### 2. 实现要点

#### 2.1 段解析与剥 custom（两侧同规则）

- 自制 LEB128 段解析器（`parseSections`）：文件头魔数校验 → 逐段 `id + size(LEB128) + payload`；
  `custom`（id=0）段再读 `nameLen(LEB) + name(UTF-8)` 得到段名。
- `stripCustomSections` 只保留非 0 段，**两侧同一函数** —— 不偏袒任何一侧。
- 实测 custom 段：MoonBit `name` + `producers` = **122 B**；fast_qr `name`(≈7.7 KB) + `producers` + `target_features` = **8038 B**。

#### 2.2 同一优化器

`moon-wasm-opt` 是 moon 自带 Binaryen，直接吃标准 wasm：
`moon-wasm-opt <in> --all-features -Oz [-–strip-debug --strip-producers] -o <out>`。
**两侧都用它**，避免「一边 wasm-opt、一边别的」。Rust 产物显式关 GC 不需要，MoonBit `wasm`(WASI) 产物也不需要；
`wasm-gc` 产物需额外 feature 且 Node 24 仍跑不动（见 §5 注②），故体积对比统一取 **`wasm`(WASI) 侧产物**
（与层②性能对比同源，见 S9e）。

#### 2.3 同功能锚点（⑤）

fast_qr 侧新增二进制：

```rust
// 外部检出副本 src/bin/s9f_size_probe.rs（不入库）
#[no_mangle]
pub extern "C" fn s9f_size_probe(sel: i32) -> usize {
    let (content, ecl, version) = match sel { 0 => (…, H, V03), 1 => (…, H, V10), _ => (…, H, V40) };
    crate_qr_with_lib(content, ecl, version).len()   // QRBuilder → build → 0/1 矩阵
}
fn main() { println!("{}", s9f_size_probe(2)); }     // 对齐 MoonBit cmd/bench「打印 + 退出」
```

- **关键**：用 `--no-default-features` 编译（**不带 wasm-bindgen**）→ 产物**零导入、单文件**，
  与 MoonBit `cmd/bench`（`_start` + 打印）同形。
- 语义自证：Node 里 `new WebAssembly.Instance(...).exports.s9f_size_probe(0/1/2)` = `841 / 3249 / 31329`
  （= 29²/57²/177²，与 `qr_with` 完全一致）。

#### 2.4 基线分解（⑤b）

两侧各编一个 hello-only：
- MoonBit：临时模块一行 `println("hello")`；
- fast_qr：`s9f_hello_probe`（`String::from + push + len`，避免被整函数消除）。

→ 得到「运行时地板」，从而把「总差」拆成 **地板差** 与 **业务净增**（§4）。

---

### 3. 重跑：同规则对照表

命令：

```bash
bash scripts/bench-size.sh                 # 环境 + 两侧产物 + 两侧探针 + 体积对比
bash scripts/bench-size.sh --no-build      # 产物就绪时只量测
```

环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1（wasm32-unknown-unknown）、wasm-bindgen 0.2.100、gcc 14.2.0。

| 档位 | MoonBit bench (B) | fast_qr_bg (B) | ours / fast_qr |
|------|------------------:|---------------:|---------------:|
| ① raw 原始产物 | 81666 | 61510 | 1.33× |
| ② 剥 custom 段 | 81544 | 53476 | 1.52× |
| ③ `-Oz` | 53745 | 49956 | **1.08×** |
| ④ `-Oz` + 宿主胶水 | 53745（无胶水） | 58173 | **0.92×** |

> 上表为 **`wasm`(WASI) 兜底后端**口径。本仓库**默认分发形态是 `wasm-gc`**，
> 其同规则对照见 §3.1b —— raw 47912 B / `-Oz` **36296 B**（对 fast_qr **0.73×**、含胶水 **0.62×**）。

#### 3.1 同功能锚点（⑤，无胶水单文件）

| 锚点 | raw (B) | `-Oz` (B) | 说明 |
|------|--------:|----------:|------|
| MoonBit `cmd/bench` bench.wasm | 81666 | **53745** | 三基准点 + `--dump` + checksum |
| MoonBit `cmd/main` main.wasm | 75949 | 51043 | 演示 CLI（终端画 + SVG） |
| fast_qr 裸探针 `s9f_size_probe` | 59440 | **45687** | 真实 QR 路径、无胶水、零导入 |

→ 锚点结论（`-Oz`）：fast_qr 45687 B vs MoonBit bench 53745 B = **1.18×**（MoonBit 略大）。

> ⚠️ 探针数字的**陷阱**（初版就是踩在这里，得出了 0.92× 的错误结论）：
> 若在**启用 `wasm-bindgen` feature 的检出副本**里构建，Cargo 会把 wasm-bindgen 强制链进**同 crate 的全部 target**
> （含 `bin`），探针体积从 59440 B 涨到 **74454 B**、`-Oz` 从 45687 B 涨到 **58632 B**，且带 `__wbindgen_*` 导入。
> **处置（已加固为硬失败）**：构建改用 `--no-default-features`，随后用 **Node 读取 `WebAssembly.Module.imports` 自检导入面必须为 0**，
> 非 0 即脚本报错退出 —— 不再靠「人工看数字像不像」。
>
> ### 3.1b `wasm-gc`（默认后端）同规则对照 —— 本次补测
>
> | 档位 | MoonBit bench (wasm-gc) (B) | fast_qr_bg (B) | ours / fast_qr |
> |------|----------------------------:|---------------:|---------------:|
> | ① raw | **47912** | 61510 | 0.78× |
> | ② 剥 custom | 47790 | 53476 | 0.89× |
> | ③ `-Oz`（可运行档） | **36296** | 49956 | **0.73×** |
> | ④ `-Oz` + 宿主胶水 | 36296（无胶水） | 58173 | **0.62×** |
>
> - 优化档用 `moon-wasm-opt --all-features --disable-custom-descriptors -Oz`：
>   `--all-features` 会开 custom-descriptors(RTT)，其 `exact` heap type / nullref 常量在 **Node 24 与 moonrun 上都编译不过**；
>   关掉它即得**可被真实宿主加载**的体积最小档（实测 moonrun 可运行且 `--dump` 逐字节一致）。
> - 跨后端：`wasm-gc` 比 `wasm`(WASI) 小 **32.5%**（36296 vs 53745 B）。
> - 另一档：`cmd/main`(wasm-gc) raw 44308 B / `-Oz` 33709 B。

#### 3.2 基线分解（⑤b）

| 侧 | hello-only（`-Oz`） | 真实 QR 命令（`-Oz`） | 业务净增 |
|----|--------------------:|----------------------:|---------:|
| MoonBit `wasm`(WASI) | **2095 B**（一行 `println`） | 53745 B（`cmd/bench`） | **+51650 B** |
| MoonBit `wasm-gc`（默认） | **263 B**（一行 `println`） | 36296 B（`cmd/bench`） | **+36033 B** |
| fast_qr | **20052 B**（一行 `println!`） | 45687 B（裸探针） | **+25635 B** |

- **运行时地板**：`wasm-gc` **263 B** ≈ Rust **20052 B** 的 **1/76**；`wasm`(WASI) **2095 B** ≈ Rust 的 **1/10**。
  → 自带运行时地板不是 MoonBit 的负担，反而是它的**优势项**（Rust 自带 core/alloc/fmt/panic）。
- **业务净增**：`wasm-gc` +36.0 KB / `wasm` +51.6 KB / fast_qr +25.6 KB —— 同量级；
  MoonBit 略高，因其还带三基准点 argv/`--dump`/checksum 路径与更宽的公共面（`SvgBuilder`/`to_str`）。

---

### 4. 分析：差在哪

| 差异来源 | 量级 | 说明 |
|----------|-----:|------|
| 元数据（custom 段） | fast_qr 多 8034 B | `name` 段是 wasm-bindgen 注入的符号名；MoonBit 仅 122 B |
| 宿主胶水 | fast_qr 多 8217 B | `fast_qr.js`；MoonBit 侧 argv 由宿主（moonrun / runner）提供，不计入产物 |
| 运行时地板 | **Rust 多 ≈18 KB**（对 `wasm-gc` 多 ≈19.8 KB） | hello-only：`wasm-gc` 263 B / `wasm` 2095 B / Rust 20052 B |
| QR 业务代码 | 同量级 | 净增 +36.0 KB（gc）/ +51.6 KB（wasi）vs +25.6 KB（fast_qr） |

**结论（修正后）**：

1. 把包装拉平（剥 custom / 同一优化器 / 同形锚点）后，**两侧 wasm 体量同档**（0.73×–1.18×，取决于口径）；
2. 「谁更小」高度依赖**怎么算**：raw 是 1.33×（MoonBit 的 `wasm` 侧大）；
   但**默认后端 `wasm-gc`** 在**所有口径下都更小**（raw 0.78×、`-Oz` 0.73×、含胶水 0.62×）；
3. **该结论必须写成「后端 + 口径 + 数字」三元组**，而不是一个孤立比值 —— 这正是 issue #50 要的「同一把尺子」；
4. **本次修正两处**：⑤ 锚点初版取了被污染的探针（→ 0.92× 实为 **1.18×**）；
   且初版**整体漏掉默认后端 `wasm-gc`**（只用 `wasm`/WASI 侧代表本项目）。

---

### 5. 踩坑记录（透明）

| # | 现象 | 根因 | 处置 |
|---|------|------|------|
| ① | 剥 custom 时读到段名乱码（`ame`、`roducers`） | 段内偏移算错：`payloadStart` 已跳过 size，却又用 `start` 再跳一次 | 解析改为「记录 `payloadStart`」，段头只走一遍（并把 `readU32` 统一返回 `[value, next]`） |
| ② | `moon-wasm-opt` 拒收 `wasm-gc` 产物 | 需 GC/ref-types/multivalue 等实验提案，Node 24 也只支持到部分（`exact heap type` 尚不可编译） | 体积对比统一用 **`wasm`(WASI)** 侧产物（与层②性能对比同源）；`wasm-gc` 仅记录现状 |
| ③ | 探针体积忽大忽小（45687 ↔ 58632 B） | 检出副本一旦启用 `wasm-bindgen`，Cargo 会把 `wasm-bindgen` 强制链进同 crate 的全部 target（含 bin） | 脚本补一次 `--no-default-features` 构建；`rawProbeDigest` 也加最小 shim 兜底 |
| ④ | fast_qr 胶水后产物无法 `WebAssembly.Instance` | `fast_qr_bg.wasm` 无 `_start`，且导入 `__wbindgen_*` | 语义护栏改走「JS 胶水 + `qr_with` 三矩阵哈希」；拷到临时目录换 wasm 文件、胶水不动 |
| ⑤ | 体积对比里 MoonBit 侧取哪份产物 | `cmd/bench` 有 `wasm`/`wasm-gc` 两份 | 与层② 性能对比（S9e）**取同一份 `wasm` 产物**，保证「性能 + 体积」两条线可互为参照 |
| ⑥ | `--no-build` 只跑量测时报错 | 探针缺失但仍要护栏 | 脚本在 `--no-build` 下**自动补编探针**（幂等），不要求重跑全流程 |
| ⑦ | **⑤ 锚点初版结论反了**（写 0.92×，实为 1.18×） | `cargo build`（默认 features）已把 `wasm-bindgen` 链入探针，体积 58632 B 而非 45687 B | 加 `--no-default-features` + **导入面自检硬失败**（见 §3.1 注）；并回填本次修订 |
| ⑧ | **整篇漏掉默认后端 `wasm-gc`** | 沿 S9e 性能口径取 `wasm`(WASI) 侧产物，未回到 `moon.mod` 的 `preferred_target` | 脚本新增 `--moon-gc-*` 通道与 ⑤-gc 段；`wasm-gc` 优化需 `--disable-custom-descriptors` 才可被宿主加载 |

---

### 6. 门禁与收尾（AGENTS §二.4）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt --check && moon check --deny-warn && moon test
for t in wasm-gc wasm; do
  moon build lib --target $t --release
  moon build cmd/main --target $t --release
  moon build cmd/bench --target $t --release
  moon test --target $t
done
```

实测：`moon fmt --check` / `moon check --deny-warn` 全过；测试 **109 全绿**（双后端）；
`cmd/bench` 默认输出逐字不变（`V03 2000`→82000、`V10 400`→32400、`V40 40`→9200，两后端一致）；
lib 公共 `.mbti` 零漂移（仅 `scripts/` + `docs/` 改动）。

层② 性能侧同环境复跑（`bash scripts/bench-layer2.sh --no-build`）：三基准点逐位对齐零差异，
`fast/moon(B)` = 0.256 / 0.324 / 0.368 —— 与 S9e §4 同量级（宿主负载相关，属正常漂移）。

---

### 7. 汇总

1. **问题**：体积此前没有统一口径，raw 相除得到的是「包装差」而不是「体量差」。
2. **统一**：`scripts/wasm-size.mjs` + `scripts/bench-size.sh` —— 五档同规则 + hello-only 基线分解 + 三侧语义护栏。
3. **重测**（`wasm`/WASI 侧）：raw 1.33×、`-Oz` 1.08×、含胶水 0.92×、同功能锚点 **1.18×**；
   **`wasm-gc`（默认后端）**：raw 0.78×、`-Oz` **0.73×**、含胶水 **0.62×**；
   地板差 ≈18 KB（Rust 高）、业务净增同量级 → **总体量同档，差在运行时地板与宿主胶水选择**。
4. **护栏**：不改 lib/快照/`cmd/bench` 默认行为；109 全绿；两侧探针都在外部检出副本、不入库。

**后续（本次已做）**：`wasm-gc` 体积列**已补齐**（§3.1b）—— 它不是「将来可选」，而是**当前默认分发形态**；
脚本已支持 `--moon-gc-*` 通道，`moon-wasm-opt` 需 `--disable-custom-descriptors` 才能产出可被宿主加载的最优档。
剩余可选：若宿主端补上 `exact heap type` 支持，可再量「开 custom-descriptors」的更小档。
S9b 的性能优化落地后可同批复跑 `bench-layer2.sh` + `bench-size.sh`，观察「性能—体积」双边收窄。

---

### 8. 参考

- 方案：本文件「实现方案」部分；issue #50。
- 性能侧：[S9e 实现记录](./S9e-性能测试统一Node调用.md)（同尺子性能）、
  [S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比.md)（层②构建链路）。
- 体积前史：[wasm-编译与运行-结果分析](./wasm-编译与运行-结果分析.md) §4/§5（早期三后端产物体积对照）。
- 本仓库实码：`scripts/wasm-size.mjs`、`scripts/bench-size.sh`、`scripts/moonbit-wasm-runner.mjs`、
  `scripts/build-fast-qr-wasm.sh`、`cmd/bench/main.mbt`（未改）。
- 参考 fast_qr v0.14.0（`53e8c99`）：`Cargo.toml`（`opt-level='s'` + `lto` + `codegen-units=1` + `panic=abort`）、
  `src/wasm.rs`；探针在外部检出副本 `src/bin/s9f_{size,hello}_probe.rs`（不入库）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 14.2.0（apt，wasm-bindgen 宿主宏所需）、`moon-wasm-opt`（moon 自带 Binaryen）。

---
