# S9d · 与 moonbit 生态 QR 包性能对比

> 本文件由原 S9d-与moonbit生态QR包性能对比-方案 / S9d-与moonbit生态QR包性能对比-实现记录 / S9d-与moonbit生态QR包性能对比-详细分析 / S9d-moonbitqrcode快速原因与产物对比-分析 / S9d-moonbitqrcode固定mask0缺陷与主流对比 于 2026-09-11 合并而成（文档整合，见 roadmap M3 收口后整理）。
> 内容除标题降级与本头部外未改写；各部分头部的承接/修订注记原样保留。

## 实现方案

> 承接 [S9-性能基准.md](./S9-性能基准.md)（层① 基准载体 `cmd/bench`）、
> [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
> 与 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
> （层② Rust fast_qr-wasm32 跨语言对比）。本方案把对比视野从「跨语言 vs Rust fast_qr」扩到
> **同语言 vs moonbit 生态现有 QR 包**：`qrc`（bobzhang/qrc）、`moonqr`（naoto24kawa/moonqr，
> 即 elchika-inc/moonqr 的 MoonBit 内核）、`moonbitqrcode`（PaiGack/moonbitqrcode，rsc.io/qr 移植）。
> 交付 = 可复跑性能对比脚本方案（环境 → 依赖 → 构建 → Node/moonrun 驱动 → 计时表）。
> 日期：2026-09-06　｜　范围：**方案文档 + 依赖/脚本文件级清单；本文不改本仓库 lib/scripts 代码**
> （落地另立实施任务）。对比结果预期：moonbit 生态包同为 MoonBit 源码，可**同一工具链同后端**编译，
> 计时宿主与层② MoonBit 侧一致（moonrun 子进程），比层②跨语言对比更干净。

---

### 0. 一句话结论

moonbit 生态已有 **3 个可对比的 QR 编码包**（qrc 0.1.1 / moonqr 0.2.0 / moonbitqrcode 0.1.0），全部经
`moon add` 从 mooncakes 获取、**实测可编译 wasm-gc 与 wasm(WASI) 双后端**，且其公共 API 足以承载
「同输入同 ECL、强制版本/自动 mask」的基准协议。方案 = 新建一个**对比专用小模块**（不并入本仓库
lib），把 3 个包 + 本仓库 `lib` 一起 import 成**单一 wasm 可执行**，复用 `cmd/bench` 的
「循环 N 次 build + 消费结果 + 多次取最小 + Node 宿主计时」口径，产出 **同宿主、同后端、同输入、
同 ECL(H) 的 4 方（本仓库 vs 3 包）边际单次成本与每模块成本对比表**。

> **为什么不是「把三包 add 进本仓库 moon.mod 再跑 cmd/bench 扩展」**：本仓库是**库**，moon.mod 若引入
> 3 个外部包会污染库的公共依赖面与 `.mbti` 校验面（moon 的依赖在 lib 包 import 层即可见）；
> 而对比实验天然是**一次性、不进 CI** 的参考测量（对齐 S9c 层②：fast_qr 检出在 `$FAST_QR_WASM_DIR`
> 不入库）。故用**仓库外独立模块**承载，仓库内仅新增 scripts（与既有 `scripts/setup-*.sh`/`bench-*.sh`
> 同模式），保持本仓库 `lib` 零依赖、`moon check/test` 不回源 mooncakes。

---

### 1. 背景与目标

#### 1.1 为什么做（承接 S9 系列）

- S9/S9b/S9c 已把「性能透明对比」做到**跨语言 vs Rust fast_qr-wasm32**（层②）：数字 0.304/1.162/9.01ms
  vs 0.061/0.335/3.18ms（边际，见 S9c 详细分析 §2），fast_qr-wasm32 快 2.8–5.0×。
- 但 moonbit 生态已有若干 QR 包；**同语言生态包对比**回答的是不同问题：同为 MoonBit 源码、同一工具链
  同一后端时，本仓库实现相对生态现成包的**纯实现效率位次**（排除语言/运行时差异，只剩算法与工程差异）。
- 该位次直接关系到本仓库对外的**可替代性话术**（用户为何选 fast_qr_moonbit 而非 qrc/moonqr/...），
  是 S9 系列「透明对比」的自然延伸（roadmap S9 行「无硬门槛」精神一致）。

#### 1.2 对比对象（已核实的事实，2026-09-06 实测）

| 包（mooncakes 全名） | 版本 | 仓库 | 说明 | 本仓库视角 |
|---------------------|------|------|------|-----------|
| `bobzhang/qrc`（别名 qrc） | 0.1.1 | github.com/bobzhang/qrc（moonbit-community/qrc） | OCaml `dbuenzli/qrc` 的 MoonBit 移植；encode(data)/encode_with_ec(data, ec)/generate_qr_with_mask；ecl 枚举 + make_ec_level_* 构造 | 公共 API 以 String 输入；**强制版本**经 `encode_with_mode_and_ec`（需 Mode+Version+ecl），**mask 自动择优**走 generate_qr_with_mask |
| `naoto24kawa/moonqr`（别名 moonqr） | 0.2.0 | github.com/elchika-inc/moonqr（core/） | **MoonBit 原生 QR 编码/解码内核**（另有 JS/npm 壳）；`encode(text, ec, version?)`、`EcLevel` 枚举、Matrix? 返回 | 公共 API 直接支持 **ecl + 可选强制 version**（`Some(3)` 等），mask 自动择优；`preferred-target=js` 但 wasm-gc/wasm 亦实测可编译 |
| `PaiGack/moonbitqrcode`（别名 moonbitqrcode） | 0.1.0 | github.com/PaiGack/moonbit-qr | Go `rsc.io/qr` 的 MoonBit 移植；`src/lib` 包 encode(text, level) + encode_low/medium/high；`src/coding` 暴露 Plan/Level/Mask | lib 层**仅自动最小版本 + 固定 mask0**（Plan 用 `Mask::of_int(0)`）；**强制版本/择优需走 `src/coding` 内层 API**（同包可 import，非 `pub(all)` 面向外暴露的限制待落地核） |

> ⚠️ **语义差异（对比方案必须显式对齐/标注）**：
> 1. **mask 策略**：qrc/moonqr 走「8 轮择优」（同本仓库/同 fast_qr）；moonbitqrcode lib 层**固定 mask 0**
>    （不做择优）→ 若直接比 lib `encode`，moonbitqrcode 天然少 8 轮择优成本，**不公平**。方案要求
>    moonbitqrcode 侧走 `src/coding` 的 `Plan` + 择优（或标注其为「无择优下限」口径，二选一，落地核）。
> 2. **ECL 构造**：qrc 用 `make_ec_level_h()`；moonqr 用 `EcLevel::H`；moonbitqrcode lib 的 `LibLevel::H`
>    经 `pub enum` 暴露、外部构造曾被 MoonBit 判「read-only」，需用其 `Level::of_int(3)`/lib helper 核通路。
> 3. **版本控制**：qrc 的 `encode_with_mode_and_ec`、moonqr 的 `encode(..., Some(v))` 可强制版本；
>    moonbitqrcode lib 层**不暴露**强制版本 → 基准点若需 V10/V40，须走其 `src/coding.Plan::new(v,...)`。
> 4. **输入介质**：三包均 String 输入（UTF-8），本仓库 `QRBuilder::from_string` 同构；ASCII 输入无差异。

#### 1.3 与层②口径的异同

| 维度 | 层②（S9c，fast_qr-wasm32） | 本方案（moonbit 生态 3 包） |
|------|---------------------------|---------------------------|
| 对比双方 | Rust wasm32 vs MoonBit wasm | MoonBit vs MoonBit（本仓库 vs 3 包） |
| 编译 | fast_qr 用 rust+wasm-bindgen（外部检出） | 三包均 `moon add`（mooncakes），与本仓库同 moon 工具链 |
| 宿主 | Node 进程内(fast) vs moonrun 子进程(MoonBit) | **统一 moonrun 子进程**（同进程形态差异消失） |
| 对齐 | 逐位对齐 sha256（跨宿主重确认） | **不要求逐位对齐**（三包算法细节/表实现独立；只做「同尺寸 + 同输入 + 同 ECL」的**行为烟测**与计时） |
| 产物 | fast_qr wasm-bindgen nodejs 产物 | moon 构建 wasm 产物 |

---

### 2. 方案总览（文件级）

```
本仓库新增：
  scripts/setup-moonbit-qr-compare-env.sh   ① 环境：建对比根目录 + moon add 三包 + 校验
  scripts/build-moonbit-qr-compare.sh       ② 构建：把「对比模块」moon build 成 wasm/wasm-gc
  scripts/bench-moonbit-qr.sh               ③ 计时：moonrun 子进程 × 三方 + 本仓库，多次取最小
  scripts/moonbit-qr-compare.mjs            ③’ 可选 Node 驱动（与 wasm-compare.mjs 同风格）

仓库外（$MOONBIT_QR_COMPARE_DIR，默认 ~/.cache/moonbit_qr_compare）：
  moon.mod / moon.pkg                       对比专用小模块（import 本仓库 lib + 3 个外部包）
  main.mbt                                  bench 驱动：argv 选方/点/N → 循环 build 累加消费 → 输出
  （由 setup/build 脚本生成/复用，不入库；对齐 S9c 的 $FAST_QR_WASM_DIR 模式）
```

> 对比模块 **import 本仓库 lib 的方式**：moon 支持以**相对路径 import 同仓库 lib**吗？——本仓库与对比模块
> 是**两个独立模块**，跨模块 import 需 registry/路径依赖。**实测备选**：① moon add 引用（仅限已发布）；
> 本仓库未发布 → 采用 **`moon.mod` 里用本地路径/或把本仓库作为依赖模块链接到对比根**的 moon 机制
> （落地时核：`import { "../fast_qr_moonbit/lib" }` 是否可行；不行则退化为「对比模块独立、本仓库侧沿用
> 现成 `cmd/bench` wasm 产物」，即本仓库不 join 同一模块，只把**同一基准协议**分别跑在 本仓库 wasm 与
> 三包 wasm 上，Node 汇总）。

---

### 3. 详细设计

#### 3.1 基准协议（对齐 S9/S9c，尽量同口径）

- **输入**：`https://example.com/`（20 字节，与 S9/S9c 完全相同）。
- **ECL**：H（同 S9/S9c）。
- **基准点**：V03H / V10H / V40H（强制版本；对应 `moon bit` 层②三点的版本序）。
- **mask**：自动择优（对齐 fast_qr benches 与 S9/S9c）；moonbitqrcode 若无择优 API 则标注「固定 mask0
  口径」，不强行拉齐（落地核后决定是走 coding 择优还是标注）。
- **迭代档**：V03H=2000、V10H=400、V40H=40（沿用 S9 默认，保证单点 ≥100ms 量级远离计时噪声）。
- **循环消费**：每轮 build 后把「矩阵尺寸 + 少量代表格明暗」累加进校验量、循环外只输出一次总量
  （防空循环/死代码消除——S9 已落地同款，方案照搬）。
- **计时**：宿主对每「方×点」整程重复 R 次取最小（R 默认 3~5），剔冷启动；与 S9/S9c 完全一致。
- **对齐/正确性烟测**：每方每点输出矩阵**尺寸必须 = 4×version+17**（V03=29/V10=57/V40=177）；
  尺寸不符即判该包该点不可比并标红（不强行 diff 内容——跨实现 mask/细节可能不同，diff 无意义）。

#### 3.2 四方驱动形态（关键差异：各包 API 不同）

| 方 | 调用入口 | 备注 |
|----|---------|------|
| 本仓库 | `@lib.QRBuilder::from_string(input).ecl(H).version(Vxx).build()` | 与 cmd/bench 完全同构，直接复用逻辑 |
| qrc | `@qrc.encode_with_mode_and_ec(input, @qrc.Mode::Byte?, ver, @qrc.make_ec_level_h())`（强制版本）或 `encode_with_ec`（自动版本） | 强制版本需 Mode 参数；**mode 用 Byte 对齐本仓库字节语义**（落地核 `Mode::Byte` 构造通路） |
| moonqr | `@mq.encode(input, @mq.EcLevel::H, Some(ver))` | 直接支持强制版本；返回 `Matrix?` |
| moonbitqrcode | lib `encode`（仅自动版本）或 `@cod.Plan::new(ver, level, mask)+encode` | 若走 lib 则只能自动最小版本 → **与三基准点不匹配**；故优先 `src/coding` 强制版本通路，落地核可见性 |

> 因为 4 方 API 无法 100% 同构，**驱动 main 为每方各写一段适配调用**（switch by argv[1]），循环/消费/
> 输出逻辑共用同一段模板——保证「计时部分同构、只有真实编码调用不同」。

#### 3.3 输出

每行：`<方> <点> <N> ok=<N> builds size=<边长> checksum=<int>`，末尾 `TOTAL_CHECKSUM=<int>`。
汇总脚本产出 markdown 表：
`| 方 | 点 | 逐位对齐n/a | 尺寸校验 | 最小整程(ms) | 边际单次(ms) | 每模块(µs) | 相对本仓库 |`

> 边际单次/每模块 = 整程/N 与 /(N×边长²)，口径沿用 S9c 详细分析（**只比同点同 N**；不做 N 扫描 LSQ 的
> 首版可省，若要「启动开销分离」再叠加 N 扫描，标为二期可选）。

---

### 4. 落地清单与验收

| # | 文件/动作 | 内容 | 验收 | 状态 |
|---|-----------|------|------|------|
| 1 | `scripts/setup-moonbit-qr-compare-env.sh` | 幂等：`MOONBIT_QR_COMPARE_DIR`（默认 `~/.cache/moonbit_qr_compare`）下建独立模块 → `moon add bobzhang/qrc@0.1.1` + `moon add naoto24kawa/moonqr@0.2.0` + `moon add PaiGack/moonbitqrcode@0.1.0`；写 moon.pkg import 4 方 | 重跑幂等；`moon info` 能看到 4 包符号 | ✅ 待实施 |
| 2 | 对比模块 `main.mbt` | 4 方适配驱动（§3.2）+ 共用循环/消费/输出（§3.1） | 每方每点输出 `size` 正确（29/57/177）；checksum 稳定 | ✅ 待实施 |
| 3 | `scripts/build-moonbit-qr-compare.sh` | `moon build <对比模块> --target wasm --release`（+ wasm-gc 可选）；产物路径回传 | wasm 产物可跑 | ✅ 待实施 |
| 4 | `scripts/bench-moonbit-qr.sh`（+ 可选 `.mjs`） | 对 方×点 用 moonrun 整程 R 取最小，串行跑；输出 §3.3 表 | 一条命令出 4 方 × 3 点表 | ✅ 待实施 |
| 5 | 首跑记录 | 本容器跑出 4 方数字；对 moonbitqrcode 择优通路落地核后的口径做注记 | §5 表 | ⏳ 待实施 |
| 6 | 收尾回归 | fmt/check/test + 双后端 release + lib `.mbti` 零漂移（仓库内只加 scripts，不动 lib） | 109 全绿 | ✅ 待实施 |
| 7 | 文档治理 | 本文 + 实施后回填记录文档；README/roadmap 索引同步 | 无死链 | 本文 |

> **接口护栏**：本方案**只在仓库加 scripts**、不 import 任何外部包进 `lib`/`cmd`，`moon.mod` 不加依赖，
> `moon test` 不触碰 mooncakes → lib `.mbti` 零漂移、109 全绿基线不受影响（与 S9c 层②同策略）。

---

### 5. 预期产出（量级参考，不承诺；以实际跑测为准）

预期 4 方 V40H 边际成本在 **2–10ms 量级**、V03H 在 **0.1–1ms 量级**；本仓库相对 3 包的具体位次与差距
**由实测给出**（不预设结论）。若 moonbitqrcode 只能走「固定 mask0」口径，其数字会比「择优」方偏低，
表中以「(固定 mask0)」标注并**不与择优方直接排名**，仅作参考下限。

---

### 6. 风险与不确定点（落地前需核）

1. **跨模块 import 本仓库 lib**：对比模块要 join 本仓库，moon 依赖机制是否支持本地/相对模块 import
   需实测（见 §2 备注）；不支持则退化为「各自 wasm + Node 汇总」（层②模式），结论不变、只是少了
   同进程同模块的极致同构。
2. **moonbitqrcode 择优通路**：lib 层固定 mask0 + 不暴露强制版本，`src/coding` 是否为可 import 的稳定
   API、`Plan/Level/Mask` 构造与 `pub(all)` 可见性需落地核；不可行则按「固定 mask0 参考口径」标注。
3. **qrc `encode_with_mode_and_ec` 是否等价完整管线**：需确认其包含 mask 择优与 format 写入（读源码
   似含 place_format；择优见 generate_qr_with_mask 分支）——落地用「同输入自动 vs 强制版本输出尺寸一致」
   烟测兜底。
4. **包版本漂移**：mooncakes 包可能更新；脚本**钉版本**（上表版本号）防数字不可复现（与 S9c 钉 fast_qr
   commit 同策略）。
5. **JS 偏好包 moonqr**：其 `preferred-target=js`，但 wasm-gc/wasm 实测可编译；若未来仅维护 JS 壳，
   对比口径需注明后端。

---

### 7. 参考

- 层②方法与口径：[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)、
  [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
- 基准载体/口径：[S9-性能基准.md](./S9-性能基准.md)、
  [S9-性能基准.md](./S9-性能基准.md)
- 生态包（mooncakes/仓库，2026-09-06 访问）：
  `bobzhang/qrc@0.1.1`（github.com/bobzhang/qrc）、`naoto24kawa/moonqr@0.2.0`
  （github.com/elchika-inc/moonqr）、`PaiGack/moonbitqrcode@0.1.0`（github.com/PaiGack/moonbit-qr）
- 实测事实：三包 `moon add` 成功、wasm-gc/wasm 均编译通过；qrc/moonqr 可强制版本；moonbitqrcode lib
  固定 mask0/自动版本、coding 层含 Plan（可见性待落地核）

---

## 实现记录

> 承接 本文件「实现方案」部分
> （层②同语言延伸方案）与本仓库性能基线
> [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)。
> 本记录落地**首跑对比**：`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、`PaiGack/moonbitqrcode@0.1.0`
> 经 `moon add` 引入独立对比模块、与本仓库 `cmd/bench` wasm 产物在同一 `moonrun` 宿主计时。
> 日期：2026-09-06　｜　范围：**只运行既有 cmd/bench/对比驱动并记录**，本仓库 lib 未再改；
> 结论与方案 §5「不预设位次」一致，且**暴露 3 个生态包在「同尺寸同语义可比」上的硬约束**（见 §3）。

---

### 0. 一句话结论

- **同尺寸、同语义（强制 V03/V10/V40 + ECL H + mask 自动择优 + 完整 Format/版本）可比子集只有「本仓库 vs moonqr」**；
  实测本仓库 **2.5–4.1× 更快**（V40H 单次 9.46ms vs 38.29ms；V03H 0.318 vs 0.805ms，R=5 取最小）。
- **qrc 与 moonbitqrcode 暂无法与本仓库做同口径对齐对比**，原因（实测核实）：
  - `qrc` 公开完整路径仅**自动版本**（`encode_with_ec`→`generate_qr_with_mask` 才含 mask/Format）；
    `encode_with_mode_and_ec` 强制版本**只 place_data、无 mask/Format**（qrc 自带 README 亦标注
    「No format information / No masking」）；且自动版本对 20B@H 返回 **V2(size=25)**，
    低于理论最小 V3(29)——疑似容量/模式口径差异，需可解码性核验。
  - `moonbitqrcode` lib 公开面 **仅 encode_low/medium/high = L/M/Q**（`LibLevel::H` 外部不可构造，
    MoonBit 报 read-only），且固定 `Plan(…, Mask::of_int(0))` **不做择优**；只可比「自动版本 + 固定
    mask0」参考口径，不能与自动择优方排名。
- 因此本记录给出：**① 可信对比（ours vs moonqr）数字表；② qrc/moonbitqrcode 参考口径表 + 不可比
  原因；③ 对本仓库的结论：同语言生态内当前也**不落后**（moonqr 是对手位）。**

---

### 1. 方法（对齐方案 §3 + S9/S9c 口径）

#### 1.1 对比模块与产物

```bash
# 仓库外独立模块（不入库，对齐层② fast_qr 检出模式）
mkdir -p ~/.cache/moonbit_qr_compare && cd ~/.cache/moonbit_qr_compare
moon new compare && cd compare
moon add bobzhang/qrc@0.1.1 naoto24kawa/moonqr@0.2.0 PaiGack/moonbitqrcode@0.1.0
# moon.pkg import 三方（@qrc/@mq/@mqr）+ main.mbt 驱动（argv: lib N [ver]）
moon build cmp --target wasm --release   # 或 .mooncakes 内直接 build 三方（本记录用 /tmp 对比模块）
```

本记录实测环境 = `/tmp/moon-scratch/qrcompare`（含三包 `.mooncakes` 检出），`moon 0.1.20260827`。

#### 1.2 计时与消费口径（沿用 S9/S9c）

- 输入 `https://example.com/`（20B），ECL H，V03/V10/V40（能强制才强制）。
- 每方每点循环 N 次 build，**消费每次结果**（累加矩阵边长进 checksum，防死代码消除）；
  输出 `SIZE=<边长>` + `TOTAL_CHECKSUM=<int>`。
- 宿主 `moonrun` 子进程整程计时，**R=5 取最小**（同层②）；单点迭代 N=2000/400/40（同 S9 默认档）。
- 「单次(ms/build)」= 整程最小/N（含 moonrun 启动摊销；双方同宿主、同 N，摊薄一致，可直接比）。
- 结果消费口径：本仓库侧沿用 `cmd/bench`（size+代表格+元数据 checksum）；三包侧为「累加矩阵边长
  checksum + 输出 SIZE」——与 fast_qr 层②侧只累加长度同量级，偏置可忽略（两侧都强制消费了每次 build）。
- 本仓库侧 = 既有 `cmd/bench --target wasm` 产物（同协议，`moonrun bench.wasm Vxx N`）。

---

### 2. 实测数字

#### 2.1 可信对比（同尺寸同语义：本仓库 vs moonqr，R=5 取最小，moonrun）

| 方 | 点 | N | 整程最小(ms) | 单次(ms/build) | 每模块(µs) | vs 本仓库(单次比) |
|----|----|--:|------------:|---------------:|-----------:|------:|
| 本仓库 | V03H | 2000 | 635.2 | 0.3176 | 0.378 | 1.00× |
| moonqr | V03H | 2000 | 1610.7 | 0.8054 | 0.958 | **2.54×** |
| 本仓库 | V10H | 400 | 475.3 | 1.1883 | 0.366 | 1.00× |
| moonqr | V10H | 400 | 1714.1 | 4.2852 | 1.319 | **3.61×** |
| 本仓库 | V40H | 40 | 378.2 | 9.4550 | 0.302 | 1.00× |
| moonqr | V40H | 40 | 1531.7 | 38.2925 | 1.222 | **4.05×** |

- 两侧都做了真实 8 轮 mask 择优 + Format/版本信息 + 完整纠错（同尺寸、同 ECL、同输入）。
- **结论**：本仓库 V03→V40 全程快 moonqr **2.5–4.1×**；差距随版本增大（与层②对 fast_qr 的差距方向
  相反，说明 moonqr 的大版本成本结构更重）。本数字与 S9c 层②口径（本仓库 V40H 单次 ≈9.0ms）自洽。

#### 2.2 参考口径（qrc / moonbitqrcode —— 不可同口径对齐，仅记录其公开路径表现）

| 方 | 路径 | N | 整程最小(ms) | 单次(ms/build) | SIZE | 备注 |
|----|------|--:|------------:|---------------:|-----:|------|
| qrc | `encode_with_ec(H)` 自动版本 | 2000 | 1191.3 | 0.5957 | 25 | ⚠️ V2 < 理论最小 V3(29)；README 自述无 mask/Format 于该 API 族 |
| moonbitqrcode | `encode_high(=Q)` 自动版本 | 2000 | 94.9 | 0.0474 | 25 | ⚠️ lib 固定 mask0（无择优）+ 仅自动版本 + 无 H 公共构造 |

> **为什么这两行不与 §2.1 排名**：
> - 尺寸不同（25 vs 29/57/177）→ 每 build 工作量不同；且 qrc 的 20B@H 落到 V2 属**容量/模式口径
>   可疑**（需可解码性核验后才能当作“正确的 QR 编码”来计时）。
> - qrc 强制版本路径无 mask/Format；moonbitqrcode 无择优（固定 mask0）→ 与「自动择优」语义不等价，
>   直接排名会把「没做择优」误读成「更快」。
> - 故两行仅作**生态包公开路径可跑性与量级参考**，标注在案、不进入与本仓库的同口径结论。

---

### 3. 生态包可比性硬约束（实测核实，供后续/他人复用）

| 包 | 强制版本 | 强制 ECL | mask 择优 | 完整 Format/版本信息 | 可比性判定 |
|----|---------|---------|-----------|---------------------|-----------|
| qrc | 有 API 但**路径无 mask/Format**（`encode_with_mode_and_ec` 只 place_data） | 有（make_ec_level_*） | 仅自动版本完整路径有（generate_qr_with_mask） | 仅自动版本路径有 | ❌ 无法与本仓库同口径对齐 |
| moonqr | ✅ `encode(text, ec, Some(v))` | ✅ EcLevel::H | ✅（自动） | ✅ | ✅ **可比** |
| moonbitqrcode | ❌ lib 仅自动版本（内部 coding.Plan 可强但非稳定公共面） | ⚠️ lib 仅 L/M/Q（H 外部不可构造） | ❌ 固定 mask0 | ✅（Plan 内部） | ❌ 仅参考口径 |

> 这本身是「调研/评估」结论的实证落地：S9d 方案 §6 预判的三处不确定点全部命中，且给出准确形态
> （qrc 强制版本缺 mask/Format、moonbitqrcode H 不可构造 + 固定 mask0、moonqr 是唯一干净可对比方）。

---

### 4. 与既有基准的关系（同一把尺子）

- 本仓库侧数字与 S9c 层②/详细分析一致（V40H 单次 ≈9.0–9.5ms，wasm+moonrun 口径），本次未改 lib，
  故 §2.1 即「本仓库 vs moonqr」的新增同语言对比基线。
- 若后续 S9b T3/T4 落地，可**直接复用本对比模块**重跑 §2.1 表，观察对 moonqr 的差距收窄（本表即
  优化前后同一把尺子；同样也可复跑 S9c bench-layer2 对 fast_qr）。

---

### 5. 验收与门禁（沿用 AGENTS §二.4）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test        # 109 全绿
for t in wasm-gc wasm; do moon build cmd/bench --target $t --release; done
```
- 本记录纯跑测 + 文档，lib/scripts 未动；`cmd/bench` 默认输出与既有记录一致（82000/32400/9200）。
- 死链零容忍：新增文档须同步 README「文档」索引 + roadmap（见 §7）。

---

### 6. 汇总与后续

1. **可信结论**：同尺寸同语义（强制版本 + H + 自动择优 + 完整输出）下，本仓库快 moonqr 2.5–4.1×。
2. **生态现状**：qrc 0.1.1 与 moonbitqrcode 0.1.0 的公共 API 尚不足以做与本仓库的同口径对比
   （mask/版本/ECL 约束见 §3）——本记录将其列为参考口径并说明原因，不夸大结论。
3. **后续可选**：
   - 对 qrc/moonbitqrcode 做「自动版本可解码性」核验（若输出本身不可解码，则其计时仅代表内部管线
     成本、不能代表“生成可用 QR”）；属参考性质量审计，非本仓库性能义务。
   - S9b T3（score 减趟）落地后重跑 §2.1，回填对 moonqr 的收窄数据。

---

### 7. 参考

- 方案：本文件「实现方案」部分
- 层②/同尺子：[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)、
  [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
- 优化路线：[S9b-性能优化.md](./S9b-性能优化.md)、
  [S9b-性能优化.md](./S9b-性能优化.md)
- 生态包（mooncakes，2026-09-06）：`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、
  `PaiGack/moonbitqrcode@0.1.0`
- 实码：`cmd/bench`（本仓库侧，未改）；仓库外对比模块（本记录 `/tmp/moon-scratch/qrcompare/cmp`）

---

## 详细分析

> 承接 本文件「实现方案」部分
> 与 本文件「实现记录」部分
> （首跑实现记录）。本文在首跑之上做**全库（4 方）逐点对照 + 逐库容量/语义核验 + 归因分析**，
> 回答三个问题：① 各库在同一宿主/同一输入下**自动最小版本口径**能跑多快（含尺寸）；② 在**可对齐的
> 强制版本子集**（H + 自动择优 + 完整输出）里本仓库 vs moonqr 的差距；③ qrc / moonbitqrcode 为何
> 不能直接对齐、其数字代表什么。
> 日期：2026-09-06　｜　范围：**只运行既有 cmd/bench/仓库外对比模块并记录分析**，本仓库 lib 未改；
> 方法/门禁/参考同 本文件「实现记录」部分。

---

### 0. 一句话结论（全库）

| 库 | 自动最小版本（20B 输入） | 同宿主单次耗时 | 每模块 | 可对齐性 |
|----|------------------------|---------------:|--------|:--------|
| **本仓库 fast_qr_moonbit** | V3（29×29）✅ 规格正确 | 0.318 ms | 0.378 µs | 基线（强制 V 全口径） |
| **moonqr** | V3（29×29）✅ 规格正确 | 0.791 ms | 0.940 µs | ✅ 可强制 V03/V10/V40 + H + 自动择优 |
| **qrc** | **V2（25×25）⚠️ 疑似容量单位 bug**（20B@H 最小应 V3） | 0.583 ms | 0.932 µs | ❌ 强制路径无 mask/Format；自动路径装不下 20B |
| **moonbitqrcode** | V2（25×25）✅ Q 档 V2 恰容 20B | **0.046 ms** | **0.074 µs** | ❌ 固定 mask0（无择优）+ 仅 L/M/Q + 仅自动版本 |

- **全库同一把尺子能排名的只有「本仓库 vs moonqr」**：强制 V03/V10/V40 + ECL H + 自动择优 + 完整
  输出，本仓库 **2.5–4.1× 更快**（V40H 9.46 vs 38.29ms/单次）。
- **moonbitqrcode 每模块极快（0.074µs）不代表算法更优**：其公开 lib 路径**固定 mask0、无 8 轮择优**、
  仅自动最小版本，且 ECL H 对外不可构造（只到 Q）；等于「跳过了择优 + 小版本」的下限口径，不能与做
  8 轮择优的库排名。若想公平比，须走其 `src/coding` 内层（Plan+择优），非稳定公共面（见 §3）。
- **qrc 自动路径疑似存在容量单位 bug**（`get_data_capacity` 返回字节数、`calculate_required_length`
  返回位数，bytes vs bits 混比 → 20B@H 错选 V2(25) 而规格最小为 V3(29)）→ 其自动口径**可能产出装不下
  数据/不可解码的码**，不能作为性能基准。

---

### 1. 全库同口径总表（实测，R=5 取最小，moonrun 宿主，输入 `https://example.com/`）

| 方 | 调用路径 | ECL | 版本 | SIZE | N | 单次(ms/build) | 每模块(µs) | 备注 |
|----|---------|-----|------|-----:|--:|---------------:|-----------:|------|
| 本仓库 | cmd/bench 强制 | H | V03 | 29 | 2000 | 0.3176 | 0.378 | 完整管线（择优+Format+版本） |
| 本仓库 | cmd/bench 强制 | H | V10 | 57 | 400 | 1.1883 | 0.366 | 同上 |
| 本仓库 | cmd/bench 强制 | H | V40 | 177 | 40 | 9.4550 | 0.302 | 同上 |
| moonqr | `encode(..,H,Some(v))` | H | V03 | 29 | 2000 | 0.8054 | 0.958 | 完整管线 |
| moonqr | 同上 | H | V10 | 57 | 400 | 4.2852 | 1.319 | 完整管线 |
| moonqr | 同上 | H | V40 | 177 | 40 | 38.2925 | 1.222 | 完整管线 |
| moonqr | `encode(..,H,None)` 自动 | H | V03 | 29 | 2000 | 0.7908 | 0.940 | 自动最小=强制 V03 同量级 |
| qrc | `encode_with_ec(H)` 自动 | H | **V2** | **25** | 2000 | 0.5826 | 0.932 | ⚠️ 疑似装不下 20B（容量单位 bug） |
| qrc | `encode_with_mode_and_ec(Byte,V3,H)` 强制 | H | V3 | 29 | 2000 | 0.1657 | 0.197 | ⚠️ 只 place_data，**无 mask/Format**（管线轻） |
| qrc | 同上 V10 | H | V10 | 57 | 400 | 1.0189 | 0.314 | ⚠️ 同上 |
| qrc | 同上 V40 | H | V40 | 177 | 40 | 39.2734 | 1.254 | ⚠️ 同上（V40 仍贵，说明其内部实现开销大） |
| moonbitqrcode | `encode_high` 自动 | **Q** | V2 | 25 | 2000 | 0.0463 | 0.074 | lib 固定 mask0 + 无 H |
| moonbitqrcode | `encode_medium` 自动 | M | V2 | 25 | 2000 | 0.0454 | 0.073 | 同上 |
| moonbitqrcode | `encode_low` 自动 | L | V2 | 25 | 2000 | 0.0433 | 0.069 | 同上 |

> 容量口径注记：20B@H 规格最小版本 = V3（V2-H 容量 14B < 20 ≤ V3-H 24B）；20B@Q = V2（V2-Q 恰容
> 20B）。moonqr/本仓库自动 H→V3 ✅；qrc 自动 H→V2 ⚠️；moonbitqrcode 自动 Q→V2 ✅（但其 ECL 只到 Q）。

---

### 2. 逐库分析

#### 2.1 本仓库（fast_qr_moonbit）——基线

- 强制 V03/V10/V40 + H + 自动择优 + 完整输出，同 S9/S9c 层② 口径，V40H 单次 ≈9.0–9.5ms
  （含 S9b O1-b 已省末次 copy 的版本；详见 [S9b-性能优化-O1实施记录](./S9b-性能优化.md)）。
- 每模块成本 0.30–0.38µs，随版本增大略降（常数项摊薄），窄带稳定。

#### 2.2 moonqr —— 唯一可对齐的生态对手

- 优势：API 干净（`encode(text, ec, version?)`），支持强制版本 + ECL H + 自动择优 + 完整输出，
  是与本仓库做**同尺寸同语义**对比的唯一生态包。
- 差距：全程 **2.5–4.1× 慢于本仓库**；且**随版本放大**（V03H 2.5× → V40H 4.0×），每模块成本 0.94–
  1.32µs，是本仓库（0.30–0.38µs）的约 3–4×——说明其大矩阵管线（放置/择优/评分）成本结构更重。
- 对本仓库意义：同语言生态里不落后；同时其绝对成本说明生态实现尚有工程空间。

#### 2.3 qrc —— 自动口径不可信，强制口径管线不全

- **自动版本疑似容量单位 bug**：`get_data_capacity` 返回「总码字−纠错码字」**字节数**，而
  `calculate_required_length` 返回 **位数**，比较时 bytes vs bits 混比 → 自动选版系统性偏小
  （实测：20B@H 选 V2、50B@H 选 V3，而 Byte-H 规格容量 v2=14<20≤v3=24、v5=44<50≤v6=58，
  即 20B 最小应为 V3、50B 最小应为 V6）。后果：其自动输出可能装不下输入（数据被截断/不可解码），
  **不能当性能基准**。
- **强制版本路径管线不全**：`encode_with_mode_and_ec` 只做 init+encode+RS+place_data，**不应用
  mask、不写真实 Format/版本信息**（其 README 亦自述「No format information…No masking」）→ 单次
  V3H 0.166ms 的低值恰因「跳过了择优与 Format」，**不代表完整 QR 成本**。
- 每模块在 V40 强制下仍达 1.25µs（即使管线更轻），说明其实现本身在版本放大后开销大；但与完整管线
  库不可直接比。

#### 2.4 moonbitqrcode —— 固定 mask0 + 无 H 的「下限」参考

- lib 公开面：`encode_low/medium/high` = L/M/Q（`LibLevel::H` 外部不可构造，MoonBit 判 read-only），
  且内部 `Plan::new(v, cl, Mask::of_int(0))` **固定 mask0、不做择优**；版本仅自动最小。
- 结果每模块 0.07µs 为全库最低——**原因正是跳过了 8 轮择优**（约一个量级的择优成本），以及只用
  小版本 V2。这与「生成质量（自动择优）」不对等，**不能解释为它比本仓库快**。
- 若要公平比择优：须走其 `src/coding` 的 Plan + 择优通路（非 lib 稳定公共面），落地需另核其公开性
  （S9d 方案 §6 风险 2 命中）。

---

### 3. 生态包可比性硬约束（实测核实汇总）

| 包 | 强制版本 | 强制 ECL | mask 择优 | 完整 Format/版本 | 容量/自动口径 | 可比性 |
|----|:--:|:--:|:--:|:--:|:--:|:--|
| qrc | 有 API 但路径无择优/Format | 有 | 仅自动路径有 | 仅自动路径有 | ⚠️ 疑似 bytes/bits bug | ❌ 不可对齐 |
| moonqr | ✅ | ✅ H | ✅ | ✅ | ✅ | ✅ 可比 |
| moonbitqrcode | ❌ lib 仅自动 | ⚠️ 仅 L/M/Q | ❌ 固定 mask0 | ✅(Plan) | ✅(Q 档) | ❌ 仅参考下限 |

> 注：本表把 S9d 方案 §6 的「待落地核」全部落实为实证结论；后续若生态包修复（qrc 容量单位、
> moonbitqrcode 开放 H/择优），再重跑本记录总表即可对齐。

---

### 4. 结论与建议

1. **排名（可对齐子集）**：本仓库 > moonqr（快 2.5–4.1×，V03→V40 全程）。
2. **参考口径**：moonbitqrcode 是「固定 mask0 + 小版本」下限（0.046ms/单次 20B），不代表完整质量；
   qrc 自动口径疑似容量 bug、强制口径管线不全，均不可作为基准。
3. **生态启示**：moonqr 是本仓库当前最直接的同类对手；生态库多偏「教学/最小实现」（qrc README 自述
   demo、moonbitqrcode 固定 mask0），**完整自动择优 + 多版本 + 可强制 ECL 的可用实现尚不多**——本仓库
   的完整性与性能都有生态价值。
4. **后续**：S9b T3（score 减趟）落地后重跑总表看对 moonqr 差距收窄；生态包版本升级后按 §3 复核可对齐性。

---

### 5. 门禁与参考

- 本记录纯跑测 + 文档；lib/scripts 未改；门禁沿用 S9d 实现记录 §5（109 全绿 + 双后端 release）。
- 前置/方案/首跑：本文件「实现方案」部分、
  本文件「实现记录」部分
- 层② 同尺子：[S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)
- 生态包：`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、`PaiGack/moonbitqrcode@0.1.0`（mooncakes）

---

## 专题分析：moonbitqrcode 快速原因与产物对比

> 承接 本文件「详细分析」部分
> （全库性能总表）与 本文件「实现记录」部分。
> 本文回答两件事：**① moonbitqrcode 0.1.0 为什么「最快」（0.046ms/次，每模块 0.074µs）**——逐行读源码
> 归因；**② 记录四库对同一输入的真实产物并交叉对比**（尺寸、结构行、能否被第三方解码器 moonqr decode
> 读回）——确认「快」不等于「可用」，并给出各库产物质量结论。
> 日期：2026-09-06　｜　范围：纯源码研读 + 跑测 + 文档；本仓库 lib 未改；门禁 109 全绿。

---

### 0. 一句话结论

- **moonbitqrcode 快的原因（源码级）**：它在 lib 公开层**固定 mask0、不跑 8 轮择优/评分**，且
  只做**自动最小版本**（20B@Q → V2，25×25=625 格）——择优是其他库（本仓库/moonqr）自动路径的
  **主要成本**（S9b：V40H 择优 ≈86% 单次 auto），跳过它自然一个量级地快；其余管线（RS、放置、
  Format）并不比别家少。**它测的是「不择优的小码」成本，不是同语义完整码成本。**
- **产物对比（用 moonqr 解码器交叉读回）**：
  | 库 | 产物尺寸 | 结构 | moonqr 解码读回 |
  |----|---------|------|:---:|
  | 本仓库 V03H | 29×29 | 标准（Format/版本/mask 择优齐全） | ✅（见 S9c 层② sha256 = fast_qr 参考） |
  | moonqr auto-H | 29×29 | 标准 | ✅ 读回输入（v=3） |
  | moonbitqrcode auto-Q | 25×25 | 标准（固定 mask0 但可解码） | ✅ 读回输入（v=2） |
  | qrc auto-H | 25×25 | ⚠️ **V2 < 最小 V3，疑似容量单位 bug** | ❌ 解码失败 |
  | qrc forced V3H | 29×29 | ⚠️ 缺 Format/mask（README 自述、代码核实） | ❌ 解码失败 |
- 结论：moonbitqrcode 的「快」来自**少做了择优 + 小版本**，且其产物**可解码**（质量 OK，只是不择优）；
  qrc 的「居中快」则建立在**产出不可解码码**上——生态内目前**可对齐同口径对比的只有 moonqr**。

---

### 1. moonbitqrcode 为什么快（源码逐层归因）

> 源码：`PaiGack/moonbitqrcode@0.1.0`（rsc.io/qr 移植）。
> `src/lib/qr.mbt` → `encode` → `src/coding/plan.mbt`（Plan::new/vplan/fplan/lplan/mplan + encode）。

#### 1.1 lib 层：固定 mask0、无择优（决定性原因）

```moonbit
// src/lib/qr.mbt:97
let p = @coding.Plan::new(v, cl, @coding.Mask::of_int(0))  // ← 固定 mask 0
let code = p.encode([enc])
```

- `Mask::of_int(0)` = **固定 mask 0**：`Plan::encode` 后只做一次 `mplan(p, mask0)` 应用，
  **没有** `for mask in 0..8 { apply+score }` 的择优循环。
- 对比：
  - 本仓库/moonqr 自动路径：8 轮 `apply_mask+score` 选最低分（S9b 成本模型：V40H 择优 ≈6.86ms /
    单次 auto 7.99ms ≈ **86%**）。
  - moonbitqrcode：0 轮择优 → 直接省掉约一个量级的「评分主循环」。
- **量级旁证**：本仓库 S9b 固定 mask 路径 V40H ≈1.13ms vs auto ≈7.99ms —— 即「有没有择优」本身就是
  ~7× 差距来源；moonbitqrcode 与同尺寸择优库的差距同理。

#### 1.2 版本策略：只做自动最小版本（小矩阵 → 更少格）

- `encode` 只在**最小适配版本**停（`src/lib/qr.mbt:86-92`）：20B@Q → V2（25×25=625 格）。
- 本仓库/moonqr 做 H 档 → V3（29×29=841 格）。同样输入、仅因 ECL/尺寸差异，moonbitqrcode 的工作格数
  就少 ~26%；但这不是它快的主因，**主因仍是 1.1 的免择优**。

#### 1.3 其余管线并非更省（避免误读）

- RS 纠错、位流打包、放置（zigzag）、Format/版本信息、`add_check_bytes` 一应俱全（`plan.mbt`
  `vplan/fplan/lplan/mplan/encode/add_check_bytes`）——**不是「残缺所以快」**。
- 数据面也是逐模块判定 + 位运算，与别家同量级；故把速度全归给「免择优」是准确的。

#### 1.4 总结（一句话）

> moonbitqrcode 快 = **固定 mask0（跳过 8 轮择优）+ 自动最小版本（小矩阵）**；产物仍可解码
> （§2），只是 mask 非最优、ECL 仅到 Q、无法强制版本——它是「最小可行编码器」，不是「同口径快手」。

---

### 2. 各库产物记录与对比（同输入 `https://example.com/`）

#### 2.1 方法：产物 → RGBA → moonqr decode 交叉读回

- 各库产物矩阵栅格化（1 module=4px、margin 16px、黑 30/白 220）→ RGBA Bytes →
  交给 **moonqr 的 `decode`**（与生产方无关的第三方解码器）尝试读回文本与版本。
- 本仓库产物已由 S9c 层② 与 **fast_qr-wasm32 逐位 sha256 一致**（那是生产级 Rust 库）作等效性确认，
  此处不再重复喂解码器。

#### 2.2 产物记录表

| 库/路径 | ECL | 版本/SIZE | 结构要点（实码核对） | moonqr 解码 |
|--------|-----|----------|---------------------|:---:|
| 本仓库 V03H | H | V3 / 29 | Format/版本/mask 择优齐全（与 fast_qr-wasm32 sha256 一致） | ✅（层②已证） |
| moonqr auto-H | H | V3 / 29 | 完整（self decode v=3） | ✅ 读回输入 |
| moonbitqrcode auto-Q | Q | V2 / 25 | 完整但固定 mask0（self decode v=2） | ✅ 读回输入 |
| qrc auto-H | H | **V2 / 25** | ⚠️ V2 < 最小 V3（疑似容量单位 bug） | ❌ FAIL |
| qrc forced V3H | H | V3 / 29 | ⚠️ 缺 Format/mask（README 自述 + 代码核实） | ❌ FAIL |

#### 2.3 结构行抽样（佐证「完整 vs 不完整」）

- 功能图案行（第 6 行 = timing）：本仓库与 moonqr 均为标准 `1111111010101010…`；qrc 强制 V3 同位置
  内容明显偏离标准布局。
- Format 行（第 8 行）：本仓库与 moonqr 均含真实 Format（位置掩码异或后图案）；qrc 强制路径该区域
  为占位/空（无真实 Format 写入）——与其「No format information」自述一致。
- 结论：**qrc 两类产物都无法被 moonqr 解码** → 目前 qrc 0.1.1 不产出「可用的完整 QR」；其性能数字
  只代表内部管线成本，不能当生成可用码的性能。

#### 2.4 质量/「快」的解释边界

| 库 | 快但少做了什么？ | 产物可用？ |
|----|----------------|:---:|
| moonbitqrcode | 固定 mask0（不择优）+ 只到 Q + 只自动版本 | ✅ 可解码（mask 非最优） |
| qrc | 自动版本疑似容量 bug / 强制路径缺 Format+mask | ❌ 当前不可解码 |
| moonqr | （对照）完整择优 + 可强制版本 | ✅ |
| 本仓库 | （对照）完整择优 + 可强制版本 + 与 fast_qr 参考逐位一致 | ✅ |

---

### 3. 结论

1. **moonbitqrcode 快 ≠ 算法更优**：快在「固定 mask0 免 8 轮择优 + 自动最小版本」，产物可解码但
   mask 非最优、能力面窄（仅 L/M/Q、无强制版本）。要与择优库比，须走其 `src/coding` 的择优通路
   （非 lib 稳定面）。
2. **生态质量现状**：四库中「完整择优 + 可强制版本 + 产物可解码」目前只有本仓库与 moonqr；qrc 0.1.1
   产物不可解码（容量单位 bug + 缺 Format/mask），moonbitqrcode 仅最小可用。→ 本仓库的完整性与性能
   是生态里有区分度的部分。
3. **后续**：若想给 moonbitqrcode 一个「公平的择优版」数字，可 fork/走 coding.Plan 择优后重测
   （参考 S9b 固定 vs auto 的 ~7× 差异作量级预期）；属可选，非本仓库义务。

---

### 4. 门禁与参考

- 纯源码研读 + 跑测 + 文档，本仓库 lib 未改；`moon fmt --check` / `moon check --deny-warn` /
  `moon test`（109 全绿）与双后端 release 构建不受影响。
- 前置：S9d 本文件「详细分析」部分 / 本文件「实现方案」部分；
  层② sha256 基准 [S9c-性能测试与fast_qr-wasm对比.md](./S9c-性能测试与fast_qr-wasm对比.md)；
  择优成本模型 [S9b-性能优化.md](./S9b-性能优化.md)
- 生态包源码（mooncakes 检出）：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、
  `PaiGack/moonbitqrcode/src/coding/plan.mbt`；`bobzhang/qrc/qrc.mbt`；`naoto24kawa/moonqr`（decode 作
  交叉读回工具）

---

## 专题分析：moonbitqrcode 固定 mask0 缺陷与主流对比

> 承接 本文件「专题分析：moonbitqrcode 快速原因与产物对比」部分
> （moonbitqrcode 0.1.0 快的原因：lib 固定 `Mask::of_int(0)` 免 8 轮择优 + 自动最小版本）。
> 本文补两个问题：**① 固定 mask0 到底「缺」了什么（缺陷）；② 为什么主流 QR 编码方案不做固定 mask，
> 而做 8 掩码评分择优**。方法 = 源码级核实（moonbitqrcode ↔ 其参考 rsc.io/qr）+ ISO/IEC 18004 语义 +
> 主流库做法对照。
> 日期：2026-09-06　｜　范围：纯分析 + 文档，本仓库 lib 未改。

---

### 0. 一句话结论

- **固定 mask0 不是「编码错误」**：QR 规范允许任意掩码（格式信息区会写明用了哪个），moonbitqrcode
  产物**可解码**（上篇已用 moonqr decode 读回 ✅）。它是**质量/鲁棒性取舍缺失**。
- **它缺的是「掩码评价」**：ISO/IEC 18004 定义 4 条惩罚规则（N1 同色连、N2 2×2、N3 类 Finder 图案、
  N4 明暗比例），编码器应**跑 8 个候选掩码 → 挑惩罚分最低者**，让矩阵更难被低质量扫描误读。
  固定 mask0 等于**跳过这个决策**，可能得到「恰好难读」的码。
- **为什么主流不做固定 mask**：因为 QR 的主要风险在**解码端**（污损/低对比/镜头畸变/小尺寸），
  掩码择优是编码端**几乎免费**就能给出的鲁棒性余量；从 ISO、zxing、qrcodegen 到 fast_qr/moonqr 的
  默认路径全做择优。rsc.io/qr（moonbitqrcode 参考）是少数以「最小实现」为目标的库，源码里自己都留了
  `// TODO: Pick appropriate mask.`——**固定 mask0 是继承自参考库的「未完成项」，不是有意设计。**

---

### 1. 缺陷是什么（源码核实 + 规范语义）

#### 1.1 moonbitqrcode 实际做了什么

```moonbit
// src/lib/qr.mbt:97 —— lib 层写死 mask0
let p = @coding.Plan::new(v, cl, @coding.Mask::of_int(0))
```

- `Plan::encode` 只应用一次 mask0（`mplan`）；**全库无 penalty/score/choose_best 任何函数**
  （已 grep 核实 `src/coding/*`、`src/lib/qr.mbt` 无评分逻辑）。
- 底层其实**支持 8 种掩码**（`Mask::M0..M7`，`pixel.mbt`），`Plan::new` 也可收任意 mask——
  但没有「择优」环节把它用起来。即：**有能力、缺策略**。

#### 1.2 参考库 rsc.io/qr 也一样（忠实移植，非移植丢功能）

`github.com/rsc/qr`（Go）`qr.go`：

```go
p, err := coding.NewPlan(v, l, 0)   // mask = 0 固定
...
// TODO: Pick appropriate mask.      // ← 作者自留 TODO
```

- rsc.io/qr 自称 **"Basic QR encoder"**（README），且其测试里比对的是 **C libqrencode** 的封装——
  libqrencode（业界常用 C 库）**是有掩码择优的**；rsc.io/qr 自己却始终 mask0。
- **结论**：moonbitqrcode 固定 mask0 = **忠实移植 rsc.io/qr 的未完成择优 TODO**，属「继承缺陷」，
  不是移植时丢功能。

#### 1.3 固定 mask0 可能造成的坏结果（风险，非必然）

QR 掩码的目的是打散数据区图案，避免解码器误判。固定 mask0 意味着：对某些数据/版本，最终矩阵
**恰好保留** ISO N3 想惩罚的「类 Finder 长图案」、过长同色游程、或极端明暗比例——从而：

- 扫描容差下降：低对比/运动模糊/镜头畸变/小尺寸打印时，本可解码的码更容易失败；
- 与解码器（尤其手机相机、工业扫描）的「最坏情况」预期不符；
- 同一内容在不同库下鲁棒性不一致（moonbitqrcode 会比做择优的库更容易踩到难读样本）。

> 注意：这**不是「一定坏」**——干净、高对比、无畸变场景下 mask0 也能扫；因此上篇用 moonqr decode
> 读回成功，两者不矛盾。缺陷是**没有兜底最坏情况**。

---

### 2. 主流为什么做 8 掩码评分择优

#### 2.1 规范层面（ISO/IEC 18004）

- 标准并不强制「必须挑最低分」——但它定义 N1–N4 惩罚规则 + 要求写 Format 掩码号，意图就是**引导
  编码器去选一个对解码更友好的掩码**。不做择优 = 放弃规范提供的质量工具。
- 格式信息区（Format Info）本身包含 3-bit 掩码号 → 解码器能识别任意掩码；所以固定 mask0 能解，
  **但规范给的「择优推荐」被跳过**。

#### 2.2 主流库做法（对照）

| 库 | 掩码策略 | 说明 |
|----|---------|------|
| fast_qr（本仓库对照的 Rust 参考，v0.14.0） | 8 轮 clone+mask+score 择优 | `placement.rs` 默认 `mask=None` 即择优 |
| 本仓库 fast_qr_moonbit | 8 轮择优（S5） | 与 fast_qr 参考逐位一致 |
| moonqr（naoto24kawa） | 自动择优（choose_mask） | encode 默认择优 |
| zxing / qrcodegen / 多数开源 | 8 掩码打分取最优 | 业界默认 |
| libqrencode（C） | 有择优（rsc.io/qr 用它做测试参考） | 业界常用 |
| **moonbitqrcode / rsc.io/qr** | **固定 mask0（TODO 未完成）** | 少数「最小实现」特例 |

#### 2.3 为什么不「固定一个」就够（经济性视角）

- 择优的成本是**常数级**：8 轮 × 评分，对任何数据都是一次性、与版本面积成正比，但**换来的是所有
  数据上的最坏情况鲁棒性**。
- 固定 mask 的问题在于：**你不知道哪份数据会踩雷**——QR 内容千变万化，一个固定掩码不可能对所有
  内容都恰好友好；择优是把「运气」变成「保证」的机制。
- 因此主流把择优做成**默认**（而非可选优化），用户无需懂掩码也能拿到尽量可读的码。

---

### 3. 对本仓库/生态的含义

1. **不要因 moonbitqrcode 快就模仿固定 mask0**：它快在「少做择优」，代价是放弃最坏情况鲁棒性。
   本仓库/moonqr 的择优成本已在 S9b 成本模型中量化（V40H ≈86% 单次 auto 在择优）——但这是**质量的
   必要成本**，是「生成尽量可读码」的默认行为。
2. **若想给 moonbitqrcode 补择优**：其底层 `Mask::M0..M7` + `Plan::new(v,l,mask)` 已支持任意掩码，
   缺的只是一段「8 轮评分取最低」的封装（可参考 S9b N1–N4 评分或移植自 libqrencode/zxing 评分）；
   属生态贡献方向，非本仓库义务。
3. **对比口径提醒**：任何「moonbitqrcode 比择优库快」的结论，必须注明它**没做择优**；同口径公平对比
   应给它加择优后再比（详见快速原因分析 §1）。

---

### 4. 结论

- 固定 mask0 缺陷 = **放弃掩码择优带来的最坏情况解码鲁棒性**，不是「编不出合法码」。
- 主流不采用固定 mask = 择优是「小成本大保险」的默认质量机制，ISO 与业界一致推荐；
  固定 mask0 是 rsc.io/qr 这类「最小实现」的自留 TODO，moonbitqrcode 忠实继承之。
- 本仓库沿用择优是正确的；生态内可用对照仍以 moonqr 为准。

---

### 5. 参考

- 快速原因/产物对比：本文件「专题分析：moonbitqrcode 快速原因与产物对比」部分
- 全库性能与可比性：本文件「详细分析」部分
- 本仓库择优实现/成本：[S9-性能基准.md](./S9-性能基准.md)（mask 自动择优）、
  [S9b-性能优化.md](./S9b-性能优化.md)（择优占 V40H ≈86%）
- 源码核实：`PaiGack/moonbitqrcode/src/lib/qr.mbt`、`src/coding/plan.mbt`、`src/coding/pixel.mbt`
  （无 penalty/score 函数；lib 固定 mask0）；`github.com/rsc/qr` `qr.go`（`NewPlan(v,l,0)` +
  `// TODO: Pick appropriate mask.`、README "Basic QR encoder"、libqrencode 测试对照）
- ISO/IEC 18004（掩码与 N1–N4 惩罚规则语义，作为规范背景）

---
