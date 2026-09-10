# S9c · 性能测试代码（与 fast_qr wasm 对比）· 实现方案

> 承接已合入的 S9 系列——[S9-性能基准-实现方案.md](./S9-性能基准-实现方案.md)（PR #42）、
> [S9-性能基准-实现评估与优化-记录.md](./S9-性能基准-实现评估与优化-记录.md)（PR #44）、
> [S9-性能基准-实现记录.md](./S9-性能基准-实现记录.md)（PR #45，层①基准载体已落地）与
> [S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)（PR #46）。
> 本文对 S9 唯一未收口环节——**层②：与 fast_qr wasm 对比的性能测试代码**——做
> 「重读代码与文档 → 思考评估 → 详细方案」，落到文件级落地清单与验收策略。
> 关键约束（本次修订纳入）：**对比宿主统一用 Node.js 调用 wasm**（不依赖 wasmtime/其他 CLI），
> fast_qr 侧与 MoonBit 侧产物均在 Node 内实例化/调用。
>
> 日期：2026-09-06　｜　前置：S9b 已合入 main（测试 **109 全绿**、工作区干净）
> 性质：**方案评估文档，纯文档 + 目录/索引同步，不改逻辑代码**（后续实现按本文清单另行提交）。
> 参考库 fast_qr v0.14.0（`53e8c99`）为撰写本文档已检出至 /tmp（不入库，仅核对事实）。
>
> **2026-09-06 实现后修订**（落地见 [S9c-性能测试与fast_qr-wasm对比-实现记录.md](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)）：
> ① 原「免 C 编译器」表述不成立——wasm-bindgen 依赖的 **host 构建脚本/过程宏需系统链接器 cc/gcc**，
> 环境脚本实际含 gcc 安装（本容器 apt 装 gcc 14.2.0）；预编译 wasm-bindgen-cli 只省去编译 CLI 本体。
> ② MoonBit 侧**采用 moonrun 子进程**（`scripts/wasm-compare.mjs` 内 execFileSync，Node 统一采集/计时）——
> 「同一 Node 进程实例化 bench.wasm + `__moonbit_fs_unstable` argv 注入」spike 失败（argv 未注入成功、
> WASI fd_write 绕过 process.stdout 拦截），走 D18 降级路径。

---

## 0. 一句话结论

S9 层①的基准载体（`cmd/bench` + `scripts/bench.sh`）已可复跑并记录了 wasm-gc/wasm 双后端数字；
但「**与 fast_qr wasm 对比**」仍是**预留占位**——`scripts/bench.sh:70-76` 的 `FAST_QR_WASM` 分支只打印
提示、不驱动任何产物，S9 实现记录 §4 与 roadmap **M3（性能与分发基线）** 三处标注「待外部环境/待办」，
**M3 尚未收口**。本文评估后给出把层②落成**Node.js 调用 wasm、同口径、可复跑性能测试代码**的方案：

1. **fast_qr 侧载体 = 检出 v0.14.0（`53e8c99`）patch `wasm.rs` 加 `qr_with(content, ecl, version)` 导出**，
   按官方 `wasm-bindgen` 链（`--target nodejs`）产出 **Node 可 require 的 JS 胶水 + `fast_qr_bg.wasm`**，
   Node 直调其导出函数做三基准点（§3.2 D17）。环境仅需 rustup stable + `wasm32-unknown-unknown` target +
   **官方预编译 `wasm-bindgen-cli 0.2.100`**（版本 = Cargo.lock，GitHub release 实测可达；cli 本体免编译，
   但 wasm-bindgen 依赖的 host 构建脚本/过程宏仍**需系统 cc/gcc**，见元信息修订注①）。
2. **MoonBit 侧载体 = `cmd/bench --target wasm`（WASI preview1）产物**，由**同一 Node 脚本**驱动
   （§3.3 D18）。实现期 spike 结论：Node 进程内 `_start` 直调 + `__moonbit_fs_unstable` argv 注入未通过
   （argv 读不到、fd_write 绕 stdout 拦截），故实际采用 `moonrun` 子进程（Node 统一采集/计时），见修订注②。
3. **补关键缺口**：现 `cmd/bench` 校验和取样走 `Module::byte()`（含**模块类型位 bit1-3**），而 fast_qr
   wasm 侧（`bool_to_u8`）只输出 **0/1 明暗值**——两套校验和**公式不可跨库互比**（§3.4）。故新增
   `cmd/bench --dump <点>`：一次 build 后导出**值全集规范矩阵**（逐行 '0'/'1'），供 Node 宿主
   `diff`/`sha256` 做逐位对齐；`--dump` 是可选新模式，**默认行为与层①数字完全不变**（82000/32400/9200 可复现）。
4. **驱动 = 一个 Node 脚本** `scripts/wasm-compare.mjs`（`scripts/bench-layer2.sh` 薄包装）：
   fast_qr 侧进程内直调计时、MoonBit 侧 `moonrun` 子进程计时（修订注②），`performance.now()`/`hrtime`
   循环计时取多次最小，产出对齐结论 + 对比 markdown 表（§4 清单 #4）。
5. 回归护栏：不动 lib 公共 API / 快照；层②对齐为**对 S1-S7 既有快照对齐的跨宿主重确认**（非新正确性门槛，
   S9 评估 §2.4 已论证），仍要求零差异；测试维持 109。

> **性质定位**：层②的增量价值 = ① 在 **Node 同一宿主**下给出对 fast_qr wasm 的**计时对比数字**
> （此前层①只有 MoonBit 内跨后端数字）；② 把「MoonBit 矩阵 = fast_qr 矩阵」从「对 native 快照」延伸到
> 「对 v0.14.0 wasm 参考产物的全矩阵逐位对齐」，**收口 roadmap M3**。

---

## 1. 范围界定

### 1.1 本文做（落地清单，§4）

- **盘点层②缺口**（`bench.sh` 占位 vs 三份文档待办）与**参考侧语义核验**（fast_qr benches/wasm.rs 事实，
  §2.2）；
- **决策 fast_qr 侧 wasm 载体**（D17）、**Node 宿主/计时口径**（D18）与**逐位对齐协议**（D19）；
- 文件级落地清单：`cmd/bench --dump`、fast_qr 参考侧 patch（外部检出，不入库）、`scripts/wasm-compare.mjs`
  驱动、环境脚本扩展、文档治理；
- 验收策略（§5）：对齐零差异 + 109 测试 + 默认 checksum 不变。

### 1.2 本文/后续不做（明确排除）

- **不做任何性能改写**（S5 O1 单列 P2，S9b 已有路线，本方案正交）；
- **不改 lib 公共 API / 快照 / `cmd/bench` 默认行为**（层①数字可复现是回归护栏）；
- **不把 wasm-gc 纳入跨语言计时**：wasm-gc 宿主只有 `moon run`，Node 无法对等托管（§3.3），其与
  `wasm` 产物的结果互证已由层① checksum 一致成立；
- **不采用 npm 现成 `fast_qr` 包做主口径**：npm latest 为 **0.13.0**（§2.2-5），与本仓库对齐的 v0.14.0
  参考不同版，且 `qr()` 无强制版本/ecl 参数——只作可选冒烟，不做基准；
- **不做层③ native 对比**（需 C 工具链，本容器无；S9 已降为可选量级注记）；
- **不把 Rust 环境/层②接入 `.cnb.yml` push CI**（同 `setup-rust.sh` 既有决策：外部参考构建、拖慢 CI）；
- **不空建顶层 `bench/` 基座**（沿用 S9 D14 决策：出现多包信号再拆）。

---

## 2. 阅读代码与文档（现状盘点）

### 2.1 本仓库「性能测试代码」现状

| 载体 | 位置 | 内容 | 状态 |
|------|------|------|------|
| 基准可执行包 | `cmd/bench/main.mbt` + `moon.pkg` | 三基准点 V03H/V10H/V40H（输入 `https://example.com/`=20 字节、ECL=H、强制版本、mask 自动择优）；循环 N 次 build **累加消费结果**防死代码消除；argv 可选 `-- <点> <N>` | ✅ 已落地（S9 PR #45） |
| 宿主计时脚本 | `scripts/bench.sh` | 对「点 × 后端」`moon run cmd/bench --release --target <t>` 整程重复 R 次取最小；输出层① markdown 表 | ✅ 层① 数字在案 |
| 层②入口 | `scripts/bench.sh:70-76` | `FAST_QR_WASM` 环境位：设置后**仅打印提示**，无实际驱动 | ⏳ **预留占位** |
| 已记录层①数字 | S9 记录 §2 | wasm-gc 0.695/0.451/0.369s、wasm 0.854/0.621/0.484s（@N=2000/400/40，R=3）；`TOTAL_CHECKSUM` 跨后端一致（82000/32400/9200） | ✅ |

**实码关键细节（影响层②设计）**：`cmd/bench/main.mbt:100-123` 校验和取样 = `q.size()` +
`q.get(0,0).byte()`/`q.get(sz-1,sz-1).byte()`/`q.get(sz/2,sz/2).byte()` 的**完整字节**（含 bit1-3 类型位，
见 `lib/module.mbt:151-153` `Module::byte`）+ mask/mode/ecl/version 序号。`Module::value()`
（`lib/module.mbt:69-71`）才是 0/1 明暗位。两套读法在层①内等价（同源码类型位一致），但 **fast_qr wasm
只输出 0/1 值** → 跨库校验和必须回到值全集（§3.4）。

**MoonBit wasm 产物可调用性（本次实测）**：`moon build cmd/bench --target wasm --release` 产物
（`_build/wasm/release/build/cmd/bench/bench.wasm`）的导入 = `wasi_snapshot_preview1.fd_write` +
`__moonbit_fs_unstable.{args_get, begin_read_string, finish_read_string, string_read_char, ...}`（`@env.args()`
经 MoonBit 自有 host 协议取 argv）；导出 = `memory` + `_start`。wasm-gc 产物导入另有 `spectest.print_char`，
导出同样仅 `_start`。⇒ Node 托管 MoonBit `wasm` 产物需补 `__moonbit_fs_unstable` 宿主实现（argv 注入 +
读回），见 D18 spike。

### 2.2 参考库 fast_qr v0.14.0（`53e8c99`）已核事实

为写本文档已将参考检出至 /tmp 逐项核验：

1. **三基准点语义**（`benches/qr.rs`）：`QRBuilder::new(black_box("https://example.com/")).ecl(ECL::H)
   .version(V03/V10/V40).build()`——输入 20 字节、ECL=H、**强制版本**、mask 不设（自动择优 8 轮）。
   MoonBit `cmd/bench` 已同构实现（S9 评估 §2.3）。
2. **wasm 导出面**（`src/wasm.rs`）：① `qr(content) -> Vec<u8>` 用 `QRCode::new(input, None, None, None,
   None)`（ECL 默认 Q、版本自动）——**无法强制 Vxx/H**；② `qr_svg(content, options)` 的 `SvgOptions`
   支持 `.ecl()/.version()` 但只出 SVG 字符串。⇒ **必须 patch 参考加带参矩阵导出**（D17 的
   `qr_with`），npm 现成包不可直接驱动三基准点。
3. **`KEEP_LAST` 位宽**（`src/compact.rs:33-53`）：`cfg(target_arch = "wasm32")` → 33 项，其余 65 项；
   对本仓库 MoonBit wasm 形态（KEEP_LAST=33）与 fast_qr 任意 wasm32 目标同样生效（S9 方案 §2.1）。
   真实路径 push ≤16 位，33 vs 65 对 V03H/V10H/V40H 输出无差别（S9 评估 §2.4）。
4. **官方构建链**（`wasm-pack.sh`）与 **feature 门控**（`src/lib.rs:105-108`）：`mod wasm` 仅
   `cfg(target_arch = "wasm32")` 编译；`wasm-bindgen` feature 打开时才生成 JS 绑定导出。`Cargo.lock`
   `wasm-bindgen = 0.2.100`——**wasm-bindgen-cli 须用同版本**（ABI 匹配），官方 GitHub release 提供
   0.2.100 预编译 x86_64-linux-musl 二进制（cli 本体免编译；宿主宏/构建脚本仍需 cc/gcc，见修订注①）。
5. **npm 现成包版本不匹配**：npm `fast_qr` latest = **0.13.0**（2025-04 发布），而本仓库所有快照对齐的
   reference 是 **v0.14.0（`53e8c99`）**——npm 包未跟进 0.14。故层②**必须自建 v0.14.0 的 wasm 产物**，
   npm 包仅可作「默认路径 × 旧版」冒烟（可选，§1.2 排除主口径）。

### 2.3 当前环境事实（决定层②可落地形态）

| 项 | 现状 |
|----|------|
| MoonBit | `moon 0.1.20260827` 已装；`moon test` **109 全绿**；wasm-gc/wasm 产物均已实测可导出 `_start`（§2.1） |
| Node | `v22.23.1`；`node:wasi`（`WASI` preview1）**实测可实例化**（带 ExperimentalWarning）；`WebAssembly` 标准 API 可用 |
| Rust | **未装**（无 cargo/rustc）；`scripts/setup-rust.sh` 可经 rsproxy 装 stable；`rustup target add wasm32-unknown-unknown` 即可（免 build-std） |
| wasm-bindgen-cli | 官方 GitHub release **0.2.100 预编译二进制实测可达**（cli 本体免 cargo install） |
| fast_qr 检出 | 无 `/fast_qr`；GitHub 可达（本文档核验时已 clone 至 /tmp） |
| C 编译器 | **需 cc/gcc**：wasm-bindgen 依赖的 host 构建脚本/过程宏（wasm-bindgen-shared、proc-macro2 等）编译要系统链接器（修订注①）；本容器已 `apt install gcc`（14.2.0）。wasm32 目标产物本身不依赖 cc |
| 网络 | npm registry / rsproxy / github / release-assets 均可达 |

> ⇒ 结论：**Node.js 调用 wasm 的层②在本容器具备实施条件**——装 Rust stable + target + 预编译
> wasm-bindgen-cli 0.2.100 + **系统 gcc**（wasm-bindgen 宿主宏/构建脚本需要）+ clone fast_qr v0.14.0。

---

## 3. 思考与评估（关键决策）

### 3.1 层②为什么仍是缺口、以及它离 M3 还差什么

S9 实现记录把层②定义为「主口径：逐位对齐 + 同口径计时双验证」，但落地时只固化层①，原因是**当时容器无
fast_qr 检出、无 Rust**。此后 roadmap M3（「三基准点可跑并给出对比数字；后端/产物分发结论记录在案」）的
「给出对比数字」一半（层① MoonBit 内跨后端）已达成，「对 fast_qr 的对比数字」一半（层②）**未达成**。
S9b §层②/③ 亦标「待外部环境」。故 M3 收口 = 把层②占位替换成真实 Node 驱动 + 把数字写进记录文档。

### 3.2 决策 D17：fast_qr 侧 wasm 载体 → **Node 可直调的 wasm-bindgen 产物（`qr_with` 导出）**

| 候选 | Node 调用形态 | 强制 Vxx/H | 与 v0.14.0 对齐 | 工具链成本 | 评价 |
|------|--------------|-----------|----------------|-----------|------|
| A. npm 现成包 `fast_qr`（0.13.0） | `import fast_qr` 直调 `qr()` | **不能** | **版本不符**（0.13.0 < v0.14.0） | 最低 | ✗ 主口径排除，仅可选冒烟 |
| B. **patch 参考 `wasm.rs` + `wasm-bindgen --target nodejs`**（本文推荐） | `require('./pkg/fast_qr.js')` 后**直调** `qr_with(content, ecl, version)` → `Uint8Array` 矩阵 | **能**（ECL/Version 经 wasm-bindgen 枚举直传） | ✅ 同 `53e8c99` | stable + `target add wasm32-unknown-unknown` + 预编译 cli 0.2.100（=Cargo.lock）+ **系统 gcc**（宿主宏/构建脚本）；`wasm-opt` 可选跳过 | ✅ 推荐（D17）：Node 直调最贴合「Node 调用 wasm」，且与官方发布形态同构 |
| C. wasm32-wasi 自建 bin（上一稿） | node:wasi 实例化调 `_start`/导出的 extern fn | 能 | ✅ | 更低（免 wasm-bindgen） | 降为**备选**：`_start` 输出靠 fd 捕获不便、取矩阵需自管 memory ABI，Node 直调体验劣于 B |

理由与取舍：
- **为何 B 是主选**：用户要求「Node 调用 wasm 对比」，B 的 `qr_with` 经 wasm-bindgen 胶水把 `Vec<u8>`
  拷贝成 `Uint8Array`，Node 侧**直接拿到 0/1 矩阵**做对齐与计时，无 stdout 捕获、无 memory ABI 手管；
  且与官方 npm 发布链（wasm-pack.sh 同款 wasm-bindgen）同构，差异仅跳过 `-Z build-std`（体积优化）与
  `wasm-opt`（可选），**算法与 cfg 分支完全一致**（KEEP_LAST=33，§2.2-3）。
- **env 论证（修订注①）**：wasm32 目标编译免外部链接器，但 cargo 需编译 wasm-bindgen 依赖的
  **host 构建脚本/过程宏**（wasm-bindgen-shared、proc-macro2 等）→ **需系统 cc/gcc**（已 apt 装 gcc
  14.2.0）；`wasm-bindgen-cli` 用 **0.2.100 官方预编译二进制**（与 Cargo.lock 同版本，ABI 匹配），只省去
  `cargo install` CLI 本体那一步。`wasm-opt`（binaryen）非必需：仅瘦身，跳过不影响语义/计时（体积略大）。
- **patch 内容（外部检出，不入库）**：`wasm.rs` 加
  `#[wasm_bindgen] pub fn qr_with(content: &str, ecl: ECL, version: Version) -> Vec<u8>`
  （内部走 `QRCode::new(content.as_bytes(), Some(ecl), Some(version), None, None)` + `bool_to_u8`，
  mask=None 自动择优——与 `benches/qr.rs` 语义一致）；版本语义 = `version as usize >= 最小适配`，
  V03H/V10H/V40H 均富余，不会 `SpecifiedVersion`。
- **B vs C 变更说明**：本文相对上一稿把 D17 主选从 C 调整为 B，是响应「Node 调用 wasm」约束的最短路径；
  C 保留为无 wasm-bindgen 产物时的兜底（实现期二选一，验收标准相同）。

### 3.3 决策 D18：宿主与计时口径 —— **同一 Node 脚本驱动两侧（fast_qr 进程内直调 / MoonBit moonrun 子进程）**

- **fast_qr 侧（天然 in-process）**：`require('./pkg/fast_qr.js')` 后循环调用 `qr_with(content, ecl, ver)` N
  次，把每次返回的矩阵字节**累加消费**（JS 侧防「调用被优化」的对应物 = 别丢弃结果，同时逐次和值进
  checksum）；时间用 `performance.now()`（或 `process.hrtime.bigint()`）包住整个循环，R 次取最小。
- **MoonBit 侧（修订注②，最终 = moonrun 子进程）**：曾首选「同一 Node 进程内 `node:wasi` 实例化
  `cmd/bench --target wasm` 产物并调用 `_start`」（argv 经 `__moonbit_fs_unstable` 宿主函数注入）；实现期
  spike 实证**未通过**——① argv 经 7 个 fs_unstable 导入注入失败（程序回到默认三点全跑，说明参数未读到）；
  ② node WASI 的 `fd_write` 直接写进程 fd，**绕过 `process.stdout.write` 拦截**，进程内无法干净捕获输出。
  故落地为**降级路径（仍统一 Node）**：`wasm-compare.mjs` 内用 `child_process.execFileSync('moonrun', …)`
  （`~/.moon/bin/moonrun` 原生 wasm 运行器，直跑 bench.wasm、启动开销小）跑 MoonBit 侧（同样 R 次取最小，
  Node 内统一采集与输出）；计时口径一致性（R 次取最小、同 Node 时钟、同表输出）不受影响，整程含 moonrun
  进程启动的口径在表注中写明。
- **wasm-gc 不参与跨语言计时**：无对等 Node 宿主（导入含 spectest.print_char + GC 运行时依赖），
  且其与 wasm 产物结果互证已成立（层① TOTAL_CHECKSUM 一致），以 `--target wasm` 产物作跨语言代表在
  方法学上可接受。
- **对齐 dump 与计时解耦**：对齐（`--dump` 矩阵 diff/sha256）每次产物只做一次、与计时正交；计时循环不
  需要跨侧同 checksum 公式（§3.4）。

### 3.4 决策 D19：逐位对齐协议 = 值全集规范矩阵 dump（并解释「为什么不能用现 checksum」）

- **问题**：层① `cmd/bench` 校验和用 `Module::byte()`（bit0 值 + bit1-3 类型位）；fast_qr wasm 侧
  `bool_to_u8` 只取 `value()`（bit0）→ **类型位在参考 wasm 侧不存在**，两套校验和公式无法跨库相等。
  直接拿层① checksum 对 fast_qr 比对会必然不等、且不可诊断。
- **方案**：新增 `cmd/bench --dump <点>`（可选模式）：一次 build 后导出**值全集（0/1）规范矩阵**：
  ```text
  QR_MATRIX V03H size=29
  111111100010010110111111100 <row0…>
  …（共 size 行，每行 size 个 '0'/'1'，行主序）
  ```
  fast_qr 侧 Node 驱动对 `qr_with` 返回的 `Uint8Array` 按同一协议写文本。Node 宿主对两侧 dump 做
  `diff`（零差异 = 逐位对齐）并 sha256 留档。
- **为什么这是重确认而非新正确性门槛**：MoonBit 各版本矩阵已对 fast_qr **native** 参考做过多轮快照逐位对齐
  （S1-S7）；wasm 侧与 native 侧同算法、同 KEEP_LAST cfg 分支 → 层② dump 对齐预期**必然通过**（S9 评估
  §2.4 论证），其价值 = ① 把验证延伸到「v0.14.0 wasm 参考产物」；② 让计时对比建立在「产物确实逐位一致」
  的前提上，避免「计时对象不同物」。

### 3.5 环境脚本策略

- `scripts/setup-rust.sh`（既有，rsproxy stable + sparse 镜像，不入 push CI）作为 Rust 环境入口；
  层②在其后补：`rustup target add wasm32-unknown-unknown` + 下载解压预编译 `wasm-bindgen-cli 0.2.100`
  到 `~/.cargo/bin`（或 `scripts/.tools`）。建议抽成 `scripts/setup-fast-qr-wasm-env.sh`（幂等）。
- **新增** `scripts/wasm-compare.mjs`（Node 驱动主体）+ `scripts/bench-layer2.sh`（薄包装：负责检出/构建
  fast_qr 产物、`moon build cmd/bench --target wasm`、调 node 脚本、汇总 markdown）。与既有 `bench.sh`
  解耦：层①（bash time / moon run）与层②（Node 调用 wasm）各自独立可跑、便于排错。
- 与 `setup-rust.sh` 一致：**不接入 `.cnb.yml` push CI**。

### 3.6 版本/来源钉住

- fast_qr 检出**钉 v0.14.0（`53e8c99`）**——与 S1-S7 快照参考同版本；`wasm-bindgen` 依赖钉 Cargo.lock
  0.2.100（cli 同版本）；`bench-layer2.sh` 支持 `FAST_QR_DIR` 环境位覆盖检出路径。
- 参考侧 patch 只存在于检出副本，**不入本仓库**（本仓库不 fork 参考库）。

---

## 4. 文件级落地清单（实现阶段执行，本文只规划）

| # | 文件/动作 | 内容 | 验收要点 |
|---|-----------|------|---------|
| 1 | `cmd/bench/main.mbt`（小改，加模式） | 新增可选参数 `--dump <点>`：对指定点 build 一次并按 §3.4 协议导出值全集矩阵；argv 解析加分支；**默认路径行为零改动** | `moon run cmd/bench --release -- V40` 输出与 PR #45 记录一致（checksum=9200 等）；`--dump V03H` 输出 `QR_MATRIX V03H size=29` + 29 行 |
| 2 | fast_qr 检出（外部，钉 `53e8c99`）patch `wasm.rs` + 构建 | `wasm.rs` 加 `qr_with(content, ecl, version)`；`cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen`；`wasm-bindgen --target nodejs --out-dir pkg` | `node -e "const w=require('./pkg/fast_qr.js'); console.log(w.qr_with('https://example.com/', w.ECL.H, w.Version.V40).length)"` 输出 31329 |
| 3 | `scripts/setup-fast-qr-wasm-env.sh`（新，幂等） | `bash scripts/setup-rust.sh`（未装时）→ `rustup target add wasm32-unknown-unknown` → 下载解压 wasm-bindgen-cli 0.2.100 预编译到 PATH | 重跑幂等；`wasm-bindgen --version` = 0.2.100；`rustup target list --installed` 含目标 |
| 4 | `scripts/wasm-compare.mjs` + `scripts/bench-layer2.sh`（新） | Node 驱动：① fast_qr 侧进程内循环调 `qr_with`（三基准点 × N，累加消费 + `performance.now` 计时，R 次取最小）；② MoonBit 侧经 `moonrun` 子进程跑 `cmd/bench --target wasm` 产物（同脚本同时钟计时，R 取最小，修订注②）；③ 两侧 `--dump`/`qr_with` 矩阵文本 `diff` + `sha256`；④ 输出 markdown（点/迭代/两测最小耗时/相对倍率/对齐结果） | 一条命令产出对齐结论 + 计时表；R/迭代可参数化；与 bench.sh 层①口径一致（多次取最小、剔冷启动） |
| 5 | 层②跑测 | 本容器实施：对齐 diff 零差异 + 计时数字 | §5 验收 |
| 6 | `docs/S9c-性能测试与fast_qr-wasm对比-实现记录.md`（实现阶段生成） | 记录两侧产物链、Node 驱动用法、spike 结论（`_start` 可调性或降级）、对齐结果、计时表；M3 标记收口 | 数字透明、口径说清、可复现 |
| 7 | `README.md` / roadmap | 「文档」表补本文与未来实现记录行；roadmap M3 补「层②方案见 S9c」 | 无死链 |

> 实现顺序建议：1（cmd/bench `--dump`，可独立验）→ 3+2（Rust env + fast_qr `qr_with` 产物，外部）
> → 4 驱动（MoonBit 侧 moonrun 子进程，修订注②）→ 5 跑测 → 6 记录 → 7 文档治理。
> 全程不改公共 API / 快照 / `cmd/bench` 默认行为。

---

## 5. 验收策略

| 层级 | 验收项 | 通过标准 |
|------|--------|---------|
| 结构 | `cmd/bench --dump` | 三基准点各导出规范矩阵；默认模式输出与 PR #45 记录逐字一致（TOTAL_CHECKSUM 82000/32400/9200） |
| 参考侧 | fast_qr `qr_with` nodejs 产物 | 单行 node require 即可调用；`qr_with(input,H,Vxx)` 返回 size² 字节矩阵；`require` 首验通过 |
| 逐位对齐 | 两侧矩阵 diff | V03H/V10H/V40H `QR_MATRIX` 文本 `diff` **零差异**（sha256 一致留档） |
| 计时 | Node 同口径多次取最小 | 输出「MoonBit wasm vs fast_qr-wasm32(v0.14.0)」每点最小耗时 + 相对倍率表；表注写清 MoonBit 侧 = `moonrun` 子进程整程（含微启动，修订注②） |
| 回归护栏 | AGENTS §二.4 | `moon fmt --check` / `moon check --deny-warn` / `moon test` 109 全绿；wasm-gc/wasm release 构建通过；lib `.mbti` 零漂移；`cmd/bench` 默认数字不变 |
| 文档 | README/roadmap | 索引新增、无死链；roadmap M3 标注「层②已出对比数字，M3 收口」 |

> 层②对齐「零差异」为硬验收（对 S1-S7 既有对齐的跨宿主重确认）；若出现非零差异，先怀疑参考检出版本/
> 协议解析（§3.6），不要立即怀疑算法——逐位定位差异点后回核 S1-S7 快照参考语义。

---

## 6. 汇总

1. **读了代码与文档**：S9 系列四篇（方案/评估/实现记录/S9b）、`cmd/bench` 与 `scripts/bench.sh` 实码、
   README/roadmap、本容器环境；检出 fast_qr v0.14.0（`53e8c99`）逐项核验参考侧事实（benches 语义、wasm
   导出面、KEEP_LAST cfg、feature 门控、Cargo.lock wasm-bindgen=0.2.100、npm 现成包停在 0.13.0）；并
   实测 MoonBit `cmd/bench` 的 wasm/wasm-gc 产物导出面（仅 `_start`、argv 走 `__moonbit_fs_unstable`）、
   node `node:wasi` 可用、wasm-bindgen-cli 0.2.100 预编译二进制可下载（宿主宏仍需 cc/gcc，修订注①）。
2. **评估结论**：层①已闭环；层②（对 fast_qr wasm 的对比）是 M3 唯一未收口项，且**本容器已具备实施条件**，
   **宿主统一为 Node.js 调用 wasm**。关键缺口有三——fast_qr 侧需 Node 可直调的带参导出（npm 现成包
   0.13.0 版本不符且不能强制 Vxx/H）、跨库校验和公式不可比、统一宿主计时。
3. **定方案**：fast_qr 侧 patch `wasm.rs` 加 `qr_with(content,ecl,version)` + `wasm-bindgen --target nodejs`
   产物（D17，Node 直调返回矩阵；env 用 stable + target + 预编译 cli 0.2.100 + 系统 gcc）；两侧由
   **同一 Node 脚本**驱动——fast_qr 侧 in-process 调用，MoonBit 侧 **moonrun 子进程**（`_start` 同进程
   spike 未过，走降级，修订注②）（D18）；新增 `cmd/bench --dump` 值全集规范矩阵做逐位对齐（D19，绕开
   byte() 含类型位导致的公式不可比）；环境脚本 + `wasm-compare.mjs` 驱动。层②对齐为既有快照对齐的跨宿主
   重确认（预期零差异），增量价值 = Node 同宿主计时数字 + **收口 roadmap M3**（实测已达成，见实现记录）。

**后续（实现阶段首个动作）**：按 §4 顺序先加 `cmd/bench --dump`（默认行为不变），再装 Rust stable +
`wasm32-unknown-unknown` + 预编译 wasm-bindgen-cli 0.2.100 + 系统 gcc、检出 fast_qr patch `qr_with` 产出
nodejs 包，写 `scripts/wasm-compare.mjs`（MoonBit 侧经 `moonrun` 子进程驱动）跑出对齐 + 计时，产 S9c
实现记录并把 M3 标收口（**已全部落地，见 [S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)**）。

---

## 7. 后续修订（S9e，issue #50）

本方案 §3.3 D18 的 MoonBit 侧「`moonrun` 子进程」是当时的降级路径（`node:wasi` spike 未通过）。
后续 issue #50 指出两侧**并非统一通过 Node 调用**，S9e 已用**裸 `WebAssembly.Instance` + 自写
`__moonbit_fs_unstable` shim**（复刻 moonrun 的 `externref` opaque 句柄 argv 协议）实现
**同一 Node 进程内**调用并重测，见 [S9e-性能测试统一Node调用-实现方案.md](./S9e-性能测试统一Node调用-实现方案.md)。

---

## 8. 参考

- S9 系列：S9 [实现方案](./S9-性能基准-实现方案.md)（PR #42）、[评估记录](./S9-性能基准-实现评估与优化-记录.md)
  （PR #44，§2.4「KEEP_LAST 33 vs 65 无差别」）、[实现记录](./S9-性能基准-实现记录.md)（PR #45，§3/§4 预留层②）、
  [S9b 性能优化评估与路线](./S9b-性能优化-评估与路线.md)（PR #46）；roadmap §4.4 **M3**。
- 参考 fast_qr v0.14.0（`53e8c99`，本方案核验检出 /tmp）：`benches/qr.rs`、`src/wasm.rs`（qr/bool_to_u8/
  SvgOptions）、`src/qr.rs`（QRCode::new/QRBuilder）、`src/compact.rs`（KEEP_LAST wasm32 33 项）、
  `src/lib.rs`（wasm 模块 cfg 门控）、`wasm-pack.sh`、`Cargo.lock`（wasm-bindgen 0.2.100）。
- npm `fast_qr` 元数据（latest 0.13.0，≠ v0.14.0）；wasm-bindgen-cli 0.2.100 官方 GitHub release 预编译二进制。
- [wasm-绑定.md](./移植参考/模块/wasm-绑定.md)（wasm 导出面/构建链）、[fast-qr-接口.md](./移植参考/fast-qr-接口.md)
  §2/§4、[wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) §5.2（宿主多次取最小口径）。
- 本仓库实码：`cmd/bench/main.mbt`、`scripts/bench.sh`、`lib/module.mbt`（value/byte）、`lib/qr_build.mbt`
  （默认 ecl=Q）、`lib/qr.mbt`（QRCode 访问器）；实测产物导出面 `_build/{wasm-gc,wasm}/release/build/cmd/bench/bench.wasm`。
- 环境：`scripts/setup-rust.sh`（rsproxy stable）、`scripts/setup-moonbit.sh`；node v22 `node:wasi` / `WebAssembly` 实测可用。
