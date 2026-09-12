# S9j · 层② 统一 Node 进程内对比（wasm-gc vs fast_qr）· 口径收敛

> ⚠️ **历史记录**：MoonBit `wasm`(WASI) 后端已按项目决策移除，本项目现仅支持 `wasm-gc`；本文涉及的 `wasm` 后端数字与口径仅作历史留存，不再作为对外口径。

> 本文把层②「MoonBit vs fast_qr-wasm32」的 MoonBit 侧从 `wasm`(WASI) 兼容后端**收敛为
> `wasm-gc`（`moon.mod` 的 `preferred_target`，本仓库实际分发形态）**，消除「MoonBit 是哪个后端」
> 与「比的是哪个产物」两处歧义；`wasm`(WASI) 侧数字退出性能/体积的对外对比，仅作历史记录保留
> （后续该后端已整体移除）。
> 日期：2026-09-11　｜　环境：`moon 0.1.20260904`、**Node `v22.23.1`**、Linux `5.4.241-tlinux4`
> 前置：**不改 lib / 公共 API / 快照 / 既有 `cmd` 默认行为 / fast_qr 参考实现**
>
> ⚠️ **2026-09-12 重测更新**：本文首测（Node v22，P0/P2/P2b 落地前）已被新一轮重测覆盖——
> 现环境为 **Node v24.21.0** 且含 P0/P2/P2b 优化，对外主口径更新为：
> **`fast/ours`(B) = 0.374 / 0.613 / 0.738×**（V03H/V10H/V40H，即本仓库慢 ≈2.7/1.6/1.4×）。
> 重测方法与原始值见 [S9o](./S9o-性能与体积数据重测-与README冗余清理.md)；下表为首测历史值保留对照。

---

## 0. 结论先行

**三基准点单次 build（同一次 run、同一 Node 进程、`R=3` 取最小；输入 `https://example.com/`=20B、
ECL H、强制 V03/V10/V40、mask 自动择优）：**

> 首测（2026-09-11，Node v22.23.1，优化前）：

| 点 | 模块数 | 迭代 N | MoonBit(wasm-gc) 单次 B (ms) | fast_qr-wasm32 单次 (ms) | fast / ours (B) | 每模块成本 ours / fast (µs) |
|----|------:|------:|-----------------------------:|-------------------------:|----------------:|---------------------------:|
| V03H | 841 | 2000 | 0.198 | 0.059 | **0.297×**（慢 ≈3.4×） | 0.235 / 0.070 |
| V10H | 3249 | 400 | 0.729 | 0.323 | **0.442×**（慢 ≈2.3×） | 0.224 / 0.099 |
| V40H | 31329 | 40 | 5.329 | 3.021 | **0.567×**（慢 ≈1.8×） | 0.170 / 0.096 |

> 重测（2026-09-12，Node v24.21.0，含 P0/P2/P2b）：

| 点 | 模块数 | 迭代 N | MoonBit(wasm-gc) 单次 B (ms) | fast_qr-wasm32 单次 (ms) | fast / ours (B) | 每模块成本 ours / fast (µs) |
|----|------:|------:|-----------------------------:|-------------------------:|----------------:|---------------------------:|
| V03H | 841 | 2000 | 0.227 | 0.085 | **0.374×**（慢 ≈2.7×） | 0.270 / 0.101 |
| V10H | 3249 | 400 | 0.652 | 0.399 | **0.613×**（慢 ≈1.6×） | 0.201 / 0.123 |
| V40H | 31329 | 40 | 4.808 | 3.547 | **0.738×**（慢 ≈1.4×） | 0.153 / 0.113 |

- A 口径（逐次新建 Instance，含宿主固定项）：fast/ours = 0.217 / 0.406 / 0.563×；
- B 口径（单实例摊薄 = 纯 build 边际）为**对外引用主口径**，即上表；
- 复跑稳定性：B 比值两次连跑为 0.297–0.305 / 0.442–0.447 / 0.567–0.581（±≈3%）。

**一句话**：**在同一 Node 进程内，fast_qr-wasm32 比 MoonBit `wasm-gc`（默认后端）快约 1.8–3.4×；
差距随版本增大而收窄（V03H 3.4× → V40H 1.8×），集中在 8 轮掩码择优主循环。**

> ⚠️ **环境绑定（S9h）**：本表绝对值绑定 **Node v22.23.1** 宿主，**不可与 [S9e](./S9e-性能测试统一Node调用.md)
> 的 Node v24.20.0 数字直接相减/相除**（v24 使 MoonBit 侧快 18–41%）。跨环境只比「同一次 run 内的成对比值」。

---

## 1. 为什么要收敛到 wasm-gc

### 1.1 分发形态与对比形态不一致

| 维度 | 声明 | S9e 对比所用 |
|------|------|--------------|
| `moon.mod` | `preferred_target = "wasm-gc"`（唯一后端） | — |
| README / AGENTS | 「主推 `wasm-gc`」 | — |
| 层② 性能对比（S9e） | — | **`wasm`(WASI)** |
| 体积对比（S9f/S9g） | — | 双后端并列（含 `wasm`） |

读者看到「本项目比 fast_qr 慢 2.7–3.7×」时，无法判断测的是哪个后端；而对外承诺的分发形态是
`wasm-gc`。**对比形态必须与分发形态一致**，否则数字再准也是歧义。

### 1.2 MoonBit `wasm` 侧退出对外对比

- 性能：层② 对外只报 `wasm-gc` vs fast_qr（本文）；`wasm`(WASI) 数据保留在 S9e 作历史记录；
- 体积：对外只报 `wasm-gc` vs fast_qr（S9i 补充命令形态/纯库调用两档）；`wasm` 数据保留在 S9g。
- **`wasm-gc` vs `wasm` 的跨后端自比**仍可用于「默认后端选型依据」，但须标注为自比、不与 fast_qr 对比混列。

---

## 2. 技术障碍与解法（此前为何没做）

S9e 之所以用 `wasm` 产物，是因为 Node 端当时无法加载 `wasm-gc`：

| 障碍 | 现状（2026-09-11 实测） |
|------|--------------------------|
| WasmGC 提案支持 | **Node v24/V8 已可 `new WebAssembly.Module` 编译 wasm-gc 产物** |
| `spectest.print_char` 宿主面 | 一行 shim（收集字符即可观测 stdout） |
| `__moonbit_fs_unstable`（argv 读取） | 按协议实现最小 shim（见 §3） |

### 2.1 argv shim 协议（照 core 实现，非猜测）

来源：`moonbitlang/core` → `lib/core/env/env_wasm.mbt`（`#external` 绑定）：

```text
args_get()                     -> XExternStringArray   # 不透明句柄，guest 只透传
begin_read_string_array(sa)    -> handle
string_array_read_string(h)    -> XExternString        # 数组以哨兵 "ffi_end_of_/string_array" 结束
begin_read_string(e)           -> handle
string_read_char(h)            -> Int                  # 码点；-1 = 结束
finish_read_string(h) / finish_read_string_array(h)
```

`scripts/gc-compare.mjs` 用「宿主侧自增整数 + Map」承载句柄（不触碰 guest 线性内存），
.argv 传入 `['bench', <点>, <N>, "ffi_end_of_/string_array"]` 即可分点驱动 `cmd/bench`。

---

## 3. 方法与护栏（与 S9e 同形）

**计时口径**（两侧同一 Node 进程、同一 `performance.now()`、同一 N 次循环、R 次取最小）：

- **A** 逐次调用：每次迭代新建 Instance 后 `cmd/bench <点> 1`（`_start` 每次只跑一次），
  含 Node 托管 Instance 创建的固定项，是与 fast_qr「一次调用」同形的保守口径；
- **B** 单实例摊薄：一个 Instance 内一次 `_start` 跑 `cmd/bench <点> N`，剔除 Instance 固定项，
  即纯 build 边际成本。

**三组护栏（缺一即 exit 1，本次全部通过）**：

| 护栏 | 内容 | 结果 |
|------|------|------|
| 逐位对齐 | `--dump <点>` 文本 vs fast_qr `qr_with` 规范矩阵，逐字符 + sha256 | 三点一致（sha256 相同） |
| 跨宿主一致 | Node shim 输出 vs `moonrun <wasm-gc bench>` 输出逐字节 | 三点一致 |
| 双后端互证 | `wasm-gc` checksum vs `wasm` 后端 checksum（跨后端同源码） | 三点一致 |

> 逐位对齐 sha256：V03H `4942f6aa…`、V10H `91c85c94…`、V40H `c3c04930…`。

---

## 4. 实测记录（2026-09-11，Node v22.23.1）

复跑命令：

```bash
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
bash scripts/bench-layer2.sh --no-build        # wasm-gc vs fast_qr
R=5 bash scripts/bench-layer2.sh --no-build    # 更多轮次取最小
```

> `wasm`(WASI) 历史回退（`MOON_TARGET=wasm`）已随后端与 `wasm-compare.mjs` 一同移除。

两次连跑（R=3）原始值：

| 点 | ours B run1 | ours B run2 | fast run1 | fast run2 | fast/ours B run1 | run2 |
|----|------------:|------------:|----------:|----------:|-----------------:|-----:|
| V03H | 0.1934 | 0.1982 | 0.0591 | 0.0588 | 0.305× | 0.297× |
| V10H | 0.7225 | 0.7289 | 0.3231 | 0.3225 | 0.447× | 0.442× |
| V40H | 5.2694 | 5.3292 | 3.0592 | 3.0206 | 0.581× | 0.567× |

**与 S9e 的关系（不做跨版本比较）**：S9e 在 Node v24.20.0 下测得 wasm(WASI) 侧
fast/ours(B) = 0.269 / 0.319 / 0.368。两套数字**后端不同、Node 大版本不同**，
按 S9h 规范不得直接对撞；S9e 保留为「wasm/WASI 后端」历史记录，其结论（差距集中在择优主循环、
方向性成立）不变。

---

## 5. 对文档与呈现的影响

| 位置 | 动作 |
|------|------|
| `scripts/bench-layer2.sh` | 默认通道为 wasm-gc（调 `gc-compare.mjs`）；`wasm`(WASI) 回退通道已随后端移除 |
| `scripts/gc-compare.mjs` | **新增**：wasm-gc vs fast_qr 同进程对比 + 三组护栏 |
| README「性能速览」 | 明细表换成 wasm-gc vs fast_qr；移除 `wasm` 侧数字（含原 ① 跨后端自比行） |
| README「编译为 Wasm」 | 体积对照表移除 MoonBit `wasm` 列，只留 `wasm-gc` vs fast_qr |
| [S9e](./S9e-性能测试统一Node调用.md) | 加修订注记：wasm/WASI 口径，对外引用改见本文 |
| [S9g](./S9g-本项目wasm产物体积-确认与修正.md) / [S9i](./S9i-纯库调用体积探针与库实际体积.md) | 加注：对外引用统一 `wasm-gc`（S9i 已是 gc 主口径） |
| [性能测试脚本-公开评审说明](./性能测试脚本-公开评审说明.md) | 层② 口径更新为 wasm-gc 默认 + 本文链接 |

---

## 6. 参考

- 历史口径（wasm/WASI）：[S9e 性能统一 Node 调用](./S9e-性能测试统一Node调用.md) · [S9c](./S9c-性能测试与fast_qr-wasm对比.md)
- 环境归因（为何不可跨 Node 版本比）：[S9h 层②性能复测异常归因](./S9h-层②性能复测异常归因-Node版本与宿主漂移.md)
- 体积口径（同为 wasm-gc 主口径）：[S9i 纯库调用体积探针](./S9i-纯库调用体积探针与库实际体积.md)
- 本仓库实码：`scripts/gc-compare.mjs`、`scripts/bench-layer2.sh`、`cmd/bench`（未改）
- 协议依据：`moonbitlang/core` 的 `lib/core/env/env_wasm.mbt`
