# MoonBit 工具链版本与特性适配评估（moonc v0.10.14 / `moon 0.1.20260920`）

> **状态**：现行　｜　日期：2026-09-23　｜　索引：[docs/README.md](../README.md) §6
> 承接：[moonbit-工具链与构建-setup-分析.md](moonbit-工具链与构建-setup-分析.md)（安装/构建面）·
> [S11c 第 6 轮体检](../02-证据/S11c-第6轮体检-工具链漂移与门禁假绿修复.md)（`dev79`/`dev25` 的首次适配）
> 一句话结论：**本仓库当前 `moon` 已在最新稳定版**（`latest` 通道解析即 `0.1.20260920`）；
> v0.10.14 的语言/工具链变更中，**两条会阻断 `--deny-warn` 的告警已在 S11c 处置**，
> 本轮无阻断级回归，识别出 **1 处口径订正（必须）+ 2 类待决项（评审后定）**。

> 本文回应：「搜索网络文档 MoonBit 最新版本/特性 → 评估本仓库如何适配 → 详细分析 → 生成/更新文档」。
> 方法：**官方动态 + 实测探针**（隔离 `MOON_HOME` 装 `latest` 复现、`moon check --warn-list +a` 暴露潜伏告警），
> 每条结论附复跑命令；**不升级工具链**（已在 latest）、**不改公共 API**、**不引入新后端**。

---

## 1. 议题定义（要回答什么）

| # | 问题 | 判据 |
|:-:|------|------|
| Q1 | 本仓库工具链距最新版有多远？ | `moon version` vs `latest` 通道实测 |
| Q2 | v0.10.14 的语言/工具链变更，哪些会**影响本仓库**？ | 逐条映射到「是否命中本仓代码/配置/脚本」 |
| Q3 | 已适配项是否仍然成立？ | 在当前工具链下重跑 `--deny-warn` / `test` |
| Q4 | 有没有**潜伏**（默认关闭）的告警会被将来默认开启砸中？ | `moon check --warn-list +a` 全量告警直方图 |
| Q5 | 新 CLI 能力（`search`/`view`/`deprecate`/`tree --package`）要不要接入？ | 与本仓「发布/审计」流程的契合度 |

**明确不做**：不追 `nightly`/`dev`；不把默认关闭的告警一次性全开（见 §4.2）；不改 `lib/` 公共面。

---

## 2. 版本核验（实测，2026-09-23）

官方动态（[MoonBit 更新日志 20260921](https://moonbitlang.cn/updates/2026/09/21/index)）：
**moonc `v0.10.14`**，含语言层 8 项、工具链 10+ 项、标准库与生态多项。

本仓库实测（隔离安装，不污染现有 `~/.moon`）：

```bash
# ① 本机版本
export PATH="$HOME/.moon/bin:$PATH" && moon version | head -1
# -> moon 0.1.20260920 (914d7da 2026-09-20)   Feature flags: rr_moon_mod,rr_moon_pkg

# ② 隔离 MOON_HOME 装 latest（脚本在 moon 已在 PATH 时会提前退出，不改 shell rc）
curl -fsSL -o /tmp/moon_install.sh https://cli.moonbitlang.cn/install/unix.sh
MOON_HOME=/tmp/moon-latest bash /tmp/moon_install.sh latest
/tmp/moon-latest/bin/moon version | head -1
# -> moon 0.1.20260920 (914d7da 2026-09-20)   ← 与 ① 相同

# ③ 生态侧版本（新 CLI 能力实测）
/tmp/moon-latest/bin/moon view TryAndRun-TvT/fast_qr_moonbit --versions
# -> 0.1.1 / 0.1.0
```

**结论 Q1**：`latest` 通道当前解析到 **`0.1.20260920`**，与本仓库所用**完全一致**——
本仓库**没有版本落后**，适配问题只在「特性/告警」层面，而非「版本升级」层面。
（`moonc` 编译器的 `v0.10.14` 与 `moon` 构建工具的 `0.1.<日期>` 是**两条版本线**，勿混。）

---

## 3. 特性逐条评估

> 逐条来自官方 20260921 更新日志；「相关性」列基于对本仓 `moon.mod` / `moon.pkg` / `lib/**` / `cmd/**` 的**实测扫描**。

| # | 官方变更 | 本仓库相关性（实测） | 判定 | 动作 |
|:-:|----------|---------------------|:----:|------|
| L1 | 未使用包告警**扩展**（显式 import core 未用；仅经方法间接使用） | `cmd/bench` 显式用 `@env.args` / `@string.parse_int`；其余包无 core import。`check --deny-warn` **绿** | ✅ 已满足 | 无 |
| L2 | `var x = 10` 提示改 `let mut` | 全仓 `lib/`+`cmd/` **零 `var` 声明**（grep 实测） | ✅ 已满足 | 无 |
| L3 | `impl` 自动提升为方法的告警**默认开启**（`dev79`） | S11c 已在 `lib/moon.pkg` 落 `warnings = "-79"`（`.mbti` 逐字节不变） | ✅ 已适配 | 保持 |
| L4 | 黑盒测试隐式导入定义的告警**默认开启**（`dev25`） | S11c 已将 8 个 `*_test.mbt` 全量改 `@lib.`（382 处）；`check` 绿 | ✅ 已适配 | 保持 |
| L5 | 切片 `a[i:j]` 改为**边界钳制视图**（不再 panic），旧语义迁 `exact_view` | 全仓**无 `a[i:j]` 切片**（grep 实测） | ➖ 不相关 | 无 |
| L6 | **Deprecate** 在 JS FFI 边界使用 `Array`（改用 `FixedArray`） | `cmd/host-probe` 的 FFI 面只有 `String`/`Int`；无 `Array` 跨界 | ➖ 不相关（**待观察**） | 见 §4.2 |
| L7 | `enum` 新增 `#non_exhaustive` 标记 | 本仓未使用；公共枚举（`ECL`/`Version`/`Mode`/`Mask`/`ModuleType`/`Shape`）刻意**穷尽** | 🚫 **明确不采用** | 无 |
| L8 | `for...in` 支持模式匹配解构 | 热路径刻意用 `while`+索引（性能取向，S9 系列）；`for...in` 仅零星 | 🔸 可选 | 不做 |
| T1 | 新增 `moon search` / `moon view` / `moon deprecate` | 已可用（实测）；`view` 已用于 §2 取证 | ✅ 接入 | 见 §4.1 |
| T2 | `moon tree --json` / `--package` | 实测 `--package` 输出内部包依赖图；本模块**零外部依赖** | 🔸 可选 | 见 §6 |
| T3 | `moon runwasm` 废弃；`moonx --target native` 废弃 | 全仓**无 `runwasm`/`moonx` 调用**；`native` 本就未纳入 | ➖ 不相关 | 无 |
| T4 | `.mbtx` 脚本 / 实验性预构建脚本 | 本仓无脚本化需求（CI 已移除，门禁走 `scripts/*.sh`） | ➖ 不相关 | 无 |

**结论 Q2/Q3**：**无阻断级影响**——两条「默认开启告警」（L3/L4）在 S11c 已处置，
其余或已满足、或与本仓无关；`check --deny-warn` 全绿（见 §5）。

---

## 4. 待适配项（本轮识别）

### 4.1 【P0·口径订正】`moon deprecate` 已存在，文档「无法撤回」的表述需补口径

**实测**：

```bash
moon deprecate --help
# -> Deprecate or restore all existing versions of a published module
#    用法: moon deprecate [OPTIONS] <MODULE>   （--reason 弃用 / --undo 恢复 / --dry-run 预览）
#    注意: "Specify the full module name without a version selector."
#          "Versions published later start undeprecated."
#          "Restoring ... does not recover previous per-version states."
```

**与现仓库文档的冲突**（`grep` 实测命中）：

| 位置 | 现表述 | 问题 |
|------|--------|------|
| `docs/03-过程/mooncakes-发布方案.md` §5.4 | 「官方文档未给出 `yank`/撤回命令」 | 现在**有** `moon deprecate`（模块级） |
| 同上 §7 风险表 R5 | 「官方文档未给 `yank` 命令」 | 同上 |
| `docs/03-过程/mooncakes-发布阻塞项3-4-落地方案.md` | 「未给出 `yank`/撤回命令（实测 `moon publish --help` 无）」 | 判据取错了命令（应为 `moon --help` 的 `deprecate` 子命令） |
| `scripts/publish.sh` ⑤ 提示 | 「官方文档未提供 yank/撤回命令 ⇒ 一旦发布不可撤回」 | 同上 |
| `scripts/publish-check.sh` 头注释 | 同上 | 同上 |

**订正口径（精确，勿简化为「可以撤回」）**：

- `moon publish` **仍无按版本撤销**（无 per-version yank/delete）；
- `moon deprecate <module>` 只能**整模块**标记弃用/恢复（所有已发版本），
  且「弃用不影响版本选择，仅在依赖解析时告警」；
- 因此「发布前门禁必须可执行」的前提**不变**（错版本发出去不能单独撤）。

> 该项为**事实性订正**，不改变发布流程与门禁行为；处置见 §6。

### 4.2 【P1·待决】默认关闭的告警：`0073` / `0074`

用「开全部告警」暴露潜伏项（S11c 曾用 `--warn-list +74` 同法）：

```bash
moon check --warn-list +a 2>&1 | grep -oE 'Warning: \[[0-9]+\]' | sort | uniq -c | sort -rn
# -> 348 Warning: [0073]   # unnecessary_annotation
# ->  13 Warning: [0074]   # missing_doc
```

**`0073 unnecessary_annotation` × 348**（默认关闭，故当前门禁不报）。分布（行数 Top）：

| 文件 | 处数 | 文件 | 处数 |
|------|:----:|------|:----:|
| `lib/fast_qr_moonbit_test.mbt` | 73 | `lib/s7_svg_test.mbt` | 14 |
| `lib/m1_snapshot_test.mbt` | 55 | `lib/s7_terminal_test.mbt` | 12 |
| `lib/s6_snapshot_test.mbt` | 42 | `lib/internal/matrix/module.mbt` | 7 |
| `cmd/bench/main.mbt` | 33 | `lib/svg.mbt` / `lib/qr_builder.mbt` | 5 / 5 |
| `lib/t4a_property_test.mbt` | 32 | `README.mbt.md` | 2 |
| `lib/s6_decode_vectors_test.mbt` | 20 | `lib/qr_build.mbt` 等其余 | 各 1–4 |
| `lib/qr_builder_test.mbt` | 20 | | |
| `lib/fast_qr_moonbit_wbtest.mbt` | 17 | | |

- **主因**：类型已知处的**冗余路径前缀**，如 `@lib.ECL::Q` / `@lib.Version::V40` / `@lib.Mode::…`
  （`@lib.ECL::` 94、`@lib.Version::` 90、`@lib.Mode::` 77、`@lib.Mask::` 26、`@lib.Shape::` 12）；
  其中**大部分来自 S11c 为修 `dev25` 而批量加 `@lib.` 的机械改写**（限定包名后，枚举路径前缀变冗余）。
- **不擅自全开**：`README.mbt.md` 的 `@lib.ECL::Q` 是**有意可读性**（落地页示例），
  生产 `lib/*.mbt` 里也有若干处；一次性全开会同时触及**示例可读性**与**测试可读性**，
  属「风格取舍」而**非 correctness**，须评审后按范围决定（如：仅测试包开、示例/生产包 `-73`）。

**`0074 missing_doc` × 13**（默认关闭）。分布与已有口径一致
（[发布阻塞项3-4](../03-过程/mooncakes-发布阻塞项3-4-落地方案.md) §4：公共 API **1** 处 + `lib/internal/**` **12** 处）。
本项已在发布方案 B1 立项，本文不重复决策。

### 4.3 【P2·可选】新 CLI 能力接入

| 能力 | 建议 | 备注 |
|------|------|------|
| `moon view <mod> --versions` | **接入**发布后核验（替代手工 `curl` API） | 已在 §2 用上 |
| `moon tree --package` | 可选：作为「零外部依赖」的**可复跑证据** | 实测本模块仅自包依赖 |
| `moon deprecate --dry-run` | 仅在**确需弃用**时用；接入发布文档（见 §4.1） | 属维护者本地动作，不进 CI |
| `moon search` | 选型/竞品检索用；本仓暂无需求 | — |

---

## 5. 已适配项回归（实测证据）

```bash
export PATH="/tmp/moon-latest/bin:$PATH"   # 用隔离装出的 latest（= 同版本）复核
moon check --deny-warn      # -> Finished（门禁绿）
moon check --warn-list +a   # -> 仅 0073 × 348 + 0074 × 13（其余为默认开启项，已 0）
```

- `--deny-warn` 绿 ⇒ S11c 的 `-79`（`lib/moon.pkg`）与 `@lib.` 全量限定**仍然成立**，
  且**默认开启的两条新告警没有在本仓命中**（L3/L4 判定由「配置/代码」而非「记忆」支撑）。
- 默认关闭的 `0073`/`0074` 是**唯一**两类潜伏告警——它们不阻断当前门禁，但若将来默认开启会一次性变红。

---

## 6. 结论与去向

| 项 | 判定 | 去向 |
|----|------|------|
| 版本落后 | **否**（`latest` == 本机 `0.1.20260920`） | 无需升级 |
| L3/L4（`dev79`/`dev25`） | **已适配**（S11c） | 保持；本文 §5 提供复跑证据 |
| L1/L2/L5/L7/L8/T3/T4 | 无影响 / 明确不做 | 记录判定，防重复评估 |
| **§4.1 `moon deprecate` 口径** | **P0 事实性订正** | 已随本文订正发布文档与脚本注释 |
| §4.2 `0073`/`0074` 是否纳入门禁 | **待评审** | 队列：先定「范围」（测试包 / 示例 / 生产包分别处理），再决定是否 `+73` |
| §4.3 新 CLI 接入 | 可选 | `moon view` 已用于核验；其余按需 |

**教训（与 S11c 一脉）**：工具链适配的**真风险不在版本号**（本仓已在 latest），
而在**默认关闭的告警会随版本「转正」**——所以每次工具链升级应同时跑一次
`moon check --warn-list +a`，把「将来会红的东西」提前看见（本仓当前仅 `0073`/`0074` 两类）。

---

## 7. 参考

- 官方更新日志：<https://moonbitlang.cn/updates/2026/09/21/index>（moonc `v0.10.14`）
- 官方构建系统/包管理：[《使用与发布包》](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html)
- 本仓相关：[工具链安装与构建](moonbit-工具链与构建-setup-分析.md) ·
  [S11c 第 6 轮体检](../02-证据/S11c-第6轮体检-工具链漂移与门禁假绿修复.md) ·
  [发布方案](../03-过程/mooncakes-发布方案.md) · [发布阻塞项 3-4](../03-过程/mooncakes-发布阻塞项3-4-落地方案.md)
- 实码：`moon.mod` / 各 `moon.pkg` / `scripts/publish.sh` / `scripts/publish-check.sh`
