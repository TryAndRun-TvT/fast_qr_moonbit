# S9e · 性能测试口径统一（Node 进程内调用两侧 wasm）· 实现记录

> 承接 [S9e-性能测试统一Node调用-实现方案.md](./S9e-性能测试统一Node调用-实现方案.md)。
> 本文记录**落地实现 + 重跑数字 + 踩坑**，回应 issue #50：把层②对比从
> 「fast_qr 进程内 / MoonBit `moonrun` 子进程」这种**不同宿主形态**，统一为**同一 Node 进程内调用**。
> 日期：2026-09-10　｜　前置：main @ `8621d57`（109 全绿）。
> **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；仅新增/改造 `scripts/` 下的对比脚本。
>
> **补充（S9f，issue #50 追加）**：性能口径统一后，**体积**口径也已统一 —— 见
> [S9f 产物体积对比-实现记录.md](./S9f-产物体积对比-实现记录.md)（复跑 `bash scripts/bench-size.sh`）。

---

## 0. 一句话结论

- **统一完成**：新增 `scripts/moonbit-wasm-runner.mjs`，在 **Node 进程内**实例化 MoonBit WASI 产物并调用；
  `scripts/wasm-compare.mjs` 改为两侧**同进程、同时钟、同循环形态**计时。
- **正确性未动**：Node 进程内 `--dump` 与 `moonrun` 输出**字节级一致**；三基准点矩阵对 fast_qr
  **逐位对齐零差异**，sha256 与 S9c 记录**逐字相同**（V03H `4942f6aa…b477`、V10H `91c85c94…0d8d`、
  V40H `c3c04930…cde7`）。
- **旧口径偏大被量化**：MoonBit 侧 `moonrun` 子进程口径比 Node 进程内口径**多 12–20%**
  （V03H 19.4% / V10H 12.5% / V40H 12.8%）。
- **重测结论**（R=5 取最小）：统一口径下
  - A（每次都新建 Instance，与 fast_qr「一次调用」同形）：MoonBit 单次 **0.473 / 1.464 / 10.08 ms**，
    fast_qr **0.0845 / 0.4006 / 3.554 ms** → fast_qr 快 **5.7× / 3.7× / 2.8×**；
  - B（单实例摊薄，剔 Instance 创建固定项）：MoonBit **0.314 / 1.257 / 9.66 ms**
    → fast_qr 快 **3.7× / 3.1× / 2.7×**。
- **量级结论不变**（fast_qr 更快，MoonBit 每模块约为其 2.7–3.7 倍），但**尺子干净了**：不再把
  MoonBit 侧的进程启动混进「单次 build」对比里。

---

## 1. 落地清单与验收

| # | 文件 | 内容 | 验收 | 状态 |
|---|------|------|------|------|
| 1 | `scripts/moonbit-wasm-runner.mjs`（新） | Node 进程内托管 MoonBit WASI 产物：`loadMoonWasm(path).run(argv)` | 与 `moonrun` 同产物 `--dump` **diff 空** | ✅ |
| 2 | `scripts/wasm-compare.mjs`（改） | 两侧统一 Node 进程内；输出 A/B 双口径；加 moonrun 跨宿主抽检；对齐逻辑沿用 | 一命令产出对齐+计时表 | ✅ |
| 3 | `scripts/bench-layer2.sh`（改） | 文案/注释更新为统一口径；支持 `MOON_HOST=moonrun` 回退 | `--no-build` 端到端可跑 | ✅ |
| 4 | `scripts/setup-fast-qr-wasm-env.sh`（补注） | 注明 wasm-bindgen 宿主宏仍需系统 gcc | 重跑幂等 | ✅ |
| 5 | 层②重跑 | 本容器实施 | §3 表 | ✅ |
| 6 | 收尾回归 | fmt/check/test + 双后端 + 默认 checksum | §5 | ✅ |
| 7 | 文档治理 | S9e 方案 + 本记录 + README/索引回链 | 无死链 | ✅ |

> **接口护栏**：新增 runner 是 `scripts/` 下的宿主脚本、`wasm-compare.mjs` 是驱动脚本，均不触 lib
> 公共 `.mbti`；`cmd/bench` 只被「调用」，源码未改。回归维持 **109 全绿**，层① 默认数字逐字不变。

---

## 2. 实现要点：Node 进程内托管 MoonBit WASI 产物

### 2.1 产物导入面（实际解析 wasm 段）

```
wasi_snapshot_preview1.fd_write                  (i32,i32,i32,i32)->i32
__moonbit_fs_unstable.args_get                   ()->externref
__moonbit_fs_unstable.begin_read_string          (externref)->externref
__moonbit_fs_unstable.string_read_char           (externref)->i32
__moonbit_fs_unstable.finish_read_string         (externref)->()
__moonbit_fs_unstable.begin_read_string_array    (externref)->externref
__moonbit_fs_unstable.string_array_read_string   (externref)->externref
__moonbit_fs_unstable.finish_read_string_array   (externref)->()
导出：memory, _start
```

**句柄 = `externref`（JS 对象）**，不是 i32 —— 旧 S9c spike 判「argv 注入失败」的根因就是把句柄当数值。

### 2.2 协议形状（从 `moonrun` 内嵌 shim 读出，实测复现）

argv 链路的关键：**`args_get()` 直接返回 argv 数组作为 opaque 句柄**，后续 MoonBit 侧把它原样回传：

```js
const argv = ['bench.wasm', ...args];
const fs = {
  args_get: () => argv,                                   // ← 返回数组本体（句柄）
  begin_read_string: (s) => ({ s, i: 0 }),
  string_read_char: (h) => (h.i >= h.s.length ? -1 : h.s.charCodeAt(h.i++)),
  finish_read_string: () => {},
  begin_read_string_array: (arr) => ({ arr, i: 0 }),      // ← arr 就是上面返回的 argv
  string_array_read_string: (h) =>
    h.i >= h.arr.length ? 'ffi_end_of_/string_array' : h.arr[h.i++],
  finish_read_string_array: () => {},
};
```

实测 trace（`--dump V03`）：

```
args_get  →  begin_read_string_array  →  begin_read_string "bench.wasm"
          →  begin_read_string "--dump"  →  begin_read_string "V03"
          →  begin_read_string "ffi_end_of_/string_array"
```

### 2.3 必须每次新建 Instance

- wasm `_start` 每个实例只能执行一次（moonrun 亦然）；**实测同实例第二次 `_start` 静默返回、无输出**
  （会误判成「程序没跑」）。
- 故 `run()` 每次 `new WebAssembly.Instance(module, freshImports)`；`module`（编译产物）在
  `loadMoonWasm` 里**预热一次**复用，测时不含编译。

### 2.4 踩坑记录（透明）

| 现象 | 根因 | 处置 |
|------|------|------|
| `new WebAssembly.Instance` 报 `function import requires a callable` | 只提供了 `__moonbit_fs_unstable.args_get`，缺其余 6 个导入 | 提供完整 7 个 shim 函数 |
| 程序回落到「默认三点全跑」（含 V03H:2000），未按 argv 分支 | **`args_get` 返回了 0/undefined**，MoonBit 侧拿到空 argv | `args_get` 必须**返回 argv 数组本体**（opaque 句柄） |
| `string_read_char` 里 `handle.s` 为 undefined | `begin_read_string(s)` 的 `s` 收到的其实是**句柄对象**（`{s,i}`），不是裸串 | 严格照搬 moonrun shim：`{ s: s, i: 0 }`，读侧同形 |
| Node 侧 `_start` 触发 OOM | 用 `Error`/`throw` 打断 wasm 内部调用栈时的副作用（且首次 spike 的 `args_get` 未返回句柄导致重试循环） | 按协议返回句柄后自然解决；不需要异常打断 |
| `begin_read_string_array(0)` 收到 0 | 该参数是 `args_get()` 的**返回值**（句柄），返回 0 即拿到空 argv | 同 2.2，返回 argv 数组 |
| `moonrun` 二进制 `strings` 无输出 | 该二进制为 stripped，字符串被压缩/无常规区段 | 直接 `python3` 在字节里 `find` 定位内嵌 shim 源码段 |

> 与 S9c「Node 进程内不可靠」的旧结论关系：旧 spike 走的是 `node:wasi` + `_start` + argv 注入，失败于
> **协议形状**（句柄当 i32 / 未返回 argv 句柄）。本次改用裸 `WebAssembly.Instance` + 自写 shim，
> 协议对齐后**完全可用**——故旧结论更新为「可用，前提是复刻 `externref` opaque 句柄协议」。

---

## 3. 统一前后的口径量化

### 3.1 统一前：两侧宿主形态差多少（同机 R=3 取最小）

| 点 | N | (a) `moonrun` 子进程整程 ms | (b) Node 进程内逐次 ms | (a)−(b) 启动占比 |
|----|--:|---------------------------:|----------------------:|-----------------:|
| V03H | 2000 | 805.19 | 648.85 | **19.4%** |
| V10H | 400 | 583.60 | 510.67 | **12.5%** |
| V40H | 40 | 466.04 | 406.31 | **12.8%** |

> 即旧口径把 MoonBit 侧抬高了约 1.13–1.19×，是 issue #50 指出的「并非统一」的实际影响量级。

### 3.2 统一后：三种 MoonBit 口径对照（同机，单次均摊）

| 点 | N | (a) `moonrun` 子进程 | (b) Node 进程内·逐次调用 | (c) Node 进程内·单实例摊薄 |
|----|--:|--------------------:|------------------------:|--------------------------:|
| V03H | 2000 | 0.4110 ms | 0.4783 ms | **0.3337 ms** |
| V10H | 400 | 1.4683 ms | 1.5161 ms | **1.2704 ms** |
| V40H | 40 | 11.7778 ms | 10.3524 ms | **10.0247 ms** |

- **(c) 纯 build 边际成本**（一次 `_start` 内跑 N 次 build）。
- **(b) 与 fast_qr「一次调用」严格同形**：每次新建 Instance；
  **Instance 创建固定项实测 ≈ 83 µs/次**（先用「非法点 → 0 次 build」的口径测得：
  500 次纯实例化 83.01 µs/iter；同一实例化 + 1 次 V03 build 525.06 µs/iter）。
  → 该项在 V03H（单次 build 仅 ~0.31ms）上占比可达 **~17%**，在小版本上不可忽略；大版本摊薄后影响很小。
- 故**主对比表同时给 A/B 两口径**：A 严格同形（含 Instance 固定项、公平但含宿主托管成本）；
  B 剔固定项（纯算法边际），两者给出同一量级结论。

---

## 4. 重跑：统一口径对比表

命令：

```bash
bash scripts/bench-layer2.sh            # 环境 → fast_qr 构建 → moon build → Node 统一对比（R=3）
R=5 bash scripts/bench-layer2.sh --no-build   # 产物就绪时只跑对比
```

口径：输入 `https://example.com/`（20 字节）、ECL=H、强制 V03/V10/V40、mask 自动择优；
两侧**同一 Node 进程**；R 次取最小，下表单次 = 最小循环时间 ÷ N。

| 基准点 | 迭代 N | 逐位对齐 | MoonBit 单次(A) ms | MoonBit 单次(B) ms | fast_qr 单次 ms | fast/moon(A) | fast/moon(B) |
|--------|-------:|:--------:|------------------:|------------------:|---------------:|-------------:|-------------:|
| V03H | 2000 | ✅ | 0.4730 | 0.3142 | 0.0845 | **0.179×** | **0.269×** |
| V10H | 400 | ✅ | 1.4636 | 1.2570 | 0.4006 | **0.274×** | **0.319×** |
| V40H | 40 | ✅ | 10.80 | 9.66 | 3.554 | **0.329×** | **0.368×** |

> A 口径（严格同形）fast_qr 快约 **5.6× / 3.7× / 3.0×**；B 口径（纯边际）快约 **3.7× / 3.1× / 2.7×**。
> 复跑稳定性：R=3 与 R=5 两次独立 run 单次值相对漂移 ≤ 7%（V03H/V10H < 3%，V40H ~4%）。

逐位对齐 sha256（moon == fast == moonrun 抽检）：
- V03H `4942f6aa5ce6be219535a8fc6ce9f1d5417e30dca5e653ff324a0f62602eb477`（29×29）
- V10H `91c85c94a3257e76ccf41a628c1b8e2c30373f387659e7770183fdef36a0d8d0`（57×57）
- V40H `c3c04930b1a90bd07d89543d2af72f62236512797b3cf02bc87043673866cde7`（177×177）

checksum 自洽：MoonBit 侧 `cmd/bench` 单次 build 与默认档一致（V03H 41↔82000、V10H 81↔32400、
V40H 230↔9200，同公式不同 N）；fast_qr = N × size²（1682000 / 1299600 / 1253160）。

---

## 5. 门禁与收尾（AGENTS §二.4）

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

实测：`moon fmt --check` / `moon check --deny-warn` 全过；测试 **109 全绿**（wasm-gc/wasm 双后端）；
`cmd/bench` 默认输出与 S9c 记录逐字一致（`V40 40` → 9200）；lib 公共 `.mbti` 零漂移（仅 `scripts/` 改动）。

---

## 6. 汇总

1. **问题**：旧层②两侧宿主形态不同（fast_qr Node 进程内 / MoonBit `moonrun` 子进程），MoonBit 侧多计
   启动 **12–20%**，对比倍率被系统性放大。
2. **统一**：新增 `scripts/moonbit-wasm-runner.mjs`（Node 进程内托管 MoonBit WASI 产物，复刻 moonrun
   的 `externref` opaque 句柄 argv 协议）；`wasm-compare.mjs` 两侧同进程/同时钟/同循环形态计时。
3. **正确性**：Node 进程内 `--dump` 与 `moonrun` **字节级一致**；三矩阵对 fast_qr **逐位对齐零差异**
   （sha256 与 S9c 同值）。
4. **重测**：统一口径 fast_qr 快约 **2.7–5.6×**（B 纯边际 2.7–3.7×，A 严格同形 3.0–5.6×），
   量级结论与旧口径一致、但尺子干净；MoonBit 每模块成本仍约为 fast_qr 的 2.7–3.7 倍。
5. **护栏**：不改 lib/快照/`cmd/bench` 默认行为；109 全绿；`MOON_HOST=moonrun` 可回退旧口径。

**后续（可选）**：S9b 的 P1（择优主循环减趟/特化）落地后，用同一 `bash scripts/bench-layer2.sh`
复跑即可量化差距收窄；本记录 §4 表即为优化前后**同一把尺子**的基线。

---

## 7. 参考

- 方案：[S9e-性能测试统一Node调用-实现方案.md](./S9e-性能测试统一Node调用-实现方案.md)；
  issue #50。
- 前序层②：[S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)、
  [S9c 详细分析](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)（N 扫描 / 固定开销拟合）。
- 本仓库实码：`scripts/moonbit-wasm-runner.mjs`、`scripts/wasm-compare.mjs`、`scripts/bench-layer2.sh`、
  `scripts/build-fast-qr-wasm.sh`、`scripts/setup-fast-qr-wasm-env.sh`、`cmd/bench/main.mbt`（未改）。
- 参考 fast_qr v0.14.0（`53e8c99`）：`src/wasm.rs`（`qr_with` patch）、`benches/qr.rs`。
- `moonrun`（`~/.moon/bin/moonrun`）内嵌宿主 shim；MoonBit `--target wasm` 产物导入/导出面（实测解析）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 12.2.0（wasm-bindgen 宿主宏所需，apt）、`moonrun`（~/.moon/bin）。
