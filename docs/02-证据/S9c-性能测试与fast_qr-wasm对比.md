# S9c · 性能测试与 fast_qr-wasm 对比

> **状态**：历史　｜　日期：2026-09-06　｜　索引：[docs/README.md](../README.md) §7　｜　并入：现行口径见 [S9p](S9p-宿主调用面性能口径-JS向wasm传参.md)（层①数字仅作历史）

> ⚠️ **历史记录**：MoonBit `wasm`(WASI) 后端已按项目决策移除，本项目现仅支持 `wasm-gc`；本文涉及的 `wasm` 后端数字与口径仅作历史留存，不再作为对外口径。

> 本文件由原 S9c-性能测试与fast_qr-wasm对比-实现方案 / S9c-性能测试与fast_qr-wasm对比-实现记录 / S9c-性能测试与fast_qr-wasm对比-详细分析 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接已合入的 S9 系列——[S9-性能基准.md](S9-性能基准.md)（PR #42）、
> [S9-性能基准.md](S9-性能基准.md)（PR #44）、
> [S9-性能基准.md](S9-性能基准.md)（PR #45，层①基准载体已落地）与
> [S9b-性能优化.md](S9b-性能优化.md)（PR #46）。
> 本文对 S9 唯一未收口环节——**层②：与 fast_qr wasm 对比的性能测试代码**——做
> 「重读代码与文档 → 思考评估 → 详细方案」，落到文件级落地清单与验收策略。
> 关键约束（本次修订纳入）：**对比宿主统一用 Node.js 调用 wasm**（不依赖 wasmtime/其他 CLI），
> fast_qr 侧与 MoonBit 侧产物均在 Node 内实例化/调用。
>
> 日期：2026-09-06　｜　前置：S9b 已合入 main（测试 **109 全绿**、工作区干净）
> 性质：**方案评估文档，纯文档 + 目录/索引同步，不改逻辑代码**（后续实现按本文清单另行提交）。
> 参考库 fast_qr v0.14.0（`53e8c99`）为撰写本文档已检出至 /tmp（不入库，仅核对事实）。
>
> **2026-09-06 实现后修订**（落地见 本文件「实现记录」部分）：
> ① 原「免 C 编译器」表述不成立——wasm-bindgen 依赖的 **host 构建脚本/过程宏需系统链接器 cc/gcc**，
> 环境脚本实际含 gcc 安装（本容器 apt 装 gcc 14.2.0）；预编译 wasm-bindgen-cli 只省去编译 CLI 本体。
> ② MoonBit 侧**采用 moonrun 子进程**（`原 wasm/WASI 对比驱动脚本` 内 execFileSync，Node 统一采集/计时）——
> 「同一 Node 进程实例化 bench.wasm + `__moonbit_fs_unstable` argv 注入」spike 失败（argv 未注入成功、
> WASI fd_write 绕过 process.stdout 拦截），走 D18 降级路径。

---

### 0. 一句话结论

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
4. **驱动 = 一个 Node 脚本** `原 wasm/WASI 对比驱动脚本`（`scripts/bench-layer2.sh` 薄包装）：
   fast_qr 侧进程内直调计时、MoonBit 侧 `moonrun` 子进程计时（修订注②），`performance.now()`/`hrtime`
   循环计时取多次最小，产出对齐结论 + 对比 markdown 表（§4 清单 #4）。
5. 回归护栏：不动 lib 公共 API / 快照；层②对齐为**对 S1-S7 既有快照对齐的跨宿主重确认**（非新正确性门槛，
   S9 评估 §2.4 已论证），仍要求零差异；测试维持 109。

> **性质定位**：层②的增量价值 = ① 在 **Node 同一宿主**下给出对 fast_qr wasm 的**计时对比数字**
> （此前层①只有 MoonBit 内跨后端数字）；② 把「MoonBit 矩阵 = fast_qr 矩阵」从「对 native 快照」延伸到
> 「对 v0.14.0 wasm 参考产物的全矩阵逐位对齐」，**收口 roadmap M3**。

---

### 1. 范围界定

#### 1.1 本文做（落地清单，§4）

- **盘点层②缺口**（`bench.sh` 占位 vs 三份文档待办）与**参考侧语义核验**（fast_qr benches/wasm.rs 事实，
  §2.2）；
- **决策 fast_qr 侧 wasm 载体**（D17）、**Node 宿主/计时口径**（D18）与**逐位对齐协议**（D19）；
- 文件级落地清单：`cmd/bench --dump`、fast_qr 参考侧 patch（外部检出，不入库）、`原 wasm/WASI 对比驱动脚本`
  驱动、环境脚本扩展、文档治理；
- 验收策略（§5）：对齐零差异 + 109 测试 + 默认 checksum 不变。

#### 1.2 本文/后续不做（明确排除）

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

### 2. 阅读代码与文档（现状盘点）

#### 2.1 本仓库「性能测试代码」现状

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

#### 2.2 参考库 fast_qr v0.14.0（`53e8c99`）已核事实

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

#### 2.3 当前环境事实（决定层②可落地形态）

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

### 3. 思考与评估（关键决策）

#### 3.1 层②为什么仍是缺口、以及它离 M3 还差什么

S9 实现记录把层②定义为「主口径：逐位对齐 + 同口径计时双验证」，但落地时只固化层①，原因是**当时容器无
fast_qr 检出、无 Rust**。此后 roadmap M3（「三基准点可跑并给出对比数字；后端/产物分发结论记录在案」）的
「给出对比数字」一半（层① MoonBit 内跨后端）已达成，「对 fast_qr 的对比数字」一半（层②）**未达成**。
S9b §层②/③ 亦标「待外部环境」。故 M3 收口 = 把层②占位替换成真实 Node 驱动 + 把数字写进记录文档。

#### 3.2 决策 D17：fast_qr 侧 wasm 载体 → **Node 可直调的 wasm-bindgen 产物（`qr_with` 导出）**

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

#### 3.3 决策 D18：宿主与计时口径 —— **同一 Node 脚本驱动两侧（fast_qr 进程内直调 / MoonBit moonrun 子进程）**

- **fast_qr 侧（天然 in-process）**：`require('./pkg/fast_qr.js')` 后循环调用 `qr_with(content, ecl, ver)` N
  次，把每次返回的矩阵字节**累加消费**（JS 侧防「调用被优化」的对应物 = 别丢弃结果，同时逐次和值进
  checksum）；时间用 `performance.now()`（或 `process.hrtime.bigint()`）包住整个循环，R 次取最小。
- **MoonBit 侧（修订注②，最终 = moonrun 子进程）**：曾首选「同一 Node 进程内 `node:wasi` 实例化
  `cmd/bench --target wasm` 产物并调用 `_start`」（argv 经 `__moonbit_fs_unstable` 宿主函数注入）；实现期
  spike 实证**未通过**——① argv 经 7 个 fs_unstable 导入注入失败（程序回到默认三点全跑，说明参数未读到）；
  ② node WASI 的 `fd_write` 直接写进程 fd，**绕过 `process.stdout.write` 拦截**，进程内无法干净捕获输出。
  故落地为**降级路径（仍统一 Node）**：`原 wasm/WASI 对比驱动脚本` 内用 `child_process.execFileSync('moonrun', …)`
  （`~/.moon/bin/moonrun` 原生 wasm 运行器，直跑 bench.wasm、启动开销小）跑 MoonBit 侧（同样 R 次取最小，
  Node 内统一采集与输出）；计时口径一致性（R 次取最小、同 Node 时钟、同表输出）不受影响，整程含 moonrun
  进程启动的口径在表注中写明。
- **wasm-gc 不参与跨语言计时**：无对等 Node 宿主（导入含 spectest.print_char + GC 运行时依赖），
  且其与 wasm 产物结果互证已成立（层① TOTAL_CHECKSUM 一致），以 `--target wasm` 产物作跨语言代表在
  方法学上可接受。
- **对齐 dump 与计时解耦**：对齐（`--dump` 矩阵 diff/sha256）每次产物只做一次、与计时正交；计时循环不
  需要跨侧同 checksum 公式（§3.4）。

#### 3.4 决策 D19：逐位对齐协议 = 值全集规范矩阵 dump（并解释「为什么不能用现 checksum」）

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

#### 3.5 环境脚本策略

- `scripts/setup-rust.sh`（既有，rsproxy stable + sparse 镜像，不入 push CI）作为 Rust 环境入口；
  层②在其后补：`rustup target add wasm32-unknown-unknown` + 下载解压预编译 `wasm-bindgen-cli 0.2.100`
  到 `~/.cargo/bin`（或 `scripts/.tools`）。建议抽成 `scripts/setup-fast-qr-wasm-env.sh`（幂等）。
- **新增** `原 wasm/WASI 对比驱动脚本`（Node 驱动主体）+ `scripts/bench-layer2.sh`（薄包装：负责检出/构建
  fast_qr 产物、`moon build cmd/bench --target wasm`、调 node 脚本、汇总 markdown）。与既有 `bench.sh`
  解耦：层①（bash time / moon run）与层②（Node 调用 wasm）各自独立可跑、便于排错。
- 与 `setup-rust.sh` 一致：**不接入 `.cnb.yml` push CI**。

#### 3.6 版本/来源钉住

- fast_qr 检出**钉 v0.14.0（`53e8c99`）**——与 S1-S7 快照参考同版本；`wasm-bindgen` 依赖钉 Cargo.lock
  0.2.100（cli 同版本）；`bench-layer2.sh` 支持 `FAST_QR_DIR` 环境位覆盖检出路径。
- 参考侧 patch 只存在于检出副本，**不入本仓库**（本仓库不 fork 参考库）。

---

### 4. 文件级落地清单（实现阶段执行，本文只规划）

| # | 文件/动作 | 内容 | 验收要点 |
|---|-----------|------|---------|
| 1 | `cmd/bench/main.mbt`（小改，加模式） | 新增可选参数 `--dump <点>`：对指定点 build 一次并按 §3.4 协议导出值全集矩阵；argv 解析加分支；**默认路径行为零改动** | `moon run cmd/bench --release -- V40` 输出与 PR #45 记录一致（checksum=9200 等）；`--dump V03H` 输出 `QR_MATRIX V03H size=29` + 29 行 |
| 2 | fast_qr 检出（外部，钉 `53e8c99`）patch `wasm.rs` + 构建 | `wasm.rs` 加 `qr_with(content, ecl, version)`；`cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen`；`wasm-bindgen --target nodejs --out-dir pkg` | `node -e "const w=require('./pkg/fast_qr.js'); console.log(w.qr_with('https://example.com/', w.ECL.H, w.Version.V40).length)"` 输出 31329 |
| 3 | `scripts/setup-fast-qr-wasm-env.sh`（新，幂等） | `bash scripts/setup-rust.sh`（未装时）→ `rustup target add wasm32-unknown-unknown` → 下载解压 wasm-bindgen-cli 0.2.100 预编译到 PATH | 重跑幂等；`wasm-bindgen --version` = 0.2.100；`rustup target list --installed` 含目标 |
| 4 | `原 wasm/WASI 对比驱动脚本` + `scripts/bench-layer2.sh`（新） | Node 驱动：① fast_qr 侧进程内循环调 `qr_with`（三基准点 × N，累加消费 + `performance.now` 计时，R 次取最小）；② MoonBit 侧经 `moonrun` 子进程跑 `cmd/bench --target wasm` 产物（同脚本同时钟计时，R 取最小，修订注②）；③ 两侧 `--dump`/`qr_with` 矩阵文本 `diff` + `sha256`；④ 输出 markdown（点/迭代/两测最小耗时/相对倍率/对齐结果） | 一条命令产出对齐结论 + 计时表；R/迭代可参数化；与 bench.sh 层①口径一致（多次取最小、剔冷启动） |
| 5 | 层②跑测 | 本容器实施：对齐 diff 零差异 + 计时数字 | §5 验收 |
| 6 | `docs/本文件「实现记录」部分（实现阶段生成） | 记录两侧产物链、Node 驱动用法、spike 结论（`_start` 可调性或降级）、对齐结果、计时表；M3 标记收口 | 数字透明、口径说清、可复现 |
| 7 | `README.md` / roadmap | 「文档」表补本文与未来实现记录行；roadmap M3 补「层②方案见 S9c」 | 无死链 |

> 实现顺序建议：1（cmd/bench `--dump`，可独立验）→ 3+2（Rust env + fast_qr `qr_with` 产物，外部）
> → 4 驱动（MoonBit 侧 moonrun 子进程，修订注②）→ 5 跑测 → 6 记录 → 7 文档治理。
> 全程不改公共 API / 快照 / `cmd/bench` 默认行为。

---

### 5. 验收策略

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

### 6. 汇总

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
   byte() 含类型位导致的公式不可比）；环境脚本 + `原 wasm/WASI 对比驱动脚本` 驱动。层②对齐为既有快照对齐的跨宿主
   重确认（预期零差异），增量价值 = Node 同宿主计时数字 + **收口 roadmap M3**（实测已达成，见实现记录）。

**后续（实现阶段首个动作）**：按 §4 顺序先加 `cmd/bench --dump`（默认行为不变），再装 Rust stable +
`wasm32-unknown-unknown` + 预编译 wasm-bindgen-cli 0.2.100 + 系统 gcc、检出 fast_qr patch `qr_with` 产出
nodejs 包，写 `原 wasm/WASI 对比驱动脚本`（MoonBit 侧经 `moonrun` 子进程驱动）跑出对齐 + 计时，产 S9c
实现记录并把 M3 标收口（**已全部落地，见 本文件「实现记录」部分**）。

---

### 7. 后续修订（S9e，issue #50）

本方案 §3.3 D18 的 MoonBit 侧「`moonrun` 子进程」是当时的降级路径（`node:wasi` spike 未通过）。
后续 issue #50 指出两侧**并非统一通过 Node 调用**，S9e 已用**裸 `WebAssembly.Instance` + 自写
`__moonbit_fs_unstable` shim**（复刻 moonrun 的 `externref` opaque 句柄 argv 协议）实现
**同一 Node 进程内**调用并重测，见 [S9e-性能测试统一Node调用.md](S9e-性能测试统一Node调用.md)。

---

### 8. 参考

- S9 系列：S9 [实现方案](S9-性能基准.md)（PR #42）、[评估记录](S9-性能基准.md)
  （PR #44，§2.4「KEEP_LAST 33 vs 65 无差别」）、[实现记录](S9-性能基准.md)（PR #45，§3/§4 预留层②）、
  [S9b 性能优化评估与路线](S9b-性能优化.md)（PR #46）；roadmap §4.4 **M3**。
- 参考 fast_qr v0.14.0（`53e8c99`，本方案核验检出 /tmp）：`benches/qr.rs`、`src/wasm.rs`（qr/bool_to_u8/
  SvgOptions）、`src/qr.rs`（QRCode::new/QRBuilder）、`src/compact.rs`（KEEP_LAST wasm32 33 项）、
  `src/lib.rs`（wasm 模块 cfg 门控）、`wasm-pack.sh`、`Cargo.lock`（wasm-bindgen 0.2.100）。
- npm `fast_qr` 元数据（latest 0.13.0，≠ v0.14.0）；wasm-bindgen-cli 0.2.100 官方 GitHub release 预编译二进制。
- [wasm-绑定.md](../移植参考/模块/wasm-绑定.md)（wasm 导出面/构建链）、[fast-qr-接口.md](../移植参考/fast-qr-接口.md)
  §2/§4、[wasm-编译与运行-结果分析.md](../03-过程/wasm-编译与运行-结果分析.md) §5.2（宿主多次取最小口径）。
- 本仓库实码：`cmd/bench/main.mbt`、`scripts/bench.sh`、`lib/module.mbt`（value/byte）、`lib/qr_build.mbt`
  （默认 ecl=Q）、`lib/qr.mbt`（QRCode 访问器）；实测产物导出面 `_build/{wasm-gc,wasm}/release/build/cmd/bench/bench.wasm`。
- 环境：`scripts/setup-rust.sh`（rsproxy stable）、`scripts/setup-moonbit.sh`；node v22 `node:wasi` / `WebAssembly` 实测可用。

---

## 实现记录

> 承接 本文件「实现方案」部分
> （层②方案）与 S9 系列（层①基准载体已落地）。本记录落地 **层② = Node.js 调用 wasm 对比**：
> fast_qr v0.14.0 `qr_with` wasm-bindgen nodejs 产物（Node 进程内直调）+ MoonBit `cmd/bench --target wasm`
> 产物（`moonrun` 子进程，Node 统一采集/计时），三基准点**逐位对齐零差异 + 计时数字**，**收口 roadmap M3**。
> 日期：2026-09-06　｜　前置：S9c 方案已合入 main（测试 109 基线，工作区干净）。
>
> **⚠️ 后续修订（S9e，issue #50）**：本记录 §3 计时口径为「fast_qr 侧 Node 进程内直调 + MoonBit 侧
> `moonrun` **子进程**整程」——两侧**不同宿主形态**，MoonBit 侧被多计进程启动（实测 12–20%）。S9e 已把
> 两侧统一为**同一 Node 进程内**调用并重测，见
> [S9e-性能测试统一Node调用.md](S9e-性能测试统一Node调用.md)。本记录的对齐结论
> （sha256 零差异、D17/D19 协议）**依然有效**，仅计时口径以 S9e 为准。

---

### 0. 一句话结论

层②已从「预留占位」（`scripts/bench.sh` 的 `FAST_QR_WASM` 只打印提示）落成**可复跑代码**并跑出数字：

- **逐位对齐**：V03H/V10H/V40H 三基准点，MoonBit `--dump` 矩阵文本与 fast_qr `qr_with` 矩阵文本
  **sha256 完全一致（零差异）**——即 MoonBit wasm 产物矩阵与 fast_qr v0.14.0 的 wasm32 参考产物逐位相同，
  构成对 S1-S7 既有（native 参考）快照对齐的**跨宿主重确认**。
- **计时**（R=3 取最小，Node 同脚本）：MoonBit wasm 整程 646.70/493.60/386.43ms vs fast_qr-wasm32
  Node 直调 124.07/132.38/126.15ms（@N=2000/400/40）→ **fast_qr-wasm32 快约 3.1–5.2×**（V03H 5.2×、
  V10H 3.7×、V40H 3.1×）。
- 新增代码：`cmd/bench --dump`（值全集规范矩阵，默认行为不变）+ `scripts/{setup-fast-qr-wasm-env,
  build-fast-qr-wasm,wasm-compare,bench-layer2}.{sh,sh,mjs,sh}`。lib 公共 API / 快照 / 层①数字全未动。

---

### 1. 落地清单与验收（对应方案 §4）

| # | 文件/动作 | 内容 | 验收 | 状态 |
|---|-----------|------|------|------|
| 1 | `cmd/bench/main.mbt` | 新增可选参数 `--dump <点>`：一次 build 导出 `QR_MATRIX` 0/1 值全集（D19 协议）；argv 分支；**默认路径零改动** | `V40 40` → checksum=9200 不变；`--dump V03` → 头行 + 29 行 | ✅ |
| 2 | fast_qr 检出（外部 `$FAST_QR_WASM_DIR`）patch `wasm.rs` + 构建 | `qr_with(content, ecl, version)` 导出；`cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen`；`wasm-bindgen --target nodejs` | `qr_with(…,H,V40)` 长度 = 31329（177²）；ECL.H / Version.V03/V10/V40 键齐全 | ✅ |
| 3 | `scripts/setup-fast-qr-wasm-env.sh` | 幂等：setup-rust.sh + `rustup target add wasm32-unknown-unknown` + 预编译 wasm-bindgen-cli 0.2.100 | `wasm-bindgen --version`=0.2.100；重跑幂等 | ✅ |
| 4 | `scripts/build-fast-qr-wasm.sh` | 检出/复用 fast_qr（钉 `53e8c99`）、幂等 patch、构建、node 首验 | 单行 node require + qr_with(V40H) 长度校验通过 | ✅ |
| 5 | `原 wasm/WASI 对比驱动脚本` + `scripts/bench-layer2.sh` | Node 驱动：fast_qr 进程内直调计时 + MoonBit moonrun 子进程计时（R 取最小）+ 逐位对齐 sha256 + markdown 表 | 一条命令产出对齐 + 计时表 | ✅ |
| 6 | 层②跑测 | 本容器实施 | §3 表 | ✅ |
| 7 | 收尾回归 | fmt/check/test + 双后端 release + 默认 checksum | §5 | ✅ |
| 8 | 文档治理 | 本文 + README/roadmap/S9 记录回链；M3 收口 | 无死链 | ✅ |

> **接口护栏**：`cmd/bench --dump` 与新增 scripts 均不触 lib 公共 `.mbti`（cmd/bench 是独立可执行包、
> scripts 是宿主脚本）；lib 公共 API 零改动，回归维持 **109 全绿**，层①默认数字逐字不变。

---

### 2. 实现要点与实测踩坑

#### 2.1 `cmd/bench --dump`（D19 协议）

- 导出格式（与 fast_qr 侧逐字符可比）：
  ```text
  QR_MATRIX V03H size=29
  11111110110001010010101111111   ← 每行 size 个 '0'/'1'（行主序，1=DARK）
  …（共 size 行）
  ```
- 取值用 `Module::value()`（bit0 明暗），**不含** `byte()` 的模块类型位（bit1-3）——fast_qr wasm
  `bool_to_u8` 也只取 bit0，故两套文本可直接 `diff`/sha256。默认（非 `--dump`）行为完全不变：
  `V40 40` 仍输出 `checksum=9200`（与 S9 PR #45 一致），V03H/V10H 同理 82000/32400。

#### 2.2 fast_qr 侧：`qr_with` + wasm-bindgen nodejs 产物（D17）

- patch 追加（外部检出 `~/.cache/fast_qr_wasm/fast_qr`，幂等，不入库）：
  ```rust
  #[cfg_attr(feature = "wasm-bindgen", wasm_bindgen)]
  #[must_use]
  pub fn qr_with(content: &str, ecl: crate::ECL, version: crate::Version) -> Vec<u8> {
      crate::QRCode::new(content.as_bytes(), Some(ecl), Some(version), None, None)
          .map(bool_to_u8)
          .unwrap_or_default()
  }
  ```
  语义对齐参考 `benches/qr.rs`：ECL=H + 强制版本 + mask=None（自动择优 8 轮）。
- 构建：stable cargo（1.98.1）`--features wasm-bindgen`，wasm32-unknown-unknown 目标（rustup 预置 std，
  免 build-std/免 nightly）；`wasm-bindgen --target nodejs` 产出 `pkg/fast_qr.js`（CJS）+ `fast_qr_bg.wasm`。
  跳过 `wasm-opt`（仅瘦身，不影响语义/计时）。
- **实测踩坑（方案修订注①）**：wasm-bindgen 依赖的 **host 构建脚本/过程宏**（wasm-bindgen-shared、
  proc-macro2）编译需系统链接器 —— 首次 build 报 `linker 'cc' not found`。解决：`apt install gcc`
  （14.2.0）。预编译 wasm-bindgen-cli 只省去 `cargo install` CLI 本体那一步，**不能免 cc**。
- **版本钉住**：fast_qr `53e8c99`（v0.14.0，与 S1-S7 快照同源）；Cargo.lock `wasm-bindgen = 0.2.100`，
  CLI 用同版本预编译二进制（ABI 匹配）。

#### 2.3 MoonBit 侧：`_start` 同进程 spike 否决 → `moonrun` 子进程（D18 降级）

- 实测 MoonBit `cmd/bench --target wasm` 产物导入面 = `wasi_snapshot_preview1.fd_write` +
  `__moonbit_fs_unstable.{args_get, begin_read_string*, string_read_char, finish_read_string*, …}`（`@env.args()`
  经 MoonBit 自有 host 协议读 argv），导出 = `memory` + `_start`。
- **spike 尝试（否决）**：Node `node:wasi` 实例化 + 自写 `__moonbit_fs_unstable` 宿主注入 argv + 调
  `_start`。失败点：① argv 未注入成功——程序回落到「默认三点全跑」（V03H:2000… 而非 `--dump V03`），
  说明 opaque 句柄协议（#external 类型跨 wasm 边界的表示）未对齐；② WASI `fd_write` 直写进程 fd，
  **绕过 `process.stdout.write` 拦截**，进程内无法干净捕获输出用于对齐 diff。
- **落地路径**：`原 wasm/WASI 对比驱动脚本` 内 `child_process.execFileSync('moonrun', [bench.wasm, …args])`。
  `moonrun`（`~/.moon/bin/moonrun`）是原生 wasm 运行器，直跑 WASI 产物（不经 moon 调度、启动开销小），
  stdout 天然可捕获，argv 直接透传。MoonBit 侧计时口径 = moonrun 子进程整程（含微启动），R 次取最小。

#### 2.4 Node 驱动（`原 wasm/WASI 对比驱动脚本`）

- fast_qr 侧：`require(pkg/fast_qr.js)` 进程内循环调 `qr_with(INPUT, ECL.H, Version.Vxx)` N 次，结果
  **累加消费**（`s += m.length` 防「调用被丢弃」），`performance.now()` 包整循环，R 次取最小。
- MoonBit 侧：`execFileSync(moonrun, [bench.wasm, point, N])` 同样 R 次取最小，并解析
  `TOTAL_CHECKSUM` 做侧内自检（82000/32400/9200，与层①记录一致）。
- 对齐：每点 MoonBit `--dump` 与 fast_qr `qr_with` 各出规范文本，逐字符比较 + sha256；不一致即退出码 1。
- 输出 markdown 表（点/迭代/对齐/两侧最小耗时/相对倍率/两侧 checksum）+ 对齐 sha 明细。

---

### 3. 层②实测数字（本容器，Node.js 调用 wasm）

命令：`bash scripts/bench-layer2.sh`（R=3）。口径：fast_qr 侧 = Node 进程内直调（无进程启动）；
MoonBit 侧 = `moonrun` 子进程整程（含微启动）；两侧均 R=3 取最小 wall time（ms）。输入
`https://example.com/`（20 字节），ECL=H，强制版本，mask 自动择优。

| 基准点 | 迭代 N | 逐位对齐 | MoonBit wasm 最小(ms) | fast_qr-wasm32 最小(ms) | fast/moon | MoonBit checksum | fast checksum |
|--------|-------:|---------|---------------------:|------------------------:|----------:|-----------------:|--------------:|
| V03H | 2000 | ✅ sha256 一致 | 646.70 | 124.07 | **0.19×** | 82000 | 1682000 |
| V10H | 400 | ✅ sha256 一致 | 493.60 | 132.38 | **0.27×** | 32400 | 1299600 |
| V40H | 40 | ✅ sha256 一致 | 386.43 | 126.15 | **0.33×** | 9200 | 1253160 |

逐位对齐 sha256（moon == fast）：
- V03H `4942f6aa…b477`（29×29）、V10H `91c85c94…0d8d`（57×57）、V40H `c3c04930…cde7`（177×177）。

单次 build 均摊（表值 ÷ N，量级参考）：MoonBit wasm ≈ 0.323/1.234/**9.66ms**；fast_qr-wasm32 ≈
0.062/0.331/**3.15ms**。

> **解读（透明，非自我设限）**：
> - **逐位对齐零差异 = 正确性双确认**：MoonBit wasm 与 fast_qr v0.14.0 的 wasm32 参考在 V03H/V10H/V40H
>   三矩阵上逐位一致（含自动择优最终 mask），印证 S1-S7 快照对齐不仅对 native 参考成立、对 wasm 参考亦成立。
> - **fast_qr-wasm32 快约 3.1–5.2×**（越小越快）：与两端实现/运行时特性相符（fast_qr 是 Rust 高度优化
>   实现 + release 全优化；本仓库 MoonBit wasm 尚处基线、未做 S9b 的 O1 主循环优化）。此数字是**现状基线**，
>   供 S9b 后续 O1-a/O1-b 优化前后对比；**不设硬门槛**（roadmap S9 行「透明对比」）。
> - 口径注记：fast_qr 侧无进程启动、MoonBit 侧含 moonrun 微启动；两侧差异在秒级总耗时下占比很小，但表格
>   已按「整程最小」如实标注。wasm-gc 不参与跨语言计时（宿主仅 moon run，无对等宿主）。

---

### 4. 脚本用法（环境配置 scripts/ 入口）

```bash
# 一键层②（环境 → fast_qr 构建 → moon wasm build → Node 对比）
bash scripts/bench-layer2.sh
R=5 bash scripts/bench-layer2.sh          # 自定义重复次数
bash scripts/bench-layer2.sh --no-build   # 产物已就绪，只跑对比

# 分步
bash scripts/setup-fast-qr-wasm-env.sh    # rust wasm32 target + wasm-bindgen-cli 0.2.100（幂等）
bash scripts/build-fast-qr-wasm.sh        # 检出/复用 fast_qr v0.14.0 + patch qr_with + nodejs 产物
moon build cmd/bench --target wasm --release
# 历史 wasm/WASI 口径（驱动脚本已随后端移除，不再可用）
```

产物/检出默认在 `$FAST_QR_WASM_DIR`（`$HOME/.cache/fast_qr_wasm`），可用环境变量覆盖。Rust/层②按既有
`setup-rust.sh` 决策**不接入 `.cnb.yml` push CI**（外部参考构建、拖慢 CI）。系统 gcc 为 wasm-bindgen 宿主
构建所需（本容器已装）。

---

### 5. 门禁与收尾（AGENTS §二.4 / 方案 §5）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test
for t in wasm-gc wasm; do moon build cmd/bench --target $t --release; moon test --target $t; done
```

实测：`moon fmt --check` / `moon check --deny-warn` 全过；测试 **109 全绿**（wasm-gc/wasm）；`cmd/bench`
默认输出与 PR #45 记录逐字一致（`V40 40` → 9200 等）；lib 公共 `.mbti` 零漂移（仅 cmd/bench + scripts
改动）。层②跑测可重复（`bash scripts/bench-layer2.sh`）。

---

### 6. 汇总

1. **按方案实施**：新增 `cmd/bench --dump`（值全集规范矩阵，默认行为不变）与 4 个 scripts
   （env/build/wasm-compare/bench-layer2），fast_qr 侧 `qr_with` nodejs 产物（Node 直调）、MoonBit 侧
   `moonrun` 子进程（Node 统一采集/计时）。
2. **实测结论**：三基准点矩阵与 fast_qr v0.14.0 wasm32 参考**逐位对齐零差异**（sha256 一致）；
   Node 同脚本计时下 **fast_qr-wasm32 快约 3.1–5.2×**（V40H 3.1×/V10H 3.7×/V03H 5.2×），数字透明在案、
   供 S9b O1 优化前后对比。
3. **踩坑修订**：wasm-bindgen 宿主宏需系统 gcc（方案修订注①）；MoonBit `_start` Node 同进程 spike 否决
   → `moonrun` 子进程（修订注②）。
4. **roadmap M3 收口**：三基准点可跑并给出对 fast_qr 的对比数字、逐位对齐在案、脚本可复跑——
   「后端/产物分发结论记录在案」达成，M3 标记 ✅（见 roadmap §4.4）。

**后续（S9b P2 / 可选）**：以本记录 §3 的 MoonBit wasm 基线为参照，落地 S9b P1（O1-a 就地翻转 /
O1-b 复用最优轮）后再跑 `bench-layer2.sh`，记录优化前后倍率变化；层③ native 对比仍需具 C 工具链 + fast_qr
native 环境（可选量级注记）。

---

### 7. 参考

- 方案：本文件「实现方案」部分
  （D17/D18/D19 + 修订注①/②）；S9 [实现记录](S9-性能基准.md)（层①数字/口径）、
  [评估记录](S9-性能基准.md)（KEEP_LAST 33 vs 65）、[S9b 优化路线](S9b-性能优化.md)。
- 本仓库实码：`cmd/bench/main.mbt`（--dump）、`scripts/bench-layer2.sh`、`原 wasm/WASI 对比驱动脚本`、
  `scripts/build-fast-qr-wasm.sh`、`scripts/setup-fast-qr-wasm-env.sh`；lib 公共 API 未动。
- 参考 fast_qr v0.14.0（`53e8c99`）：`benches/qr.rs`、`src/wasm.rs`（bool_to_u8/qr_with patch）、
  `Cargo.lock`（wasm-bindgen 0.2.100）。
- 环境：moon 0.1.20260827、node v22.23.1（node:wasi 实验态但未采用）、rustc 1.98.1 + wasm32-unknown-unknown、
  wasm-bindgen 0.2.100（GitHub release 预编译）、gcc 14.2.0（apt，wasm-bindgen 宿主宏所需）、`moonrun`
  （~/.moon/bin）。

---

## 详细分析

> 承接已合入的 本文件「实现方案」部分
> 与 本文件「实现记录」部分
> （层②落地，roadmap M3 ✅）。本记录对层②对比做**复测 + N 扫描成本分解**：复测确认三基准点逐位对齐零差异
> 与计时可复现（R=3/5/7，多次 run 相对漂移 ≤3%、多数点 <2%）；N 扫描把「整程最小时间」拆成 **进程固定开销
> + N × 单次 build 边际成本**（线性回归 R²≈1），给出两侧**边际单次成本**与**每模块成本**的同口径对比，
> 作为 S9b P1/P2 优化落地的量化基线。
> **⚠️ 后续修订（S9e，issue #50）**：本文 §1–§3 的 N 扫描 / 固定开销分解基于「MoonBit 侧 `moonrun`
> 子进程」口径（`a_moon≈23–34ms` 即该子进程启动）。S9e 已把两侧统一为**同一 Node 进程内**调用并重测，
> 见 [S9e 实现记录](S9e-性能测试统一Node调用.md)；本文的「剔启动边际 b」结论与 S9e 的 B 口径
> 同源、可互相印证（S9e B 口径 ≈ 本文 b）。
>
> 日期：2026-09-06　｜　范围：只运行既有 `cmd/bench`/scripts 并做文档分析，**未改任何代码**
> （lib 公共 API/`.mbti`、`cmd/bench`、scripts 全部未动，回归 109 全绿基线不受影响）。

---

### 0. 一句话结论

- **复测可复现**：三基准点逐位对齐 **sha256 完全一致**（与 S9c 实现记录逐字相同）；整程最小计时多次 run
  （R=3/5/7）相对漂移 **≤3%（多数点 <2%）**，MoonBit V03H 646.70–651.03 / V10H 485.40–495.32 /
  V40H 386.43–392.60ms、fast_qr V03H 121.92–124.07 / V10H 130.11–132.44 / V40H 123.79–127.41ms
  （@N=2000/400/40），与已入库数字吻合。
- **成本分解新结论**：整程时间 **T = 进程固定开销 + N × 边际单次成本**，线性拟合 R²≈1（两侧三点全过）。
  - 进程固定开销：MoonBit 侧 **23–34ms/run**（`moonrun` 子进程整程，含 exec+启动+WASI init），fast_qr 侧
    **≈0**（Node 进程内直调无子进程）。该固定开销摊薄到 N 次后占比很小（默认档 ≈5–7%），故 S9c 记录
    的整程对比口径依然成立。
  - **边际单次 build 成本**（剔启动后最干净的 per-build 口径）：MoonBit wasm **0.304 / 1.162 / 9.01ms**、
    fast_qr-wasm32 **0.061 / 0.335 / 3.18ms**（V03H/V10H/V40H）→ **fast_qr 快约 2.8–5.0×**，逐点趋势与
    整程比（3.1–5.2×）方向一致。
  - **每模块成本**（边际 ÷ 模块数）：MoonBit **0.29–0.36µs/module**、fast_qr **0.07–0.10µs/module**，
    逐点比 0.20/0.29/0.35——**差距随版本增大而收窄**（V03H 差 5×、V40H 差 2.8×），解读见 §3.4。
- **口径注记**：边际成本已剔 moonrun 进程启动；整程比含该启动故数值略大。两份口径均如实记录、可复算。

---

### 1. 复测：逐位对齐与计时稳定性

#### 1.1 命令与产物（与 S9c 实现记录 §4 相同）

```bash
bash scripts/bench-layer2.sh            # R=3：环境 → fast_qr 构建 → moon build → Node 对比
# R=7 历史 wasm/WASI 复测（驱动脚本已随后端移除，不再可用）
```

输入 `https://example.com/`（20 字节）、ECL=H、强制版本 V03/V10/V40、mask 自动择优。构建产物幂等复用
（cargo `Finished` 0.04s、`moon: no work to do`），计时干净无重编译污染。

#### 1.2 三组整程最小数字对照（ms，R 次取最小）

| 基准点 | N | S9c 记录(R=3) moon/fast | 本次 R=3 moon/fast | 本次 R=7 moon/fast |
|--------|--:|------------------------:|-------------------:|-------------------:|
| V03H | 2000 | 646.70 / 124.07 | 651.03 / 121.94 | 646.79 / 121.92 |
| V10H | 400 | 493.60 / 132.38 | 485.40 / 132.44 | 495.32 / 130.11 |
| V40H | 40 | 386.43 / 126.15 | 389.71 / 127.41 | 392.60 / 123.79 |

- 跨 run 相对极差（表内三组，max−min ÷ 均值）：MoonBit 侧 V03H ≈0.7%、V10H ≈2.0%、V40H ≈1.6%；
  fast_qr 侧 V03H ≈1.8%、V10H ≈1.8%、V40H **≈2.9%**——**全部 ≤3%、多数 <2%**。结论：**数字可复现，
  S9c 记录不失真**（注：单次 R=3 偶发系统负载异常点可更大，本表取三组稳态 run 的最小值；勿把瞬时
  异常点当趋势，详见下方并行污染注记）。
- 每 run 逐位对齐 sha256 均与 S9c 记录逐字相同（V03H `4942f6aa…b477` / V10H `91c85c94…0d8d` /
  V40H `c3c04930…cde7`），无任何 run 出现差异。
- checksum 恒定：MoonBit 82000/32400/9200；fast_qr = N × size²（2000×841=1682000 等），两侧自洽。

> **并行污染教训（测量注记）**：曾并行发起 V10H 与 V40H 两组 N 扫描，两路同时占 CPU，单侧数字整体被抬高
> ~40%（如 V10H N=400 冲到 752ms），**快慢两侧同比例抬升**、比值不受影响但绝对量失真。后改为**逐点串行**
> 复扫，数字回到与 R=7 复测一致的水平。结论：**层②基准必须逐点串行跑，勿并行多路扫描**。

---

### 2. N 扫描：把整程时间拆成「固定开销 + 边际成本」

#### 2.1 口径

- 对每个基准点跑 4 档 N（同一 build 只按点跑 N 次），R=5 取最小，串行执行。
- 模型：**T(N) = a + b·N**。`b` = 边际单次 build 成本（不含任何启动/固定开销）；`a` = 该 run 的进程级固定
  开销（MoonBit 侧 = `moonrun` 子进程整程开销，fast_qr 侧 ≈0）。最小二乘拟合，R² 检验线性度
  （也顺带复核「cmd/bench 循环消费结果、无死代码消除/无缓存假象」——线性即无启动偏置、无二次项）。

#### 2.2 原始 N 扫描数据（R=5 取最小，ms）

| 基准点 | N= | T_moon | T_fast | 基准点 | N= | T_moon | T_fast | 基准点 | N= | T_moon | T_fast |
|--------|---:|-------:|-------:|--------|---:|-------:|-------:|--------|---:|-------:|-------:|
| V03H | 500 | 185.28 | 30.32 | V10H | 100 | 139.26 | 33.68 | V40H | 10 | 111.91 | 30.44 |
| V03H | 1000 | 335.26 | 61.74 | V10H | 200 | 257.42 | 66.55 | V40H | 20 | 204.67 | 63.48 |
| V03H | 2000 | 646.83 | 122.69 | V10H | 400 | 496.44 | 133.03 | V40H | 40 | 384.02 | 125.11 |
| V03H | 4000 | 1248.42 | 244.53 | V10H | 800 | 953.18 | 268.11 | V40H | 80 | 743.42 | 253.92 |

（默认档即表内 N=2000/400/40 行，与 §1 复测值一致。）

#### 2.3 线性拟合（LSQ：T = a + b·N）

| 基准点 | b_moon（边际 ms/build） | a_moon（固定 ms/run） | b_fast（边际 ms/build） | a_fast（固定 ms/run） | R² |
|--------|------------------------:|----------------------:|------------------------:|----------------------:|------:|
| V03H | 0.3041 | 33.78 | 0.0611 | 0.23 | ≥0.9999 |
| V10H | 1.1623 | 25.70 | 0.3352 | −0.35 | ≥0.9999 |
| V40H | 9.0074 | 23.23 | 3.1848 | −1.19 | ≥0.9999 |

- **R²≈1**：线性模型成立 → 无启动偏置/缓存/死代码假象，`cmd/bench` 计时可信。
- **a_moon ≈ 23–34ms** = `execFileSync` 起 `moonrun` + WASI 初始化整程固定开销；**a_fast ≈ 0** = Node
  进程内直调，无子进程。V03H 档 a 略大或属 run 间调度抖动，量级一致即可。
- **固定开销占比**（默认档 a/N）：V03H 33.78/2000≈1.7%、V10H 25.70/400≈6.4%、V40H 23.23/40≈6.6%——
  全部 <7%，印证 S9c 实现记录「含 moonrun 微启动、占比很小」的表述。

---

### 3. 详细分析

#### 3.1 边际单次成本（剔启动的纯 per-build 对比）

| 基准点 | 边际 moon (ms) | 边际 fast (ms) | fast/moon | 即 MoonBit 慢 |
|--------|---------------:|---------------:|----------:|:--------------|
| V03H | 0.3041 | 0.0611 | **0.20×** | ≈5.0× |
| V10H | 1.1623 | 0.3352 | **0.29×** | ≈3.5× |
| V40H | 9.0074 | 3.1848 | **0.35×** | ≈2.8× |

- 与整程比对照：整程（含启动）fast/moon = 0.19/0.26–0.27/0.32–0.33；边际（剔启动）= 0.20/0.29/0.35。
  两者方向一致、数值接近；整程比略小源于 MoonBit 侧固定启动被计入而 fast 侧没有。
- 量级旁证：边际 moon 的 V40H ≈9.01ms，与 S9b 评估的 wasm-gc V40H auto 单次 ≈7.99ms 同量级
  （本次为 wasm 后端、口径含完整校验和消费，量级吻合即可）。

#### 3.2 每模块成本（面积归一）

模块数：V03=29²=841、V10=57²=3249、V40=177²=31329。以边际 b 除以模块数：

| 基准点 | MoonBit µs/module | fast_qr µs/module | fast/moon |
|--------|------------------:|------------------:|----------:|
| V03H | 0.362 | 0.0726 | 0.20× |
| V10H | 0.358 | 0.1032 | 0.29× |
| V40H | 0.287 | 0.1017 | 0.35× |

- MoonBit 每模块成本稳定在 ~0.29–0.36µs 窄带，fast_qr 稳定在 ~0.07–0.10µs 窄带——**两侧均为常数系数
  级特征**（随版本无超线性偏离），差距主要来自「每模块处理的实现/运行时系数」而非某版本特有问题。
- 这也与 S9b「择优成本随版本超线性放大」不矛盾：择优 8 轮×4 趟扫描本身 ∝ 面积，放大的是**择优占单次
  auto 的比例**（V40H ≈86%），而非每模块系数本身随版本恶化。

#### 3.3 与 fast_qr 实现方式的差距来源（现状基线，供优化对照）

fast_qr 是 Rust 高度优化实现 + `--release` 全优化（LLVM wasm32 后端），矩阵为紧凑存储、每模块处理极少
间接层；MoonBit wasm 尚处基线，含 GC 容器（`Array`）与逐模块索引访问。S9b 已定位 MoonBit 侧头号开销是
**8 轮择优主循环**（V40H 约 86%）：每轮 `apply_mask` 全量 copy（共 9 次）+ `score` 多趟全矩阵扫描。
故本表所测差距中，可被 S9b P1（O1-a 就地翻转 / O1-b 复用最优轮）与 P2（O2 减趟 / O3 按 size² 分配）
直接削减的部分集中在 V40H 这类大版本择优路径上——**本表即 S9b 优化落地前/后的同一把尺子**
（用 `bash scripts/bench-layer2.sh` 复跑即可量化前后差距）。

#### 3.4 为什么差距随版本收窄（5.0× → 3.5× → 2.8×）

- **观察**：整程比与边际比一致显示 V03H 差距最大、V40H 最小。
- **解释（方向性，非定论）**：V03H 单次 build 极小（边际仅 ~0.30ms），两侧的**固定路径成本**
  （QRCode 组装、`wrap_packed` 恒量分配等与面积无关的常数项）占比较高，MoonBit 侧这类常数项相对更大，
  把「每模块系数差距」放大；到 V40H 时面积（∝size²）主导、常数项摊薄，比值向每模块系数本值收敛。
  实测佐证：V03H 的 fast/moon 比 0.20 明显低于 V10H/V40H 的 0.29/0.35，而 V10H 与 V40H 已接近每模块
  系数本值（0.29/0.35）。若 O3（`wrap_packed` 按 size*size 分配）落地，小版本固定常数项下降，预期
  V03H 的比值向大版本靠拢。

---

### 4. 可信性与边界（透明注记）

1. **进程形态差异**：fast_qr 侧 Node 进程内直调（无进程启动）；MoonBit 侧 `moonrun` 子进程整程。边际
   （b）已剔该差异，整程（a+bN）如实含启动——两份口径分别给出，不混淆。
2. **wasm-gc 不参与本对比**：层②主口径为 `wasm`（WASI）产物，因 `wasm-gc` 宿主仅 `moon run`、无对等
   Node 宿主可同进程直调（S9c 方案 §1）。层①跨后端选型见 S9 实现记录 §2。
3. **消费结果防死代码消除**：`cmd/bench` 循环累加 size/代表性模块字节/元数据序号进 checksum（V03H 默认档
   checksum=82000），`原 wasm/WASI 对比驱动脚本` 两侧均消费输出（fast 侧 `s += m.length`），R²≈1 佐证无空循环假象。
4. **采样量**：复测 R=3/5/7 三组独立 run；N 扫描每点 4 档 × R=5，串行执行。相对漂移 ≤3%（多数点 <2%），
   结论稳健。
5. **未动代码**：本记录纯跑测 + 文档，lib/`cmd/bench`/scripts 零改动；快照与 `.mbti` 不受影响。

---

### 5. 汇总

1. **复测**：三基准点逐位对齐 sha256 恒定零差异；整程最小计时多次 run 相对漂移 ≤3%（多数点 <2%），
   与 S9c 记录一致。
2. **分解**：整程 = 固定启动（moon 23–34ms/run，fast ≈0）+ N × 边际（moon 0.304/1.162/9.01ms，fast
   0.061/0.335/3.18ms），R²≈1 线性成立。
3. **对比结论**：边际口径 fast_qr-wasm32 快约 2.8–5.0×（整程口径 3.1–5.2×，含启动故略大）；每模块成本
   MoonBit 0.29–0.36µs vs fast_qr 0.07–0.10µs，差距随版本收窄（5.0→3.5→2.8×），指向每模块系数 +
   小版本固定常数项两大来源。
4. **用途**：本表作为 S9b P1/P2 优化落地**前后同一把尺子**；落地后用 `bash scripts/bench-layer2.sh`
   复跑即可量化差距收窄（预期 V40H 边际向 fast_qr 的 3.18ms 方向靠拢，V03H 经 O3 减常数项后比值向
   大版本收敛）。

---

### 6. 参考

- 层②方案与记录：本文件「实现方案」部分、
  本文件「实现记录」部分
- 层①数字/口径：[S9-性能基准.md](S9-性能基准.md)；
  优化评估：[S9b-性能优化.md](S9b-性能优化.md)（O1/O2/O3 与验收口径）
- 本仓库实码：`cmd/bench/main.mbt`（--dump/checksum）、`原 wasm/WASI 对比驱动脚本`（--points/--iters/
  --reps 驱动）、`scripts/bench-layer2.sh`
- 环境：moon 0.1.20260827、node v22.23.1、rustc 1.98.1、wasm-bindgen 0.2.100、gcc 14.2.0、`moonrun`

---
