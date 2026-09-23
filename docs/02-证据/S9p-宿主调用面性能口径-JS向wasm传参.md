# S9p · 宿主调用面性能口径（JS 向 wasm 传参）

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README.md](../README.md) §2

> 承接：ISSUE #50「性能测试代码仍然不够规范：模拟正常调用 js 向 wasm 传参场景，而非单独 bench
> 程序运行 —— 思考 && 评估合理性 && 如何优化，详细分析」。
> 日期：2026-09-14　｜　环境：`moon 0.1.20260904`、**Node v24.21.0**、Linux（8 vCPU）
> 前置：**不改 lib / 公共 API / 快照 / 既有 `cmd` 默认行为 / 既有层①② 口径**；
> 新增 `cmd/host-probe`（探针包）+ 2 个脚本 + 本文。

---

## 0. 结论先行

1. **用户指出的问题是成立的。** 既有层②（`scripts/gc-compare.mjs`）的 MoonBit 侧产物是
   `cmd/bench`（**命令形态**：导出面只有 `_start`，输入经 `__moonbit_fs_unstable` 协议走 argv）。
   由此只能得到两种口径，**都不是**「宿主反复调 wasm」：
   - **A**（逐次新建 Instance 再 `_start`）：把「模块实例化」成本算进**每一次调用**；
   - **B**（一次 `_start` 跑 N 次）：宿主**无法在两次调用之间改参数**，测的是 wasm 内部紧循环。
2. **根因是导出面，不是脚本写法。** `cmd/bench` 的 wasm 导出面实测只有
   `function:_start`（`imports: __moonbit_fs_unstable.* + spectest.print_char`）——
   宿主**没有**任何可以「带参数反复调用」的函数入口。`gc-compare.mjs` 已经把能做的都做了。
3. **wasm-gc 下「JS 传字符串给 wasm」是可行的，但要两个开关一起用**（本文 §2，实测踩坑）：
   `pkgtype(kind:"foreign_library")` + `link.exports` + `use-js-builtin-string: true` +
   `imported-string-constants: "_"`；宿主侧 `WebAssembly.compile(src, {builtins:["js-string"]})`
   并为 `_` 命名空间提供 `{ <name>: <name> }`。**缺任何一项都会在运行期 `illegal cast`**。
4. **新口径已落地并跑出数字**（`cmd/host-probe` + `scripts/bench-host.sh`），
   三组护栏全绿，其中 **ALIGN-CLI** 证明「宿主传参面」与「CLI 面」是**同一计算**
   （同点 checksum 逐点相同），不是各测各的。
5. **新口径数字与旧 B 口径高度吻合**（V40H 4.66 vs 4.81 ms）——
   即 **B 口径作为代理是合理的**，但现在它是**被真正测量**出来的，而不是推断的。

| 点 | 宿主传参（新，主口径）ms | 旧 A（新建 Instance）ms | 旧 B（单实例摊薄）ms | fast_qr ms | fast/ours（新） | fast/ours（旧 A） | fast/ours（旧 B） |
|----|-------------------------:|------------------------:|---------------------:|-----------:|----------------:|------------------:|------------------:|
| V03H | **0.2125** | 0.3189 | 0.2471 | 0.0840 | **0.407×** | 0.263× | 0.340× |
| V10H | **0.6426** | 0.7596 | 0.6987 | 0.4007 | **0.620×** | 0.528× | 0.574× |
| V40H | **4.6593** | 4.8878 | 4.8255 | 3.5560 | **0.756×** | 0.728× | 0.737× |

> **旧 A 会系统性夸大差距**（V03H 0.263× vs 真值 0.407×，差 55%）；旧 B 也偏保守 7–16%。
> 方向性结论不变：**本仓库慢 ≈1.3–2.5×（2026-09-12 原口径），差距随版本增大而收窄**。
>
> 🟢 **2026-09-23 介质换代后（`Array[Int]`→`FixedArray[Int]`）**：同 run 比值收窄到 **≈1.0–2.2×**
> （V40H 已逼近 1.0×），见 [S9s §10](S9s-数组介质与字节加速-真实A-B实测.md)。本表为 **2026-09-12 快照**，
> 未随换代重写（绝对 ms 跨会话不可比）。

---

## 1. 问题确认：为什么旧口径「不够规范」

### 1.1 实测 `cmd/bench` 的宿主面

```text
exports: function:_start
imports: __moonbit_fs_unstable.{args_get, begin_read_string_array, string_array_read_string,
                              begin_read_string, string_read_char, finish_read_string,
                              finish_read_string_array}
         spectest.print_char
```

宿主能做的只有：**新建 Instance → 调 `_start` → 读 stdout**。参数只能经 argv 协议在
**实例创建时**注入。于是「参数化调用」被迫退化成 A/B 两种代理口径：

| 口径 | 做法 | 把什么算进了「一次调用」 | 失真方向 |
|------|------|--------------------------|----------|
| A 逐次新建 Instance | 每次 `new Instance` + `_start` | 模块实例化 + 运行时初始化 | **偏慢**（与 fast_qr「一次调用」不同形） |
| B 单实例摊薄 | 一次 `_start` 跑 N 次 | 无 | **偏快**（宿主传参/调度成本被抹平） |

S9j 已诚实标注 A/B 并列、B 为「对外引用主口径」，并在 S9o 标注「两套口径不可对撞」——
这已是当前产物形态下的最优解。**但缺的正是「宿主真实调用」这一档**。

### 1.2 「真实宿主调用」长什么样

宿主嵌入一个 wasm 库的典型形态是：

```js
const mod  = await WebAssembly.compile(bytes);     // 一次
const inst = await WebAssembly.instantiate(mod, imports); // 一次
for (const content of inputs) {                    // 多次
  const n = inst.exports.qr_generate(content, ver); // 每次真实带参调用
}
```

关键点：**一次实例化 + 反复带参调用**。fast_qr 的 `qr_with(content, ecl, version)` 正是这个形态；
MoonBit 侧此前**没有任何对称入口**——这是口径缺口的本质。

---

## 2. 技术路径：wasm-gc 如何「真的」把字符串传给 JS

### 2.1 为什么默认不行

MoonBit wasm-gc 的 `String` 默认编译为**内部 GC 引用**。实测导出函数类型段：

```text
(type (func (param (ref null 0) i32) (result i32)))   ;; (ref null 0) = 内部结构引用
```

JS 无法构造这种引用 → 传任何 JS 值都报
`TypeError: type incompatibility when transforming from/to JS`。
同理 `Bytes` / `Array[Byte]` 也不可直接传（实测确认）。

### 2.2 可行路径：`use-js-builtin-string`（JS String Builtins 提案）

在 `moon.pkg` 中：

```toml
pkgtype(kind: "foreign_library")          # ① 外部库形态：导出面可自定义

options(
  link: {
    "wasm-gc": {
      "exports": [ "qr_generate", "qr_checksum" ],  # ② 显式导出名
      "use-js-builtin-string": true,                # ③ String ≡ stringref
      "imported-string-constants": "_",             # ④ 字符串常量的导入命名空间
    },
  },
)
```

宿主侧：

```js
const mod  = await WebAssembly.compile(src, { builtins: ["js-string"] }); // ⑤ 开 builtins
const inst = await WebAssembly.instantiate(mod, {
  spectest: { print_char: () => {} },
  _: { "https://example.com/": "https://example.com/", ... },              // ⑥ 常量表
});
inst.exports.qr_generate("https://example.com/", 0);   // 直接传 JS 字符串 ✅
```

### 2.3 踩坑记录（缺一即 `illegal cast`，均已实测确认）

| # | 缺失项 | 现象 |
|:-:|--------|------|
| ① | 仍是 `pkgtype(kind:"executable")` | 导出面只有 `_start`，参数仍只能走 argv |
| ③ | 无 `use-js-builtin-string` | 参数类型是内部 GC 引用，JS 无法构造 |
| ④/⑥ | 无 `imported-string-constants` / 未提供 `_` 表 | **模块内字符串常量**在运行期 `illegal cast`（`String::length` 即崩） |
| ⑤ | 宿主未开 `builtins:["js-string"]` | `wasm:js-string.*` 导入无法满足，实例化失败 |

> ④/⑥ 是最隐蔽的一条：`use-js-builtin-string` 会把模块里的**字符串字面量**编译成
> `_` 命名空间下的**导入**（导入名 = 字符串内容本身）。实测 `_` 下出现
> `https://example.com/`、`0123456789abcdefghijklmnopqrstuvwxyz`、
> `bounds check failed: allocate_len = ` 等 10 条，宿主必须逐条给值。
> 另注：`foreign_library` 包**不能含 `fn main`**（报 `Unexpected main function in the non-main package`）。

### 2.4 边界与代价（诚实标注）

- 需要宿主支持 **JS String Builtins**（Node ≥ 22 / V8；实测 v24.21.0 可用）；
  这**收窄**了宿主面（原本只需 `spectest.print_char`）；
- `imported-string-constants` 会把库内的字符串常量暴露为导入项，宿主需按名喂值——
  对「库被第三方宿主嵌入」而言是**额外的接入负担**，属 wasm-gc 生态现状，非本仓库可改；
- 因此本口径**不取代** `cmd/bench`（CLI 面）与 `cmd/qr-min`（体积面），
  而是与它们**并列**：命令面回答「命令行怎么跑」，宿主面回答「被宿主嵌入怎么跑」。

---

## 3. 落地物

| 文件 | 角色 |
|------|------|
| `cmd/host-probe/`（新） | `foreign_library` 宿主调用面探针：导出 `qr_generate(content:String, version:Int) -> Int` 与 A/B 对照 `qr_checksum(version:Int) -> Int` |
| `scripts/host-bench.mjs`（新） | 基准驱动：单 Node 进程、单 Instance、反复带参调用；三组护栏；可选 fast_qr 对撞 |
| `scripts/bench-host.sh`（新） | 入口包装：构建 `cmd/host-probe` + `cmd/bench`，可选准备 fast_qr 参考侧 |

### 3.1 为什么 checksum 公式与 `cmd/bench` **完全一致**

`cmd/host-probe::host_checksum` 逐项复刻 `cmd/bench::bench_point_checksum` 的单次项
（`size + get(0,0) + get(sz-1,sz-1) + get(sz/2,sz/2) + mask + mode + ecl + version`）。
这样两个口径在同参数下必须给出**相同数字**——ALIGN-CLI 护栏即由此成立：

```text
qr_generate("https://example.com/", 0/1/2) = 41 / 81 / 230
moonrun cmd/bench.wasm V03/V10/V40 1       = 41 / 81 / 230   ✅ 逐点相同
```

### 3.2 为什么 `qr_checksum` 是必要的（而非冗余）

它把「宿主传字符串参数」的成本**单独分账**：`qr_generate − qr_checksum` 即传参边际成本。
实测该项在 **−0.005 ~ +0.035 ms/次**（V40H 最大、V03H 为负即噪声量级）——
**结论：宿主传参成本可忽略**（`stringref` 是零拷贝引用）。
这条结论必须可测，否则「新口径比 B 慢」会被误归因为传参开销。

---

## 4. 实测数据（2026-09-14，Node v24.21.0）

复跑：

```bash
export PATH="$HOME/.moon/bin:$HOME/.cargo/bin:$PATH"
bash scripts/bench-host.sh                 # 全流程（含 fast_qr 参考侧）
bash scripts/bench-host.sh --no-build      # 产物就绪时只测
NO_FAST=1 bash scripts/bench-host.sh --no-build   # 只测 MoonBit 宿主面
```

| 点 | N | 宿主传参 `qr_generate` (ms/次) | 同实例 `qr_checksum` (ms/次) | 传参成本 | fast_qr `qr_with` (ms/次) | fast/ours |
|----|---:|-------------------------------:|------------------------------:|---------:|--------------------------:|----------:|
| V03H | 2000 | 0.2125 | 0.2130 | −0.0005 | 0.0865 | **0.407×** |
| V10H | 400 | 0.6426 | 0.6316 | +0.0110 | 0.3987 | **0.620×** |
| V40H | 40 | 4.6593 | 4.6387 | +0.0205 | 3.5228 | **0.756×** |

**复跑稳定性**：两次连跑 `fast/ours` = 0.414/0.608/0.757 与 0.407/0.620/0.756（±≈2%）。

### 4.1 三口径对照（同一次会话实测，Node v24.21.0）

同一台机器、紧邻两次 run；A/B 由 `scripts/bench-layer2.sh`（`gc-compare.mjs`）产出：

| 点 | 宿主面（S9p，**新增**）ms | 旧 A（逐次新建 Instance）ms | 旧 B（单实例摊薄）ms | fast_qr ms |
|----|--------------------------:|----------------------------:|---------------------:|-----------:|
| V03H | **0.2125** | 0.3189 | 0.2471 | 0.0840 |
| V10H | **0.6426** | 0.7596 | 0.6987 | 0.4007 |
| V40H | **4.6593** | 4.8878 | 4.8255 | 3.5560 |

**读数**：宿主面在三种口径里**最小**，且明显低于 A、略低于 B。
- **A 偏慢 3–50%**：确实把每次 `Instance` 创建 + 运行时初始化算进了「一次调用」
  （V03H 最夸张，因为 841 格的 build 只占 0.21 ms，固定项占比极高）；
- **B 偏慢 1–16%**：B 的「内容」在 wasm 侧是**常量字符串**、且迭代数要经
  `__moonbit_fs_unstable` argv 协议解析后驱动一次 `_start`；S9p 的 `qr_checksum`
  A/B 对照（传参成本 ≈0）说明差额不在「传参」，而在 argv 协议 + 内部循环的调度形态。
- 结论：**宿主面（S9p）是目前最贴近真实集成、且最快的口径**；
  A/B 仍保留其用途（A 与 fast_qr「一次调用」同形、B 剔除 Instance 固定项）。

> ⚠️ 上表同时说明**为什么不能拿旧口径当主口径**：A 会把「本仓库比 fast_qr 慢」
> 系统性夸大（V03H: 0.263× vs 0.407×，差 55%），这直接污染对外结论。

### 4.2 与既有结论的关系

方向性结论**不变**：本仓库慢 ≈1.3–2.5×（原口径）、差距随版本增大而收窄、瓶颈在 8 轮掩码择优主循环
（[S9k](S9k-性能瓶颈与理论上限评估.md)）。**新口径只是把「B 代理」换成「真测」。**
（2026-09-23 介质换代后量级收窄至 **≈1.0–2.2×**，见 §0 注与 [S9s §10](S9s-数组介质与字节加速-真实A-B实测.md)。）

---

## 5. 护栏

| 护栏 | 内容 | 结果 |
|------|------|------|
| **ALIGN-CLI** | `qr_generate` vs `cmd/bench <点> 1` 的 checksum 逐点相同 | ✅ 41/81/230 |
| **ALIGN-BATCH** | 同一实例上 N 次调用的结果恒等于 1 次（内容与迭代数无关） | ✅ |
| **SPEC** | `_` 命名空间字符串常量导入可正确读取（否则 `illegal cast`） | ✅ 10 条 |
| 非恒定校验 | 换输入（`http://a.io`）结果改变（证明测的是真实计算） | ✅ 41 → 42 |

任一护栏失败 → 脚本 `exit 1`，**不输出数字**（与 `bench-size.sh` 探针自检同一纪律）。

---

## 6. 与其它脚本的定位关系（避免口径混淆）

| 脚本 | MoonBit 产物形态 | 回答的问题 | 角色 |
|------|------------------|------------|------|
| `scripts/bench-host.sh`（**新**） | `cmd/host-probe` 宿主调用面 | 宿主反复调 wasm 有多快 | **宿主集成口径（新增主口径）** |
| `scripts/bench-layer2.sh` | `cmd/bench` 命令形态 | 同进程 A/B 与跨宿主一致性 | 保留（A/B 对照 + 跨宿主护栏） |
| `scripts/bench.sh` | `cmd/bench` 命令形态 | 后端整程 wall time | 保留（层①） |
| `scripts/bench-size.sh` | `cmd/{bench,main,qr-min}` | 产物多大 | 保留（体积） |
| `cmd/qr-min` | 纯库调用执行包 | 库实际体积下限 | 保留（体积主口径） |

> **不可对撞**：S9p 宿主面（V40H 4.66 ms）与 S9k `cmd/bench` 边际（4.42 ms）、旧 B（4.81 ms）
> 是**不同 harness**下的数字，只可看比值与趋势，不可直接加减。

---

## 7. 明确不做 / 边界

- **不改 `cmd/bench` 默认行为**：它仍是 CLI 面与 A/B 口径的载体（导出面由 executable 形态决定）；
- **不改 lib / 公共 API / 快照**：`cmd/host-probe` 是独立包，lib `.mbti` 零漂移；
- **不把宿主面写进 push CI**：`use-js-builtin-string` + `imported-string-constants` 依赖
  Node ≥ 22 的 `js-string` builtins 与参考侧 fast_qr 产物；与 `bench-*.sh` 同属
  「本地/审计用」，不进 `.cnb.yml`（与 S9o §1.1 的既有约定一致）；
- **不做 native 对比**（仍受 C 工具链约束）；
- **不宣称这是「宿主接入面全部形态」**：真实宿主还可能用 Component Model（WIT）等；
  本文只覆盖「wasm 模块 + JS 直调」这一档，且已标注其宿主面代价（§2.4）。

---

## 8. 参考

- 问题来源：ISSUE #50（性能测试口径）；历史口径：[S9j](S9j-层②统一Node对比-wasm-gc与fast_qr.md) · [S9e](S9e-性能测试统一Node调用.md)
- 数据重测与归因：[S9o](S9o-性能与体积数据重测-与README冗余清理.md) · [S9h](S9h-层②性能复测异常归因-Node版本与宿主漂移.md)
- 瓶颈与理论上限：[S9k](S9k-性能瓶颈与理论上限评估.md)
- 脚本审阅入口：[性能测试脚本-公开评审说明](性能测试脚本-公开评审说明.md)
- MoonBit 官方依据：`package.html` §Wasm GC 后端链接选项（`use-js-builtin-string` / `imported-string-constants`）；
  `ffi.html` §导出函数（`#export_name` 与 `exports`）
- 本仓库实码：`cmd/host-probe/{moon.pkg,main.mbt}`、`scripts/{host-bench.mjs,bench-host.sh}`、`cmd/bench`
