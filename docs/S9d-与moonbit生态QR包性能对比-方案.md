# S9d · 与 moonbit 生态 QR 包（qrc / moonqr / moonbitqrcode）性能对比 · 实现方案

> 承接 [S9-性能基准-实现记录.md](./S9-性能基准-实现记录.md)（层① 基准载体 `cmd/bench`）、
> [S9c-性能测试与fast_qr-wasm对比-实现记录.md](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)
> 与 [S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)
> （层② Rust fast_qr-wasm32 跨语言对比）。本方案把对比视野从「跨语言 vs Rust fast_qr」扩到
> **同语言 vs moonbit 生态现有 QR 包**：`qrc`（bobzhang/qrc）、`moonqr`（naoto24kawa/moonqr，
> 即 elchika-inc/moonqr 的 MoonBit 内核）、`moonbitqrcode`（PaiGack/moonbitqrcode，rsc.io/qr 移植）。
> 交付 = 可复跑性能对比脚本方案（环境 → 依赖 → 构建 → Node/moonrun 驱动 → 计时表）。
> 日期：2026-09-06　｜　范围：**方案文档 + 依赖/脚本文件级清单；本文不改本仓库 lib/scripts 代码**
> （落地另立实施任务）。对比结果预期：moonbit 生态包同为 MoonBit 源码，可**同一工具链同后端**编译，
> 计时宿主与层② MoonBit 侧一致（moonrun 子进程），比层②跨语言对比更干净。

---

## 0. 一句话结论

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

## 1. 背景与目标

### 1.1 为什么做（承接 S9 系列）

- S9/S9b/S9c 已把「性能透明对比」做到**跨语言 vs Rust fast_qr-wasm32**（层②）：数字 0.304/1.162/9.01ms
  vs 0.061/0.335/3.18ms（边际，见 S9c 详细分析 §2），fast_qr-wasm32 快 2.8–5.0×。
- 但 moonbit 生态已有若干 QR 包；**同语言生态包对比**回答的是不同问题：同为 MoonBit 源码、同一工具链
  同一后端时，本仓库实现相对生态现成包的**纯实现效率位次**（排除语言/运行时差异，只剩算法与工程差异）。
- 该位次直接关系到本仓库对外的**可替代性话术**（用户为何选 fast_qr_moonbit 而非 qrc/moonqr/...），
  是 S9 系列「透明对比」的自然延伸（roadmap S9 行「无硬门槛」精神一致）。

### 1.2 对比对象（已核实的事实，2026-09-06 实测）

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

### 1.3 与层②口径的异同

| 维度 | 层②（S9c，fast_qr-wasm32） | 本方案（moonbit 生态 3 包） |
|------|---------------------------|---------------------------|
| 对比双方 | Rust wasm32 vs MoonBit wasm | MoonBit vs MoonBit（本仓库 vs 3 包） |
| 编译 | fast_qr 用 rust+wasm-bindgen（外部检出） | 三包均 `moon add`（mooncakes），与本仓库同 moon 工具链 |
| 宿主 | Node 进程内(fast) vs moonrun 子进程(MoonBit) | **统一 moonrun 子进程**（同进程形态差异消失） |
| 对齐 | 逐位对齐 sha256（跨宿主重确认） | **不要求逐位对齐**（三包算法细节/表实现独立；只做「同尺寸 + 同输入 + 同 ECL」的**行为烟测**与计时） |
| 产物 | fast_qr wasm-bindgen nodejs 产物 | moon 构建 wasm 产物 |

---

## 2. 方案总览（文件级）

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

## 3. 详细设计

### 3.1 基准协议（对齐 S9/S9c，尽量同口径）

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

### 3.2 四方驱动形态（关键差异：各包 API 不同）

| 方 | 调用入口 | 备注 |
|----|---------|------|
| 本仓库 | `@lib.QRBuilder::from_string(input).ecl(H).version(Vxx).build()` | 与 cmd/bench 完全同构，直接复用逻辑 |
| qrc | `@qrc.encode_with_mode_and_ec(input, @qrc.Mode::Byte?, ver, @qrc.make_ec_level_h())`（强制版本）或 `encode_with_ec`（自动版本） | 强制版本需 Mode 参数；**mode 用 Byte 对齐本仓库字节语义**（落地核 `Mode::Byte` 构造通路） |
| moonqr | `@mq.encode(input, @mq.EcLevel::H, Some(ver))` | 直接支持强制版本；返回 `Matrix?` |
| moonbitqrcode | lib `encode`（仅自动版本）或 `@cod.Plan::new(ver, level, mask)+encode` | 若走 lib 则只能自动最小版本 → **与三基准点不匹配**；故优先 `src/coding` 强制版本通路，落地核可见性 |

> 因为 4 方 API 无法 100% 同构，**驱动 main 为每方各写一段适配调用**（switch by argv[1]），循环/消费/
> 输出逻辑共用同一段模板——保证「计时部分同构、只有真实编码调用不同」。

### 3.3 输出

每行：`<方> <点> <N> ok=<N> builds size=<边长> checksum=<int>`，末尾 `TOTAL_CHECKSUM=<int>`。
汇总脚本产出 markdown 表：
`| 方 | 点 | 逐位对齐n/a | 尺寸校验 | 最小整程(ms) | 边际单次(ms) | 每模块(µs) | 相对本仓库 |`

> 边际单次/每模块 = 整程/N 与 /(N×边长²)，口径沿用 S9c 详细分析（**只比同点同 N**；不做 N 扫描 LSQ 的
> 首版可省，若要「启动开销分离」再叠加 N 扫描，标为二期可选）。

---

## 4. 落地清单与验收

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

## 5. 预期产出（量级参考，不承诺；以实际跑测为准）

预期 4 方 V40H 边际成本在 **2–10ms 量级**、V03H 在 **0.1–1ms 量级**；本仓库相对 3 包的具体位次与差距
**由实测给出**（不预设结论）。若 moonbitqrcode 只能走「固定 mask0」口径，其数字会比「择优」方偏低，
表中以「(固定 mask0)」标注并**不与择优方直接排名**，仅作参考下限。

---

## 6. 风险与不确定点（落地前需核）

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

## 7. 参考

- 层②方法与口径：[S9c-性能测试与fast_qr-wasm对比-实现记录.md](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)、
  [S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)
- 基准载体/口径：[S9-性能基准-实现记录.md](./S9-性能基准-实现记录.md)、
  [S9-性能基准-实现评估与优化-记录.md](./S9-性能基准-实现评估与优化-记录.md)
- 生态包（mooncakes/仓库，2026-09-06 访问）：
  `bobzhang/qrc@0.1.1`（github.com/bobzhang/qrc）、`naoto24kawa/moonqr@0.2.0`
  （github.com/elchika-inc/moonqr）、`PaiGack/moonbitqrcode@0.1.0`（github.com/PaiGack/moonbit-qr）
- 实测事实：三包 `moon add` 成功、wasm-gc/wasm 均编译通过；qrc/moonqr 可强制版本；moonbitqrcode lib
  固定 mask0/自动版本、coding 层含 Plan（可见性待落地核）
