# S9c · 性能测试代码（与 fast_qr wasm 对比）· 实现记录

> 承接 [S9c-性能测试与fast_qr-wasm对比-实现方案.md](./S9c-性能测试与fast_qr-wasm对比-实现方案.md)
> （层②方案）与 S9 系列（层①基准载体已落地）。本记录落地 **层② = Node.js 调用 wasm 对比**：
> fast_qr v0.14.0 `qr_with` wasm-bindgen nodejs 产物（Node 进程内直调）+ MoonBit `cmd/bench --target wasm`
> 产物（`moonrun` 子进程，Node 统一采集/计时），三基准点**逐位对齐零差异 + 计时数字**，**收口 roadmap M3**。
> 日期：2026-09-06　｜　前置：S9c 方案已合入 main（测试 109 基线，工作区干净）。
>
> **⚠️ 后续修订（S9e，issue #50）**：本记录 §3 计时口径为「fast_qr 侧 Node 进程内直调 + MoonBit 侧
> `moonrun` **子进程**整程」——两侧**不同宿主形态**，MoonBit 侧被多计进程启动（实测 12–20%）。S9e 已把
> 两侧统一为**同一 Node 进程内**调用并重测，见
> [S9e-性能测试统一Node调用-实现记录.md](./S9e-性能测试统一Node调用-实现记录.md)。本记录的对齐结论
> （sha256 零差异、D17/D19 协议）**依然有效**，仅计时口径以 S9e 为准。

---

## 0. 一句话结论

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

## 1. 落地清单与验收（对应方案 §4）

| # | 文件/动作 | 内容 | 验收 | 状态 |
|---|-----------|------|------|------|
| 1 | `cmd/bench/main.mbt` | 新增可选参数 `--dump <点>`：一次 build 导出 `QR_MATRIX` 0/1 值全集（D19 协议）；argv 分支；**默认路径零改动** | `V40 40` → checksum=9200 不变；`--dump V03` → 头行 + 29 行 | ✅ |
| 2 | fast_qr 检出（外部 `$FAST_QR_WASM_DIR`）patch `wasm.rs` + 构建 | `qr_with(content, ecl, version)` 导出；`cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen`；`wasm-bindgen --target nodejs` | `qr_with(…,H,V40)` 长度 = 31329（177²）；ECL.H / Version.V03/V10/V40 键齐全 | ✅ |
| 3 | `scripts/setup-fast-qr-wasm-env.sh` | 幂等：setup-rust.sh + `rustup target add wasm32-unknown-unknown` + 预编译 wasm-bindgen-cli 0.2.100 | `wasm-bindgen --version`=0.2.100；重跑幂等 | ✅ |
| 4 | `scripts/build-fast-qr-wasm.sh` | 检出/复用 fast_qr（钉 `53e8c99`）、幂等 patch、构建、node 首验 | 单行 node require + qr_with(V40H) 长度校验通过 | ✅ |
| 5 | `scripts/wasm-compare.mjs` + `scripts/bench-layer2.sh` | Node 驱动：fast_qr 进程内直调计时 + MoonBit moonrun 子进程计时（R 取最小）+ 逐位对齐 sha256 + markdown 表 | 一条命令产出对齐 + 计时表 | ✅ |
| 6 | 层②跑测 | 本容器实施 | §3 表 | ✅ |
| 7 | 收尾回归 | fmt/check/test + 双后端 release + 默认 checksum | §5 | ✅ |
| 8 | 文档治理 | 本文 + README/roadmap/S9 记录回链；M3 收口 | 无死链 | ✅ |

> **接口护栏**：`cmd/bench --dump` 与新增 scripts 均不触 lib 公共 `.mbti`（cmd/bench 是独立可执行包、
> scripts 是宿主脚本）；lib 公共 API 零改动，回归维持 **109 全绿**，层①默认数字逐字不变。

---

## 2. 实现要点与实测踩坑

### 2.1 `cmd/bench --dump`（D19 协议）

- 导出格式（与 fast_qr 侧逐字符可比）：
  ```text
  QR_MATRIX V03H size=29
  11111110110001010010101111111   ← 每行 size 个 '0'/'1'（行主序，1=DARK）
  …（共 size 行）
  ```
- 取值用 `Module::value()`（bit0 明暗），**不含** `byte()` 的模块类型位（bit1-3）——fast_qr wasm
  `bool_to_u8` 也只取 bit0，故两套文本可直接 `diff`/sha256。默认（非 `--dump`）行为完全不变：
  `V40 40` 仍输出 `checksum=9200`（与 S9 PR #45 一致），V03H/V10H 同理 82000/32400。

### 2.2 fast_qr 侧：`qr_with` + wasm-bindgen nodejs 产物（D17）

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

### 2.3 MoonBit 侧：`_start` 同进程 spike 否决 → `moonrun` 子进程（D18 降级）

- 实测 MoonBit `cmd/bench --target wasm` 产物导入面 = `wasi_snapshot_preview1.fd_write` +
  `__moonbit_fs_unstable.{args_get, begin_read_string*, string_read_char, finish_read_string*, …}`（`@env.args()`
  经 MoonBit 自有 host 协议读 argv），导出 = `memory` + `_start`。
- **spike 尝试（否决）**：Node `node:wasi` 实例化 + 自写 `__moonbit_fs_unstable` 宿主注入 argv + 调
  `_start`。失败点：① argv 未注入成功——程序回落到「默认三点全跑」（V03H:2000… 而非 `--dump V03`），
  说明 opaque 句柄协议（#external 类型跨 wasm 边界的表示）未对齐；② WASI `fd_write` 直写进程 fd，
  **绕过 `process.stdout.write` 拦截**，进程内无法干净捕获输出用于对齐 diff。
- **落地路径**：`wasm-compare.mjs` 内 `child_process.execFileSync('moonrun', [bench.wasm, …args])`。
  `moonrun`（`~/.moon/bin/moonrun`）是原生 wasm 运行器，直跑 WASI 产物（不经 moon 调度、启动开销小），
  stdout 天然可捕获，argv 直接透传。MoonBit 侧计时口径 = moonrun 子进程整程（含微启动），R 次取最小。

### 2.4 Node 驱动（`wasm-compare.mjs`）

- fast_qr 侧：`require(pkg/fast_qr.js)` 进程内循环调 `qr_with(INPUT, ECL.H, Version.Vxx)` N 次，结果
  **累加消费**（`s += m.length` 防「调用被丢弃」），`performance.now()` 包整循环，R 次取最小。
- MoonBit 侧：`execFileSync(moonrun, [bench.wasm, point, N])` 同样 R 次取最小，并解析
  `TOTAL_CHECKSUM` 做侧内自检（82000/32400/9200，与层①记录一致）。
- 对齐：每点 MoonBit `--dump` 与 fast_qr `qr_with` 各出规范文本，逐字符比较 + sha256；不一致即退出码 1。
- 输出 markdown 表（点/迭代/对齐/两侧最小耗时/相对倍率/两侧 checksum）+ 对齐 sha 明细。

---

## 3. 层②实测数字（本容器，Node.js 调用 wasm）

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

## 4. 脚本用法（环境配置 scripts/ 入口）

```bash
# 一键层②（环境 → fast_qr 构建 → moon wasm build → Node 对比）
bash scripts/bench-layer2.sh
R=5 bash scripts/bench-layer2.sh          # 自定义重复次数
bash scripts/bench-layer2.sh --no-build   # 产物已就绪，只跑对比

# 分步
bash scripts/setup-fast-qr-wasm-env.sh    # rust wasm32 target + wasm-bindgen-cli 0.2.100（幂等）
bash scripts/build-fast-qr-wasm.sh        # 检出/复用 fast_qr v0.14.0 + patch qr_with + nodejs 产物
moon build cmd/bench --target wasm --release
node scripts/wasm-compare.mjs --fast "$HOME/.cache/fast_qr_wasm/pkg/fast_qr.js" \
  --moon _build/wasm/release/build/cmd/bench/bench.wasm --reps 3
```

产物/检出默认在 `$FAST_QR_WASM_DIR`（`$HOME/.cache/fast_qr_wasm`），可用环境变量覆盖。Rust/层②按既有
`setup-rust.sh` 决策**不接入 `.cnb.yml` push CI**（外部参考构建、拖慢 CI）。系统 gcc 为 wasm-bindgen 宿主
构建所需（本容器已装）。

---

## 5. 门禁与收尾（AGENTS §二.4 / 方案 §5）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test
for t in wasm-gc wasm; do moon build cmd/bench --target $t --release; moon test --target $t; done
```

实测：`moon fmt --check` / `moon check --deny-warn` 全过；测试 **109 全绿**（wasm-gc/wasm）；`cmd/bench`
默认输出与 PR #45 记录逐字一致（`V40 40` → 9200 等）；lib 公共 `.mbti` 零漂移（仅 cmd/bench + scripts
改动）。层②跑测可重复（`bash scripts/bench-layer2.sh`）。

---

## 6. 汇总

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

## 7. 参考

- 方案：[S9c-性能测试与fast_qr-wasm对比-实现方案.md](./S9c-性能测试与fast_qr-wasm对比-实现方案.md)
  （D17/D18/D19 + 修订注①/②）；S9 [实现记录](./S9-性能基准-实现记录.md)（层①数字/口径）、
  [评估记录](./S9-性能基准-实现评估与优化-记录.md)（KEEP_LAST 33 vs 65）、[S9b 优化路线](./S9b-性能优化-评估与路线.md)。
- 本仓库实码：`cmd/bench/main.mbt`（--dump）、`scripts/bench-layer2.sh`、`scripts/wasm-compare.mjs`、
  `scripts/build-fast-qr-wasm.sh`、`scripts/setup-fast-qr-wasm-env.sh`；lib 公共 API 未动。
- 参考 fast_qr v0.14.0（`53e8c99`）：`benches/qr.rs`、`src/wasm.rs`（bool_to_u8/qr_with patch）、
  `Cargo.lock`（wasm-bindgen 0.2.100）。
- 环境：moon 0.1.20260827、node v22.23.1（node:wasi 实验态但未采用）、rustc 1.98.1 + wasm32-unknown-unknown、
  wasm-bindgen 0.2.100（GitHub release 预编译）、gcc 14.2.0（apt，wasm-bindgen 宿主宏所需）、`moonrun`
  （~/.moon/bin）。
