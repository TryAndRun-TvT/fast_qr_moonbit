# S9s · 数组介质与「字节加速」实测（真实代码 A/B）

> **状态**：现行　｜　日期：2026-09-24　｜　索引：[docs/README.md](../README.md) §2
> 承接 [S9n](S9n-优化方案复评与wasm-gc收敛审计.md) **§2.1-H4 / §6.4-⑵**（「P3 介质窄化必须先做
> `Array[Int]`/`FixedArray[Byte]`/`Bytes` 三向微基准」）与 [S9m](S9m-ReadOnlyArray适用性评估.md)（表容器）·
> [S9k](S9k-性能瓶颈与理论上限评估.md)（各段成本占比，用于封顶外推）
> 一句话结论：**本仓库未启用任何「byte 加速」**；实测表明**字节窄化本身几乎不加速**（≈1.16×，
> 与不窄化的 `FixedArray[Int]` ≈1.19× 基本等同），**真正的杠杆是去掉 `Array` 的 `{buf,len}` 二层间接**
> （矩阵扫描 **≈1.19×**、RS 工作区 **≈1.50×，真实代码 A/B 验证**）；按占比封顶，矩阵介质约 **≈10–13%**、
> RS 仅 **≈0.8%** 整 build 量级。
> **§10（追加）把矩阵介质换代真落两版并交错实测**：V40 宿主面 **−15%**、体积 **−5~6%**、
> **语义零差异（147/147 + checksum）**，公共 API 不变；**其中 `FixedArray[Int]` 已落地 `main`（提交 `ea7d7ae`）**。

> 方法：① 性能关键路径容器盘点（只读源码）；② **代表性微基准**（把 `score.mbt::line_scan_buf` 与
> `reedsolomon.mbt::division` 的内层循环**逐字内联**到探针，四容器对照）；
> ③ **真实代码 A/B**（临时把 `reedsolomon.division` 的工作区换成 `FixedArray[Byte]`，测**真实函数**后还原）。
> 日期：2026-09-23　｜　环境：`moon 0.1.20260920`、**仅 `wasm-gc` release**（`moonrun` 边际斜率，N vs N/2，R=5 取 min，交错）。
> 范围：**只测不落**——探针在 `/tmp`，真实 A/B 的临时改动**测毕 `git checkout` 还原**（`lib/` 零残留）。

---

## 1. 议题定义

| # | 问题 |
|:-:|------|
| Q1 | 性能关键路径上，各处的**数组容器选择**是什么？是否已启用 byte 优化？ |
| Q2 | 把热介质**窄化为字节**（`Bytes` / `FixedArray[Byte]`）能不能提速？提多少？ |
| Q3 | 若提速，按各段**占比**外推到整 build 还有多少？（S9n §3 要求「不得重复计数」） |
| Q4 | RS 工作区该做的是**复用**（S9m T-R5）还是**换容器**？ |

**明确不做**：不改 `lib/` 入库代码（本文只出结论，落地另行立项）；不动公共 API（`QRCode.data` 仍 `Array[Module]`）；
不把「`wasm-gc` 的静态初始化/启动」当收益（S9m §1.2 已否）。

---

## 2. 现状盘点：性能关键路径的容器选择

| 位置 | 容器（实码） | 读/写 | 段占比（S9k，V40） | byte 优化 |
|------|-------------|-------|-------------------|:---------:|
| 工作矩阵 `internal/matrix/matrix.mbt`、`score.mbt`、`placement.mbt`、`datamasking.mbt` | **`Array[Int]`**（D3 介质：`明暗\|类型<<1`） | **就地读改写** | `score` **68%** + `apply_mask` **11%** | ❌ 未用 |
| RS 表 `reedsolomon.mbt:17,280` | `ReadOnlyArray[Byte]` | 纯读 | `pipe` 的大头 | ✅ 已用（S9m T-R1） |
| RS 工作区 `reedsolomon.mbt::division` | **`Array[Byte]`**（每次 `Array::make(255)`） | 就地写 | `pipe`(encode+RS) ≈**2.5%** | ❌ 未用 |
| RS 结果 `structure` / `slice` | `Array[Byte]`（5430 / 逐块） | 写 | 同上 | ❌ 未用 |
| 位流 `bitbuffer.mbt::CompactQR.data` | `Array[Byte]`（按需 `push`） | 追加写 | `pipe` 极小 | ❌ 未用 |
| 结果容器 `lib/qr.mbt` `QRCode.data` | `Array[Module]`（**公共**） | 构建期写 | V03 **44%**（装箱税） | ❌（S9n 已否决 T-R3） |
| 查找表 `bitbuffer.keep_last` | `ReadOnlyArray[Int]` | 纯读 | 微 | ✅ 已用 |

**Q1 答**：**没有启用任何 byte 加速**——全仓 `lib`/`cmd` **零** `Bytes`、**零** `FixedArray`（仅 `ReadOnlyArray` 用于只读表）。
`Bytes`/`FixedArray[Byte]`/`ArrayView` 系（core 的 `bytes.mbt` / `bytes_unsafe.mbt` / `view`）均未使用。

> **`Bytes` 的硬约束（core 源码）**：`bytes.mbt` 只提供 `make`/`from_array`/`to_array`/`unsafe_get` 与
> `bytes_unsafe.mbt` 的 `%bytes.unsafe_read/write_uint{16,32,64}_*`，**无公开 `Bytes::set`**。
> ⇒ `Bytes` **不能**作矩阵/RS 工作区这类**需要就地写**的介质（只能作只读视图/结果载体）。
> 另：`bytes_unsafe.mbt` 的多字节 intrinsic 在 **native 是 intrinsic 降低、在 wasm-gc 是真实实现**
> （其 `*_unroll_wbtest.mbt` 明说），但本库热路径是**位级/逐字节 GF 运算**，形态不匹配，暂不适用。

---

## 3. 方法

### 3.1 代表性微基准（Q2 的容器轴）

把真实热循环**逐字内联**到独立探针（`/tmp`，不入库），避免「回调/只读视图」等代理失真（S9m §3.4-F1 的教训）：

- **矩阵扫描**：内联 `score.mbt::line_scan_buf`（N1 运行 + N3 窗口 + 暗格计数），`size=177`（V40）；
  1 op = 逐行扫完整矩阵；四容器：`Array[Int]`（现行）/ `FixedArray[Int]` / `FixedArray[Byte]` / `Bytes`。
- **RS 取余**：内联 `reedsolomon.mbt::division` 的取余循环；`15B` 数据 + 32 项生成式（真实 V40H 块长）；
  四态：`Array[Byte]` 工作区（每次分配 / 复用）× `FixedArray[Byte]` 工作区（每次分配 / 复用）。
- 计时：`moonrun` 整程 wall time，N 与 N/2 **边际斜率**，R=5 取 min，**交错 ABAB** 降热漂移；
  语义护栏：同类各变体 **checksum 必须一致**。

### 3.2 真实代码 A/B（Q4 的 RS 工作区，替代代理）

微基准是「代表性内联」，不是整函数。为免重蹈 S9m F1（代理不可迁移），对 RS 工作区另做**真实函数 A/B**：
临时把 `reedsolomon.mbt::division` 的 `let buf = Array::make(255, …)` 换成 `FixedArray::make(255, …)`，
用临时探针 `lib/probe` 调**真实 `@reedsolomon.division`**（生成式仍取真实 `get_polynomial(39,3)`，
表仍是 `ReadOnlyArray[Byte]`），测毕删探针 + `git checkout` 还原。

---

## 4. 结果（wasm-gc，moonrun 边际斜率）

### 4.1 矩阵扫描（size=177，V40 的 `score` 热循环）

| 容器 | ns / cell | 相对 `Array[Int]` |
|------|----------:|------------------:|
| **`Array[Int]`（现行）** | **5.184** | 1.00× |
| `FixedArray[Int]` | 4.354 | **1.19×** |
| `FixedArray[Byte]` | 4.469 | 1.16× |
| `Bytes` | 4.481 | 1.16× |

> **关键读数**：`FixedArray[Int]`（不窄化）**≈ `FixedArray[Byte]`（窄化）**（4.354 vs 4.469，差 ≈2.6%）。
> ⇒ **速度收益来自「去 `Array` 间接」而非「窄到 byte」**；窄化几乎只买内存。

### 4.2 RS 取余（15B/32taps）

| 变体 | ns / division | 相对 `Array` 复用 |
|------|--------------:|------------------:|
| `Array[Byte]` 工作区 · 每次分配（≈现行） | 1790 | 1.08× |
| `Array[Byte]` 工作区 · 复用（S9m T-R5 原案） | 1650 | 1.00× |
| `FixedArray[Byte]` 工作区 · 每次分配 | 1175 | 1.40× |
| `FixedArray[Byte]` 工作区 · 复用 | **1070** | **1.54×** |

**真实代码 A/B（§3.2，必做）**：

| 工作区容器（真实 `division`） | ns / division | 相对 |
|------------------------------|--------------:|-----:|
| **`Array[Byte]`（现行）** | **1165** | 1.00× |
| `FixedArray[Byte]` | **775** | **1.50×** |

> 逐位护栏：两种工作区容器下 `division` 余数 checksum **相同（9075）**。
> **1.50× 在真实函数上复现** ⇒ 不是代理假象。

---

## 5. 分析

1. **「byte 加速」在速度上不成立**：窄化 = 1.16×，与不窄化 = 1.19× 基本等同（`to_int()`/`to_byte()` 转换抵消了
   窄读的收益）。它的价值在**内存**（V40 矩阵 177²×4B ≈ **125 KB** → 字节档 ≈ **31 KB**，×8 轮掩码副本即
   ~1 MB → ~250 KB）与**类型语义**——属**资源/语义**优化，不是速度项。
2. **真正的杠杆 = `Array` → `FixedArray`**：`Array[T]` 是 `{buf,len}` 两层（`arraycore_nonjs.mbt:16-19`），
   每次访问多一层间接 + 两处边界；`FixedArray` 一层。这与 S9m §1.3 的**布局**归因一致，
   且在**写密集**路径（RS 工作区）上放大到 **1.50×**（读密集的扫描只有 ≈1.19×）。
3. **按占比封顶外推（Q3，S9n §3 纪律：不叠加、不重复计数）**：
   - **矩阵介质**受益于 `score`(68%) + `apply_mask`(11%) 的扫描/读写 → 上界 ≈ `79% × (1 − 1/1.19)` ≈ **12.6%**；
     取保守 **≈10%**（`score` 另含 N2/N4 未逐一建模）。**这是量级估算，非整 build 直测**。
   - **RS**：`pipe` 2.5% → `2.5% × (1 − 1/1.50)` ≈ **0.83%**（≈**0.8%**）。受 `pipe` 硬封顶。
   - V03 侧介质收益更小（`wrap` 固定容器占 44%，与介质无关）。
4. **Q4 答**：RS 该做的是**换容器**（1.50×），其**收益/改动比远高于** S9m T-R5 只说的「复用」（1.08×）；
   两者可叠加但复用是次要项。

---

## 6. 结论与建议

| 项 | 结论 | 建议 |
|----|------|------|
| Q1 byte 加速 | **未启用**（零 `Bytes` / 零 `FixedArray`） | 见下三项 |
| **T-R5′ 升级** | RS 工作区 `Array[Byte]` → `FixedArray[Byte]`：**真实 A/B ≈1.50×**（仅 1 行改动） | **可做**（低风险、逐位不变、收益 ≈0.8% 整 build）——优先级高于「复用」 |
| **P3 介质窄化（重定义）** | 目标是**`FixedArray` 化**（≈1.19×），**不是** byte 窄化（≈1.16×，无速度收益） | **已落地 `main`**（`ea7d7ae`，选 `FixedArray[Int]`）：V40 宿主 **−15%**、体积 **−5~6%**；D3 与 8 个白盒测试已同步；`[Byte]` 版留作对照分支 |
| 内存/GC | 字节档把矩阵降 4×（125 KB→31 KB；×8 副本） | 与 P3 同批评估；GC 收益**本文未测**，须整 build 实测 |
| `Bytes` 作介质 | ❌ **无公开 setter**，不能就地写 | 只可作只读视图/结果载体 |
| core 多字节 intrinsic | 形态不匹配（本库是位级/逐字节 GF） | 不做 |
| 只读表 `ReadOnlyArray` | 已启用（S9m/S9n T-R1/T-R2） | 保持 |

**一句话给决策**：**别为「字节」去窄化**（收益≈0）；要提速就**去 `Array` 的间接**——
RS 工作区是一行就能拿的 **1.50×**（但整 build 仅 ≈0.8%）；矩阵介质**已真落两版实测**（§10）：
**V40 宿主 −15%、体积 −5~6%**，`FixedArray[Int]` 与 `FixedArray[Byte]` **速度持平**，
择一按内存/改动面取舍。

---

## 7. 局限（本文自身的漏洞）

| # | 局限 | 影响 |
|:-:|------|------|
| L1 | 矩阵扫描是**代表性内联**，非整函数/整 build A/B；`score` 的 N2/N4 与掩码 `copy` 未逐一建模 | 矩阵 ≈10% 为**量级估算** |
| L2 | RS 微基准的 exp/log 用运行时构造的 `Array[Int]` 表（非同真实 `ReadOnlyArray[Byte]`） | **故另做 §3.2 真实 A/B 兜底**；真实 A/B 结论以 §4.2 为准 |
| L3 | 计时分辨率 ≈1 ms（N 取大以压噪声）；单机、`moonrun` 宿主 | 比值可信、绝对值不跨机 |
| L4 | 内存/GC 收益**未测**（只测速度） | 字节档的真实价值待整 build 实测 |
| L5 | 矩阵介质换代是 D3 级改动，风险未评估（本文只给量级与前置条件） | 不构成落地承诺 |

---

## 8. 复现

```bash
# ① 代表性微基准（探针在 /tmp，不入库）
#    /tmp/arrbench/cmd/probe/main.mbt：scan_{arr|farr|fbyte|bytes}、rs_{a_alloc|a_reuse|f_alloc|f_reuse}
moon build cmd/probe --target wasm-gc --release
moonrun _build/wasm-gc/release/build/cmd/probe/probe.wasm scan_arr 5000 177   # 与各变体 checksum 须一致
# 计时：对 N 与 N/2 各跑 R=5 取整程最小，取边际斜率（本文用 date +%s%N）

# ② 真实代码 A/B（RS 工作区；测毕还原）
#    临时把 reedsolomon.mbt:547 `Array::make(255, …)` → `FixedArray::make(255, …)`，
#    以临时 lib/probe 调 @reedsolomon.division(gen=get_polynomial(39,3), data=15B) 测斜率；
#    测毕 rm -rf lib/probe && git checkout -- lib/internal/reedsolomon/reedsolomon.mbt
```

> 护栏：`division` 余数 checksum 变前后一致（**9075**）；探针与临时改动**均未入库**（测毕 `git status -- lib/` 干净）。

**③ 介质换代两版（§10，实验分支）**

```bash
git switch exp/fixedarray-int     # 或 exp/fixedarray-byte
moon test --target wasm-gc && moon run cmd/qr-min      # 语义护栏：147/147、QR_MIN_CHECKSUM=283
# 交错 3 轮对比（每轮三分支各一次）：
for r in 1 2 3; do for br in main exp/fixedarray-int exp/fixedarray-byte; do
  git switch -q "$br"
  for p in host-probe bench main qr-min; do moon build cmd/$p --target wasm-gc --release; done
  R=5 bash scripts/bench-host.sh --no-build | grep -E '^\| V[0-9]+H \| '
done; done
```

---

## 10. 实码分支实测（2026-09-23 追加）：介质换代真落两版

> 承接 §6-P3：把「去 `Array` 间接」从微基准推进到**真码两版**，各开一条实验分支。
> 三条线对照：`main`（现行 `Array[Int]`）→ 分支 **`exp/fixedarray-int`**（`FixedArray[Int]`）→
> 分支 **`exp/fixedarray-byte`**（`FixedArray[Byte]`）。
> 方法：**交错 3 轮**（每轮三分支各跑一次宿主面 R=5 + 层① R=5），取**中位数**；表内标 `int`/`byte`。
> 语义护栏：三分支均 `moon test --target wasm-gc` **147/147**，`TOTAL_CHECKSUM` 三点
> （V03H=41 / V10H=81 / V40H=230、`QR_MIN_CHECKSUM=283`、整程 9200）**逐点相同**。
> 改动面：`lib/internal/matrix/**`（介质）+ `lib/qr_build.mbt::wrap_packed` + 8 个白盒测试；
> **公共 API / `.mbti` 不变**（`QRCode.data` 仍 `Array[Module]`，`wrap_packed` 逐格包装不变）。

### 10.1 宿主调用面（R=5 中位数，ms/次；取 3 轮中位数）

| 点 | `main`（`Array[Int]`） | `exp/int` | `exp/byte` | int vs main | byte vs main |
|----|----------------------:|----------:|-----------:|------------:|-------------:|
| V03H | 0.2749 | 0.2076 | 0.2126 | **−24%** | **−23%** |
| V10H | 0.7144 | 0.5958 | 0.6353 | **−17%** | −11% |
| V40H | 5.3033 | 4.4885 | 4.4770 | **−15%** | **−16%** |

同轮 `fast/ours` 比值（越大越接近 fast_qr）：

| 点 | `main` | `exp/int` | `exp/byte` |
|----|-------:|----------:|-----------:|
| V03H | 0.325 | 0.381 | 0.382 |
| V10H | 0.642 | 0.716 | 0.661 |
| V40H | 0.713 | **0.907** | **0.851** |

### 10.2 层①（`bench.sh` R=5 min，s）

| 点 | `main` | `exp/int` | `exp/byte` |
|----|-------:|----------:|-----------:|
| V03H | 0.554 | 0.513 | **0.449** |
| V10H | 0.320 | 0.282 | **0.273** |
| V40H | 0.255 | 0.240 | **0.218** |

### 10.3 体积（`-Oz` 可加载档，B）

| 产物 | `main` | `exp/int` | `exp/byte` | int Δ | byte Δ |
|------|-------:|----------:|-----------:|------:|-------:|
| `cmd/qr-min`（库实际） | 31629 | 29649 | 29765 | **−6.3%** | **−5.9%** |
| `cmd/main` | 33841 | 31852 | 31968 | −5.9% | −5.5% |
| `cmd/bench` | 39706 | 37731 | 37850 | −5.0% | −4.7% |

### 10.4 分析

1. **收益与 §5 估算同向且略高**：V40 宿主 **−15%**（估算 ≈10–13%）。机制 = 去 `Array[T]` 的
   `{buf,len}` 二层间接（S9m §1.3），在 `score` 8 轮扫描 + `apply_mask` 上累积。
2. **`FixedArray[Int]` ≈ `FixedArray[Byte]`（速度）**：V40 4.4885 vs 4.4770（差 0.3%，噪声内）；
   V10/V03 互有胜负 ⇒ 与 §4.1 微基准一致：**byte 窄化不带来速度收益**。
3. **Byte 版省内存**：矩阵 4B/格 → 1B/格（V40 177² ≈ 125 KB → 31 KB；`create_auto_qr` 每轮一个副本，
   8 副本 ≈ 1 MB → 250 KB）。代价：**代码略大**（`qr-min` +116 B / +0.4%，
   因新增 `*_b` Byte 边界 helper）；且需在 8 个白盒测试与生产读点插入 `Byte↔Int` 转换，**改动噪声更大**。
4. **体积 −5~6% 是意外收益**：`FixedArray` 不走 `Array` 的运行时增长/`{buf,len}` 辅助例程。

### 10.5 结论与选型建议

- **介质换代（去 `Array` 间接）实测成立、已落地**：`FixedArray[Int]` 合入 `main`（提交 `ea7d7ae`），
  V40 宿主 **−15%**、体积 **−5~6%**、语义零差异、公共 API 不变。
- **选型**：采用 `FixedArray[Int]`（改动小、无 `Byte` 转换噪声、速度与 Byte 版持平）；
  若**在意宿主侧内存/GC**（多实例、长驻）可切 `exp/fixedarray-byte`（保留为对照分支，未合并）。
- **前置**：D3 介质决策（`S4 §3.1 D3`）与 8 个白盒测试**已随落地同步**；`.mbti` 不变已实测。
- 分支 `exp/fixedarray-byte` 为**对照分支**（**未合并、未推送**）；落地入 `main` 的是 `FixedArray[Int]`。

### 10.6 局限

| # | 局限 |
|:-:|------|
| M1 | 单机 `moonrun`/Node 宿主；**轮间离散仍大**（V40H `main` 5.23–5.89ms），结论以「中位数 + 三分支方向一致」为准，**不宣称精确倍数** |
| M2 | **未测堆峰值/GC**：Byte 版的内存收益只有算术论证，无实测 |
| M3 | V03/V10 的宿主面离散最大（部分轮 ±20–50%），其百分比仅供参考 |
| M4 | 分支上 `score` 的临时缓冲（`buf`/`colbuf`）在 Byte 版一并窄化，未单独分离其影响 |

---

## 9. 参考

- 成本占比与上限：[S9k](S9k-性能瓶颈与理论上限评估.md)；统一优先级：[S9n](S9n-优化方案复评与wasm-gc收敛审计.md) §3/§6.4
- 表容器（`ReadOnlyArray`）：[S9m](S9m-ReadOnlyArray适用性评估.md)
- core 源码：`builtin/bytes.mbt`（无 setter）、`builtin/bytes_unsafe.mbt`（多字节 intrinsic，wasm-gc 真实实现）、
  `builtin/arraycore_nonjs.mbt:16-19`（`{buf,len}`）、`builtin/fixedarray.mbt`、`builtin/readonlyarray.mbt`
- 本项目实码：`lib/internal/reedsolomon/reedsolomon.mbt:547`、`lib/internal/matrix/{score,matrix,placement,datamasking,module}.mbt`、
  `lib/internal/bitstream/bitbuffer.mbt`
