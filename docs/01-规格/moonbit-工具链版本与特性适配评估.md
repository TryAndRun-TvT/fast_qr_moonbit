# MoonBit 工具链版本与特性适配评估（moonc v0.10.14 / `moon 0.1.20260920`）

> **状态**：现行　｜　日期：2026-09-23　｜　索引：[docs/README.md](../README.md) §6
> 承接：[moonbit-工具链与构建-setup-分析.md](moonbit-工具链与构建-setup-分析.md)（安装/构建面）·
> [S11c 第 6 轮体检](../02-证据/S11c-第6轮体检-工具链漂移与门禁假绿修复.md)（`dev79`/`dev25` 的首次适配）
> 一句话结论：本仓库 `moon` 已在最新稳定版（`latest` 通道 == `0.1.20260920`），**无版本落后**；
> v0.10.14 的变更里**无阻断级影响**。**第 2 轮自查修正了首版 3 处不严谨/错误**，
> 并识别出**最高优先问题不在「特性」而在「工具链未钉版」**——它让门禁与基准数字不可复现。

> 本文回应两轮要求：①「搜索官方最新版本/特性 → 评估适配 → 详细分析 → 生成文档」；
> ②「**重新思考：上述方案是否存在漏洞？如何优化？** → 更新文档」。
> 方法：**官方动态 + 实测探针**（隔离 `MOON_HOME` 装 `latest`、`moon check --warn-list +a` 暴露潜伏告警、
> `moon.pkg` 告警开关实测）；每条结论附复跑命令。**不升级工具链、不改公共 API、不引入新后端**。

---

## 1. 议题定义

| # | 问题 | 判据 |
|:-:|------|------|
| Q1 | 工具链距最新版多远？ | `moon version` vs `latest` 通道实测 |
| Q2 | v0.10.14 的语言/工具链变更哪些影响本仓库？ | 逐条映射到本仓代码/配置/脚本 |
| Q3 | 已适配项是否仍成立？ | 当前工具链重跑 `--deny-warn` / `test` |
| Q4 | 有无**潜伏**（默认关闭）告警会被将来砸中？ | `moon check --warn-list +a` 直方图 |
| Q5 | 新 CLI 能力要不要接入？ | 与本仓「发布/审计」流程契合度 |
| **Q6** | **本评估自身可信吗？可复现吗？** | **§5 自查**（第 2 轮新增） |

**明确不做**：不追 `nightly`/`dev`；不擅自全开默认关闭告警（见 §4.2）；不改 `lib/` 公共面。

---

## 2. 版本核验（实测，2026-09-23）

官方动态（[更新日志 20260921](https://moonbitlang.cn/updates/2026/09/21/index)）：**moonc `v0.10.14`**。

```bash
# ① 本机 / ② 隔离 MOON_HOME 装 latest（脚本在 moon 已在 PATH 时提前退出，不改 shell rc）
moon version | head -1
curl -fsSL -o /tmp/moon_install.sh https://cli.moonbitlang.cn/install/unix.sh
MOON_HOME=/tmp/moon-latest bash /tmp/moon_install.sh latest && /tmp/moon-latest/bin/moon version | head -1
# ①②均 -> moon 0.1.20260920 (914d7da 2026-09-20)   Feature flags: rr_moon_mod,rr_moon_pkg

# ③ 生态侧（新 CLI 能力）
moon view TryAndRun-TvT/fast_qr_moonbit --versions      # -> 0.1.1 / 0.1.0
```

**结论 Q1**：`latest` 当前解析到 **`0.1.20260920`**，与本仓一致 ⇒ **无版本落后**。
（`moonc` 编译器 `v0.10.14` 与 `moon` 构建工具 `0.1.<日期>` 是**两条版本线**，勿混。）

> ⚠️ 此结论是**快照**：`latest` 会移动，且本评估**未核验** moonc `v0.10.14` 与某个精确 `moon` 版本的对应表
> （CLI 服务只按 `latest`/日期取包）。局限见 §5-H2。

---

## 3. 特性逐条评估

| # | 官方变更 | 本仓库相关性（实测） | 判定 | 动作 |
|:-:|----------|---------------------|:----:|------|
| L1 | 未使用包告警**扩展**（显式 import core 未用；仅经方法间接使用） | `cmd/bench` 显式用 `@env.args`/`@string.parse_int`；`check --deny-warn` 绿 | ✅ 已满足 | 无 |
| L2 | `var x = 10` 提示改 `let mut` | 全仓 **零 `var` 声明** | ✅ 已满足 | 无 |
| L3 | `impl` 自动提升告警**默认开**（`dev79`） | S11c 已 `lib/moon.pkg` 落 `warnings = "-79"` | ✅ 已适配 | 保持 |
| L4 | 黑盒测试隐式导入告警**默认开**（`dev25`） | S11c 已全量 `@lib.`（382 处） | ✅ 已适配 | 保持 |
| L5 | 切片 `a[i:j]` 改**钳制视图**（不 panic），旧语义迁 `exact_view` | 全仓**无 `a[i:j]`** | ➖ 不相关 | 无 |
| L6 | **Deprecate** 在 JS FFI 边界使用 `Array`（改 `FixedArray`） | `cmd/host-probe` FFI 面只有 `String`/`Int` | ➖ 不相关（**待观察**） | §5-H5 |
| L7 | `enum` 新增 `#non_exhaustive` | 未使用；公共枚举刻意穷尽 | 🔸 **需再评估**（`Mode`） | §6-P3 |
| L8 | `for...in` 支持模式匹配解构 | 热路径刻意 `while`+索引（性能取向） | 🔸 可选 | 不做 |
| **S1** | core：QuickCheck 无偏随机 + 边界覆盖 + `derive(Shrink)` | **本仓未用 QuickCheck**：属性测试是**确定性 LCG**（`lib/t4a_property_test.mbt`） | ➖ 不相关（**且是优点**：可复现） | 无 |
| **S2** | core：`Array` 遍历/`pop`/`truncate`/`clear` 语义调整、新增 `fill_unused` | 全仓仅 `constants_poly_wbtest.mbt:97` 用 `g.clear()`（生成器复位）；**无 `pop`/`truncate`** | ➖ 不相关 | 无 |
| T1 | 新增 `moon search` / `moon view` / `moon deprecate` | 均可用；`view` 已用其取证 | ✅ 可用 | §6-P1 |
| T2 | `moon tree --json` / `--package` | 实测：本模块**零外部依赖**，仅自包图 | 🔸 可选 | §6-P2 |
| T3 | `moon runwasm` 废弃；`moonx --target native` 废弃 | 全仓**无调用** | ➖ 不相关 | 无 |
| T4 | `.mbtx` 脚本 / 实验性预构建脚本 | 本仓无脚本化需求 | ➖ 不相关 | 无 |

> **第 2 轮修正**：首版遗漏了**标准库变更**（S1/S2）——已补测，结论「不相关」由**实码证据**支撑
> （LCG 非 QuickCheck、无 `pop`/`truncate`），而非默认忽略。

**结论 Q2/Q3**：**无阻断级影响**；`check --deny-warn` 全绿（§4.2 复跑）。

---

## 4. 待适配项

### 4.1 【P0·已落地】`moon deprecate` 已存在 → 订正「无法撤回」口径

```bash
moon deprecate --help
# Deprecate or restore all existing versions of a published module
# 用法: moon deprecate [OPTIONS] <MODULE>   （--reason 弃用 / --undo 恢复 / --dry-run 预览）
# "Specify the full module name without a version selector." / "Versions published later start undeprecated."
```

**精确口径**：`moon publish` **仍无按版本撤销**；`moon deprecate` 只作用于**整模块**（所有已发版本），
且「弃用不影响版本选择，仅在依赖解析时告警」⇒「发布前门禁必须可执行」的前提不变。

已订正 4 处：`docs/03-过程/mooncakes-发布方案.md` §5.4 + R5 ·
`docs/03-过程/mooncakes-发布阻塞项3-4-落地方案.md` ·
`scripts/publish.sh` ⑤ 提示 · `scripts/publish-check.sh` 头注释。

### 4.2 【P1·待决】默认关闭告警 `0073` / `0074`（含首版表格修正）

```bash
moon check --warn-list +a 2>&1 | grep -oE 'Warning: \[[0-9]+\]' | sort | uniq -c | sort -rn
# -> 348 [0073] unnecessary_annotation ; 13 [0074] missing_doc
```

> **首版勘误**：初版把 `0073` 与 `0074` 的**文件分布混算**成一张表（各文件行数合计 361 = 348 + 13），
> 并把 `lib/internal/**`（实为 `0074`）误记为 `0073`。以下为**按告警码拆分后**的正确分布。

**`0073 unnecessary_annotation` × 348**（默认关闭）：

| 区域 | 处数 | 说明 |
|------|:----:|------|
| 测试（`lib/*_test.mbt` + `*_wbtest.mbt`） | **285** | 大头；多为 S11c 批量 `@lib.` 后**枚举路径前缀变冗余** |
| `cmd/**`（bench 33 / host-probe 4 / qr-min 4 / main 1） | **42** | 命令面 |
| `lib/**` 生产代码（qr_builder 5 / svg 5 / module 3 / qr 3 / bitbuffer 2 / qr_build 1） | **19** | **非** S11c 机械改写所致 |
| `README.mbt.md`（文档测试） | **2** | 落地页示例，`@lib.ECL::Q` 属**有意可读性** |

类型：`@lib.ECL::` 94 · `@lib.Version::` 90 · `@lib.Mode::` 77 · `@lib.Mask::` 26 · `@lib.Shape::` 12。

**`0074 missing_doc` × 13**（默认关闭）：`lib/internal/matrix/module.mbt` 7 ·
`lib/internal/constants/hardcode.mbt` 3 · `lib/internal/reedsolomon/reedsolomon.mbt` 2 ·
`lib/qr_build.mbt` 1 ⇒ 公共 API **1** + internal **12**，与 [发布阻塞项 3-4](../03-过程/mooncakes-发布阻塞项3-4-落地方案.md) §4 口径**一致**。

**「纳入门禁」的机制（第 2 轮实测补齐，首版缺失）**：

| 方式 | 实测结果 |
|------|---------|
| `moon check --warn-list +73`（CLI） | ✅ 生效，但**不持久**（须写进 `scripts/check.sh`） |
| `moon.pkg` 内 `warnings = "+73"` | ✅ 生效（`cmd/bench` 实测 33 处） |
| 同一 `warnings` **同时关 79 开 73**：`"-79+73"`（字符串拼接） | ✅ 生效（`lib/moon.pkg` 实测 302 处；`implicit_impl_as_method` 仍为 0） |
| 数组写法 `warnings = ["-79", "+73"]` | ❌ **不生效**（与 S11c 在 `moon.mod` 的观测一致） |
| `moon.mod` 层追加编号 | ❌ 不可行（S11c：`+` 拼接 lexing error / 数组不生效） |

> **粒度提醒**：在 `lib/moon.pkg` 开 `+73` 会**连带该包的黑/白盒测试包**（继承），
> 故「只对测试包开、生产包不开」这一细粒度诉求**做不到**——只能按包或全模块（CLI）取舍。

### 4.3 新 CLI 能力（措辞订正）

首版写 `moon view`「**已接入**」属**过度声明**——它只是在本文取证时用过，**未接入任何脚本/流程**。
准确表述：`moon view --versions` **可用于**发布后核验（替代手工 `curl` API）；`moon tree --package`
**可作**「零外部依赖」的可复跑证据；`moon deprecate --dry-run` 仅在确需弃用时用。

---

## 5. 本评估的漏洞与局限（自查）

| # | 漏洞 / 局限 | 影响 | 处置 |
|:-:|-------------|------|------|
| **H1** | **工具链未钉版**：`scripts/setup-moonbit.sh` 直接 `curl … \| bash` 装 `latest`，无期望版本；`.cnb.yml` 的 vscode 阶段调它 | **门禁/基准数字不可复现**；某天 `latest` 变红会「不知为何」 | §6-P0（最高优先） |
| H2 | 「`latest` == 本机」是快照；未核验 moonc `v0.10.14` ↔ `moon` 精确版本 | 结论会随时间失效 | 记为「截至 2026-09-23」并给复跑命令 |
| H3 | `--warn-list +a` 的**完备性未独立证明**（只证明「本版本下当前为这两簇」） | 可能仍有未暴露的默认关闭告警 | §5 复跑 + 每次升级重跑 |
| H4 | 首版 `0073`/`0074` **分布混算**、internal 文件误标 | 数字误导 | ✅ 已在 §4.2 修正 |
| H5 | 仅在**默认 target（`wasm-gc`）** 下探测；未逐 target / 未在 `moon test` 下全量开告警 | 可能漏 `test` 专属告警 | 记录；`README.mbt.md` 的 0073 已出现在 `check` 输出 |
| H6 | 「纳入门禁」缺机制（首版只说「决定 +73」） | 结论不可执行 | ✅ 已在 §4.2 补实测机制表 |
| H7 | `#non_exhaustive` 首版判「**明确不采用**」**过于绝对** | `Mode` 是唯一有**未来变体**（Kanji，README 已声明暂不支持）的公共枚举 | §6-P3 |
| H8 | 首版**漏评标准库变更**（QuickCheck / `Array` 语义） | 可能漏真实影响 | ✅ 已补 S1/S2 并给实码证据 |
| H9 | 「`moon view` 已接入」**过度声明** | 与事实不符 | ✅ 已在 §4.3 订正 |
| H10 | 本文是**单人静态评估**，未做**负向验证**（如故意构造一个会触发新告警的写法，确认探针能抓到） | 探针灵敏度未被证伪 | §5 复跑含一条负向样例（见下） |

**负向验证（补 H10）**：探针能否真的抓到默认关闭告警？——

```bash
# 在 cmd/bench/moon.pkg 追加 warnings = "+73" 后，check 立即报 33 处（见 §4.2 机制表）
# 即：探针（--warn-list +a / 包级 +73）对「默认关闭告警」是**灵敏**的，不是恒空。
```

---

## 6. 优化建议（按优先级）

| 优先级 | 优化 | 做法 | 风险/取舍 |
|:------:|------|------|-----------|
| **P0** | **工具链钉版 + 期望版本断言** | `scripts/setup-moonbit.sh` 支持 `MOONBIT_INSTALL_VERSION`（默认固定到本评估的 `0.1.20260920`，允许 env 覆盖）；`moon version` 断言与文档一致；`.cnb.yml` 传固定版本 | 与「moon 自动升级」相悖，需评审：建议**钉版 + 显式升级流程**（升版时同步重跑本文 §5 探针） |
| **P1** | **探针脚本化** | 新增只读脚本（如 `scripts/toolchain-probe.sh`）：打印 `moon version` + `--warn-list +a` 直方图 + 本模块依赖图；**非阻断**（同 `docs-date-check.sh`），登记进 AGENTS.md 例行检查 | 新脚本须有引用面，避免成死代码；不接入 gates 必选阶段 |
| **P2** | `0073` 处置范围决策 | 三条路：① 维持默认关闭（记录理由）；② `scripts/check.sh` 加 `--warn-list +73` + 一次性修 348 处；③ 仅 `cmd/**` 包级 `+73`（42 处）。**推荐先 ③ 试点**（范围小、无示例可读性损失） | ②会改 README 示例可读性；`lib` 包级 `+73` 会连带测试包（§4.2 粒度提醒） |
| **P3** | `Mode` 的 `#non_exhaustive` 评估 | 若将来确认要加 Kanji 模式，再决定是否给 `Mode` 标 `#non_exhaustive`（让下游 `Mode::..` 兜底而非编译失败） | 会**增加下游匹配负担**；现无 Kanji 计划，故**暂不标**、仅登记为「未来变体出口」 |
| **P4** | 触发策略制度化 | 每次 `moon upgrade` / 改 `setup-moonbit.sh` 后**必跑** §5 探针；结果与本篇对齐 | 依赖人工纪律（无 push CI） |

---

## 7. 结论与去向

| 项 | 判定 | 去向 |
|----|------|------|
| 版本落后 | **否**（`latest` == `0.1.20260920`，截至 2026-09-23） | 无需升级 |
| L3/L4（`dev79`/`dev25`） | **已适配**（S11c） | 保持；§4.2 复跑证据 |
| L1/L2/L5/L8/T3/T4 | 无影响 / 明确不做 | 记录判定，防重复评估 |
| S1/S2（标准库） | 无影响（LCG 非 QuickCheck；无 `pop`/`truncate`） | 已补证据 |
| §4.1 `moon deprecate` 口径 | **P0 已订正** | 发布文档/脚本注释已改 |
| §5-H1 **工具链未钉版** | **本轮最高优先** | §6-P0（待评审） |
| 0073/0074 是否入门禁 | 待决 | §6-P2（推荐先 `cmd/**` 试点） |
| `Mode::#non_exhaustive` | 暂不标 | §6-P3（未来 Kanji 时再评估） |

**教训**：适配评估的真风险有两层——**表层**是「默认关闭的告警会随版本转正」（本仓仅 `0073`/`0074`）；
**深层**是「工具链本身没钉版，因此任何一次评估都可能在下一次 `setup` 后失效」（§5-H1）。
前者靠 `--warn-list +a` 探针，后者靠**钉版**。

---

## 8. 参考

- 官方更新日志：<https://moonbitlang.cn/updates/2026/09/21/index>（moonc `v0.10.14`）
- 官方《使用与发布包》：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html>
- 本仓相关：[工具链安装与构建](moonbit-工具链与构建-setup-分析.md) ·
  [S11c 第 6 轮体检](../02-证据/S11c-第6轮体检-工具链漂移与门禁假绿修复.md) ·
  [发布方案](../03-过程/mooncakes-发布方案.md) · [发布阻塞项 3-4](../03-过程/mooncakes-发布阻塞项3-4-落地方案.md)
- 实码：`moon.mod` / 各 `moon.pkg` / `scripts/setup-moonbit.sh` / `scripts/publish.sh` / `scripts/publish-check.sh`
