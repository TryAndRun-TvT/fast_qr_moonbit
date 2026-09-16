# mooncakes.io 发布方案（评估 + 落地清单）

> **状态**：现行　｜　日期：2026-09-14　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §5

> 承接 Issue #71。目标：给出把 `TryAndRun-TvT/fast_qr_moonbit` 发布到
> [mooncakes.io](https://mooncakes.io) 的**详细、可执行、可审计**方案。
>
> 本文为**方案评估文档**：只做「读官方文档 + 核验本仓库真实状态 + 定发布清单与门禁」，
> **不执行实际发布**（发布需 `moon login` 凭据，属维护者本地动作）。
>
> 依据：
> - 官方《使用与发布包》<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html>
> - 官方《模块配置》<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html>
> - 本仓库实测（工具链 `moon 0.1.20260904`；结论均标注「实测」）
>
> 日期：2026-09-14　｜　状态：**待评审 → 待执行**
>
> **最新进展（2026-09-14）**：A3/B2 已落地；**A1 账户归属已决策并落地** —— mooncakes 账户为
> `TryAndRun-TvT`，模块名 `tryandrun/fast_qr_moonbit` → `TryAndRun-TvT/fast_qr_moonbit`，
> 全仓 import 路径已同步（清单与核验见 [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)）；
> `moon publish --dry-run` 实测 `202 Accepted`（退出码 255 属已知 CLI 行为，见 §1.1）。

---

## 0. 一句话结论

本仓库**已具备发布的技术条件**（可构建、测试全绿、元数据基本齐备、`moon package` 可产出归档），
但存在 **4 个阻塞项**必须先处理：

1. ~~**命名空间冲突/归属**：`moon.mod` 的 `name = "tryandrun/fast_qr_moonbit"` 要求 mooncakes 账户名
   恰为 `tryandrun`——**该用户实测不存在**（发布前必须先注册/确认）。~~
   ✅ **2026-09-14 已解决**：账户定为 **`TryAndRun-TvT`**，`moon.mod` 的 `name` 与全仓 `moon.pkg`
   import 前缀已同步迁移为 `TryAndRun-TvT/fast_qr_moonbit`
   （改动清单与核验见 [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)）。
2. **仓库 URL 与 mooncakes 生态不兼容**：`repository` 指向 CNB（`cnb.cool`），mooncakes 从未收录过该源。
3. **归档内容未收敛**：实测 `moon package --list` 打进 **158 个文件**，含 `scripts/`(35) 与
   `docs/`(54)——审计上下文混入分发面。
4. **发布前质量门禁缺口**：公共 API 的 `missing_doc`(0074) 告警未接入；CI 无「发布前冒烟」。

方案结论：**先修 A/B 类阻塞（§6），再做首个 `0.1.0` 发布**；
发布内容用 `.moonignore` 收敛（§4.3，实测可行）；
版本策略与 `unpublished` 演进用 §5 的阶梯表。

> **落地进展（2026-09-14 更新）**：#3（归档面收敛）与 #4（发布前门禁缺口）已**落地并实测通过**：
> - `.moonignore` 把归档 **155 → 32 项**（解压 1886 → 179 KiB；**2026-09-14 起为 34 项**，见 §4.2.1），
>   并以**离线 registry 注入**证明 32 项归档下游 `moon add`/`build`/`run` 全通
>   （34 项版本的回归见 §4.2.1）；
> - 新增 `scripts/publish-check.sh`（归档基线 + 内容白/黑名单 + 元数据 + 质量基线）
>   并挂入 push CI（2026-09-14 起 push 流水线整体移除，现随 `scripts/gates.sh` 本地执行）。
>
> 详见 **[mooncakes-发布阻塞项3-4-落地方案.md](./mooncakes-发布阻塞项3-4-落地方案.md)**。
> 该文同时**订正**本文 §6-B1 的口径：`lib/**` 的 `missing_doc` 缺口分布为
> 「公共 API 1 处 + `lib/internal/**` 12 处」，而非「公共 API 缺 13 处」。

---

## 1. 官方发布流程（文档原文摘录 + 本仓库对应）

### 1.1 前置：账户与凭据

官方口径（《使用与发布包》「设置 mooncakes.io 账户」）：

> 如果你没有 mooncakes.io 账户，请运行 `moon register` 并按照指南操作。
> 如果你之前注册过账户，可以使用 `moon login` 登录。
> 当你看到以下消息时，表示你已成功登录：
> `API token saved to ~/.moon/credentials.json`

本仓库核验（实测）：

| 项 | 结果 |
|----|------|
| `~/.moon/credentials.json` | ✅ **已存在**（2026-09-14 维护者本地 `moon login` 后；属本地私有凭据，**不得**入库） |
| `moon publish --dry-run` | ✅ `Server status: 202 Accepted, detail: Dry run completed successfully...`（见下方「已知 CLI 行为」） |

> **已知 CLI 行为（实测 2026-09-14，工具链 `moon 0.1.20260904`）**：
> `moon publish --dry-run` 在服务端返回 `202 Accepted / Dry run completed successfully` 之后，
> 进程**仍以 exit 255 结束**并打印 `Error: \`moon publish\` failed`。
> 用全新空模块（`moon new` 后立即 dry-run）复现结果**完全相同** ⇒ 与仓库内容无关，属该版本 CLI 行为。
> 因此干跑判据应看 `Server status: 202 Accepted ... Dry run completed successfully`，
> **不要**只看退出码（否则会把「干跑成功」误判为发布失败）。

> 说明：`moon register` / `moon login` 均为**交互式**命令，无法在 NPC/CI 环境（无 TTY）中完成，
> 必须由维护者在本地终端执行。`credentials.json` 属**本地私有凭据**，
> 与 `AGENTS.md` §一「永不提交本地 Secret」一致——**不得**入库、不得注入 CI。

### 1.2 发布命令

官方口径：`moon publish` 把当前模块推送到 mooncakes.io。

本仓库实测的 CLI 实际签名（`moon publish --help`）：

```
Usage: moon publish [OPTIONS]
Options:
  -h, --help
Manifest Options:
      --frozen                  Do not sync dependencies, assuming local dependencies are up-to-date
Common Options:
      --target-dir <TARGET_DIR>
  -q, --quiet / -v, --verbose / --trace
      --dry-run                 Do not actually run the command
```

可执行清单（维护者本地）：

```bash
export PATH="$HOME/.moon/bin:$PATH"
cd <repo-root>            # moon.mod 所在目录
moon login                # 或首次 moon register；成功标志 = API token saved to ~/.moon/credentials.json
bash scripts/publish.sh   # 推荐：自检 + 发布前门禁 + 归档清单 + 干跑（默认不真发）
moon publish              # 正式发布（等价：bash scripts/publish.sh --publish）
```

> **脚本化（2026-09-14）**：发布动作已收敛为 `scripts/publish.sh`
> （**默认干跑**；`--publish` 才真发且需确认；退出码判据见 §1.1「已知 CLI 行为」），
> 等价的本地全量门禁为 `scripts/gates.sh`。`.cnb.yml` 的 push 流水线已移除，
> **发布不进 CI**（凭据属本地私有，`AGENTS.md` §一）。

### 1.3 发布物构成

官方口径（《模块配置》「使用 .moonignore 控制发布文件」）：

> 发布时默认遵循 `.gitignore` 规则……包根目录下的 `_build/` 始终会被排除……
> 使用 `moon package --list` 检查将要打包的文件。

本仓库实测的归档规则（关键）：

- 默认**继承 `.gitignore`** → `_build/`、`*.wasm`、`*.js`、`*.mbti`、`.env*`、`node_modules/` 自动排除 ✅
- **但 `scripts/` 与 `docs/` 不在 `.gitignore` 内** → 被打进归档（实测 35 + 54 项）⚠️
- 产物名：`_build/publish/<user>-<module>-<version>.zip`（实测 `TryAndRun-TvT-fast_qr_moonbit-0.1.0.zip`，
  154 项、737858 B）

---

## 2. 本仓库发布前状态核验（实测）

### 2.1 元数据（`moon.mod`）逐字段对照官方要求

| 字段 | 官方要求 | 本仓库当前值 | 判定 |
|------|---------|-------------|:----:|
| `name` | 必需；**发布到 mooncakes 必须以用户名开头** | `TryAndRun-TvT/fast_qr_moonbit` | ✅ 与已注册账户 `TryAndRun-TvT` 一致（迁移前为 `tryandrun/fast_qr_moonbit`，见 §2.3 / [模块名迁移…](./模块名迁移与发布链路核验.md)） |
| `version` | 发布则必须符合 SemVer 2.0.0 | `0.1.0` | ✅ |
| `readme` | 指定 README 路径；内容将展示在 mooncakes | `README.md`（符号链接 → `README.mbt.md`） | ✅ 对齐官方模板（2026-09-14 落地，见 §4.2） |
| `repository` | 源码仓库 URL | `https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit` | ❌ 非 github.com（见 §3.1） |
| `license` | 必须符合 SPDX 许可证列表 | `Apache-2.0` | ✅ |
| `keywords` | 关键字 | `["qr", "qrcode", "fast-qr"]` | ✅ |
| `description` | 简短描述 | `Fast QR code generator library written in MoonBit` | ✅ |
| `preferred_target` | 默认后端 | `wasm-gc` | ✅（有意的单后端策略） |
| `supported_targets` | 声明的兼容后端集合 | `"+wasm-gc"` | ⚠️ 见 §3.2（生态兼容性） |
| `warnings` | 告警开关 | `"+prefer_readonly_array"` | ✅ |
| `homepage` | 主页 URL（可选） | **未设置** | ⚠️ 建议补 |

> 官方元数据清单原文：`license` / `keywords` / `repository` / `description` / `homepage` 五者
> "将显示在 mooncakes.io 上"。本仓库缺 `homepage`。

### 2.2 发布前质量基线（实测）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon check --deny-warn     # ✅ 通过（0 warning，26 tasks）
moon test                  # ✅ 全绿（计数以实跑为准，登记处见 S10b）
moon package --list        # ✅ 可产出归档（158 项，见 §4）
moon publish --dry-run     # ✅ 202 Accepted（exit 255 属已知 CLI 行为，见 §1.1）
```

### 2.3 命名空间与生态竞品（实测，2026-09-14）

从 mooncakes 公共索引 `https://mooncakes.io/api/v0/modules`（2460 个模块）实测检索：

| 检索项 | 结果 |
|--------|------|
| `tryandrun/*` | **0 个模块** —— 该账户名下无已发布模块（账户可能尚未注册） |
| `fast_qr_moonbit` | **不存在**（`/api/v0/modules/TryAndRun-TvT/fast_qr_moonbit` → `Module not found`）→ **名称可用** |
| QR 相关竞品 | `bobzhang/qrc` 0.1.2（ISC）、`caozhanhao/qrcode` 0.1.1、`naoto24kawa/moonqr` 0.2.0、`PaiGack/moonbitqrcode` 0.1.0 |

> **命名判定**：moocakes 上无同名/近似名模块，`fast_qr_moonbit` 作为模块名**不冲突**。
> 唯一变量曾是**账户名**——`.cnb.yml`/仓库路径用的是 CNB 组织名 `tryandrun`，
> **而已注册 mooncakes 账户为 `TryAndRun-TvT`（二者不同名）**，故触发全仓改名。
> 迁移过程中 `moon check` 的典型报错：
> `Cannot find import 'tryandrun/fast_qr_moonbit/lib' in TryAndRun-TvT/fast_qr_moonbit/cmd/bench@0.1.0`
> （`moon.mod` 已改名、`moon.pkg` 未同步），处置与核验见
> [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)。
> 若注册时该用户名已被他人占用或需改名，则 `moon.mod` 的 `name` 前缀必须同步修改
> （官方硬性要求：`name` 必须以**你自己的用户名**开头）。

---

## 3. 生态兼容性评估（发布前必须知情的两个「硬边界」）

### 3.1 `repository` 指向 CNB，而非 GitHub

当前 `repository = "https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit"`。

- 官方未强制要求 GitHub，但整个 mooncakes 生态（`moon add`、文档站、社区检视）默认围绕 GitHub。
- 实测同生态 QR 包的 `repository` **全部**指向 github.com
  （`bobzhang/qrc` → `github.com/bobzhang/qrc`；`naoto24kawa/moonqr` → `github.com/elchika-inc/moonqr`；
  `PaiGack/moonbitqrcode` → `github.com/PaiGack/moonbit-qr`）。

**选项（需维护者决策，本文不代为拍板）**：

| 方案 | 说明 | 风险 |
|------|------|------|
| A. 保持 CNB | 如实填写 CNB 地址 | 社区用户/工具可能无法直达源码；不影响 `moon add` |
| B. 建 GitHub 镜像 | GitHub 建镜像仓，`repository` 指向镜像 | 双仓维护成本；需选定「主仓」 |
| C. 建 GitHub 主仓 | 迁主仓到 GitHub，CNB 作 CI/镜像 | 迁移成本最高，但生态足迹最佳 |

> 本文建议：**至少不改动 `moon add` 可达性**（`name`/`version` 与 `repository` 解耦），
> 先按 A 发布 0.1.0 打通流程，仓库托管决策另立 Issue。

### 3.2 `supported_targets = "+wasm-gc"` 的生态影响

本仓库**有意**只支持 `wasm-gc`（见 README「能力与局限」、`docs/S9n`）。但发布到公共 registry 后需注意：

- 下游若在 `js`/`native` 后端 `moon add` 本库，构建系统会**直接拒绝**
  （实测报错：`does not support target backend 'native'`）。
- 生态同类包（`qrc`/`moonqr`/`moonbitqrcode`）均为多后端（含 `js`），**发行面更宽**。
- wasm-gc 对宿主要求：Node ≥ 22 / 启用 GC 的 wasmtime（README 已声明）。

**结论**：这是**有意的分发范围收缩**，但**必须在 mooncakes 首页可见处（README 首屏）明确标注**，
避免下游「装上了却编译不过」的负面预期。本仓库 README「能力与局限」已覆盖，发布前**不需改动**，
仅需确认它在 README 前 1/3 位置（当前 ✅）。

---

## 4. 归档内容治理（`.moonignore` 方案）

### 4.1 现状（实测）

`moon package --list` → **158 项**，顶层分布：

| 顶层目录/文件 | 项数 | 是否应进分发面 | 判定 |
|--------------|:----:|:--------------:|------|
| `lib/` | 53 | ✅ 是（分发主体） | 保留 |
| `cmd/` | 8 | ⚠️ 部分（`cmd/main` 示例可留，`cmd/bench`/`cmd/qr-min`/`cmd/host-probe` 是审计外壳） | 待定 |
| `docs/` | 54 | ❌ 否（本仓库文档体系，指向 CNB Issue/PR 可复现路径） | **排除** |
| `scripts/` | 35 | ❌ 否（环境配置 + 门禁 + 基准脚本，含 Rust/Python/Node 外部依赖） | **排除** |
| `AGENTS.md` | 1 | ⚠️ 可选（AI 协作指南，非分发必需品） | 待定 |
| `README.md`/`LICENSE`/`moon.mod` | 3 | ✅ 是 | 保留 |

> `scripts/` 内的 `setup-rust.sh`、`snapshot_gen_*.rs`、`*.mjs` 等在分发面对消费者**无意义**，
> 且会给「这包为何混着 Rust 脚本」的第一印象减分。

### 4.2 `readme` 字段与官方模板的差异（可选优化）

官方《使用与发布包》模板生成的是：

```
├── README.mbt.md                    # 带 MoonBit 类型检查支持的 README 文件
├── README.md -> README.mbt.md       # 为需要 README.md 的平台提供的符号链接
```

- **官方推荐**：README 正文放 `README.mbt.md`（`moonbit check` 代码块会被**类型检查**），
  `README.md` 只作符号链接满足平台约定。
- **本仓库现状（2026-09-14 起）**：**已迁官方布局**——正文在 `README.mbt.md`，
  `README.md` 为符号链接；`moon.mod` 的 `readme = "README.md"` 不变（符号链接可被解析）。
  示例写进 ```mbt check``` 块，由 `moon check`/`moon test` 编译并运行。

**落地记录**（与原「建议」清单的差异已实测）：

| 原评估项 | 实测结果 |
|---------|---------|
| ① 全仓相对链接需批量改指向 | **不需要**：`README.md` 符号链接仍存在，所有 `./docs/**` 相对链接基线不变 |
| ② `docs-link-check.sh` / CI / `gen-readme-qr-svg.sh` 需同步 | **不需要改脚本**（脚本读的是 `git ls-files '*.md'`，符号链接不计入；实跑 625 链零死链） |
| ③ 符号链接在 CNB/Git 上行为需实测 | 已实测：`git` 侧记录为 `mode 120000`（符号链接），内容指向 `README.mbt.md` |
| ④ **新增前提**（原评估未预见） | **模块根必须有 `moon.pkg`**，否则根目录的 `.md` 不被当文档测试扫描 → 见 §4.2.1 |

**收益（实测）**：`moon test --target wasm-gc` **+1 条 README 文档测试**（计数见 [S10b](S10b-测试覆盖率报告.md) 登记处），
改公共 API 而不同步改示例会**直接变红**。

#### 4.2.1 新增根空包 `moon.pkg`（文档测试宿主）——发布面影响

- 归档会**多一个 `moon.pkg`**（模块根，空包）：内容只有 `import "…/lib"` + `warnings = "-29"`，
  **不含实现、不导出 API**，对消费者无影响（下游 `moon add` 后用 `.../lib` 路径，与根包无关）。
- 该 `warnings = "-29"` 的作用：文档测试里的 `@lib` 对静态分析不可见，否则 `moon check --deny-warn`
  失败（**实测**）。发布前 `publish-check.sh` 的归档清单基线需随之 **+1 项**（见 §5/§6-A3）。

### 4.3 推荐 `.moonignore`（实测可行）

官方明示：`.moonignore` 存在时**替代**同目录 `.gitignore`（二者不合并）。
因此 `.moonignore` 必须**显式重述**原 `.gitignore` 中仍想生效的规则。

实测验证（临时副本，`moon package --list` 从 158 → **69 项**，`scripts/`、`docs/` 归零）：

```gitignore
# ── 继承 .gitignore（.moonignore 存在时不会自动合并，必须重述）──
/_build/
/*.wasm
/*.js
*.mbti
.Trash-*/
.env*
.DS_Store
/node_modules/
/package-lock.json

# ── 发布归档额外排除（不进分发面）──
# 审计/基准/环境配置脚本：含 Rust/Python/Node 外部依赖，对消费者无意义
/scripts/
# 仓库文档体系：与 CNB Issue/PR 路径绑定，属维护者上下文
/docs/
# CI 与 AI 协作配置
/.cnb.yml
/.githooks/
/.codebuddy/
```

> ✅ **已落地（2026-09-14）**：本仓库根目录已提交 `.moonignore`，实测归档 32 → **34 项**
> （含 `cmd/main`、排除全部测试文件）。最终内容与负向验证见
> [mooncakes-发布阻塞项3-4-落地方案.md](./mooncakes-发布阻塞项3-4-落地方案.md) §2。
> 归档基线由 `scripts/publish-check.sh` 守住（条目数偏离 32 即 CI 红）。
>
> **须维护者拍板的两条**（本文不改默认行为）：
> 1. `cmd/` 四包是否留？`cmd/main` 是「怎么用」的可运行示例（对消费者有价值）；
>    `cmd/bench`/`cmd/qr-min`/`cmd/host-probe` 是 S9 审计外壳（含 wasm 链接选项，无分发价值）。
>    可只保留 `cmd/main`：追加 `!/cmd/`、`/cmd/bench/`、`/cmd/qr-min/`、`/cmd/host-probe/`。
> 2. `AGENTS.md` 是否留？它是 AI 协作约定，非分发必需品；文件仅 10 KB，保留无害。
>
> 选定后**必须**用 `moon package --list` 复核，并把最终条目数写进本文（本方案的自校验点）。

---

## 5. 版本与发布节奏

### 5.1 首个版本：`0.1.0`

- 当前 `moon.mod` 已是 `0.1.0`，**无需改动**。
- 官方口径：`0.x.y` 属预发布语义，`0.1.0` 作为首个公开版本**语义恰当**
  （功能对齐 M0–M3 已收口，但外部 API 未承诺稳定）。

### 5.2 版本阶梯（对齐官方 SemVer 约定）

官方原文：MAJOR = 不兼容 API 变更；MINOR = 向后兼容地加功能；PATCH = 向后兼容的修复。

| 类型 | 触发条件（本仓库语境） | 示例 |
|------|----------------------|------|
| MAJOR | 公共 API 破坏性变更（`lib/*.mbt` 的 `pub` 签名/枚举增删）；`.mbti` 快照不兼容 | 0.1.x → 1.0.0（承诺稳定）/ 1.0.0 → 2.0.0 |
| MINOR | 新增公共能力（如 Kanji 模式、新输出格式、新 `Shape`）且旧调用不变 | 0.1.0 → 0.2.0 |
| PATCH | 纯修复 / 内部重构（`.mbti` 无变化） / 文档与性能改进 | 0.1.0 → 0.1.1 |

> 本仓库有天然判据：`moon info` 生成的 `*.mbti` 是**对外接口快照**。
> **`.mbti` 无变化 ⇒ 至少是 PATCH**；`.mbti` 有变化 ⇒ 至少 MINOR（或 MAJOR，视兼容性）。
> 这与 `AGENTS.md` §二.4「`.mbti` 无变化通常属安全重构」的约定一致。

### 5.3 依赖解析：最小版本选择（MVS）

官方口径：moon 实现**最小版本选择**，按各模块声明的依赖要求 + SemVer 解析。

对本仓库的影响：本库**零外部依赖**（`moon tree` 实测 `(no dependencies)`），
因此下游解析**不会引入任何传递依赖**——这是可对外宣传的分发优势，建议写入 mooncakes 描述。

### 5.4 发布后不可回滚的前提假设（需维护者确认）

官方文档仅说明 `moon publish` 推送模块，**未给出 `yank`/撤回命令**（本文核验的
`moon publish --help` 中无相关选项）。因此**发布前必须视「已发布版本不可撤回」**
——这正是 §6 发布前门禁必须可执行的原因。

---

## 6. 落地清单（分优先级，可勾选执行）

### A. 阻塞项（发布前必须完成）

- [x] **A1 确认/注册 mooncakes 账户** —— ✅ 已完成（2026-09-14）：账户 = `TryAndRun-TvT`，
      `~/.moon/credentials.json` 已存在；`moon.mod` 的 `name` 与全仓 import 路径已同步迁移
      （`moon.mod` + 9 个 `moon.pkg` + `scripts/gen-readme-qr-svg.sh` + `README.md` + `AGENTS.md`）；
      `moon publish --dry-run` 实测 `202 Accepted`。
- [ ] **A2 决策 `repository` 指向**（§3.1 选项 A/B/C），改 `moon.mod`。
- [x] **A3 提交 `.moonignore`**（§4.3）——✅ 已完成，基线由 `publish-check.sh` 守卫
      （2026-09-14 README 布局调整后由 32 → **33 项**，新增模块根 `moon.pkg`，见 §4.2.1）。
- [ ] **A4 补 `homepage`**（可选但建议）：指向启用 Pages/文档入口的 URL。

### B. 质量门禁（发布前建议完成）

- [ ] **B1 公共 API 文档覆盖**：当前 `missing_doc`(0074) 未接入。实测 `moon check --warn-list +74`
      报 **13 warnings**，**分布已订正**：
      **`lib/*.mbt`（公共 API）仅 1 处**（`qr_build.mbt:109` 的 `QRCode::build_fixed`，其上方是
      `///|` 块分隔符而非文档正文）；其余 12 处在 `lib/internal/**`
      （`matrix/module.mbt` 7、`constants/hardcode.mbt` 3、`reedsolomon/reedsolomon.mbt` 2）。
      **口径订正**：原文「公共 API 缺 13 处」不准确——公共 API 覆盖实测 **51/52**。
      **语法坑**：`moon.mod` 的 `warnings` 字段**无法**追加 0074（`+` 拼接 = Lexing error；
      数组写法解析通过但不生效），**唯一可行路径**是 `moon check --warn-list +74`。
      建议：补全 13 处后把 `--warn-list +74` 加进 `scripts/check.sh`
      （`--deny-warn` 会把告警升级为失败，须与补文档同批提交）。
      该决定属「改公共代码 + 改 CI」，**留维护者拍板**，详见
      [阻塞项3-4-落地方案](./mooncakes-发布阻塞项3-4-落地方案.md) §4。
- [x] **B2 发布前冒烟门禁** ——✅ 已完成：`scripts/publish-check.sh` 已落地并挂入 push CI
      （该流水线已于 2026-09-14 整体移除，现随 `scripts/gates.sh` 本地执行）。
      四段式：质量基线（fmt/check/test）+ 归档条目数基线（=34）+ 内容白/黑名单 + 元数据自检。
      负向验证（削弱 `.moonignore` / 错基线 / 放回 `AGENTS.md`）三种破坏均能被拦住。
- [ ] **B3 README 首屏复核**：确认「仅 wasm-gc / 宿主需 GC」的边界在 README 前 1/3（当前 ✅），
      并确认 `moon add TryAndRun-TvT/fast_qr_moonbit` 的示例路径与 `lib` 包路径一致。

### C. 发布执行（维护者本地）

- [x] **C1** `moon package --list` 复核归档 —— 已并入 `scripts/publish.sh` ③ 段（基线由
      `publish-check.sh` 守 34 项，见 A3）
- [x] **C2** `moon publish --dry-run` 干跑 —— ✅ 2026-09-14 实测
      `Server status: 202 Accepted, detail: Dry run completed successfully...`
      （退出码 255 为已知 CLI 行为，见 §1.1；脚本判据为**文本匹配**而非退出码）
- [ ] **C3** 正式发布：**`bash scripts/publish.sh --publish`**
      （不可逆；交互输入模块全名确认，或 `CONFIRM_NAME=TryAndRun-TvT/fast_qr_moonbit ... --yes`）
- [ ] **C4** 核验 `https://mooncakes.io/docs/TryAndRun-TvT/fast_qr_moonbit` 页面（元数据/README/接口文档渲染）
- [ ] **C5** 在**干净环境**验证下游可用性（关键！）：

```bash
mkdir /tmp/consumer && cd /tmp/consumer && moon new .
moon add TryAndRun-TvT/fast_qr_moonbit         # 从 mooncakes 真实拉取
# 在 cmd/main/moon.pkg 加 import { "TryAndRun-TvT/fast_qr_moonbit/lib" }
# 跑通 README「快速开始」示例，确认 QRBuilder 生成 + to_str/SVG 输出
moon build cmd/main --target wasm-gc --release
```

### D. 发布后

- [ ] **D1** README 的「快速开始」去掉「需本模块已发布至 mooncakes；发布前可 clone」的过渡说明
- [ ] **D2** 在 README 头部补 mooncakes 徽章（官方文档「开发者 - 徽章」）
- [ ] **D3** 建立版本发布 checklist（复用本文 §5.2 与 §6）

---

## 7. 风险与未决项

| # | 风险/未决 | 影响 | 处置 |
|:-:|----------|------|------|
| R1 | ~~账户名 `tryandrun` 在 mooncakes 的可用性未确认~~ | 已消除：账户定为 `TryAndRun-TvT` 并完成全仓改名 | ✅ 已解（见 [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)） |
| R2 | `repository` 非 GitHub | 生态可达性/信誉 | A2 决策 |
| R3 | 归档含 `scripts/`/`docs/` | 分发面混杂、体积增大 | ✅ 已解：A3 落地，155→32（现 34）项，`publish-check.sh` 守基线 |
| R4 | 仅 `wasm-gc` 单后端 | 下游 `js`/`native` 编译被拒 | 已在 README 声明；可考虑后续补 `js` 后端（另立任务） |
| R5 | 官方文档未给 `yank` 命令 | 发布不可逆 | ✅ 已缓解：§5.4 + `publish-check.sh` 已可执行 |
| R6 | `missing_doc` 未接入 | 公共 API 无文档，mooncakes 文档页质量低 | B1（实测公共 API 仅缺 1 处，余 12 处在 internal） |
| R7 | 仓库文档大量引用 CNB Issue/PR | 外部读者断链（相对链接门禁只查仓内） | 已有 `docs-link-check.sh` 兜仓内；外链属已知边界 |

---

## 8. 复现方式（本文所有结论的最小复现）

```bash
export PATH="$HOME/.moon/bin:$PATH"

# 1) 元数据与依赖
cat moon.mod
moon tree                              # -> (no dependencies)

# 2) 质量基线
moon check --deny-warn                 # -> 通过
moon test                              # -> 全绿（计数见 S10b 登记处）

# 3) 归档面
moon package --list                    # -> 34 项（.moonignore 已收敛；未收敛时为 158 项）

# 4) 发布链路（需登录）
# moon login
# moon publish --dry-run

# 5) 生态检索（只读）
curl -s https://mooncakes.io/api/v0/modules | \
  python3 -c "import json,sys;[print(m['name'],m['version']) for m in json.load(sys.stdin) if 'qr' in m['name'].lower()]"
```

---

## 9. 与既有文档的关系

- 本文是 **发布/分发** 视角的方案；`docs/moonbit-实现布局与文件职责.md` 是**内部布局**视角。
- `docs/moonbit-工具链与构建-setup-分析.md` 覆盖工具链安装与 CI 集成，
  本文**不重复**其内容，仅补充其中未覆盖的 `moon publish`/`mooncakes` 链路。
- 版本判据与 `AGENTS.md` §二.4（`moon info` / `.mbti`）一致，不新增约定。
- 本文新增后需同步 `README.md` 的「文档索引」表（`AGENTS.md` §四：新增文档须更新索引）。
- 模块名迁移（`tryandrun/` → `TryAndRun-TvT/`）的改动清单、报错根因与核验记录见
  [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md)。
