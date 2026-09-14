# README 优化 · 最佳实践对照与冗余清理

> 面向：README 维护者 / 审阅者。
> 背景：ISSUE #47 多轮要求「README 优化 / 去冗余 / 继续优化」。
> 前置：第一轮（PR #48）补齐依赖用法/能力局限/性能速览；第二轮（PR #54）示例码改 SVG；
> 第一/二轮冗余清理（PR #55/#56，§1–§5 为本轮记录）；**第三轮见文末 §6（2026-09-14）**。
> 日期：2026-09-12（§1–§5）｜ 2026-09-14（§6）　｜　工具链：`moon 0.1.20260904`、`wasm-gc`
> 影响面：§1–§5 **仅 README.md**（不改 lib / 公共 API / 快照 / 用例 / 脚本）；
> §6 起为「README 可达性与自校验」轮次，**新增根空包 `moon.pkg` + README 布局恢复官方形态**。

---

## 0. 结论先行

- README **473 → 391 行**（**−82 行，−17%**），字节 **32029 → 24030**（**−8.0 KB，−25%**）；
- 删除的是**与 `docs/` 重复的过程性内容**，不是能力/口径/诚实声明：
  - **文档索引 44 行扁平长表 → 15 行**（S1–S9n 由「20 行逐篇表格 + `<details>` 折叠」收敛为
    **1 行系列入口 + 重点篇目导航**，避免「索引正文 = 文档目录复制」）；
  - **wasm 体积/性能章节去重**：`cmd/main` 双档命令形态重复出现 3 次、`wasm`(WASI)「历史注记」
    块重复 4 处、fast_qr 体积对照表重复 2 处 → 各保留 1 处；
  - 「能力与局限」的 wasm-gc 边界与「编译为 Wasm」章节的边界说明**合并为单一出处**。
- **零信息丢失**：所有被删数字/口径仍在本文档与 `docs/` 原档中可查；README 保留**引用规范与出处**。
- 全部内链核验通过（**0 死链**）；文档本体改动的只是**引用深度**，`docs/` 文件一个都没删（见 §4 刻意取舍）。

---

## 1. 最佳实践调研（先查官方，再对照通用惯例）

### 1.1 MoonBit 官方对 README 的既有约束

| 来源 | 结论 | 对本仓库的含义 |
|------|------|----------------|
| `moon.mod` `readme` 字段（[Module Configuration](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html)） | 指定模块 README 路径 | `readme = "README.md"` 必须存在且可读 |
| `moon new` 模板（[Build System Tutorial](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html)） | 模板产出 `README.mbt.md` + `README.md -> README.mbt.md` 符号链接 | 官方**推荐**用 `.mbt.md` 让示例可被 `moon check` / `moon test` 验证 |
| [Comments and Documentation](https://docs.moonbitlang.com/zh-cn/latest/language/docs.html) | `mbt check` 代码块是 **document test**，由 `moon check` / `moon test` 自动检查运行；`moonbit` 围栏只是展示、不编译 | 示例若写成 `mbt check` 则**永不过期** |
| [Use and publish packages](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html) | `moon.mod` 元数据（`license`/`keywords`/`repository`/`description`）与 **`README.md` 一起展示在 mooncakes.io** | README 是**第一屏落地页**：头部要给 What/状态/用法，而不是内部过程记录 |

> 官方对 `.mbt.md` 的定位与本仓库现状：本仓库 README 未走 `.mbt.md` 形式（示例为 `moonbit` 展示块），
> 因此**示例本身不被 CI 校验**。本次已**逐条手工实测**（见 §3.1）；是否迁到官方
> `README.mbt.md + mbt check` 属**可选的下一步**，本次不改（会牵动 `moon.mod` 与文件布局，超范围）。

### 1.2 通用 README 惯例（对照后取适用项）

| 惯例 | 本仓库是否适用 | 处置 |
|------|----------------|------|
| 头部 1–3 行讲清 What + 状态 | 适用 | 已有，保留 |
| 「安装 → 最小可运行示例」前置于深度内容 | 适用 | 已有，保留（公共类型表列在示例之后） |
| 能力与**局限**显式声明 | 适用（库） | 已有，保留并**只留一处** |
| 文档索引「分层不冗长」 | **适用且本次重点** | 已重构（§2） |
| 徽章（CI/版本/许可证） | 部分适用 | 暂不加：CNB 徽章需额外配置，且与正文「项目状态」重复 |
| 完整 changelog / roadmap 过程记录 | **不适用** | 属 `docs/`，README 只留结论与入口（§2.2） |
| 大段性能表 | 适用但应**单一主口径** | 保留主口径表，其余降为「出处链接」（§2.3） |

---

## 2. 冗余清单与处置（逐条）

### 2.1 文档索引：44 行 → 15 行

**问题**：旧索引把 `docs/` 44 篇**逐篇平铺**（其中 S1–S9n 20 篇放在 `<details>` 里再表格一次），
每行「说明」又高度压缩，等于把 `docs/` 目录复制一遍；同时正文已被压到「文档索引」之后。

**处置**：

- 只保留**读者首次需要**的 10 行（工程/布局/CI/评审入口 + 4 篇对外口径文档 + 2 篇维护者入口）；
- S1–S9n、`移植参考/`、历史基线文档 → 各收敛为**1 行系列入口**（`⤷` 标记），
  深入由 `docs/S1-数据结构.md` / `docs/移植参考/fast-qr-索引.md` 统辖；
- 补一行**性能重点篇目导航**（S9b/S9d/S9f/S9g/S9h/S9l/S9m 的角色），
  弥补「不再平铺」后的可发现性。

### 2.2 wasm 体积章节：三处重复 → 一处

| 重复项 | 旧位置 | 处置 |
|--------|--------|------|
| `cmd/main` 体积双档表 | 「编译为 Wasm」正文 **+** 上方脚本注释 | 只留表，脚本注释改为指向表 |
| 「`wasm`(WASI) 已移除，其数据仅作历史记录」 | 共 **4 处**（体积块 ×2、性能块 ×1、开发与 CI ×1） | 统一到「能力与局限」+ 各块**一行**历史注记，删去展开式复述 |
| fast_qr 体积对照 A 块 | 正文 **+** 性能速览第 ③ 行 | 保留 A 块（唯一主口径），性能速览只留一行「见 [编译为 Wasm]」 |

### 2.3 性能章节：数字细节下沉，README 只留主口径

**问题**：旧「性能速览」把 S9k/S9l/S9m/S9n 的**实验倍数、护栏、方法学漏洞、编号体系**
（P0/P2/P2b、T-R1/T-R2/T-R4、H1–H6、ABAB 受控探针…）都写进了 README，
与 `docs/S9*.md` 高度重复，且读者难以判断哪条是**对外口径**。

**处置**：保留三件必需信息，其余下沉：

1. **主口径表**（S9j：三基准点单次 build 对比）+ 口径/环境护栏各一段；
2. **成本分解结论**（V40 score 68% / V03 wrap 44%）+ **已落地收益**（V40 −26%）；
3. **Roadmap 与上限**（P1 受阻、待做项、V40/V03 现实区间），**编号只提到项名**，
   实验方法与漏洞复评留给 [S9n](./S9n-优化方案复评与wasm-gc收敛审计.md)。

### 2.4 其他精简

| 项 | 处置 |
|----|------|
| 目录（TOC） | 「性能速览」→「性能与体积」（章节合并后同步） |
| 「开发与 CI」脚本表 | 由 12 行逐脚本 → **6 行按角色分组**（安装 / 门禁 / 性能 / 体积 / fast_qr 侧 / 生成器） |
| 「项目结构」注释 | 删去与 `docs/`/`S9x` 编号绑定的历史注释（`S9i`/`S9f` 等），只留事实 |
| 项目状态行 | 保留「111 单测 + 快照全绿，仅 `wasm-gc`」（与 `moon test` 实测一致） |

---

## 3. 验证

### 3.1 示例代码实测（不经 `.mbt.md`，手工复现）

在**独立临时模块**中建同名结构（`cmd/main` 调 `@lib`），把 README 示例**逐字复制**后执行：

```bash
# 临时模块通过 moon.work 引用本仓库（本仓库未发布至 mooncakes）
moon.work: members = [ ".", "/workspace" ]
moon.mod : import { "TryAndRun-TvT/fast_qr_moonbit@0.1.0" }

moon check --deny-warn   # 通过
moon run cmd/main        # 输出终端字符画 + "<svg viewBox=...>"（示例的四项设置均生效）
```

结论：示例与实码 API **一致**（`QRBuilder::from_string` / `SvgBuilder::default` /
`module_color` / `background_color` / `shape` / `to_str` / `QRCode::to_str` 全部存在且签名匹配）。

### 3.2 仓库门禁

```bash
moon fmt --check                                   # 通过
moon check --deny-warn                             # 通过
moon test --target wasm-gc                         # 111/111 通过
```

### 3.3 链接与可发现性

| 检查 | 结果 |
|------|------|
| README 内全部 `./docs/**`、`./LICENSE`、`./AGENTS.md` 相对链接 | **0 死链** |
| README 引用的 14 个 `scripts/*.sh｜*.mjs` | 全部存在 |
| `docs/` 顶层 24 篇 + `移植参考/` 语料 | 由 3 个系列入口（S1 / fast-qr 索引 / 实现布局）统辖，**无孤儿目录** |

---

## 4. 刻意取舍（为什么没有做得更「干净」）

| 取舍 | 理由 |
|------|------|
| **没有删除或合并任何 `docs/` 文档** | 它们是历史与实验依据，且文档间互链密集（`S9n` 被 4 处引用）；**删文档的代价远大于 README 掉几行索引** |
| **没有把 README 迁成 `README.mbt.md`** | 官方推荐且能让示例受 CI 保护，但会牵动 `moon.mod` 的 `readme` 字段、文件布局与文档约定（AGENTS.md），**属独立议题**，本次只做冗余清理 |
| **没有把 44 篇文档合并进少数几篇** | 「单文档 ≤800 行」（AGENTS.md）会立刻被违反；按 S 系列编号保留也更利于追溯提交历史 |
| **索引保留 `⤷` 系列入口而非彻底删掉 S 系列** | 读者仍需一条**可执行**的深入路径；纯删索引会让 `docs/S/` 变成不可发现的黑洞 |

> 若后续要继续瘦身，建议方向（**不在本次范围**）：① README 迁 `README.mbt.md` 让示例受 CI 保护；
> ② 把「体积历史口径」文档（S9e/S9f/S9g）合并为单篇「历史口径」并入 S9 系列；
> ③ 为 `docs/` 增设一份 `docs/索引.md`，让 README 的索引只保留 1 行链接。

---

## 5. 参考

- 官方：`moon.mod` readme 字段、`moon new` 模板、document test（`mbt check`）、mooncakes 元数据展示
  —— 链接见 §1.1 表格
- 前两轮记录：[README示例二维码-SVG资源与生成.md](./README示例二维码-SVG资源与生成.md)（第二轮 SVG 化）
- 对外口径来源：[S9j](./S9j-层②统一Node对比-wasm-gc与fast_qr.md) · [S9i](./S9i-纯库调用体积探针与库实际体积.md) ·
  [S9n](./S9n-优化方案复评与wasm-gc收敛审计.md)
- 本仓库实码：`README.md`、`moon.mod`、`.cnb.yml`、`scripts/`、`docs/`

---

## 6. 第三轮（2026-09-14）：从「去冗余」到「可检出漂移」

> 响应 ISSUE #47 新一轮「继续优化」。前两轮解决了**体积/重复**，本轮解决**可达性与可信度**：
> README 该有的「入口信号」缺失、示例无门禁、唯一图形资产存在渲染缺陷。

### 6.1 官方依据（本轮重新核验）

| 来源 | 结论 | 本轮落地 |
|------|------|---------|
| [CNB 徽章文档](https://docs.cnb.cool/zh/develops/badge.md) | 仓库相关徽章路径 `https://cnb.cool/{group}/{repo}/-/badge/{star\|fork\|release}`，直接嵌 Markdown 即可 | README 头部新增 star / fork / latest release + Apache-2.0 四个徽章（**逐个实测 HTTP 200**） |
| [MoonBit 包管理文档](https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html) | `moon new` 产 `README.mbt.md` + `README.md` 符号链接；`moon.mod` 元数据与 README 一同展示在 mooncakes.io | 恢复官方布局（§6.2） |
| [MoonBit Comments and Documentation](https://docs.moonbitlang.cn/zh-cn/latest/language/docs.html) | ```mbt check``` 代码块是 **document test**，由 `moon check`/`moon test` 运行 | README 示例改为文档测试（§6.3） |

> 前两轮**刻意没做**的两件事（§1.1 记为「可选的下一步」），本轮做了其中 ①「README 迁 `README.mbt.md`」；
> ②「`docs/索引.md`」仍未做（理由见 §6.6）。

### 6.2 README 恢复官方布局：`README.mbt.md` + 符号链接

- `git mv README.md README.mbt.md` + `ln -s README.mbt.md README.md`（与官方模板一致）；
  `moon.mod` 的 `readme` 仍解析到 `README.md`（符号链接）→ **mooncakes/平台零影响**。
- **代价（诚实声明）**：① 编辑链接需 **follow**（编辑器直接改 `README.md` 会写穿符号链接，
  也能工作，但 git 侧仍是同一个 blob）；② `docs-link-check.sh` 跳过内容相同路径；
  ③ 部分平台对符号链接的展示差异**未在本环境验证**（CNB 仓库页渲染待线上确认）。
- **收益**：README 示例从此可被 `moon check` / `moon test` 真正编译运行。

### 6.3 关键实测：模块根的 `.md` 何时才会被当作文档测试

这是本轮**唯一的硬技术障碍**，三种布局各跑一遍（临时模块 + `moon.work` 引用本仓库）：

| 布局 | `mbt check` 是否被执行 | 结论 |
|------|:---------------------:|------|
| 根 `README.mbt.md`，**根无 `moon.pkg`** | ❌ 完全不扫描 | 必需项缺失 → 文档测试静默失效 |
| 根 `README.mbt.md` + **根空 `moon.pkg`** | ✅ `moon test --outline` 出现 `README.mbt.md:174 index=0 readme_quick_start` | **采用** |
| 文档测试写在源码 `///` 注释里 | ✅ 同样被 `moon test` 执行 | 可作替代方案（但正文就不在 README 了） |

**结论**：官方 README 布局要真正生效，**模块根必须有 `moon.pkg`**（哪怕只写 `warnings`）。
本项目此前把「模块根零 `moon.pkg`」当作「方案 3」的标志，本轮把它修订为
「**模块根不放库代码**；根空包仅作文档测试宿主」（`docs/moonbit-实现布局与文件职责.md` §1 已改写）。

**`@lib` 的 `unused_package` 处理**：文档测试里的 `@lib` 对静态分析不可见 → 必须
显式 `warnings = "-29"`，否则 `moon check --deny-warn` 直接失败（**实测**）。

### 6.4 示例去重：正文示例与 `cmd/main` 合一

第二轮已把 README「快速开始」的 `SvgBuilder` 链式示例落进 `cmd/main/main.mbt`（消除 §3.1 的
「文档/CLI 不一致」）。本轮把 README 里那段 **13 行 `moonbit` 展示块**（正文示例的副本）
替换为**指向 `cmd/main/main.mbt` 的一行说明**，示例本体只保留在 `mbt check` 块——
**同一示例不再有两份载体**。

### 6.5 SVG 资产的渲染缺陷修正（`fill-rule`）

- **现象**：`docs/assets/qr-example.svg` 的子路径由「连续暗段」合并而来，**方向未归一化**；
  默认 `nonzero` 填充规则下，同向嵌套子路径会互相填充（定位图案中心、1 模块宽白缝）。
- **修法**：给 `<path>` 加 `fill-rule="evenodd"`（对同向/反向子路径都按奇偶覆盖判定），
  并**同步修改生成脚本**（`scripts/gen-readme-qr-svg.sh`）避免重生成回退。
- **口径**：这是**渲染健壮性**修正，几何语义（暗格集合）未变，仍与库矩阵逐格一致。

### 6.6 本轮数据与刻意取舍

| 指标 | 本轮前 | 本轮后 |
|------|:------:|:------:|
| `moon test --target wasm-gc` | 146 | **147**（+1 README 文档测试） |
| `moon fmt --check` / `moon check --deny-warn` | 绿 | 绿 |
| `docs-link-check` | 556 链零死链 | **625 链零死链** |
| README 头部徽章 | 0 | 4（all HTTP 200） |
| README 可被门禁校验的示例 | 0 | 1（`readme_quick_start`） |
| 根 `moon.pkg` | 无 | 1（空包，仅文档测试宿主） |

| 取舍 | 理由 |
|------|------|
| **不加 push CI 徽章** | 本仓库 push 流水线已于 2026-09-14 移除，徽章会长期显示 `unknown`（实测）→ 不诚实，不加 |
| **未加 `docs/索引.md`** | README 索引已收敛到 15 行系列入口；再拆一层会与 AGENTS 的「文档索引即入口」重复 |
| **未删任何 `docs/` 文档** | 同 §4：历史与实验依据，互链密集 |
| **README 正文仍为中文单语** | 与既有文档一致；英文摘要属独立议题（真要国际化应整篇做） |

### 6.7 一句话总结

> 本轮把 README 从「写给人看、只能靠人维护」推进到「**示例能被门禁验证**」：
> 头部有徽章（入口信号）、布局回归官方（`README.mbt.md` + 符号链接）、
> 示例进 `mbt check`（146 → 147 用例，改 API 不改示例即红）、
> 图形资产修掉真实渲染缺陷（`fill-rule="evenodd"`）。
> 唯一的结构性代价是**模块根多了一个空 `moon.pkg`**——它不做任何事，只为让文档测试被看见。
