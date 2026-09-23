# TryAndRun-TvT/fast_qr_moonbit

> 基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。
> 纯 MoonBit 实现、无外部依赖，逐位对齐 Rust 参考库 [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr)。

[![mooncakes](https://cnb.cool/svg/badge/mooncakes?message=TryAndRun-TvT%2Ffast_qr_moonbit&color=blue)](https://mooncakes.io/docs/TryAndRun-TvT/fast_qr_moonbit)
[![star](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/star)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit)
[![fork](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/fork)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit)
[![latest release](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/badge/release)](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/releases)
[![license](https://cnb.cool/svg/badge/license?message=Apache-2.0&color=green)](./LICENSE)

**项目状态**：功能对齐收口（M0–M3 里程碑 ✅），`moon test` 全绿（含快照与 README 文档测试），
仅 `wasm-gc` 后端回归通过。

<img src="https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/git/raw/main/docs/assets/qr-example.svg" alt="由 fast_qr_moonbit 生成的二维码：内容 https://example.com/" width="220" height="220">

示例二维码（内容 `https://example.com/`，由 `SvgBuilder` 生成、**SVG 矢量**，缩放不失真）；
复跑 `moon run cmd/main` 可同时看到终端字符画与 SVG 输出。

| | |
|---|---|
| **语言** | [MoonBit](https://www.moonbitlang.cn/)（**仅 `wasm-gc`**） |
| **标准** | ISO/IEC 18004 二维码（版本 V01–V40，ECL L/M/Q/H，8 掩码评分择优） |
| **许可** | [Apache-2.0](LICENSE) |
| **参考** | Rust [fast_qr v0.14.0](https://github.com/erwanvivien/fast_qr) 逐位移植对齐 |
| **性能/体积** | 单次 build 慢 fast_qr ≈1.3–2.5×（逐位零差异）· 库体积约 **0.69×**　→ [量级与出处](#性能与体积) |
| **测试** | 三载体分层（黑盒/白盒/文档测试）· 变异检测 + 第三方解码回读全绿　→ [证据链](#测试) |

> 本页是**落地页**：只给「能做什么 / 怎么用 / 边界在哪 / 去哪看细节」。
> **数字、参数、实验设计与历史记录**一律在 [`docs/`](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/README.md)，
> 本页的每条结论都带出处链接。

---

## 目录

- [功能特性](#功能特性)
- [能力与局限](#能力与局限)
- [快速开始](#快速开始)
- [构建与运行](#构建与运行)
- [性能与体积](#性能与体积)
- [测试](#测试)
- [文档索引](#文档索引)
- [项目结构](#项目结构)
- [工程约定与贡献](#工程约定与贡献)
- [License](#license)

---

## 功能特性

- **纯 MoonBit 实现**，无外部依赖，可直接 `moon add` 依赖到你的项目。
- **标准合规**：ISO/IEC 18004 —— 版本 V01–V40、四种纠错级别、三模式自动编码
  （Numeric / Alphanumeric / Byte）+ 自动回退、8 种掩码评分择优。
- **逐字节对齐参考**：矩阵与 fast_qr v0.14.0 全量快照逐位一致，可被第三方解码器读回原文。
- **单后端产物**：仅 `wasm-gc`（体积小、性能好；宿主需支持 GC 提案）。
- **两用接口**：过程式 `QRCode::build` 编排入口 + 链式 `QRBuilder` 便捷构造器。
- **多样输出**：终端字符画（`to_str`/`print`）与 SVG 字符串（`SvgBuilder`，6 种模块形状）。

## 能力与局限

| 能力 | 说明 |
|------|------|
| 编码内容 | **字节（ASCII）** 输入；自动选择 Numeric / Alphanumeric / Byte，也可强制指定模式 |
| 版本/纠错 | 自动最小适配或强制指定版本 V01–V40；ECL 缺省 Quartile(Q)，可显式 L/M/Q/H |
| 掩码 | 自动 8 轮评分择优，或指定固定掩码（走快速路径） |
| 输出 | 终端 Unicode 字符画、SVG 字符串 |

已知局限（诚实声明）：

- **编码模式**仅支持 Byte/Alphanumeric/Numeric；**Kanji 模式暂不支持**（与参考 fast_qr 一致）。
- 输入按 **ASCII 字节** 处理（非 ASCII 多字节字符的语义见 [S6 评审记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/01-规格/S6-端到端对齐与公共API.md) 的优化建议）。
- 产物形态面向 **wasm**：MoonBit `Int` 32 位、纠错位流 `KEEP_LAST=33`（取 Rust wasm32 分支），
  对真实 QR 语义无差别（详见 [S9 评估记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9-性能基准.md) §2.4）。
- **仅支持 `wasm-gc`**：`moon.mod` 声明 `supported_targets = "+wasm-gc"`，下游 `native`/JS 消费者会被构建系统
  直接拒绝（实测 `does not support target backend 'native'`）。库本身是纯 MoonBit，此为**有意的分发范围收缩**；
  其中 `native` 另需系统 C 编译器（当前 CI/本地镜像未装）。
- **宿主需支持 wasm-gc（GC 提案）**：如 Node ≥ 22 / V8、启用 GC 的 wasmtime；CLI `println` 依赖
  `spectest.print_char` 导入（非标准 WASI）。`wasm`(WASI) 通用兜底已移除，宿主接入面相应变窄。
  取舍与复核见 [S9n wasm-gc 收敛审计](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9n-优化方案复评与wasm-gc收敛审计.md) §1。

---

## 快速开始

在项目根目录（`moon.mod` 所在处）添加本库为依赖：

```bash
moon add TryAndRun-TvT/fast_qr_moonbit
```

> **发布状态**：**已发布（首个版本）**；本页为**仓库当前文档**，
> 可能领先于线上归档，精确版本以 [mooncakes 页面](https://mooncakes.io/docs/TryAndRun-TvT/fast_qr_moonbit) 为准。
> 发布流程与发布前门禁见[文档索引](#文档索引) → 发布相关篇目；
> 发布动作已脚本化：`bash scripts/publish.sh`（默认干跑，`--publish` 真发）。

在 `moon.pkg` 中声明依赖并起别名（本库包路径为 `.../lib`，别名默认即目录名 `lib`）：

```toml
import {
  "TryAndRun-TvT/fast_qr_moonbit/lib",
}
```

然后即可用 `QRBuilder` 生成二维码——下面的示例**由门禁真编译真运行**（`mbt check` 文档测试），
可运行版本另见 [`cmd/main/main.mbt`](cmd/main/main.mbt)（`moon run cmd/main` 输出字符画 + SVG）。

```mbt check
///|
test "readme_quick_start" {
  let qr = @lib.QRBuilder::from_string("https://example.com/").build()
  match qr {
    Ok(q) => {
      // V02 → 边长 4*2+17 = 25；访问器返回 Option（手搓 QRCode 无元数据）
      assert_eq(q.size(), 25)
      assert_eq(q.version().unwrap().width(), q.size())
      assert_eq(q.ecl().unwrap(), @lib.ECL::Q)
      assert_true(q.to_str().length() > 0)
      let svg = @lib.SvgBuilder::default()
        .module_color("#0000ff")
        .background_color("#ffffff")
        .shape(@lib.Shape::RoundedSquare)
        .to_str(q)
      assert_true(svg.has_prefix("<svg"))
    }
    Err(_) => abort("README 示例内容构建失败")
  }
}
```

> 上面的 `mbt check` 块是 **document test**：`moon test` 会真编译、真运行它——
> 改公共 API 而不同步改示例，测试直接变红。机制与踩坑见
> [README优化-冗余清理与最佳实践.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/README优化-冗余清理与最佳实践.md) §6.3。

**下一步**：可用类型一览、逐格矩阵读写与从零自建示例，见
[公共 API 与矩阵读写明细](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#3-公共类型一览readme-旧正文承接)；
完整公共契约以 `moon info` 的 `.mbti` 与 `lib/*.mbt` 为准。

---

## 构建与运行

先安装 MoonBit 工具链：

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

模块根不设包（core 式布局）：库包在 `lib/`，CLI 在 `cmd/main/`，构建需显式给包名。

```bash
moon build lib                    # 编译库包
moon build cmd/main --release     # 编译 CLI（唯一后端 wasm-gc）
moon run   cmd/main               # 运行 CLI 演示（终端字符画 + SVG）
moon test                         # 运行单元/快照/文档测试
```

提交前本地收尾检查（对齐门禁）：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon info && moon check --deny-warn && moon test
moon build lib --target wasm-gc --release
moon build cmd/main --target wasm-gc --release
moon test --target wasm-gc
```

> **没有 push CI**（2026-09-14 移除，每次推送重复全量构建收益不成比例）。
> 门禁改为**本地一键**：`bash scripts/gates.sh`（`fmt-check → check → test → docs-link-check →
> docs-ref-check → docs-index → docs-consistency → test-scale → build-and-run → diff-gate → publish-check`；
> 支持 `STAGES="check test"` / `SKIP_SLOW=1`）。
> 提交前跑一遍是**必须**动作。脚本分组与逐个用途见
> [S9r §4 脚本分组](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#4-脚本分组readme-旧正文承接)。

`-Oz` 体积最优档的命令、`moon-wasm-opt` 参数与「为何要 `--disable-custom-descriptors`」，
见 [S9r §1](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#1-产物体积release-bash-scriptsbench-sizesh)。

---

## 性能与体积

> 数字仅作选型与迭代基线，**不代表对 fast_qr 的追赶承诺**。本页只给量级；
> **表格、参数、统计离散与护栏**见 [S9r · 明细](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#2-性能三口径核心结论表)。

- **性能 vs fast_qr-wasm32**：单次 build 慢 **≈1.3–2.5×**（点数越小差距越大），
  **逐位对齐 sha256 零差异**；差距集中在 8 轮掩码择优主循环。
  复跑 `bash scripts/bench-host.sh`　→ 口径 [S9p](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9p-宿主调用面性能口径-JS向wasm传参.md) · 离散 [S9q](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9q-性能口径统计差异与取平均评估.md)
- **性能 vs 生态 `moonqr`**：全程快 **2.5–4.1×**（**历史口径**，未随最近一轮重测）。
  复跑 `bash scripts/bench-layer2.sh`　→ [S9d](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9d-与moonbit生态QR包性能对比.md)
- **体积 vs fast_qr**：库对库对称锚点 **≈0.69×**（本仓库更小）；差距大头是**运行时地板**，非 QR 实现。
  复跑 `bash scripts/bench-size.sh`　→ [S9i](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9i-纯库调用体积探针与库实际体积.md)
- **优化状态**：已落地 P0 掩码特化 + P2 评分去闭包/列缓冲 + P2b，V40H 受控 A/B **−26%**（输出逐位不变）；
  待做与上限见 [S9n](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9n-优化方案复评与wasm-gc收敛审计.md) · [S9k](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9k-性能瓶颈与理论上限评估.md)
- **报告纪律**：只引用**同 run 内成对比值**；绝对毫秒绑定 Node 版本与调度态，跨环境不可比（[S9q](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9q-性能口径统计差异与取平均评估.md)）。

## 测试

- **分层**：黑盒 `*_test.mbt`（锁公共契约）/ 白盒 `*_wbtest.mbt`（锁实现）/ README `mbt check`（文档测试）。
- **证据链**：变异检测（植入最小缺陷须被检出）+ 第三方解码回读（jsQR 读回原文）+
  黄金值钉版重建 + 与参考 wasm 逐位 sha256 差分。
- **门禁**：`bash scripts/gates.sh`（全量）· 单项 `scripts/test.sh`、`scripts/coverage.sh --floor`。
- **维护入口**：[S10 测试 roadmap](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10-测试用例设计与完善roadmap.md)（覆盖矩阵 + 七条铁律）·
  [S10b 覆盖率报告](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10b-测试覆盖率报告.md) · [S10c 真 bug 修复记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10c-select-capacity模式语义缺陷-定位与修复.md)。

> **用例数与文件数不写进 README**——它们随实现漂移，写死必然自相矛盾。需要数字时以 `moon test` 实跑为准。

---

## 文档索引

> **本页只保留落地页所需的入口**；文件名前缀 `S1`–`S9r` 为按实现顺序编号的阶段文档。
> 面向**本仓库读者**的完整导航（读者路径 / 按议题 / 全量清单）在
> [`docs/README.md`](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/README.md)；
> 面向**发布归档读者（mooncakes 落地页）**的明细承接一律用**仓库绝对链接**（见文末「链接约定」）。

| 我想… | 去哪 |
|-------|------|
| **用这个库** | 本页[快速开始](#快速开始) → [公共 API 与矩阵读写](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#3-公共类型一览readme-旧正文承接) |
| **看性能/体积明细** | [S9r 明细承接](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md) · [S9p](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9p-宿主调用面性能口径-JS向wasm传参.md) · [S9i](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9i-纯库调用体积探针与库实际体积.md) |
| **看测试与证据链** | [S10 roadmap](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10-测试用例设计与完善roadmap.md) · [S10b 覆盖率](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10b-测试覆盖率报告.md) · [S10c 修复记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S10c-select-capacity模式语义缺陷-定位与修复.md) |
| **发布到 mooncakes** | [mooncakes-发布方案.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/mooncakes-发布方案.md) · [发布阻塞项落地](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/mooncakes-发布阻塞项3-4-落地方案.md) · [模块名迁移核验](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/模块名迁移与发布链路核验.md) |
| **改代码 / 提 PR** | [AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/AGENTS.md)（**硬性约定**）· [实现布局与文件职责](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/01-规格/moonbit-实现布局与文件职责.md) · [目录设置最佳实践](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/01-规格/moonbit-项目目录设置-最佳实践.md) |
| **审计脚本与口径** | [性能测试脚本-公开评审说明.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/性能测试脚本-公开评审说明.md) · [S9r §4 脚本分组](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S9r-README性能体积长口径与公共API明细.md#4-脚本分组readme-旧正文承接) |
| **README 为何这样写** | [README优化-冗余清理与最佳实践.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/README优化-冗余清理与最佳实践.md) · [示例码资产与生成](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/README示例二维码-SVG资源与生成.md) |
| **清理/收敛评估** | [S11 评估入口](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S11-无效代码与冗余文档清理评估.md) · [S11b 落地记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S11b-清理落地记录-v3-v5.md) · [S11c 第6轮体检](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/02-证据/S11c-第6轮体检-工具链漂移与门禁假绿修复.md) |
| **改 / 新增文档** | [S12 文档体系规范](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/S12-文档体系SDD诊断与优化方案.md)（准入 CheckList · 状态字段 · 防漂移门禁）· [S12b 落地记录](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/04-元/S12b-落地记录-门禁落地与D2目录分类.md)（门禁自身审计 · D2 目录分类） |
| **看实现系列文档** | ⤷ [S1 数据结构](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/01-规格/S1-数据结构.md)（S1–S9 系列总入口）· ⤷ [fast_qr 移植参考](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/移植参考/fast-qr-索引.md) |
| **看历史基线** | ⤷ [项目基础框架](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/项目基础框架-详细分析.md) · ⤷ [重写 roadmap](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/moonbit-重写-roadmap-详细分析.md) · ⤷ [wasm 编译运行分析](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/03-过程/wasm-编译与运行-结果分析.md) |

> **全量清单**（含 `docs/` 全部篇目与角色）在
> [docs/README.md §8](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/README.md#8-全量文档清单按文件名供检索)。
> 新增文档须同步更新该文件与本表，否则 `bash scripts/docs-link-check.sh` 与
> `scripts/docs-consistency.sh` ③ 会红（死链零容忍 + 索引覆盖）。

### 链接约定（本仓库文档纪律）

发布归档（mooncakes）**只收录随包分发面**（`README.md` / `LICENSE` / `lib/**` / `cmd/main` 等），
`.moonignore` 显式排除 `/docs/` 与 `/AGENTS.md`。因此 README 里指向它们的**相对链接**
在 mooncakes 落地页会被重写为 `assets.mooncakes.io/source/.../docs/...` 而 **404**。
本页采用如下约定（由 `bash scripts/publish-check.sh` 的 ⑤ 断言兜底）：

| 链接目标 | 形态 | 例 |
|----------|------|-----|
| `README.md` / `LICENSE` / `cmd/main/**`（**在归档内**） | 相对链接 | [`./cmd/main/main.mbt`](cmd/main/main.mbt) |
| `docs/**` / `AGENTS.md`（**不在归档内**） | **仓库绝对链接**（`https://cnb.cool/.../-/blob/main/...`） | 见上表「我想… → 去哪」 |
| 本页内锚点 | 相对锚点 | [快速开始](#快速开始) |
| 图片资产 `docs/assets/**`（**不在归档内**） | **仓库绝对直链**（`/-/git/raw/main/...`，实测 `image/svg+xml`） | 本页头部示例二维码 |

> **硬约束（门禁 ⑤ 断言）**：本页**不含**任何 `./docs/**` 或 `./AGENTS.md` 相对链接——
> 否则归档读者必 404。在仓库内需要相对导航时，请到
> [`docs/README.md`](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/README.md)
> （该文件在仓库内使用相对链接，属**仓库内导航面**；它不在归档内，故不受归档约束）。

---

## 项目结构

```
.
├── moon.mod                    # MoonBit 模块配置
├── moon.pkg                    # 模块根空包：README 文档测试宿主（不写库代码）
├── lib/                        # 库包（公共 API）
│   ├── ecl / version / mode / mask.mbt  # 公共枚举（ECL/Version/Mode/Mask）
│   ├── module / qr / qr_build / qr_builder.mbt  # 容器、编排入口、链式构造器
│   ├── helpers / svg / shape.mbt        # 输出层（终端画 + SVG）
│   ├── *_test.mbt / *_wbtest.mbt        # 黑盒测试 / 白盒测试
│   └── internal/               # 实现子包（各带 moon.pkg；不反向依赖 lib）
│       ├── constants/          #   常量表 + 容量/元数据表
│       ├── bitstream/          #   位流缓冲（CompactQR）
│       ├── reedsolomon/        #   GF(256) 除法 + 交织
│       ├── data_encoding/      #   三模式编码 + 自动回退
│       └── matrix/             #   放置 / 掩码 / 评分
├── cmd/                        # 可执行包：main（CLI）/ bench / qr-min / host-probe
├── docs/                       # 项目文档（入口 = docs/README.md，见「文档索引」）
│   ├── README.md               #   目录首页：读者路径 + 分类地图 + 全量清单（§8 生成物）
│   ├── 01-规格/ 02-证据/        #   D2 分类：实现规格 / 审计数据
│   ├── 03-过程/ 04-元/          #   D2 分类：历史基线+发布过程 / 文档与 README 元规范
│   ├── 移植参考/                #   fast_qr 外部语料（自成一域，由域首页统辖）
│   └── assets/                 #   文档资源（qr-example.svg = README 示例码）
├── scripts/                    # 构建/门禁/基准脚本（分组见 S9r §4）
├── .githooks/ .cnb.yml         # 可选 Git 钩子 / 云原生构建配置
├── AGENTS.md                   # AI 协作代理指南（贡献前必读）
├── README.mbt.md -> README.md  # 文档测试入口（符号链接；正文在 README.md）
└── LICENSE                     # Apache-2.0
```

> **布局纪律**：模块根只放元数据；库代码一律 `lib/`，实现细节 `lib/internal/`，**不要建 `src/`**。
> 唯一例外是根 `moon.pkg`（空包，README 文档测试宿主）。
> 测试放所属包内，`*_test.mbt`（黑盒）与 `*_wbtest.mbt`（白盒）**不可混用**。
> 文件级职责见 [moonbit-实现布局与文件职责.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/docs/01-规格/moonbit-实现布局与文件职责.md)。

---

## 工程约定与贡献

- **硬性约定（贡献前必读）**：[AGENTS.md](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/blob/main/AGENTS.md)——密钥/Token 永不入库、
  不提交本地配置与构建产物、MoonBit 布局、文档死链零容忍、README 只保留结论+出处。
- **门禁**：`bash scripts/gates.sh`（一键全量）。**没有 push CI**，本地跑是唯一自动闸门。
- **发布**：`bash scripts/publish.sh`（默认干跑）。凭据属本地私有，**发布不进 CI**。
- **问题与建议**：提交至仓库 [Issue](https://cnb.cool/tryandrun/moonbit_dev/fast_qr_moonbit/-/issues)。
- **Git 钩子（可选）**：`git config core.hooksPath .githooks`（属个人本地配置，仓库不代设）。

---

## License

[Apache-2.0](LICENSE)
