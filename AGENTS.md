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
  （公共 API 总览由 `README.md` + `docs/moonbit-实现布局与文件职责.md` 承载，见 [S11b](./docs/S11b-清理落地记录-v3-v5.md) §12）。
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
> README 示例过去只能靠人工实测，现在由门禁兜底（见 docs/README优化-冗余清理与最佳实践.md）。

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

### 2. 七条铁律（详见 `docs/S10-测试用例设计与完善roadmap.md` §5）

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
bash scripts/docs-link-check.sh       # 文档互链死链检查（进 push CI）
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
  `docs/S10b-测试覆盖率报告.md` 顶部 `<!-- coverage-floor: lib_uncovered=N -->`
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
  **两处索引**：`docs/README-导航与索引.md`（全量清单）与 `README.md` 的「文档索引」表（落地页入口）。
  两处都须更新，否则 `bash scripts/docs-link-check.sh` 会红（`README.mbt.md` 是指向 `README.md` 的符号链接）。
- **README 正文改 `README.md`，不要改 `README.mbt.md`**：后者是符号链接。
  `README.md` 里的 `mbt check` 示例会被 `moon test` 校验，请勿把示例写回 `moonbit` 展示块。
- **不要在 README 里写会被写死的计数**（用例数 / 文件数 / 链接条数）：它们随实现漂移，
  写死必然自相矛盾（曾出现同一文件内 146/147 冲突）。需要数字时指向实跑命令。
- **改公共 API 必须同步 README 示例**：否则 `moon test` 变红（文档测试即门禁）。
- **README 只保留「落地页 + 索引」（v5 纪律，2026-09-14）**：`README.md` 是**落地页**，
  只写「能做什么 / 怎么用 / 边界在哪 / 去哪看细节」——**结论 + 出处链接**。
  数字表、参数、实验设计、历史记录、脚本逐项说明**一律下沉 `docs/`**（长口径承接见
  `docs/S9r-README性能体积长口径与公共API明细.md`，导航见 `docs/README-导航与索引.md`）。
  新增内容前先自问：「这条是**读者第一屏需要**的，还是**证据**？」后者进 `docs/`。
- **纯本地 / 私人配置调整**（如本地默认值改动）：只改代码/配置，**不生成、不更新项目文档**。

---

## 五、参考

- 项目文档索引：[docs/README-导航与索引.md](./docs/README-导航与索引.md)（**全量清单 + 按读者路径**）→
  [README.md](./README.md)「文档索引」表（落地页入口；`README.mbt.md` 为其符号链接）。
- MoonBit 技能库：<https://github.com/moonbitlang/skills>
- MoonBit 构建系统：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
