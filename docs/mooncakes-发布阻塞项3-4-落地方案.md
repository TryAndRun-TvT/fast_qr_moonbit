# mooncakes 发布阻塞项 3/4 —— 详细分析与落地方案

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §5

> 承接 Issue #71 的后续任务：对 PR #72（`docs/mooncakes-发布方案.md`）提出的 **4 个阻塞项**中
> 的 **#3（归档面未收敛）** 与 **#4（发布前门禁缺口）** 做**详细分析 + 实测 + 落地**。
>
> 与 [`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) 的关系：**该文是全景评估（要做什么），本文是 #3/#4 的深挖与落地**
> （怎么做的、为什么这么做、实测数字、验证方式）。#2（`repository` 指向）属
> 维护者决策项，本文不展开，仅在 §5 标注边界。
>
> **2026-09-14 补充**：#1（账户归属）**已决策并落地** —— mooncakes 账户定为 `TryAndRun-TvT`，
> 模块名由 `tryandrun/fast_qr_moonbit` 迁移为 `TryAndRun-TvT/fast_qr_moonbit`，
> 详见 [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)。
>
> 工具链：`moon 0.1.20260904 (94521db 2026-09-04)`。本文所有数字均标注「实测」，
> 复跑命令见 §6。日期：2026-09-14。

---

## 0. 结论速览

| 阻塞项 | 结论 | 交付 |
|:------:|------|------|
| **#3 归档面未收敛** | ✅ **已解并落地**：`.moonignore` 把归档 **155 → 32 项**（2026-09-14 起 34 项，解压 1886 → 179 KiB），并以**离线 registry 注入**实测证明 32 项归档下游可用（`moon add`/`build`/`run` 全通） | `.moonignore` |
| **#4 发布前门禁缺口** | ✅ **已解并落地**：新增 `scripts/publish-check.sh` 四段式门禁（归档基线 + 内容白/黑名单 + 元数据 + 质量基线），原挂 push CI（**2026-09-14 push 流水线已整体移除**，门禁改为本地/发布前手跑，
一键全量命令见 `.cnb.yml` 头部注释）；公共 API 文档缺口实测**仅 1 处**（非原估 13 处，见 §4.2） | `scripts/publish-check.sh` |
| 附带修复 | 🔴→✅ **main 已红**：PR #72 引入 `docs-link-check` 死链误报（行内 code span 例子被当链接），已修脚本口径 + 正文 | `scripts/docs-link-check.sh` |

**一句话**：#3 与 #4 都已从「待处理」变为「已落地且可复跑可门禁」；
#1（账户归属）已于 2026-09-14 决策为 `TryAndRun-TvT` 并完成全仓改名；
剩余 4 个发布前置动作里，只有 #2（`repository` 指向）仍需维护者拍板（且不阻塞技术链路验证）。

---

## 1. 背景与问题重述

PR #72 给出的 4 个阻塞项：

1. **账户名归属** —— ✅ **已决策（2026-09-14）**：mooncakes 账户为 `TryAndRun-TvT`（**非** `tryandrun`），
   模块名同步迁移为 `TryAndRun-TvT/fast_qr_moonbit`（迁移清单与核验见
   [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)）
2. **`repository` 指向 CNB** —— 生态同类包全部指向 github.com（决策项）
3. **归档面未收敛** —— `scripts/` + `docs/` 混入分发面
4. **发布前门禁缺口** —— 公共 API 文档 + 归档基线校验

**为什么 #3 是真问题（不是洁癖）**：

- **体积**：实测归档含 155 项 / 解压 1886 KiB，其中 `docs/`(55) + `scripts/`(35) 占大头，
  而**库本体**（`lib/`）只有 53 项。消费者拉到的是一个「仓库快照」，不是一个「库」。
- **语义**：`scripts/*.rs`、`snapshot_gen_*.py`、`bench-*.mjs` 是**本仓库的审计/基准外壳**，
  含 Rust/Python/Node 外部依赖，对消费者零价值，且会造成「这包为何混着 Rust 脚本」的负面第一印象。
- **维护者上下文泄漏**：`docs/` 内的文档大量引用 CNB Issue/PR 路径（[`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) §R7），
  对外部读者是断链，且属内部审计记录。

**为什么 #4 是真问题**：

- 官方文档**未给出 `yank`/撤回命令**（实测 `moon publish --help` 无相关选项），
  故必须假设「**已发布版本不可撤回**」。
- 「不可撤回」+ 「无发布前校验」= 唯一防线是**人工记得检查**，这在 CI 化仓库里是缺口。

---

## 2. 阻塞项 #3：归档面收敛

### 2.1 机制澄清（实测）

`moon package` 的打分范围遵循 **`.moonignore`（存在时）或 `.gitignore`（否则）**，二者**不合并**。
故 `.moonignore` 必须**显式重述** `.gitignore` 中仍想生效的规则（`_build/`、`*.mbti`、`*.wasm` 等）。

> ⚠️ **实测陷阱 1**：`moon package --list` **与真实 zip 不一致**。
> `--list` 输出 **57 项**（漏掉 `LICENSE`），而真实 zip 是 **58 项**（含 `LICENSE`）。
> 基线门禁若只信 `--list`，就会漏计 `LICENSE`——所以 `publish-check.sh` 的基线值
> 以 `--list` 口径登记，并额外用白名单断言覆盖「三件套」是否齐全。

> ⚠️ **实测陷阱 2**：`moon package --list` 会**混入 moon 自身日志行**
> （`Running moon check ...` / `Check passed` / `Finished. moon: ...` / `Package to ...`）。
> 直接 `wc -l` 会把日志算成条目；必须先过滤（`publish-check.sh` 已处理）。

### 2.2 逐层收敛（实测数字）

| 配置 | `--list` 项数 | 真实 zip 项数 | 解压体积 | zip 体积 |
|------|:---:|:---:|:---:|:---:|
| 无 `.moonignore`（现状） | 158 | 155 | 1886 KiB | 747 KB |
| 仅排除 `scripts/`+`docs/`+平台配置 | 64 | — | — | — |
| + 排除 `cmd/{bench,qr-min,host-probe}` | 58 | 58 | 599 KiB | 173 KB |
| + 排除 `AGENTS.md` | 57 | 58 | 599 KiB | 173 KB |
| **+ 排除测试文件（定稿）** | **32** | **32** | **179 KiB** | **74 KB** |

定稿 `.moonignore`（本仓库根目录）：

```gitignore
# ── 继承 .gitignore（.moonignore 存在时不会自动合并，须重述）──
/_build/
/*.wasm
/*.js
*.mbti
.Trash-*/
.env*
.DS_Store
/node_modules/
/package-lock.json
# ── 发布归档额外排除 ──
/scripts/          # 环境配置 + 门禁 + 基准脚本（含 Rust/Python/Node 外部依赖）
/docs/             # 仓库文档体系（绑定 CNB Issue/PR 路径，属维护者上下文）
/.cnb.yml          # CI 配置
/.githooks/        # 本地钩子
/.codebuddy/       # AI 协作配置
/cmd/bench/        # S9 审计外壳（可执行基准）
/cmd/qr-min/       # S9 体积探针
/cmd/host-probe/   # S9p 宿主调用面探针（foreign_library）
/AGENTS.md         # AI 协作约定，非分发必需品
**/*_test.mbt      # 黑盒测试
**/*_wbtest.mbt    # 白盒测试
```

**最终分发面 32 项**：`lib/**`(27) + `cmd/main`(2) + `LICENSE`/`README.md`/`moon.mod`(3)。

> **2026-09-14 增量（32 → 34）**：README 恢复官方布局（`README.mbt.md` + `README.md` 符号链接，+1）
> 并新增模块根空包 `moon.pkg` 作 README 文档测试宿主（+1）。两项**均非维护者上下文**，
> 前者是 mooncakes 首页展示的 README 正文，后者不含实现与导出，消费者无感（详见发布方案 §4.2.1）。

### 2.3 关键实测：排除测试文件是否安全？

`.moonignore` 的一个反直觉行为（实测）：**根级 glob `/*_test.mbt` 不生效**，
必须用 `**/*_test.mbt`（递归）。定稿用后者，实测 26 个测试文件全部排除（残留 0）。

**安全性论证（为什么排除测试文件是对的）**：

1. **消费者不需要**：`lib/**` 的 `_test.mbt`（黑盒）与 `_wbtest.mbt`（白盒）
   是**本仓库**的测试资产。下游 `moon add` 后跑的是**自己的**测试，不会跑上游测试。
2. **不影响功能**：实测（§2.4）归档中**无任何测试文件**时，
   下游 `moon add` → `moon build` → `moon run` 全通，输出正确。
3. **体积收益大**：26 个测试文件占 **420 KiB / 599 KiB ≈ 70%** 的解压体积——
   排除后归档从 599 KiB 降到 179 KiB（-70%）。
4. **无 `mbti` 依赖**：`*.mbti`（接口快照）已被 `.gitignore` 排除且属构建产物；
   下游从源码重新生成，实测归档解压后 `moon check` 通过（见 §2.4）。

> 口径提示：[`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) §4.3 曾建议「`cmd/main` 保留、其余 `cmd/*` 排除」。
> 本方案**采纳该建议并落地**（`cmd/main` 是「怎么用」的可运行示例，对消费者有价值）。

### 2.4 决定性验证：32 项归档的下游可用性

「条目数减少」本身不是价值，**「减少后下游还能用」才是**。故做了完整的**离线 registry 注入**实测：

```bash
# ① 从仓库产出归档
moon package                       # -> _build/publish/TryAndRun-TvT-fast_qr_moonbit-0.1.0.zip

# ② 伪造本地 registry：写入索引条目 + 放置归档到缓存
#    索引: ~/.moon/registry/index/user/TryAndRun-TvT/fast_qr_moonbit.index（含 sha256 checksum）
#    缓存: ~/.moon/registry/cache/TryAndRun-TvT/fast_qr_moonbit/0.1.0.zip

# ③ 新建「干净消费者」工程，声明 registry 依赖
#    consumer/moon.mod:  import { "TryAndRun-TvT/fast_qr_moonbit@0.1.0" }

# ④ 真实走 moon 的依赖解析链路
cd consumer && moon build cmd/main --target wasm-gc --release   # ✅ Finished
cd consumer && moon run   cmd/main --target wasm-gc             # ✅ size=25 + SVG
```

实测结果：

| 步骤 | 结果 |
|------|------|
| `moon add TryAndRun-TvT/fast_qr_moonbit` | ✅ `Using cached ...@0.1.0`（历史输出：实测时模块名尚为 `tryandrun/fast_qr_moonbit`） |
| 归档解压后 `moon check --deny-warn` | ✅ 通过（14 tasks） |
| 归档解压后 `moon build lib --target wasm-gc --release` | ✅ 通过 |
| 消费者 `moon build cmd/main --target wasm-gc --release` | ✅ 通过 |
| 消费者 `moon run cmd/main --target wasm-gc` | ✅ `size=25` + `<svg viewBox="0 0 33 33" ...>` |

> **结论**：32 项归档是**自足**的——下游经真实 registry 解析链路可编译可运行，
> 且**不依赖** `scripts/`、`docs/`、`AGENTS.md`、任何测试文件。
>
> 该验证同时覆盖了 C5（干净环境验证下游可用性）的**技术链路部分**；
> 仅「从 mooncakes 公网真实拉取」需发布后才能跑（属 §6-C）。

### 2.5 `--list` vs 真实 zip：为何门禁要双口径

实测的 `--list` / zip 差异表（定稿配置）：

| 口径 | 项数 | 差异 |
|------|:---:|------|
| `moon package --list` | 32 | 漏 `LICENSE`（在 §2.2 未排除 `AGENTS.md` 时为 57 vs 58） |
| 真实 zip | 32 | 全集 |

> `publish-check.sh` 因此采用**双重断言**：
> ① `--list` 条目数 == 基线（防膨胀）；
> ② `--list` 非 `lib/` 条目 ⊆ 白名单 `{LICENSE, README.md, moon.mod, cmd/main/*}`（防缺件/多件）。
> 单一断言都可能被绕过：只看项数会漏「项数对但内容错」，只看白名单会漏「lib/ 悄悄膨胀」。

---

## 3. 阻塞项 #4：发布前门禁

### 3.1 设计目标

| 目标 | 理由 | 实现 |
|------|------|------|
| **能挡「归档膨胀」** | 归档面是最易被无意识破坏的（加个脚本/文档就变大） | 条目数基线 `BASELINE=34`（2026-09-14 由 32 上调） |
| **能挡「上下文泄漏」** | `scripts/`/`docs/` 混入是 `mooncakes` 生态的负面信号 | 黑名单断言（7 条模式） |
| **能挡「缺件」** | 漏 `LICENSE` 会影响许可合规展示 | 白名单断言 |
| **能挡「元数据漏字段」** | 官方要求 `license`/`keywords`/`repository`/`description`/`homepage` 展示 | 6 字段存在性断言 |
| **零网络、秒级** | 要能进 push CI，不能靠网络或外部工具链 | 纯 `moon` + `grep`，只读 |
| **失败可定位** | 新成员看到 ❌ 要知道改哪 | 每条 ❌ 后给「处置」提示 |

### 3.2 四段式门禁（`scripts/publish-check.sh`）

```
① 质量基线      bash scripts/{fmt-check,check,test}.sh     三项串联，任一失败即红
② 归档基线      moon package --list 条目数 == 32           防膨胀
③ 内容白/黑名单  非 lib/ 条目 ⊆ 白名单；且无黑名单模式命中    防缺件 + 防泄漏
④ 元数据自检    moon.mod 六字段齐备 + name 形如 <user>/<module>
```

**负向验证（AGENTS.md §三.5「先证明测试能红」）**——实测三种破坏都能被抓住：

| 破坏动作 | 门禁反应 | 命中哪段 |
|---------|---------|:---:|
| 删掉 `.moonignore` 的 `/docs/` 行 | ❌ 条目数 32 → 87 | ② |
| `ARCHIVE_BASELINE=999`（基线错） | ❌ 差 -967 | ② |
| 删掉 `.moonignore` 的 `/AGENTS.md` 行 + 基线改 33 | ❌ `AGENTS.md` 白名单外 + 黑名单命中 | ③（双重） |

> 注意第三种：基线已放行（33 对 33），但**白名单仍独立拦住** `AGENTS.md`——
> 这正是「② 与 ③ 不能互相替代」的实测证据。

### 3.3 CI 挂接（`.cnb.yml`）

> **2026-09-14 变更**：`.cnb.yml` 的 **push 流水线已整体移除**（每次推送重复全量构建+测试，
> 资源收益不成比例）。`publish-check` 等阶段**脚本本身不变**，改为本地/发布前按需执行：
> 全量链 = `bash scripts/gates.sh`（支持 `STAGES=` / `SKIP_SLOW=1`），发布 = `bash scripts/publish.sh`。
> **门禁能力未削弱，只是触发方式由「推送」改为「人」**。

`publish-check` 作为新阶段加在 `diff-gate` 之后。选择理由：

- **纯只读**：不写仓库、不发网络、不改 `moon.mod` → 对 push CI 无副作用。
- **复用了已有阶段**：① 段的 `fmt-check`/`check`/`test` 与 CI 既有阶段重叠。
  这是**有意的冗余**：让 `publish-check.sh` **单独可跑**（本地/发布前手跑一条命令即全查），
  代价是 CI 有少量重复计算（秒级，可接受）。若日后在意，可加 `SKIP_QUALITY=1` 跳过 ① 段。
- **不阻塞发布动作**：门禁不含 `moon login`/`moon publish`（需本地凭据），
  与 `AGENTS.md` §一「密钥不入库」一致。

---

## 4. 阻塞项 #4 的第二个子项：公共 API 文档缺口（口径订正）

### 4.1 原评估

[`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) §6-B1 称：开启 `missing_doc`(0074) 后 `lib/**` 有 **13 处**缺口。

### 4.2 实测订正（重要）

用 `moon check --warn-list +74` 实测（本仓库 `warnings` 字段**不支持**追加 0074，
详见 §4.3），结果：

| 范围 | 缺口 | 性质 |
|------|:---:|------|
| `lib/*.mbt`（**公共 API**） | **1** 处 | `QRCode::build_fixed` 的 `///` 后缺正文 |
| `lib/internal/**`（**实现细节**） | 12 处 | 内部 `pub` 常量/函数，按 `AGENTS.md` §二.1 不属对外契约 |
| 合计 | 13 处 | 与 PR #72 数字一致，但**分布**与「公共 API 缺 13 处」的印象不同 |

逐处定位（实测）：

```
lib/internal/constants/hardcode.mbt:802,818,828      3   （内部常量表访问器）
lib/internal/matrix/module.mbt:21,24,27,30,33,36,39  7   （module_type_* 类型号常量）
lib/internal/reedsolomon/reedsolomon.mbt:546,596      2   （内部除法/gf 运算）
lib/qr_build.mbt:109                                  1   ← 唯一公共 API 缺口
```

> **结论订正**：公共 API 的文档覆盖实测为 **51/52**，唯一缺口是 `QRCode::build_fixed`。
> 根因：该函数上方是 `///|`（块分隔符），而 `///|` **不算**文档——
> 0074 要求「文档置于声明上方，以 `///` 开头且有正文」。

### 4.3 `warnings` 字段的语法坑（实测）

`moon.mod` 的 `warnings` 字段**不能**用 `+` 拼接多个字面量：

| 写法 | 结果 |
|------|------|
| `warnings = "+prefer_readonly_array" + "missing_doc"` | ❌ Lexing error |
| `warnings = "+prefer_readonly_array"\nwarnings = "..."` | ❌ Duplicate key |
| `warnings = ["+prefer_readonly_array", "+missing_doc"]` | ⚠️ 解析通过但**不生效**（0074 仍不报） |
| `moon check --warn-list +74` | ✅ **唯一可行路径**（实测 13 warnings） |

> 因此若要把文档门禁纳入 CI，**不能只改 `moon.mod`**，
> 必须在 `scripts/check.sh` 里用 `moon check --deny-warn --warn-list +74`。
> 这解释了 §6-B1 原文「`moonc` 实测 `warnings = "+74"` 报 13 warnings」的口径差异——
> `--warn-list` 是命令行开关，与 `moon.mod` 的 `warnings` 字段不是同一机制。

### 4.4 建议路径（本方案不擅自改门禁）

| 选项 | 说明 | 取舍 |
|------|------|------|
| **A. 只补 `lib/*.mbt`，门禁查 `lib/**`** | 补 1 处即可让公共 API 零缺口 | ✅ 成本最低，但门禁无法用 `--warn-list` 限定范围（0074 是全模块的） |
| **B. 补全部 13 处** | 公共 + 内部全部补 `///` 正文 | 内部属实现细节，与 `AGENTS.md` 分层约定略有张力；但成本也仅在 12 处 |
| **C. 暂不入门禁** | 保持现状，发布前人工确认 | 与 #4「门禁缺口」的初衷相悖 |

> **本方案倾向 B**：`lib/internal/**` 虽非对外契约，但补文档零风险、体量小（12 处），
> 且能让 0074 **整条入门禁**（口径干净、无需特例）。
> 但这属「改公共代码 + 改 CI 门禁」的连带决定，**留维护者拍板**（与 §5 的 #1/#2 同列）。
> 现阶段 `publish-check.sh` **不**包含文档段，避免在未补全时把 CI 弄红。

---

## 5. 边界与未决（本文不代为拍板）

| # | 事项 | 归属 | 本文态度 |
|:-:|------|------|---------|
| 1 | 账户名归属 | 维护者 | ✅ **已决策**：账户 = `TryAndRun-TvT`（决策依据即「`tryandrun` 名下 0 模块、索引 2473 模块无 `tryandrun`」）；改名已落地，见 [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md) |
| 2 | `repository` 指向 CNB vs GitHub | 维护者 | 实测 4 个同类 QR 包 `repository` **全部** github.com（含 `bobzhang/qrc`/`moonqr`/`moonbitqrcode`/`qrcode.mbt`）；不影响 `moon add` 可达性 |
| 3 | 是否把 0074 纳入 CI 门禁 | 维护者 | 见 §4.4，倾向 B（补全 13 处） |
| 4 | `readme` 迁移到 `README.mbt.md` | 维护者 | [`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) §4.2 已评估，建议 0.1.1 跟进 |

**一个实测否定项（避免日后踩坑）**：`moon.mod` 写 `source = "lib"` 会**破坏构建**
（实测报 `Cannot find import '.../lib/internal/data_encoding'`）。
官方 registry 索引里的 `source: "lib"` 字段是 **`moon publish` 依目录布局自动写入**的，
**不是**在 `moon.mod` 里手写的——本仓库「模块根无包、库包在 `lib/`」的布局无需任何声明。

---

## 6. 复跑方式（本文所有结论的最小复现）

```bash
export PATH="$HOME/.moon/bin:$PATH"

# ── #3 归档面 ─────────────────────────────────────────────
moon package --list | grep -vE '^(Running|Check|Finished|Package to)' | wc -l   # -> 32
moon package && python3 -c "
import zipfile; z=zipfile.ZipFile('_build/publish/TryAndRun-TvT-fast_qr_moonbit-0.1.0.zip')
print(len(z.namelist()), 'items')"                                              # -> 32
# 去掉 .moonignore 后同法 -> 155

# ── #4 发布前门禁 ─────────────────────────────────────────
bash scripts/publish-check.sh                    # -> 全绿，34 项
bash scripts/publish-check.sh 2>&1 | grep '❌'    # -> 无

# 负向：削弱 .moonignore 后应红（验证门禁有效）
cp .moonignore /tmp/mi.bak && sed -i '/^\/docs\/$/d' .moonignore
bash scripts/publish-check.sh >/dev/null 2>&1; echo "exit=$?（期望 1）"
cp /tmp/mi.bak .moonignore

# ── #4 文档缺口 ───────────────────────────────────────────
moon check --warn-list +74 2>&1 | tail -1       # -> 13 warnings
moon check --warn-list +74 2>&1 | grep '╭─' | sed 's|.*/lib/|lib/|;s| \]||' \
  | awk -F: '{p[$1]++} END {for (k in p) print p[k], k}' | sort -rn

# ── 下游可用性（离线 registry 注入）──────────────────────
# 见 §2.4；关键：把 zip 放进 ~/.moon/registry/cache/<user>/<mod>/<ver>.zip
# 并写 index 条目（checksum = zip 的 sha256），再在干净工程里 import 该模块。

# ── 既有 CI 门禁回归 ──────────────────────────────────────
for s in fmt-check check test docs-link-check test-scale build-and-run publish-check; do
  printf '%-18s ' "$s"; bash scripts/$s.sh >/dev/null 2>&1 && echo ✅ || echo ❌
done
```

---

## 7. 与既有文档的关系

- [`docs/mooncakes-发布方案.md`](./mooncakes-发布方案.md) —— **全景评估**（4 阻塞项 / 风险表 / 落地清单 A–D）。
  本文完成其 §4.3（`.moonignore`）与 §6-B2（`publish-check.sh`）的**落地**，
  并**订正**其 §6-B1 的口径（13 处缺口的分布，见 §4.2）。
- [`AGENTS.md`](../AGENTS.md) —— §三.4「变异检测前 `lib/` 必须干净」「新增变异项必须首跑」等纪律，
  本文的负向验证沿用了「先证明能红」的同一原则；
  §四「死链零容忍」是本次附带修复（`docs-link-check.sh`）的依据。
- [`docs/S10-测试用例设计与完善roadmap.md`](./S10-测试用例设计与完善roadmap.md) —— 门禁 T4/T5/T6/T7 的登记处；
  新增 `publish-check` 属「发布面」门禁，本文登记于 §3，未占用 T 编号。
