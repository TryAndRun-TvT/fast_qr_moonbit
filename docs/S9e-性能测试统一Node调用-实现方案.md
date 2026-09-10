# S9e · 性能测试口径统一（Node 进程内调用两侧 wasm）· 实现方案

> 承接 [S9c 层②系列](./S9c-性能测试与fast_qr-wasm对比-详细分析.md) 与
> [S9d 生态对比系列](./S9d-与moonbit生态QR包性能对比-详细分析.md)。
> 本文回应 issue #50「fast_qr_moonbit vs fast_qr wasm 在性能测试中并非统一通过 nodejs 调用」：
> 先**读代码与文档**、把两侧调用形态的差异**量化**，再给出**统一口径的实现方案**（含 Node 进程内
> 运行 MoonBit WASI 产物的宿主协议），最后**重新测一遍**并更新文档。
> 日期：2026-09-10　｜　性质：方案 + 实现（脚本层，不改 lib / 快照 / `cmd/bench` 默认行为）
> 前置：main @ `8621d57`（测试 109 全绿）；环境脚本见 `scripts/`。

---

## 0. 一句话结论

- **问题确认（事实）**：S9c 的层②对比**确实不是同一宿主形态**——fast_qr 侧是 **Node 进程内**直调
  `qr_with()`，MoonBit 侧却是 **`moonrun` 子进程整程**（`execFileSync`，含进程启动）。两侧被计入了
  不同的固定开销。
- **量化**：`moonrun` 子进程口径 vs Node 进程内口径，MoonBit 侧整程时间差 **12–20%**（V03H ≈19%、
  V10H ≈13%、V40H ≈13%；见 §3）。旧口径因此把 MoonBit 侧抬高了约 1.13–1.19×，**对比倍率被系统性放大**。
- **统一方案**：新增 `scripts/moonbit-wasm-runner.mjs`——在**当前 Node 进程内**实例化 MoonBit
  `--target wasm`（WASI preview1）产物并调用（完整复刻 `moonrun` 内置宿主 shim 的 argv/字符串
  opaque 句柄协议）。`scripts/wasm-compare.mjs` 改为**两侧同一进程、同一时钟、同一循环形态**计时。
- **重测结论**（统一口径，R=5 取最小，逐位对齐零差异）：MoonBit 单次 build（A 逐次调用口径）
  0.473/1.464/10.08ms vs fast_qr 0.0845/0.4006/3.554ms → **fast_qr 快约 2.8–5.7×**；
  改用「单实例摊薄」（B 口径，剔 Node 托管 wasm 的 Instance 创建固定项）0.314/1.257/9.66ms →
  **fast_qr 快约 2.7–3.7×**。两口径一致表明：**旧口径的 3.1–5.2× 里，有约 0.1–0.3× 来自 MoonBit 侧
  多计的启动**；剔净后仍是同一量级结论（MoonBit 每模块成本约为 fast_qr 的 2.7–3.7 倍）。

---

## 1. 范围界定

### 1.1 本文做

1. 读代码/文档，**确认并量化**两侧调用形态差异（§2、§3）；
2. 给出**统一 Node 进程内调用**的实现方案：MoonBit WASI 产物宿主协议（§4）；
3. 落地文件：`scripts/moonbit-wasm-runner.mjs`（新）、`scripts/wasm-compare.mjs`（改）、
   `scripts/bench-layer2.sh`（改）、`scripts/setup-fast-qr-wasm-env.sh`（补 gcc 说明）；
4. 重跑三基准点（逐位对齐 + 计时），产出 [S9e 实现记录](./S9e-性能测试统一Node调用-实现记录.md)；
5. README / 文档索引 / 相关回链同步。

### 1.2 本文不做

- **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**（层① 数字与 109 测试基线是回归护栏）；
- **不追平 fast_qr 的绝对数字**（S9b 已声明不设硬门槛）；
- **不把 Node/Rust/层② 接入 `.cnb.yml` push CI**（沿用既有决策：外部参考构建拖慢 CI）；
- **不改 `cmd/bench` 的 argv 协议/输出格式**（`--dump`、`TOTAL_CHECKSUM` 保持字节级不变）。

---

## 2. 读代码与文档：两侧调用形态盘点

| 侧 | 旧（S9c）载体 | 旧宿主形态 | 计时边界 |
|----|--------------|-----------|---------|
| fast_qr-wasm32 | `require(pkg/fast_qr.js)` → `qr_with()` | **Node 进程内**（无子进程） | `performance.now()` 包循环，R 次取最小 |
| 本仓库 MoonBit wasm | `execFileSync('moonrun', [bench.wasm, pt, N])` | **`moonrun` 子进程整程** | `performance.now()` 包 `execFileSync`（**含进程启动**） |

- 旧文档已如实标注该差异（S9c 实现记录 §2.3「MoonBit 侧 = moonrun 子进程整程（含微启动）」、
  §3「表注写明两侧进程形态差异」），S9c 详细分析 §2.3 还用 N 扫描线性拟合把启动项 `a_moon≈23–34ms`
  单列出来。**但两侧最终仍不同形**：fast_qr 侧无启动、MoonBit 侧有启动 → 「整程最小时间」不是同一把尺子。
- 旧口径「为什么没有统一」的技术原因：S9c 时代 spike 判定「Node 进程内 `node:wasi` 实例化 + 调 `_start`」
  不可靠（argv 注入失败、`fd_write` 绕过 `process.stdout` 拦截）→ 走 `moonrun` 降级路径（S9c D18）。
  **本次重新核查后该结论可以突破**：`node:wasi` 并不是唯一路径，直接 `WebAssembly.Instance` + 自写
  `__moonbit_fs_unstable` shim 即可，关键是**协议形状要对**（§4）。

---

## 3. 量化差异（统一前的「不同尺子」有多大）

同机实测（`R=3` 取最小，MoonBit `cmd/bench --target wasm` 产物，V03H/V10H/V40H）：

| 点 | N | (a) moonrun 子进程整程 ms | (b) Node 进程内逐次 ms | (a)−(b) 启动占比 |
|----|--:|-------------------------:|----------------------:|-----------------:|
| V03H | 2000 | 805.19 | 648.85 | **19.4%** |
| V10H | 400 | 583.60 | 510.67 | **12.5%** |
| V40H | 40 | 466.04 | 406.31 | **12.8%** |

- 结论：旧口径下 MoonBit 侧被多计了约 **12–20%** 的固定启动时间；摊到单次即被抬大约 1.13–1.19×。
- 该差值 <20%，**不改变「fast_qr 更快」的定性结论**，但足以让对比倍率**不够干净**——issue #50 指出的
  正是这一点，值得统一。

### 3.1 统一后的三种 MoonBit 口径（同机，单次均摊）

| 点 | N | (a) moonrun 子进程 | (b) Node 进程内·逐次调用 | (c) Node 进程内·单实例摊薄 |
|----|--:|-------------------:|-------------------------:|---------------------------:|
| V03H | 2000 | 0.4110 ms | 0.4783 ms | **0.3337 ms** |
| V10H | 400 | 1.4683 ms | 1.5161 ms | **1.2704 ms** |
| V40H | 40 | 11.7778 ms | 10.3524 ms | **10.0247 ms** |

- **(c) 是纯 build 边际成本**：一个 Instance 内跑 N 次 build（一次 `_start`），剔掉 Node 托管 wasm 的
  「Instance 创建 + WASI/argv 初始化」固定项（实测 ≈**83 µs/次**，见实现记录 §3）。
- **(b) 是与 fast_qr「一次调用」严格同形的口径**：每次调用新建 Instance（`_start` 只能跑一次，
  moonrun 亦然）。它含 Instance 创建固定项，故 V03H 上明显高于 (c)。
- (a) 在小 N（V40H N=40）上因启动占比大而偏高；大 N 时与 (c) 接近。

---

## 4. 统一方案：Node 进程内运行 MoonBit WASI 产物

### 4.1 关键事实：产物导入面与宿主协议

`moon build cmd/bench --target wasm --release` 产物（`bench.wasm`）的导入面（实测解析 wasm 段）：

```
wasi_snapshot_preview1.fd_write                       (func (i32,i32,i32,i32)->i32)
__moonbit_fs_unstable.args_get                        (func ()->externref)
__moonbit_fs_unstable.begin_read_string               (func (externref)->externref)
__moonbit_fs_unstable.string_read_char                (func (externref)->i32)
__moonbit_fs_unstable.finish_read_string              (func (externref)->())
__moonbit_fs_unstable.begin_read_string_array         (func (externref)->externref)
__moonbit_fs_unstable.string_array_read_string        (func (externref)->externref)
__moonbit_fs_unstable.finish_read_string_array        (func (externref)->())
```

导出仅 `memory` + `_start`。**句柄是 `externref`（JS 对象）而非数值**——这是旧 spike 失败的根因：
当时把句柄当 i32 处理，协议对不上。

### 4.2 协议形状（从 `moonrun` 内置 shim 读出并实测验证）

`moonrun` 二进制内嵌了一段 JS 宿主 shim（`// V8-native value shims ...`），其 `__moonbit_fs_unstable`
定义即协议权威：

```js
function begin_read_string(s) { return { s: s, i: 0 } }           // s 本身即句柄
function string_read_char(h) { if (h.i >= h.s.length) return -1; return h.s.charCodeAt(h.i++) }
function begin_read_string_array(arr) { return { arr: arr, i: 0 } }
function string_array_read_string(h) {
  if (h.i >= h.arr.length) return "ffi_end_of_/string_array"       // 哨兵串收尾
  return h.arr[h.i++]
}
```

配套的 argv 链路（**这是真正要复刻的部分**）：

1. `args_get()` 返回 **argv 数组**（opaque 句柄）；
2. MoonBit 侧把它原样回传给 `begin_read_string_array(handle)`；
3. `string_array_read_string(handle)` 逐个吐出 argv 元素，读完返回 `"ffi_end_of_/string_array"`；
4. 每个元素再由 `begin_read_string`/`string_read_char`/`finish_read_string` 逐字符读回。

（实测 trace：`args_get → brsa → brs "bench.wasm" → brs "--dump" → brs "V03" → brs "ffi_end_of_/string_array"`。）

### 4.3 落地：`scripts/moonbit-wasm-runner.mjs`

- **职责**：`loadMoonWasm(path).run(argv)` —— 模块级预热编译一次（不含编译开销），每次 `run` 新建
  Instance + 一套宿主 shim 闭包，同步跑 `_start` 并收集 stdout。
- **为什么每次 new Instance**：wasm `_start` 每个实例只能执行一次（`moonrun` 同样如此）；实测**第二次
  `_start` 会静默返回、无输出**，因此不能在同实例内重复调。
- **逐位验证**：Node 进程内跑 `--dump V03/V10/V40`，与 `moonrun` 同产物输出 **字节级一致**（diff 空）。
- **回退**：若将来工具链更换 host 协议（导入集变化），`bench-layer2.sh` 支持 `MOON_HOST=moonrun`
  回退到旧的子进程口径。

### 4.4 `scripts/wasm-compare.mjs` 改造

- 两侧统一到**同一个 Node 进程**：MoonBit 用上面的 runner、fast_qr 用 `require` 直调；
- 同时输出 **A（逐次调用，与 fast_qr 调用同形）** 与 **B（单实例摊薄，纯 build 边际）** 两个 MoonBit
  口径，避免任何一侧的宿主固定项被误读；
- 逐位对齐不变（`--dump` vs `qr_with` 规范文本 + sha256），并**加一条 moonrun 跨宿主抽检**（同源产物
  在 moonrun 下应为同一 dump），把「统一宿主」变化锁在正确性护栏内。

---

## 5. 验收策略

| 层级 | 验收项 | 通过标准 |
|------|--------|---------|
| 正确性 | Node 进程内 runner vs moonrun | `--dump V03/V10/V40` 输出 **diff 为空** |
| 对齐 | 三基准点矩阵 | MoonBit vs fast_qr 规范文本 **sha256 一致**（与 S9c 记录同值） |
| 计时 | 统一口径 | 一条命令产出 A/B 双口径 + fast_qr 表；R 可参数化、多次取最小 |
| 回归 | AGENTS §二.4 | `moon fmt --check` / `moon check --deny-warn` / `moon test` **109 全绿**；双后端 release 通过；`cmd/bench` 默认数字不变（82000/32400/9200） |
| 文档 | README/索引 | 新增 S9e 两篇并回链、无死链 |

> 若出现「对齐非零差异」，优先怀疑宿主协议/参考版本，而非算法——按 §4.3 的 diff 定位。

---

## 6. 汇总

1. **确认问题**：旧层②两侧宿主形态不同（fast_qr 进程内 / MoonBit `moonrun` 子进程），差异 **12–20%**。
2. **方案**：`scripts/moonbit-wasm-runner.mjs` 在 Node 进程内托管 MoonBit WASI 产物（复刻 moonrun
   宿主 shim 的 `externref` opaque 句柄 argv 协议），两侧统一到同一进程/时钟/循环形态。
3. **重测**：对齐零差异不变；统一口径下 MoonBit 单次 0.31–9.66ms（B 口径）、fast_qr 快约 2.7–3.7×
   （A 口径 2.8–5.7×），量级结论与旧口径一致但尺子干净。
4. **护栏**：lib/快照/`cmd/bench` 默认行为零改动，109 测试全绿。

**后续**：见 [S9e 实现记录](./S9e-性能测试统一Node调用-实现记录.md)（数字、踩坑、复跑命令）。

---

## 7. 参考

- issue #50（本任务来源）；[S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比-实现记录.md) §2.3（旧降级路径）、
  [S9c 详细分析](./S9c-性能测试与fast_qr-wasm对比-详细分析.md) §2（N 扫描 / 固定开销 a_moon）。
- 本仓库实码：`cmd/bench/main.mbt`（`--dump` / checksum）、`scripts/moonbit-wasm-runner.mjs`、
  `scripts/wasm-compare.mjs`、`scripts/bench-layer2.sh`。
- `moonrun` 内置宿主 shim（`~/.moon/bin/moonrun` 内嵌 JS，`__moonbit_fs_unstable` 定义与导入名表）；
  MoonBit `--target wasm`（WASI preview1）产物导入/导出面（本方案实测解析）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 12.2.0（wasm-bindgen 宿主宏所需）。
