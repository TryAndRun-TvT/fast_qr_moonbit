# AGENTS.md — AI 协作代理仓库指南

> 文件名对齐 MoonBit 官方 `moon new` 生成的 `AGENTS.md`（单一事实源，仓库不再提供小写名符号链接）。

> 本文件为在本仓库（MoonBit 项目 `fast_qr_moonbit`）工作的 AI 编码代理提供硬性约定。
> 请优先遵守；违反可能导致密钥泄露或构建破坏。

---

## 一、Git 安全（最高优先级）—— 避免密钥 / 私人配置入库

1. **API Key / Token / Secret 永不写入任何入库文件**
   - 不得写入源码常量、配置文件、文档示例。
   - 本仓库当前为纯本地库项目；若将来接入需在 CI 中部署的服务，
     密钥一律走平台 Secret 注入，**不得**写入 `.cnb.yml` 的 `vars` 或任何跟踪文件。
2. **永不提交本地 Secret / 私人配置**
   - `.env*` / `.dev.vars*` / `.gitignore` 中声明的本地文件，**禁止** `git add -f` 强制添加。
   - 本地/私人配置保持未提交状态（`git status` 显示 `M` 属预期，**切勿 `git add`**）。
3. **不得入库构建产物**
   - `_build/`、`*.wasm`、`*.js`、`*.mbti` 均已 gitignore。
   - `moon info` 会生成 `*.mbti`，属构建产物，禁止提交。
4. **提交前自查**
   - `git status` + `git diff`：确认暂存区无 Secret、私人配置、构建产物混入。

---

## 二、MoonBit 项目约定

### 1. 包与文件放置（方案 3 布局，对齐 core）

- **模块根只放元数据**（`moon.mod` / `README.md` / `docs/` 等）；库包统一放 `lib/`，
  实现细节藏 `lib/internal/`。
- **模块根唯一例外 = 空 `moon.pkg`**（README 文档测试宿主）：它是 README「示例即测试」落地的前提——
  `mbt check` 代码块由 `moon check`/`moon test` 当作文档测试运行，而模块根的 `.md` **只有归属到某个包才会被扫描**。
  **布局方向（2026-09-14 v4 回正）**：`README.md` 是**实体正文**，`README.mbt.md` 是指向它的**符号链接**
  （文档测试只认文件名恰为 `README.mbt.md` 的 markdown；而 `README.md` 若为符号链接，
  平台/blob/raw/不解析链接的宿主只会读到存根文本，落地页即劣化）。
  该包**不含任何实现、不导出 API**（`boundary` 仍由 `lib/` 承担），
  已用 `warnings = "-29"` 关掉「声明 `@lib` 但只在文档测试里使用」的 `unused_package` 告警。
  **不要把库代码放进根包。**
- 包按目录组织，每个目录一个 `moon.pkg`。
- 公共文件统一放 `lib/`，`.mbt` 文件名可任取、按职责命名（如 ecl/version/mode/mask/module/
  qr/qr_build/qr_builder/helpers/shape/svg）；MoonBit 同包共享命名空间，**不设「入口注释文件」**
  （公共 API 总览由 `README.md` + `docs/01-规格/moonbit-实现布局与文件职责.md` 承载，见 [S11b](docs/02-证据/S11b-清理落地记录-v3-v5.md) §12）。
- 测试文件放**所属包目录内**，分两类，**不可混用**：

  | 文件 | 运行位置 | 可访问范围 |
  |------|---------|-----------|
  | `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` 导出的公共 API；用 `@lib` 别名引用本包（别名 = 目录名 `lib`，自动可用） |
  | `*_wbtest.mbt` | 包**内**（白盒） | 私有函数与内部实现，无需 `pub` 导出 |

- CLI 可执行包固定为 `cmd/main/`，其 `moon.pkg` 需写 `pkgtype(kind: "executable")`。
- 弃用代码统一放各目录的 `deprecated.mbt`。
- 依赖方向无环：`lib` 可 import `lib/internal/*`，internal 永不反向 import `lib`（MoonBit 禁止 import 环）。

### 2. 依赖声明

- 跨包依赖在**使用方**的 `moon.pkg` 中声明（库包路径为 `.../lib`）：

  ```toml
  import {
    "TryAndRun-TvT/fast_qr_moonbit/lib" @lib,
  }
  ```

- **声明后必须使用**：若声明了 `@lib` 却未实际使用，会触发 `unused_package` 告警
  并导致 `moon check` 失败。骨架阶段若无 API 可调用，**不要提前声明**。

### 3. 后端与构建

- 模块声明 `supported_targets = "+wasm-gc"`（**`js` 与 `wasm`(WASI) 均已按项目决策移除**），
  默认 `preferred_target = "wasm-gc"`。
- 主推并**只支持 `wasm-gc`**（实测体积更小、计算微基准更快、宿主接入成本最低）。
- 构建需显式指定包与后端：`moon build cmd/main --target wasm-gc --release`
  （模块根无包，构建需显式给包名）。
- **`native` 后端需系统 C 编译器**（`cc` / `gcc` / `clang`）。当前环境缺失，
  在修复前**不得**把 native 阶段写进 CI 必选流程。
- 代码块以 `///|` 分隔块风格组织，块间顺序无关。

### 4. 收尾检查

每次改动后执行：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon info && moon check --deny-warn && moon test
# 后端回归（release，显式构建 lib 与 cmd/main；js、wasm(WASI) 已移除，仅 wasm-gc）
for t in wasm-gc; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done
```

> **README 也是被测试的代码**：`README.md` 的 `mbt check` 代码块是**文档测试**
> （经 `README.mbt.md` 符号链接被扫描），`moon check` / `moon test` 会真编译、真运行。
> 改公共 API 而不同步改 README 示例 → **`moon test` 直接变红**。这是刻意的：
> README 示例过去只能靠人工实测，现在由门禁兜底（见 docs/04-元/README优化-冗余清理与最佳实践.md）。

> **push CI 已于 2026-09-14 移除**（每次推送重复全量构建+测试，资源收益不成比例）。
> 原 CI 阶段（fmt / check / test / docs-link-check / test-scale / build-and-run / diff-gate /
> publish-check）**脚本均在 `scripts/` 下且零改动**，改为本地/发布前按需执行：
>
> ```bash
> bash scripts/gates.sh                        # 一键全量门禁（等价于原 push 流水线）
> STAGES="check test" bash scripts/gates.sh    # 只跑指定阶段
> SKIP_SLOW=1        bash scripts/gates.sh    # 跳过 build-and-run
> bash scripts/publish.sh                     # 发布：默认干跑（--publish 才真发）
> ```
>
> 因此在推送前本地跑 `gates.sh`（或启用本地钩子）是**唯一**的自动质量闸门，不可省略。
> 可选启用本地钩子：
> `git config core.hooksPath .githooks`（属个人本地配置，仓库不代设）。

- `moon fmt` 会就地格式化（含 `moon.mod` / `moon.pkg`），提交前务必执行。
- `moon info` 生成的 `*.mbti` 是包的对外接口快照：若 `.mbti` 无变化，
  说明改动未影响对外可见接口，通常属安全重构。

---

## 三、测试约定（S10 收口）

### 1. 三载体分工

| 载体 | 运行位置 | 可访问范围 | 用途 |
|------|---------|-----------|------|
| `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` API | 锁公共契约 |
| `*_wbtest.mbt` | 包**内**（白盒） | 私有实现 | 锁实现细节 |
| 源码内联 `test {}` | 包内 | 私有 | 贴近实现的单行不变量（当前未使用） |

测试文件放**所属包目录内**；单测试文件 ≤800 行（`bash scripts/test-scale.sh` 校验），超长按主题拆分。

### 2. 七条铁律（详见 `docs/02-证据/S10-测试用例设计与完善roadmap.md` §5）

1. **黄金值必须有脚本出处**：参考值一律由 `scripts/` 下生成器在**钉版参考**
   （fast_qr commit `53e8c99`）上产出，禁止手抄、禁止「跑一遍写下自己的输出」；
   可用 `bash scripts/gen-goldens.sh --verify` 校验未漂移。
2. **黑盒锁契约、白盒锁实现**：公共 API 语义变化必须先体现在 `*_test.mbt`。
3. **禁止 `actual == actual`**：断言两端不得来自同一段实现逻辑。
4. **每个断言可定位**：失败信息须能指出模块 + 函数 + 行/列/格 + 版本/ECL 等参数。
5. **负向优先于正向**：先证明「测试能红」（`bash scripts/test-audit.sh mutation`），再谈覆盖率；
   禁止把运行结果拼成断言字符串。
6. **真值集合而非用例数**：评审看「独立真值点数 / 参数叉积」，拒绝机械展开的重复断言。
7. **测试不得有破坏性副作用**：不写临时文件、不改全局状态、不依赖执行顺序。

### 3. 例行检查

```bash
bash scripts/test.sh          # moon test（黑盒 + 白盒）
bash scripts/test-scale.sh    # 单测试文件 ≤800 行护栏（进 push CI）
bash scripts/docs-link-check.sh       # 文档互链死链检查（进 gates）
bash scripts/docs-ref-check.sh        # 章节引用门禁：S<N>x §M 须在被引篇目存在该节（S12b §15.2）
bash scripts/docs-index.sh --verify   # 索引 §8 清单与实跑一致（生成物，勿手改；S12b §15.1）
bash scripts/docs-consistency.sh      # 文档一致性（状态/计数/版本/索引/规模；S12 §6.2 D4）
bash scripts/docs-date-check.sh       # 状态头日期漂移**提示**（仅警告，永不阻断；S12b §15.3）
bash scripts/test-audit.sh mutation   # 变异检测：确认「实现被改坏时有测试变红」
bash scripts/test-audit.sh decode     # 第三方解码回读（jsqr；含 T3-d 54 组语料）
bash scripts/gen-goldens.sh --verify  # 黄金值未漂移（需 fast_qr 检出）
bash scripts/diff-gate.sh     # 与参考 wasm 逐位 sha256（无制品时显式 skipped）
bash scripts/coverage.sh              # 覆盖率报告（T5-a，仅报告）
bash scripts/coverage.sh --floor      # 覆盖率不下降门禁（T5-b）
```

> 新增/修改一个模块的实现后，建议重跑 `test-audit.sh mutation`，确认该模块仍有有效测试。

### 4. 变异检测 / 黄金值的操作纪律（v4 补充，均为实跑踩坑）

- **跑变异检测前 `lib/` 必须干净**：脚本会就地改写并 `git checkout -- lib/` 还原，
  **未提交的改动会被一并清掉**。脚本自带校验，但人工 `git commit` 前请再 `git status -- lib/` 看一眼
  （本环境曾把「被变异状态」的源码误提交）。
- **`set -e` 与 `moon test`**：`moon test` 在有失败用例时返回非 0，`set -e` 下必须
  `out="$(moon test ... || true)"` 兜住，否则脚本会**静默退出**（表头打印后一行都没有）。
- **新增变异项必须首跑**：首跑出现 ❌ 是**正常且有价值**的（说明找到了真漏检），
  必须补测到 ✅ 再收口；不要因为「首跑就红」而删掉该变异项。
- **契约型行为要有显式用例**：并列取谁、越界回退到哪、优先级顺序——这类**语义契约**
  不能指望随机夹具撞上，须用「实跑搜出的输入」或穷举显式锁定（如 T2-d2 / T5-b）。
- **参考侧实算器**（`snapshot_gen_*.rs`）需在参考检出内编译，**Rust 侧需系统 C 编译器**；
  优先写成**自包含夹具**，避免依赖参考测试模块的可见性。

### 5. 小步提交纪律（v5 补充，实跑踩坑）

- **每完成一处有意义的改动就 `git commit`**，不要攒到最后统一提交。
  本环境曾出现「改完 `lib/` 后工作区在两次命令之间被还原」，导致修复丢失需重做。
- 这与 §三.4 的「变异检测会 `git checkout -- lib/`」是**两个不同陷阱**：
  前者是审计脚本的**预期行为**，后者是**环境态**——必须靠「小步提交」而不是「小心」来防。

### 6. 覆盖率与文档门禁（v5 新增）

- **T5-b 覆盖率「不下降」**：`bash scripts/coverage.sh --floor` 读取
  `docs/02-证据/S10b-测试覆盖率报告.md` 顶部 `<!-- coverage-floor: lib_uncovered=N -->`
  （只按 `lib/**` 计，**不含 `cmd/*` 探针包**）。新增代码拉高未覆盖行时，
  要么补测（优先负向/契约用例），要么在报告里写明理由并更新该标记——**两条路都要评审可见**。
- **T6-c 文档死链**：`bash scripts/docs-link-check.sh` 检查受版本控制 Markdown 的
  **相对链接**（跳过外链/锚点，忽略代码块）。新增文档须同步更新 `README.md` 的文档索引，否则门禁红。

---

## 四、文档管理

- 文档统一放 `docs/`，命名用连字符分隔的小写词段（kebab-case，允许中英混排，
  如 `wasm-编译与运行-结果分析.md`）。
- **单文档 ≤800 行**，超长应拆分。
- **死链零容忍**：文档中不得引用不存在的文件；新增文档须同步更新
  **两处索引**：`docs/README.md`（全量清单）与 `README.md` 的「文档索引」表（落地页入口）。
  两处都须更新，否则 `bash scripts/docs-link-check.sh` 会红（`README.mbt.md` 是指向 `README.md` 的符号链接）。
- **README 正文改 `README.md`，不要改 `README.mbt.md`**：后者是符号链接。
  `README.md` 里的 `mbt check` 示例会被 `moon test` 校验，请勿把示例写回 `moonbit` 展示块。
- **不要在 README 里写会被写死的计数**（用例数 / 文件数 / 链接条数）：它们随实现漂移，
  写死必然自相矛盾（曾出现同一文件内 146/147 冲突）。需要数字时指向实跑命令。
- **改公共 API 必须同步 README 示例**：否则 `moon test` 变红（文档测试即门禁）。
- **README 只保留「落地页 + 索引」（v5 纪律，2026-09-14）**：`README.md` 是**落地页**，
  只写「能做什么 / 怎么用 / 边界在哪 / 去哪看细节」——**结论 + 出处链接**。
  数字表、参数、实验设计、历史记录、脚本逐项说明**一律下沉 `docs/`**（长口径承接见
  `docs/02-证据/S9r-README性能体积长口径与公共API明细.md`，导航见 `docs/README.md`）。
  新增内容前先自问：「这条是**读者第一屏需要**的，还是**证据**？」后者进 `docs/`。
- **README 里的跨文档链接：归档外目标一律用仓库绝对链接（v6 纪律，2026-09-14）**：
  发布归档（`.moonignore`）**排除** `/docs/` 与 `/AGENTS.md`，故 README 中指向它们的**相对链接**
  会在 mooncakes 落地页被重写为 `assets.mooncakes.io/source/.../docs/...` 而 **404**。
  约定：`docs/**` / `AGENTS.md` → `https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/<path>`；
  `README.md` / `LICENSE` / `cmd/main/**`（**在归档内**）→ 保留相对链接。
  该约定由 `bash scripts/publish-check.sh` 的 **⑤ 发布面链接可达性**断言兜底
  （与 `docs-link-check.sh` 分工不同：前者查「归档读者能否点到」，后者查「仓库内文件是否存在」）。
- **发布状态不写死具体版本号**：写「已发布（首个版本）」+ 指向 mooncakes 版本页；
  写死版本（如「线上是 0.1.0」）会在下次发布后漂移，与「计数不写进 README」同源。
- **纯本地 / 私人配置调整**（如本地默认值改动）：只改代码/配置，**不生成、不更新项目文档**。

### 4.1 文档准入（新增 / 修订文档前必过 · S12 §7.1）

> 出处：[S12 文档体系 SDD 诊断与优化方案](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/S12-文档体系SDD诊断与优化方案.md) §7。
> 本节把 S12 的规范条文**落为硬约定**；违反由 `bash scripts/docs-consistency.sh` 兜底。

1. **头部三字段齐备**（缺一不予合入）：

   ```markdown
   > **状态**：现行 | 历史 | 已失效　｜　日期：YYYY-MM-DD　｜　索引：[docs/README.md](./docs/README.md) §N
   ```

   - `现行`：结论仍是对外口径，可直接引用；
   - `历史`：结论已并入某现行篇（**必须紧跟 `并入：[篇名]`**），本文仅留过程价值；
   - `已失效`：所述前提已不存在（如 `wasm`(WASI)/`js` 后端移除、旧模块名），**不得被引用为口径**。

2. **单文件 ≤800 行**；超出须拆出「承接篇」并在两处索引登记（此前该约束只管 `.mbt`，
   2026-09-18 起由 `docs-consistency.sh` ④ 一并覆盖文档）。
3. **可复跑原则**：任何**数字结论**必须附复跑命令，或指向**登记处**（见 §4.2）；
   无复跑路径的结论降级为「讨论稿」，不入 `docs/`。
4. **不新建「索引的索引」**：导航层次 ≤2 级（`docs/README.md` → 分类 → 篇章）。
   `docs/**` 除索引自身外**不得**出现 `README.md`（门禁 ③c）；域首页用「域-索引.md」命名
   （现状：`docs/移植参考/fast-qr-索引.md`——该 12 篇**由域首页统辖**，不要求逐篇进顶层索引）。
5. **不合并已判定解耦的域**：`docs/移植参考/**`（外部语料）不并入主域（S11 §6.3 已有判定）。
6. **索引双更新**：`docs/README.md`（全量清单）+ `README.md` 的「文档索引」表（落地页入口）。
7. **归类固定 4 类 + 移植参考**（D2 目录分类，2026-09-18）：新篇按**读者意图**放，勿再平铺顶层——
   `01-规格/`（我要改代码）· `02-证据/`（我要审计数据）· `03-过程/`（我要复盘决策）· `04-元/`（我要改文档）；
   `移植参考/`（外部语料）自成一域。目录地图见 `docs/README.md` §0.5；
   迁移由四道门禁兜底（死链 / 章节引用 / 索引双向 / 清单生成），见 S12b §17。

### 4.2 数字单点化与防漂移（S12 §6.2 D4）

- **易变计数只允许一个「登记处」**，其余篇章一律写「见登记处」，**不得复制数字**：

  | 数字 | 唯一登记处 |
  |------|-----------|
  | 测试用例计数 | `docs/02-证据/S10b-测试覆盖率报告.md` 顶部 `<!-- test-count: N -->` |
  | 覆盖率地板 | `docs/02-证据/S10b-测试覆盖率报告.md` 顶部 `<!-- coverage-floor: lib_uncovered=N -->` |
  | 版本号 | `moon.mod` 的 `version`（README **不得**写死「发布状态为 X.Y.Z」） |
  | 索引 §8 的篇数与行数 | `scripts/docs-index.sh`（生成物；`--verify` 校验、`--write` 更新，**禁止手改**） |

- **漂移门禁**（三条，均接入 `scripts/gates.sh`）：
  - `bash scripts/docs-consistency.sh`：七项断言（① 状态 / ② 计数 / ②b 版本 /
    ③ 索引正向（含**摘要区按名链接**）/ ③b 索引反查 / ③c 无子目录 `README.md` / ④ 规模）
    + ⑤ 日期漂移**提示**（非阻断）；
  - `bash scripts/docs-ref-check.sh`：**章节引用门禁**——`S<N>x §M` 须在被引篇目存在该节
    （反引号内为「引述」不算活引用）；
  - `bash scripts/docs-index.sh --verify`：索引 §8 与实跑一致。
    **§8 由 `--write` 生成，禁止手改行数/篇数**（S12 §6.2 D4 数字单点化）。
  - **门禁纪律（S12b §13）**：新增/修改断言必须**负向 + 正向双跑**——
    注入错误**必红**（负向），且**现状必绿**（正向回归）。
    只跑负向会漏检「判据本身写错」（如 basename 子串匹配、深度 glob 漏层）。
  - **判据不得用子串/glob 近似**：链接判定用**归一化路径精确相等**，
    文件枚举用 `git ls-files <目录>`，**不要**用 `docs/*/*/*.md` 这类深度 glob。
  - **门禁输出不得静默**：取不到实跑数字（如 `moon` 不在 PATH）必须 **fail**，
    且报错要指向**真实原因**（计数解析失败），不要指向看似可信的替罪羊（工具链缺失）。
- **状态变更纪律**：改某篇 `状态` 时，必须**同时**移动引用它的现行篇的表述，否则门禁 ① 红。

### 4.3 篇章结构模板（新增文档抄这份 · S12 §7.3）

```markdown
# S<N><x> · <语义标题>（标题不要只写代号）

> **状态**：现行|历史|已失效　｜　日期：YYYY-MM-DD　｜　索引：§N
> 承接：[上位篇]　｜　并入：[若为历史，写明结论去哪了]
> 一句话结论：<本页唯一的 TL;DR>

## 实现方案 / 议题定义     ← 要做什么、为什么、验收标准（含「明确不做」）
## 实现记录 / 证据         ← 实际怎么做的、可复跑命令、与方案的偏离及原因
## 评审与优化 / 结论去向    ← 复核发现、结论去处、后续队列
```

- **文件名保留 `S<N><x>` 代号**（实现顺序是可追溯资产）；**可读性靠标题与索引，不靠文件名**
  （S12 §6.1 D3-A）。索引表与 H1 一律用**语义标题**。

### 4.4 链接纪律（条文化，S12 §7.2）

| 链接方位 | 形态 | 兜底门禁 |
|----------|------|---------|
| `README.md` → `docs/**` / `AGENTS.md`（**归档外**） | **仓库绝对链接** | `publish-check.sh` ⑤ |
| `docs/**` 内部互链（仓库内导航面） | **相对链接** | `docs-link-check.sh` |
| 图片资产 `docs/assets/**` | README 用 `/-/git/raw/main/...` 绝对直链 | `publish-check.sh` ⑤（含 HTML `src`） |
| 锚点 `#fragment` | 仅保留在相对链接或渲染面绝对链接 | 人工 |

---

## 五、参考

- 项目文档索引：[docs/README.md](docs/README.md)（**全量清单 + 按读者路径**）→
  [README.md](README.md)「文档索引」表（落地页入口；`README.mbt.md` 为其符号链接）。
- MoonBit 技能库：<https://github.com/moonbitlang/skills>
- MoonBit 构建系统：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
