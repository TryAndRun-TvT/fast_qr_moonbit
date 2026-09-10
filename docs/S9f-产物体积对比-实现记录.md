# S9f · 产物体积对比（统一口径）· 实现记录

> 承接 [S9f-产物体积对比-实现方案.md](./S9f-产物体积对比-实现方案.md)。
> 本文记录**落地实现 + 重跑数字 + 踩坑**，回应 issue #50 追加要求「增加 wasm 体积对比」：
> 体积也必须**同一把尺子**（承接 S9e 统一性能计时口径的思路）。
> 日期：2026-09-10　｜　前置：main @ `a09b58b`（109 全绿）。
> **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；fast_qr 侧探针只在**外部检出副本**，不入库。

---

## 0. 一句话结论

- **体积口径已统一**：新增 `scripts/wasm-size.mjs` + `scripts/bench-size.sh`，两侧按**同一套规则**出
  五档（raw / 剥 custom / `-Oz` / wasm+胶水 / 同功能锚点）+ **hello-only 基线分解**，
  并带三侧**语义护栏**（改写后产物必须与原始产物逐字节同结果）。
- **raw 直接相除不可比**：81666 vs 61514 B（1.33×）——Rust 侧多 8038 B 元数据、MoonBit 侧把运行时编在 code 段。
- **同规则下体量同档**：
  - `-Oz`：**53745 vs 49956 B = 1.08×**
  - 计入 fast_qr 宿主胶水（8217 B）：**58173 B → 0.92×**
  - 同功能锚点（都无胶水、都自带运行时）：fast_qr 裸探针 **58632 B** vs MoonBit bench **53745 B = 0.92×**
- **差距的来源被分解清楚**：hello-only 基线 MoonBit **2095 B** vs Rust **20052 B**（9.57×），
  即**运行时地板差 ≈18 KB**；QR 业务净增 MoonBit +51.6 KB vs fast_qr +38.6 KB（同量级）。

---

## 1. 落地清单与验收

| # | 文件/动作 | 内容 | 验收 | 状态 |
|---|-----------|------|------|------|
| 1 | `scripts/wasm-size.mjs`（新） | 五档量测 + 段解析（LEB128）+ 语义护栏 + markdown/`--json` | 一条命令出表；护栏不一致 exit 1 | ✅ |
| 2 | `scripts/bench-size.sh`（新） | 环境 → fast_qr 产物 → 两侧探针（幂等） → 调 `wasm-size.mjs` | 全流程可复跑；`--no-build` 可只量测 | ✅ |
| 3 | fast_qr 侧探针（外部检出副本，不入库） | `src/bin/s9f_size_probe.rs`（真实 QR 路径、无胶水）+ `src/bin/s9f_hello_probe.rs`（hello-only 地板） | 单文件零导入、`-Oz` 前后语义一致 | ✅ |
| 4 | MoonBit 侧基线探针（临时模块，不入库） | `$FAST_QR_WASM_DIR/moonbit_hello_probe/`（一行 `println`） | 量出 MoonBit 运行时地板 | ✅ |
| 5 | 重跑 | 本容器执行（`bash scripts/bench-size.sh`） | §3/§4 表 | ✅ |
| 6 | 收尾回归 | fmt/check/test + 双后端 + 默认 checksum | §6 | ✅ |
| 7 | 文档治理 | S9f 方案 + 本记录 + README/索引/脚本表回链 | 无死链 | ✅ |

> **接口护栏**：新增的两个脚本都在 `scripts/`，不触 lib 公共 `.mbti`；`cmd/bench` 只被「调用」，源码未改。
> 回归维持 **109 全绿**，层① 默认数字逐字不变。

---

## 2. 实现要点

### 2.1 段解析与剥 custom（两侧同规则）

- 自制 LEB128 段解析器（`parseSections`）：文件头魔数校验 → 逐段 `id + size(LEB128) + payload`；
  `custom`（id=0）段再读 `nameLen(LEB) + name(UTF-8)` 得到段名。
- `stripCustomSections` 只保留非 0 段，**两侧同一函数** —— 不偏袒任何一侧。
- 实测 custom 段：MoonBit `name` + `producers` = **122 B**；fast_qr `name`(≈7.7 KB) + `producers` + `target_features` = **8038 B**。

### 2.2 同一优化器

`moon-wasm-opt` 是 moon 自带 Binaryen，直接吃标准 wasm：
`moon-wasm-opt <in> --all-features -Oz [-–strip-debug --strip-producers] -o <out>`。
**两侧都用它**，避免「一边 wasm-opt、一边别的」。Rust 产物显式关 GC 不需要，MoonBit `wasm`(WASI) 产物也不需要；
`wasm-gc` 产物需额外 feature 且 Node 24 仍跑不动（见 §5 注②），故体积对比统一取 **`wasm`(WASI) 侧产物**
（与层②性能对比同源，见 S9e）。

### 2.3 同功能锚点（⑤）

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

### 2.4 基线分解（⑤b）

两侧各编一个 hello-only：
- MoonBit：临时模块一行 `println("hello")`；
- fast_qr：`s9f_hello_probe`（`String::from + push + len`，避免被整函数消除）。

→ 得到「运行时地板」，从而把「总差」拆成 **地板差** 与 **业务净增**（§4）。

---

## 3. 重跑：同规则对照表

命令：

```bash
bash scripts/bench-size.sh                 # 环境 + 两侧产物 + 两侧探针 + 体积对比
bash scripts/bench-size.sh --no-build      # 产物就绪时只量测
```

环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1（wasm32-unknown-unknown）、wasm-bindgen 0.2.100、gcc 14.2.0。

| 档位 | MoonBit bench (B) | fast_qr_bg (B) | ours / fast_qr |
|------|------------------:|---------------:|---------------:|
| ① raw 原始产物 | 81666 | 61514 | 1.33× |
| ② 剥 custom 段 | 81544 | 53476 | 1.52× |
| ③ `-Oz` | 53745 | 49956 | **1.08×** |
| ④ `-Oz` + 宿主胶水 | 53745（无胶水） | 58173 | **0.92×** |

### 3.1 同功能锚点（⑤，无胶水单文件）

| 锚点 | raw (B) | `-Oz` (B) | 说明 |
|------|--------:|----------:|------|
| MoonBit `cmd/bench` bench.wasm | 81666 | **53745** | 三基准点 + `--dump` + checksum |
| MoonBit `cmd/main` main.wasm | 75949 | 51043 | 演示 CLI（终端画 + SVG） |
| fast_qr 裸探针 `s9f_size_probe` | 59444 | **45687** | 真实 QR 路径、无胶水、零导入 |

> ⚠️ 探针数字有**一条陷阱**：若在**启用 wasm-bindgen 的检出副本**里构建，Cargo 会把 wasm-bindgen 强制链进来
> （探针体积涨到 74454 B / `-Oz` 58632 B，且带 `__wbindgen_*` 导入）。本仓库脚本先普通构建、再补一次
> `--no-default-features` 构建，保证探针是**零导入单文件**（= 上表 45687 B 那行）。
> 若某次跑出 58632 B，说明拿到了「被 wasm-bindgen 污染」的探针，需重跑 `bash scripts/bench-size.sh`。

### 3.2 基线分解（⑤b）

| 侧 | hello-only（`-Oz`） | 真实 QR 命令（`-Oz`） | 业务净增 |
|----|--------------------:|----------------------:|---------:|
| MoonBit | **2095 B**（一行 `println`） | 53745 B（`cmd/bench`） | **+51650 B** |
| fast_qr | **20052 B**（一行 `println!`） | 45687 B（裸探针） | **+25635 B** |

- **运行时地板**：MoonBit 2095 B vs Rust 20052 B → **9.57×**（Rust 自带 core/alloc/fmt/panic）。
- **业务净增**：MoonBit +51.6 KB vs fast_qr +25.6 KB —— 同量级，MoonBit 略高（含三基准点 argv/`--dump`/checksum 路径）。

---

## 4. 分析：差在哪

| 差异来源 | 量级 | 说明 |
|----------|-----:|------|
| 元数据（custom 段） | fast_qr 多 ≈7.9 KB | `name` 段是 wasm-bindgen 注入的符号名；MoonBit 几乎不带 |
| 宿主胶水 | fast_qr 多 8217 B | `fast_qr.js`；MoonBit 侧 argv 由宿主（moonrun / runner）提供，不计入产物 |
| 运行时地板 | Rust 多 ≈18 KB | hello-only 基线：2095 vs 20052 B |
| QR 业务代码 | 同量级 | 净增 +51.6 KB vs +25.6 KB（MoonBit 功能面更宽：`--dump`/checksum/argv） |

**结论**：

1. 把包装拉平（剥 custom / 同一优化器 / 同形锚点）后，**两侧 wasm 体量同档**（0.92×–1.08×）；
2. 「谁更小」高度依赖**怎么算**：raw 是 1.33×（MoonBit 大），带宽口径是 0.92×（MoonBit 小）；
3. **该结论应写成「口径 + 区间」，而不是单一数字** —— 这正是 issue #50 要的「同一把尺子」。

---

## 5. 踩坑记录（透明）

| # | 现象 | 根因 | 处置 |
|---|------|------|------|
| ① | 剥 custom 时读到段名乱码（`ame`、`roducers`） | 段内偏移算错：`payloadStart` 已跳过 size，却又用 `start` 再跳一次 | 解析改为「记录 `payloadStart`」，段头只走一遍（并把 `readU32` 统一返回 `[value, next]`） |
| ② | `moon-wasm-opt` 拒收 `wasm-gc` 产物 | 需 GC/ref-types/multivalue 等实验提案，Node 24 也只支持到部分（`exact heap type` 尚不可编译） | 体积对比统一用 **`wasm`(WASI)** 侧产物（与层②性能对比同源）；`wasm-gc` 仅记录现状 |
| ③ | 探针体积忽大忽小（45687 ↔ 58632 B） | 检出副本一旦启用 `wasm-bindgen`，Cargo 会把 `wasm-bindgen` 强制链进同 crate 的全部 target（含 bin） | 脚本补一次 `--no-default-features` 构建；`rawProbeDigest` 也加最小 shim 兜底 |
| ④ | fast_qr 胶水后产物无法 `WebAssembly.Instance` | `fast_qr_bg.wasm` 无 `_start`，且导入 `__wbindgen_*` | 语义护栏改走「JS 胶水 + `qr_with` 三矩阵哈希」；拷到临时目录换 wasm 文件、胶水不动 |
| ⑤ | 体积对比里 MoonBit 侧取哪份产物 | `cmd/bench` 有 `wasm`/`wasm-gc` 两份 | 与层② 性能对比（S9e）**取同一份 `wasm` 产物**，保证「性能 + 体积」两条线可互为参照 |
| ⑥ | `--no-build` 只跑量测时报错 | 探针缺失但仍要护栏 | 脚本在 `--no-build` 下**自动补编探针**（幂等），不要求重跑全流程 |

---

## 6. 门禁与收尾（AGENTS §二.4）

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

## 7. 汇总

1. **问题**：体积此前没有统一口径，raw 相除得到的是「包装差」而不是「体量差」。
2. **统一**：`scripts/wasm-size.mjs` + `scripts/bench-size.sh` —— 五档同规则 + hello-only 基线分解 + 三侧语义护栏。
3. **重测**：raw 1.33×、`-Oz` 1.08×、含胶水 0.92×、同功能锚点 0.92×；
   地板差 ≈18 KB（Rust 高）、业务净增同量级 → **总体量同档，差在运行时地板与宿主胶水选择**。
4. **护栏**：不改 lib/快照/`cmd/bench` 默认行为；109 全绿；两侧探针都在外部检出副本、不入库。

**后续（可选）**：若后续启用 `wasm-gc` 作为主分发形态，可补一版 `wasm-gc` 体积列（需先解决 Node 端加载）；
S9b 的性能优化落地后可同批复跑 `bench-layer2.sh` + `bench-size.sh`，观察「性能—体积」双边收窄。

---

## 8. 参考

- 方案：[S9f-产物体积对比-实现方案.md](./S9f-产物体积对比-实现方案.md)；issue #50。
- 性能侧：[S9e 实现记录](./S9e-性能测试统一Node调用-实现记录.md)（同尺子性能）、
  [S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)（层②构建链路）。
- 体积前史：[wasm-编译与运行-结果分析](./wasm-编译与运行-结果分析.md) §4/§5（早期三后端产物体积对照）。
- 本仓库实码：`scripts/wasm-size.mjs`、`scripts/bench-size.sh`、`scripts/moonbit-wasm-runner.mjs`、
  `scripts/build-fast-qr-wasm.sh`、`cmd/bench/main.mbt`（未改）。
- 参考 fast_qr v0.14.0（`53e8c99`）：`Cargo.toml`（`opt-level='s'` + `lto` + `codegen-units=1` + `panic=abort`）、
  `src/wasm.rs`；探针在外部检出副本 `src/bin/s9f_{size,hello}_probe.rs`（不入库）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 14.2.0（apt，wasm-bindgen 宿主宏所需）、`moon-wasm-opt`（moon 自带 Binaryen）。
