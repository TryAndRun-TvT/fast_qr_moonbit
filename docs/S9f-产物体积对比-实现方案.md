# S9f · 产物体积对比（统一口径）· 实现方案

> 承接 [S9e 统一 Node 调用性能口径](./S9e-性能测试统一Node调用-实现方案.md) 与
> [S9c 层② fast_qr-wasm 对比](./S9c-性能测试与fast_qr-wasm对比-实现方案.md)。
> 本文回应 issue #50 追加要求「**增加 wasm 体积对比**」：先**读代码与文档**盘清两侧产物形态，
> 再定**统一口径**（不是拿两个 `.wasm` 文件大小直接相除），最后给出可复跑脚本与重测记录。
> 日期：2026-09-10　｜　性质：方案 + 实现（脚本层，不改 lib / 快照 / `cmd/bench` 默认行为）
> 前置：main @ `a09b58b`（测试 109 全绿）；环境脚本见 `scripts/`。

---

## 0. 一句话结论

- **体积同样不是「同一把尺子」**：MoonBit 侧是 `_start` 可执行包（自带 MoonBit 运行时、无宿主胶水）；
  fast_qr 侧是 wasm-bindgen 库导出（自带 Rust core/alloc/fmt、带 8.2 KB JS 胶水、
  多 8 KB 级 `name`/`target_features` 元数据）。**raw 直接相除 = 拿两种包装比**。
- **统一口径**：两侧按**同一套规则**出五档 —— ① raw ② 剥 custom 段 ③ `moon-wasm-opt --all-features -Oz`
  （同一优化器）④ 单次调用 wasm+胶水 ⑤ **同功能锚点**（对 fast_qr 另编「无胶水单文件 + 打印」裸探针，
  与 MoonBit `cmd/bench` 同形）。
- **量测结论**：
  - raw：81666 vs 61514 B（**1.33×**）——不可比（包装不同）。
  - `-Oz`：53745 vs 49956 B（**1.08×**）；把 fast_qr 胶水计入 → 58173 B（**0.92×**）。
  - 同功能锚点（都无胶水、都自带运行时）：fast_qr 裸探针 58632 B vs MoonBit bench 53745 B → **0.92×**。
  - 基线分解（hello-only —— 一行 `println`）：MoonBit **2095 B** vs Rust **20052 B**（**9.57×**）。
  - **即：两侧总差主要是「运行时地板 + 宿主面」的选择差异，QR 业务净增量同量级（+51.6 KB vs +38.6 KB）。**

---

## 1. 范围界定

### 1.1 本文做

1. 读代码/文档，盘清**两侧产物形态差异**（§2）；
2. 定义**五档同规则口径**与两个基线锚点（§3）；
3. 落地 `scripts/wasm-size.mjs`（新）+ `scripts/bench-size.sh`（新）：量测 + **语义护栏** + markdown 表；
4. 重跑出数字，产出 [S9f 实现记录](./S9f-产物体积对比-实现记录.md)；
5. README / 文档索引 / 脚本表 / 性能段同步。

### 1.2 本文不做

- **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；
- **不改两侧任何源码**：fast_qr 侧探针只存在于**外部检出副本**（`$FAST_QR_WASM_DIR`），不入库；
- **不把 Rust / 层② / 体积对比接入 `.cnb.yml` push CI**（沿用既有决策：外部参考构建拖慢 CI）；
- **不追平 fast_qr 的绝对数字**（S9b 已声明不设硬门槛）。

---

## 2. 读代码与文档：两侧产物形态盘点

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

## 3. 统一口径定义（五档 + 两基线）

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

## 4. 语义护栏（体积优化不得悄悄改语义）

| 侧 | 护栏方式 | 判据 |
|----|---------|------|
| MoonBit（`_start` 可执行包） | Node 进程内（`scripts/moonbit-wasm-runner.mjs`）跑 `--dump V03/V10/V40`，**逐字节**比对原始产物 | 剥 custom / `-Oz` 后**输出完全一致** |
| fast_qr（胶水后产物无 `_start`） | 把改写后 `.wasm` 拷进临时目录（胶水不变），`require` 后 `qr_with` 出三矩阵 → sha256 | 与原始产物哈希**一致** |
| fast_qr 裸探针 | 直接 `WebAssembly.Instance` 调 `s9f_size_probe(0/1/2)`（最小 shim 兜底） | `-Oz` 前后**一致** |

不一致即**退出码 1**，不输出表格 —— 与 S9e §4 的「对齐零差异」同一护栏思路。

---

## 5. 落地文件

| 文件 | 内容 |
|------|------|
| `scripts/wasm-size.mjs`（新） | 五档 + 基线分解量测；wasm 段解析（LEB128）；语义护栏；markdown 报告；`--json` |
| `scripts/bench-size.sh`（新） | 环境 → 两侧产物 → 两侧探针（幂等，不入库）→ 调 `wasm-size.mjs` |

不接受新依赖：只用 Node 内建（`node:fs/crypto/child_process/module`）+ `moon-wasm-opt`（moon 自带）。

---

## 6. 验收策略

| 层级 | 验收项 | 通过标准 |
|------|--------|---------|
| 量测 | 一条命令出表 | `bash scripts/bench-size.sh` 产出可复跑 markdown |
| 护栏 | 改写后语义 | 三侧护栏**全一致**（不一致即 exit 1） |
| 幂等 | 重跑 | 重复执行结果一致；探针缺失自动补编 |
| 回归 | AGENTS §二.4 | `moon fmt --check` / `moon check --deny-warn` / `moon test` **109 全绿**；双后端 release 通过；`cmd/bench` 默认数字不变（82000/32400/9200） |
| 文档 | README/索引 | 新增 S9f 两篇并回链、无死链 |

---

## 7. 汇总

1. **问题**：体积对比此前没有被统一口径，raw 直接相除会得到「1.33×」这种**包装差**。
2. **方案**：五档同规则 + hello-only 基线分解 + 三侧语义护栏，全部脚本化可复跑。
3. **结论**：同规则下 MoonBit 与 fast_qr 的 wasm **体量同档**（`-Oz` 1.08×、同功能锚点 0.92×）；
   差主要来自**运行时地板**（Rust 2 万 B vs MoonBit 2 千 B）与**宿主胶水**（fast_qr 8.2 KB）。
4. **护栏**：lib/快照/`cmd/bench` 默认行为零改动，109 测试全绿。

**后续**：见 [S9f 实现记录](./S9f-产物体积对比-实现记录.md)（数字、踩坑、复跑命令）。

---

## 8. 参考

- issue #50（本任务来源）；[S9e 方案](./S9e-性能测试统一Node调用-实现方案.md)（性能侧同尺子）、
  [S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)（层②构建链路）、
  [wasm-编译与运行-结果分析](./wasm-编译与运行-结果分析.md)（早期三后端产物体积对照）。
- 本仓库实码：`cmd/bench/main.mbt`（未改）、`scripts/wasm-size.mjs`、`scripts/bench-size.sh`、
  `scripts/moonbit-wasm-runner.mjs`、`scripts/build-fast-qr-wasm.sh`。
- 参考 fast_qr v0.14.0（`53e8c99`）：`src/wasm.rs`（`qr`/`qr_with`）、`Cargo.toml`（`opt-level='s'`+`lto`+`panic=abort`）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 14.2.0（wasm-bindgen 宿主宏所需）、`moon-wasm-opt`（moon 自带 Binaryen）。
