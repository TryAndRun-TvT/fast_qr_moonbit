# S9e · 性能测试统一 Node 调用

> **状态**：历史　｜　日期：2026-09-10　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §7　｜　并入：统一 Node 口径已并入 [S9j](S9j-层②统一Node对比-wasm-gc与fast_qr.md) / [S9p](S9p-宿主调用面性能口径-JS向wasm传参.md)

> ⚠️ **历史记录**：MoonBit `wasm`(WASI) 后端已按项目决策移除，本项目现仅支持 `wasm-gc`；本文涉及的 `wasm` 后端数字与口径仅作历史留存，不再作为对外口径。

> 本文件由原 S9e-性能测试统一Node调用-实现方案 / S9e-性能测试统一Node调用-实现记录 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接 [S9c 层②系列](./S9c-性能测试与fast_qr-wasm对比.md) 与
> [S9d 生态对比系列](./S9d-与moonbit生态QR包性能对比.md)。
> 本文回应 issue #50「fast_qr_moonbit vs fast_qr wasm 在性能测试中并非统一通过 nodejs 调用」：
> 先**读代码与文档**、把两侧调用形态的差异**量化**，再给出**统一口径的实现方案**（含 Node 进程内
> 运行 MoonBit WASI 产物的宿主协议），最后**重新测一遍**并更新文档。
> 日期：2026-09-10　｜　性质：方案 + 实现（脚本层，不改 lib / 快照 / `cmd/bench` 默认行为）
> 前置：main @ `8621d57`（测试 109 全绿）；环境脚本见 `scripts/`。
>
> **补充（S9f，issue #50 追加）**：本文统一的是**性能**计时口径；**产物体积**的口径统一见
> [S9f 产物体积对比-实现方案.md](./S9f-产物体积对比.md)（同规则五档 + 基线分解 + 语义护栏）。
> 两条线取**同一份 MoonBit `wasm` 侧产物**，可互为参照。
>
> **修订（S9j，2026-09-11 口径收敛）**：本文 MoonBit 侧用的是 `wasm`(WASI) **兼容兜底后端**产物，
> 与 `moon.mod` 的 `preferred_target = "wasm-gc"`（实际分发形态）不一致，对外引用易生歧义。
> **层② 对外引用口径已收敛为 `wasm-gc` vs fast_qr，见 [S9j](./S9j-层②统一Node对比-wasm-gc与fast_qr.md)**；
> 本文保留为「`wasm`/WASI 后端」历史记录（其方法结论：统一 Node 进程内调用、差距集中在择优主循环，仍成立）。
> 复跑历史口径：`MOON_TARGET=wasm bash scripts/bench-layer2.sh`。

---

### 0. 一句话结论

- **问题确认（事实）**：S9c 的层②对比**确实不是同一宿主形态**——fast_qr 侧是 **Node 进程内**直调
  `qr_with()`，MoonBit 侧却是 **`moonrun` 子进程整程**（`execFileSync`，含进程启动）。两侧被计入了
  不同的固定开销。
- **量化**：`moonrun` 子进程口径 vs Node 进程内口径，MoonBit 侧整程时间差 **12–20%**（V03H ≈19%、
  V10H ≈13%、V40H ≈13%；见 §3）。旧口径因此把 MoonBit 侧抬高了约 1.13–1.19×，**对比倍率被系统性放大**。
- **统一方案**：新增 `原 wasm/WASI Node 运行器`——在**当前 Node 进程内**实例化 MoonBit
  `--target wasm`（WASI preview1）产物并调用（完整复刻 `moonrun` 内置宿主 shim 的 argv/字符串
  opaque 句柄协议）。`原 wasm/WASI 对比驱动脚本` 改为**两侧同一进程、同一时钟、同一循环形态**计时。
- **重测结论**（统一口径，R=5 取最小，逐位对齐零差异）：MoonBit 单次 build（A 逐次调用口径）
  0.473/1.464/10.08ms vs fast_qr 0.0845/0.4006/3.554ms → **fast_qr 快约 2.8–5.7×**；
  改用「单实例摊薄」（B 口径，剔 Node 托管 wasm 的 Instance 创建固定项）0.314/1.257/9.66ms →
  **fast_qr 快约 2.7–3.7×**。两口径一致表明：**旧口径的 3.1–5.2× 里，有约 0.1–0.3× 来自 MoonBit 侧
  多计的启动**；剔净后仍是同一量级结论（MoonBit 每模块成本约为 fast_qr 的 2.7–3.7 倍）。

---

### 1. 范围界定

#### 1.1 本文做

1. 读代码/文档，**确认并量化**两侧调用形态差异（§2、§3）；
2. 给出**统一 Node 进程内调用**的实现方案：MoonBit WASI 产物宿主协议（§4）；
3. 落地文件：`原 wasm/WASI Node 运行器`（新）、`原 wasm/WASI 对比驱动脚本`（改）、
   `scripts/bench-layer2.sh`（改）、`scripts/setup-fast-qr-wasm-env.sh`（补 gcc 说明）；
4. 重跑三基准点（逐位对齐 + 计时），产出 本文件「实现记录」部分；
5. README / 文档索引 / 相关回链同步。

#### 1.2 本文不做

- **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**（层① 数字与 109 测试基线是回归护栏）；
- **不追平 fast_qr 的绝对数字**（S9b 已声明不设硬门槛）；
- **不把 Node/Rust/层② 接入 `.cnb.yml` push CI**（沿用既有决策：外部参考构建拖慢 CI）；
- **不改 `cmd/bench` 的 argv 协议/输出格式**（`--dump`、`TOTAL_CHECKSUM` 保持字节级不变）。

---

### 2. 读代码与文档：两侧调用形态盘点

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

### 3. 量化差异（统一前的「不同尺子」有多大）

同机实测（`R=3` 取最小，MoonBit `cmd/bench --target wasm` 产物，V03H/V10H/V40H）：

| 点 | N | (a) moonrun 子进程整程 ms | (b) Node 进程内逐次 ms | (a)−(b) 启动占比 |
|----|--:|-------------------------:|----------------------:|-----------------:|
| V03H | 2000 | 805.19 | 648.85 | **19.4%** |
| V10H | 400 | 583.60 | 510.67 | **12.5%** |
| V40H | 40 | 466.04 | 406.31 | **12.8%** |

- 结论：旧口径下 MoonBit 侧被多计了约 **12–20%** 的固定启动时间；摊到单次即被抬大约 1.13–1.19×。
- 该差值 <20%，**不改变「fast_qr 更快」的定性结论**，但足以让对比倍率**不够干净**——issue #50 指出的
  正是这一点，值得统一。

#### 3.1 统一后的三种 MoonBit 口径（同机，单次均摊）

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

### 4. 统一方案：Node 进程内运行 MoonBit WASI 产物

#### 4.1 关键事实：产物导入面与宿主协议

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

#### 4.2 协议形状（从 `moonrun` 内置 shim 读出并实测验证）

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

#### 4.3 落地：`原 wasm/WASI Node 运行器`

- **职责**：`loadMoonWasm(path).run(argv)` —— 模块级预热编译一次（不含编译开销），每次 `run` 新建
  Instance + 一套宿主 shim 闭包，同步跑 `_start` 并收集 stdout。
- **为什么每次 new Instance**：wasm `_start` 每个实例只能执行一次（`moonrun` 同样如此）；实测**第二次
  `_start` 会静默返回、无输出**，因此不能在同实例内重复调。
- **逐位验证**：Node 进程内跑 `--dump V03/V10/V40`，与 `moonrun` 同产物输出 **字节级一致**（diff 空）。
- **回退**：若将来工具链更换 host 协议（导入集变化），`bench-layer2.sh` 支持 `MOON_HOST=moonrun`
  回退到旧的子进程口径。

#### 4.4 `原 wasm/WASI 对比驱动脚本` 改造

- 两侧统一到**同一个 Node 进程**：MoonBit 用上面的 runner、fast_qr 用 `require` 直调；
- 同时输出 **A（逐次调用，与 fast_qr 调用同形）** 与 **B（单实例摊薄，纯 build 边际）** 两个 MoonBit
  口径，避免任何一侧的宿主固定项被误读；
- 逐位对齐不变（`--dump` vs `qr_with` 规范文本 + sha256），并**加一条 moonrun 跨宿主抽检**（同源产物
  在 moonrun 下应为同一 dump），把「统一宿主」变化锁在正确性护栏内。

---

### 5. 验收策略

| 层级 | 验收项 | 通过标准 |
|------|--------|---------|
| 正确性 | Node 进程内 runner vs moonrun | `--dump V03/V10/V40` 输出 **diff 为空** |
| 对齐 | 三基准点矩阵 | MoonBit vs fast_qr 规范文本 **sha256 一致**（与 S9c 记录同值） |
| 计时 | 统一口径 | 一条命令产出 A/B 双口径 + fast_qr 表；R 可参数化、多次取最小 |
| 回归 | AGENTS §二.4 | `moon fmt --check` / `moon check --deny-warn` / `moon test` **109 全绿**；双后端 release 通过；`cmd/bench` 默认数字不变（82000/32400/9200） |
| 文档 | README/索引 | 新增 S9e 两篇并回链、无死链 |

> 若出现「对齐非零差异」，优先怀疑宿主协议/参考版本，而非算法——按 §4.3 的 diff 定位。

---

### 6. 汇总

1. **确认问题**：旧层②两侧宿主形态不同（fast_qr 进程内 / MoonBit `moonrun` 子进程），差异 **12–20%**。
2. **方案**：`原 wasm/WASI Node 运行器` 在 Node 进程内托管 MoonBit WASI 产物（复刻 moonrun
   宿主 shim 的 `externref` opaque 句柄 argv 协议），两侧统一到同一进程/时钟/循环形态。
3. **重测**：对齐零差异不变；统一口径下 MoonBit 单次 0.31–9.66ms（B 口径）、fast_qr 快约 2.7–3.7×
   （A 口径 2.8–5.7×），量级结论与旧口径一致但尺子干净。
4. **护栏**：lib/快照/`cmd/bench` 默认行为零改动，109 测试全绿。

**后续**：见 本文件「实现记录」部分（数字、踩坑、复跑命令）。

---

### 7. 参考

- issue #50（本任务来源）；[S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比.md) §2.3（旧降级路径）、
  [S9c 详细分析](./S9c-性能测试与fast_qr-wasm对比.md) §2（N 扫描 / 固定开销 a_moon）。
- 本仓库实码：`cmd/bench/main.mbt`（`--dump` / checksum）、`原 wasm/WASI Node 运行器`、
  `原 wasm/WASI 对比驱动脚本`、`scripts/bench-layer2.sh`。
- `moonrun` 内置宿主 shim（`~/.moon/bin/moonrun` 内嵌 JS，`__moonbit_fs_unstable` 定义与导入名表）；
  MoonBit `--target wasm`（WASI preview1）产物导入/导出面（本方案实测解析）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 12.2.0（wasm-bindgen 宿主宏所需）。

---

## 实现记录

> 承接 本文件「实现方案」部分。
> 本文记录**落地实现 + 重跑数字 + 踩坑**，回应 issue #50：把层②对比从
> 「fast_qr 进程内 / MoonBit `moonrun` 子进程」这种**不同宿主形态**，统一为**同一 Node 进程内调用**。
> 日期：2026-09-10　｜　前置：main @ `8621d57`（109 全绿）。
> **不改 lib / 公共 API / 快照 / `cmd/bench` 默认行为**；仅新增/改造 `scripts/` 下的对比脚本。
>
> **补充（S9f，issue #50 追加）**：性能口径统一后，**体积**口径也已统一 —— 见
> [S9f 产物体积对比-实现记录.md](./S9f-产物体积对比.md)（复跑 `bash scripts/bench-size.sh`）。
>
> **⚠️ 修订（S9h，2026-09-11）**：本文 §4 的毫秒数字**绑定测量环境**（node v24.20.0 + 当时宿主）。
> 复测确认同环境内 ≤3% 稳定、语义零回归，但跨环境存在系统性漂移：Node 大版本使 MoonBit 侧单次
> 变动 −18~41%（v24 比 v22 快）、宿主/会话再 ±20–40%；比值口径 V10H/V40H 同 Node 大版本下稳
> （±4%）、V03H 敏感。**引用本文数字必须带「Node 版本 + 宿主 + 日期」**；量级结论
> （fast_qr 快 2.7–5.7×）在所有测过环境成立（复测范围 2.6–6.0×）。详见
> [S9h 层②性能复测异常归因](./S9h-层②性能复测异常归因-Node版本与宿主漂移.md)。

---

### 0. 一句话结论

- **统一完成**：新增 `原 wasm/WASI Node 运行器`，在 **Node 进程内**实例化 MoonBit WASI 产物并调用；
  `原 wasm/WASI 对比驱动脚本` 改为两侧**同进程、同时钟、同循环形态**计时。
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

### 1. 落地清单与验收

| # | 文件 | 内容 | 验收 | 状态 |
|---|------|------|------|------|
| 1 | `原 wasm/WASI Node 运行器`（新） | Node 进程内托管 MoonBit WASI 产物：`loadMoonWasm(path).run(argv)` | 与 `moonrun` 同产物 `--dump` **diff 空** | ✅ |
| 2 | `原 wasm/WASI 对比驱动脚本`（改） | 两侧统一 Node 进程内；输出 A/B 双口径；加 moonrun 跨宿主抽检；对齐逻辑沿用 | 一命令产出对齐+计时表 | ✅ |
| 3 | `scripts/bench-layer2.sh`（改） | 文案/注释更新为统一口径；支持 `MOON_HOST=moonrun` 回退 | `--no-build` 端到端可跑 | ✅ |
| 4 | `scripts/setup-fast-qr-wasm-env.sh`（补注） | 注明 wasm-bindgen 宿主宏仍需系统 gcc | 重跑幂等 | ✅ |
| 5 | 层②重跑 | 本容器实施 | §3 表 | ✅ |
| 6 | 收尾回归 | fmt/check/test + 双后端 + 默认 checksum | §5 | ✅ |
| 7 | 文档治理 | S9e 方案 + 本记录 + README/索引回链 | 无死链 | ✅ |

> **接口护栏**：新增 runner 是 `scripts/` 下的宿主脚本、`原 wasm/WASI 对比驱动脚本` 是驱动脚本，均不触 lib
> 公共 `.mbti`；`cmd/bench` 只被「调用」，源码未改。回归维持 **109 全绿**，层① 默认数字逐字不变。

---

### 2. 实现要点：Node 进程内托管 MoonBit WASI 产物

#### 2.1 产物导入面（实际解析 wasm 段）

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

#### 2.2 协议形状（从 `moonrun` 内嵌 shim 读出，实测复现）

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

#### 2.3 必须每次新建 Instance

- wasm `_start` 每个实例只能执行一次（moonrun 亦然）；**实测同实例第二次 `_start` 静默返回、无输出**
  （会误判成「程序没跑」）。
- 故 `run()` 每次 `new WebAssembly.Instance(module, freshImports)`；`module`（编译产物）在
  `loadMoonWasm` 里**预热一次**复用，测时不含编译。

#### 2.4 踩坑记录（透明）

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

### 3. 统一前后的口径量化

#### 3.1 统一前：两侧宿主形态差多少（同机 R=3 取最小）

| 点 | N | (a) `moonrun` 子进程整程 ms | (b) Node 进程内逐次 ms | (a)−(b) 启动占比 |
|----|--:|---------------------------:|----------------------:|-----------------:|
| V03H | 2000 | 805.19 | 648.85 | **19.4%** |
| V10H | 400 | 583.60 | 510.67 | **12.5%** |
| V40H | 40 | 466.04 | 406.31 | **12.8%** |

> 即旧口径把 MoonBit 侧抬高了约 1.13–1.19×，是 issue #50 指出的「并非统一」的实际影响量级。

#### 3.2 统一后：三种 MoonBit 口径对照（同机，单次均摊）

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

### 4. 重跑：统一口径对比表

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

### 5. 门禁与收尾（AGENTS §二.4）

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

### 6. 汇总

1. **问题**：旧层②两侧宿主形态不同（fast_qr Node 进程内 / MoonBit `moonrun` 子进程），MoonBit 侧多计
   启动 **12–20%**，对比倍率被系统性放大。
2. **统一**：新增 `原 wasm/WASI Node 运行器`（Node 进程内托管 MoonBit WASI 产物，复刻 moonrun
   的 `externref` opaque 句柄 argv 协议）；`原 wasm/WASI 对比驱动脚本` 两侧同进程/同时钟/同循环形态计时。
3. **正确性**：Node 进程内 `--dump` 与 `moonrun` **字节级一致**；三矩阵对 fast_qr **逐位对齐零差异**
   （sha256 与 S9c 同值）。
4. **重测**：统一口径 fast_qr 快约 **2.7–5.6×**（B 纯边际 2.7–3.7×，A 严格同形 3.0–5.6×），
   量级结论与旧口径一致、但尺子干净；MoonBit 每模块成本仍约为 fast_qr 的 2.7–3.7 倍。
5. **护栏**：不改 lib/快照/`cmd/bench` 默认行为；109 全绿；`MOON_HOST=moonrun` 可回退旧口径。

**后续（可选）**：S9b 的 P1（择优主循环减趟/特化）落地后，用同一 `bash scripts/bench-layer2.sh`
复跑即可量化差距收窄；本记录 §4 表即为优化前后**同一把尺子**的基线。

---

### 7. 参考

- 方案：本文件「实现方案」部分；
  issue #50。
- 前序层②：[S9c 实现记录](./S9c-性能测试与fast_qr-wasm对比.md)、
  [S9c 详细分析](./S9c-性能测试与fast_qr-wasm对比.md)（N 扫描 / 固定开销拟合）。
- 本仓库实码：`原 wasm/WASI Node 运行器`、`原 wasm/WASI 对比驱动脚本`、`scripts/bench-layer2.sh`、
  `scripts/build-fast-qr-wasm.sh`、`scripts/setup-fast-qr-wasm-env.sh`、`cmd/bench/main.mbt`（未改）。
- 参考 fast_qr v0.14.0（`53e8c99`）：`src/wasm.rs`（`qr_with` patch）、`benches/qr.rs`。
- `moonrun`（`~/.moon/bin/moonrun`）内嵌宿主 shim；MoonBit `--target wasm` 产物导入/导出面（实测解析）。
- 环境：moon 0.1.20260904、node v24.20.0、rust 1.98.1 + wasm32-unknown-unknown、wasm-bindgen 0.2.100、
  gcc 12.2.0（wasm-bindgen 宿主宏所需，apt）、`moonrun`（~/.moon/bin）。

---
