# 项目文档导航与索引（README 的明细承接）

> 面向：**首次到访的读者**选择阅读路径 / **维护者**查找权威出处。
> 背景：ISSUE #47 多轮要求「README 过于冗杂 → 把内容转移到其他文档，README 只保留索引」。
> 第四轮（PR #75）已把 README 的**长口径**压成「结论 + 出处」；
> 第五轮（v5，PR #76）进一步**下沉全部细节**，README 只保留**落地页 + 索引**。
> 第六轮（v6，本文件同步）修「下沉后链接去哪」：README 指向 `docs/**` 与 `AGENTS.md` 的链接
> 一律改为**仓库绝对链接**（归档外目标在 mooncakes 落地页会 404），并新增
> `publish-check.sh` ⑤ 发布面可达性断言。详见
> [README优化 §9](./README优化-冗余清理与最佳实践.md#9-第六轮2026-09-14-v6发布面可达性闭环链接策略--发布状态--门禁-)。
> 日期：2026-09-14　｜　工具链：`moon 0.1.20260904`、`wasm-gc`　｜　维护者入口：[AGENTS.md](../AGENTS.md)

> **本文件 vs README 的链接形态**（重要，别改错）：
> 本文件**不在发布归档内**（`.moonignore` 排除 `/docs/`），故**全篇用相对链接**（仓库内导航面）；
> **README 在归档内**，故它指向 `docs/**` 一律用**绝对链接**。两处纪律不同，各按各的来。

---

## 0. 读者路径（先选一条，再按索引深入）

| 我是谁 | 建议阅读顺序 |
|--------|--------------|
| **只想用这个库** | [README 快速开始](../README.md#快速开始) → [公共 API 一览](#1-公共-api一览权威对照) → [`cmd/main`](../cmd/main/main.mbt) 实跑 |
| **想知道性能/体积能不能用** | [§2 性能与体积口径](#2-性能与体积口径权威出处) → S9p（宿主调用面主口径）→ S9q（统计纪律） |
| **想审计「数据是不是真的」** | [§2](#2-性能与体积口径权威出处) → [§3 测试与证据链](#3-测试与证据链权威出处) → `scripts/` 复跑命令 |
| **要发布到 mooncakes** | [§5 发布](#5-发布与元数据) → `bash scripts/publish.sh`（默认干跑） |
| **要改代码 / 提 PR** | [AGENTS.md](../AGENTS.md) → [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) → [§4 测试维护](#4-测试与覆盖率) |
| **AI / 协作者** | [AGENTS.md](../AGENTS.md)（硬性约定：密钥安全、布局、死链零容忍）→ 本文件 |

> **口径纪律**：README 只给**结论与入口**；**数字、参数、实验设计与历史记录**一律以本文档指向的出处为准。
> 若发现 README 与出处冲突，**以出处为准**，并改 README 的引用行（不要在两处各写一份数字）。

---

## 1. 公共 API 一览（权威对照）

README 只列**类型名**；签名、语义与用法以 `lib/*.mbt` 与 `.mbti` 快照为准，实跑示例见
[`cmd/main`](../cmd/main/main.mbt)（`moon run cmd/main`）。

| 类型 | 位置 |
|------|------|
| `ECL` / `Version` / `Mode` / `Mask` | `lib/ecl.mbt` · `lib/version.mbt` · `lib/mode.mbt` · `lib/mask.mbt` |
| `QRCode` / `QRCodeError` / 读写访问器 | `lib/qr.mbt` |
| `QRCode::build` / `build_fixed` / `select_capacity` | `lib/qr_build.mbt` |
| `QRBuilder` | `lib/qr_builder.mbt` |
| `Module` / `ModuleType` | `lib/module.mbt` |
| `SvgBuilder` / `Shape` | `lib/svg.mbt` · `lib/shape.mbt` |
| `to_str` / `print`（终端画） | `lib/helpers.mbt` |

- **完整公共契约快照**：`moon info` 产出的 `*.mbti`（构建产物，不入库）。
- **API 语义与移植对照**：[S6 端到端对齐与公共 API](./S6-端到端对齐与公共API.md)。
- **改动纪律**：改公共 API **必须**同步 README 的 `mbt check` 示例，否则 `moon test` 变红
  （见 [README 优化 §6](./README优化-冗余清理与最佳实践.md)）。

---

## 2. 性能与体积口径（权威出处）

> README 只保留「量级结论 + 复跑命令」；**表格、参数、实验设计、统计离散**全在本节列出的文档。

| 议题 | 权威文档 | 复跑命令 |
|------|----------|----------|
| **宿主调用面主口径**（JS 反复带参调 wasm，与 fast_qr `qr_with` 形态对称） | [S9p](./S9p-宿主调用面性能口径-JS向wasm传参.md) | `bash scripts/bench-host.sh` |
| **统计纪律**（为何取中位数、报离散、跨 run 不比绝对毫秒） | [S9q](./S9q-性能口径统计差异与取平均评估.md) | `bash scripts/bench-host-var.sh` |
| **层②**（统一 Node 进程内 shim vs fast_qr） | [S9j](./S9j-层②统一Node对比-wasm-gc与fast_qr.md) | `bash scripts/bench-layer2.sh` |
| **层①**（后端自身） | [S9c](./S9c-性能测试与fast_qr-wasm对比.md) · [S9e](./S9e-性能测试统一Node调用.md) | `bash scripts/bench.sh` |
| **库实际体积口径**（纯库调用探针，引用库体积请用这条） | [S9i](./S9i-纯库调用体积探针与库实际体积.md) | `bash scripts/bench-size.sh` |
| **体积对比 / 历史口径** | [S9f](./S9f-产物体积对比.md) · [S9g](./S9g-本项目wasm产物体积-确认与修正.md) | 同上 |
| **瓶颈成本分解与理论上限**（roadmap 依据） | [S9k](./S9k-性能瓶颈与理论上限评估.md) | — |
| **优化优先级统一清单 + 已落地项** | [S9n](./S9n-优化方案复评与wasm-gc收敛审计.md) | — |
| **已否决项** | [S9b](./S9b-性能优化.md) | — |
| **跨环境漂移归因**（Node 版本 / 调度态） | [S9h](./S9h-层②性能复测异常归因-Node版本与宿主漂移.md) | — |
| **脚本参数口径（审计入口）** | [性能测试脚本-公开评审说明.md](./性能测试脚本-公开评审说明.md) | — |
| **vs moonbit 生态 `moonqr`** | [S9d](./S9d-与moonbit生态QR包性能对比.md) | — |
| **数据重测与归因** | [S9o](./S9o-性能与体积数据重测-与README冗余清理.md) | — |

**README 保留的最小结论**（细节，勿在 README 展开）：

- vs fast_qr-wasm32：单次 build 慢 ≈1.3–2.5×（点数越小差距越大），**逐位对齐 sha256 零差异**；
- vs 生态 `moonqr`：全程快 2.5–4.1×（**历史口径**，未随最近一轮重测）；
- 产物体积：库对库对称锚点 **≈0.69×**（`wasm-gc` 更小），差距大头是**运行时地板**而非 QR 实现；
- **报告纪律**：只引用**同 run 内成对比值**；绝对毫秒绑定 Node 版本与调度态，跨环境不可比。

---

## 3. 测试与证据链（权威出处）

| 议题 | 权威文档 | 复跑命令 |
|------|----------|----------|
| **测试 roadmap / 覆盖差距矩阵 / 七条铁律** | [S10](./S10-测试用例设计与完善roadmap.md)（**测试维护入口**） | `bash scripts/test.sh` |
| **覆盖率报告 + 不下降门禁** | [S10b](./S10b-测试覆盖率报告.md) | `bash scripts/coverage.sh` · `--floor` |
| **真 bug 修复记录**（`select_capacity` 模式语义） | [S10c](./S10c-select-capacity模式语义缺陷-定位与修复.md) | — |
| **变异检测 / 第三方解码回读** | S10 附录 + [S11b](./S11b-清理落地记录-v3-v5.md) | `bash scripts/test-audit.sh mutation` · `decode` |
| **黄金值来源与重建** | S10 §5 铁律 1 | `bash scripts/gen-goldens.sh --verify` |
| **与参考 wasm 逐位差分** | [S9i](./S9i-纯库调用体积探针与库实际体积.md) | `bash scripts/diff-gate.sh` |

**README 保留的最小结论**：测试**按三载体分层**（黑盒 `*_test.mbt` / 白盒 `*_wbtest.mbt` / 源码内联）；
**用例数与文件数不写进 README**（会漂移），需要数字时以 `moon test` 实跑为准。

---

## 4. 测试与覆盖率

见 [§3](#3-测试与证据链权威出处)。维护者主入口：
[S10 测试 roadmap](./S10-测试用例设计与完善roadmap.md)（覆盖面与铁律）、
[S10b 覆盖率报告](./S10b-测试覆盖率报告.md)（数字与门禁标记）。

---

## 5. 发布与元数据

| 议题 | 权威文档 |
|------|----------|
| **发布入口**（流程核验、命名/元数据评估、版本策略、发布前门禁清单） | [mooncakes-发布方案.md](./mooncakes-发布方案.md) |
| **归档面收敛落地方案**（`.moonignore` 与 `publish-check.sh`，含负向验证） | [mooncakes-发布阻塞项3-4-落地方案.md](./mooncakes-发布阻塞项3-4-落地方案.md) |
| **模块名迁移记录**（`TryAndRun-TvT` + `moon publish --dry-run` 实测） | [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md) |

```bash
bash scripts/publish.sh            # 默认干跑（环境自检 + 发布前门禁 + 归档清单 + dry-run）
bash scripts/publish.sh --publish  # 真实发布（不可逆，需确认；凭据属本地私有，不进 CI）
```

---

## 6. 工程与协作（硬性约定）

| 议题 | 权威文档 |
|------|----------|
| **密钥安全 / 布局 / 文档死链零容忍**（贡献前必读） | [AGENTS.md](../AGENTS.md) |
| **文件级职责 / 无环依赖 / 测试放置** | [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) |
| **目录与包设置的官方依据 + 实证** | [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md) |
| **工具链安装与构建系统** | [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) |
| **无效代码/冗余文档判定口径与处置队列** | [S11](./S11-无效代码与冗余文档清理评估.md) · [S11b](./S11b-清理落地记录-v3-v5.md) |
| **README 历次优化总账**（含劣化复现与 §7 教训） | [README优化-冗余清理与最佳实践.md](./README优化-冗余清理与最佳实践.md) |
| **README 示例码资产与生成** | [README示例二维码-SVG资源与生成.md](./README示例二维码-SVG资源与生成.md) |

---

## 7. 实现系列（S1–S9）与历史基线

> 以下为**按实现顺序编号**的阶段文档与立项期基线：按需深入，不必顺序通读。
> 每篇含「实现方案 / 实现记录 / 评审与优化」等分部；`wasm`(WASI) 与 `js` 口径仅作**历史留存**，
> 现行口径见 [§2](#2-性能与体积口径权威出处) 与 [S9n](./S9n-优化方案复评与wasm-gc收敛审计.md)。

| 入口 | 内容 |
|------|------|
| [S1-数据结构.md](./S1-数据结构.md) | S1 → S9n 实现系列总入口（按阶段顺序进入） |
| [移植参考/fast-qr-索引.md](./移植参考/fast-qr-索引.md) | Rust 参考库 v0.14.0 的架构/接口/概念分析语料 |
| [项目基础框架-详细分析.md](./项目基础框架-详细分析.md) | 立项时的资产盘点、目标架构与分阶段路线（**历史基线**） |
| [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) | fast_qr 源码级核对 + 里程碑 roadmap（**历史基线**） |
| [core-仓库布局参考与目标架构.md](./core-仓库布局参考与目标架构.md) | 借鉴 `moonbitlang/core` 的拆包判据（`lib/` 布局依据） |
| [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) | **历史记录**：早期多后端编译运行对比 |
| [rust-环境配置脚本与fast_qr对比-setup.md](./rust-环境配置脚本与fast_qr对比-setup.md) | Rust 参考环境配置（`scripts/setup-rust.sh`） |

---

## 8. 全量文档清单（按文件名，供检索）

<details>
<summary>展开：<code>docs/</code> 全部文档（点击展开）</summary>

| 文档 | 角色 |
|------|------|
| [README优化-冗余清理与最佳实践.md](./README优化-冗余清理与最佳实践.md) | README 优化总账（§1–§8） |
| [README示例二维码-SVG资源与生成.md](./README示例二维码-SVG资源与生成.md) | 示例码资产规格与生成 |
| [模块名迁移与发布链路核验.md](./模块名迁移与发布链路核验.md) | 发布链路核验 |
| [性能测试脚本-公开评审说明.md](./性能测试脚本-公开评审说明.md) | 脚本参数口径 |
| [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) | 维护者入口 |
| [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) | 工具链/构建 |
| [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md) | 目录设置依据 |
| [mooncakes-发布方案.md](./mooncakes-发布方案.md) | 发布入口 |
| [mooncakes-发布阻塞项3-4-落地方案.md](./mooncakes-发布阻塞项3-4-落地方案.md) | 发布落地 |
| [rust-环境配置脚本与fast_qr对比-setup.md](./rust-环境配置脚本与fast_qr对比-setup.md) | 参考环境 |
| [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) | 历史记录 |
| [core-仓库布局参考与目标架构.md](./core-仓库布局参考与目标架构.md) | 布局依据 |
| [项目基础框架-详细分析.md](./项目基础框架-详细分析.md) | 历史基线 |
| [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) | 历史基线 |
| S1 / S2 / S3 / S4 / S5 | 数据结构 · 常量表与 GF256 · 数据编码 · 矩阵与放置 · 掩码评分 |
| S6 / S7 / S8 | 端到端与公共 API · 输出层 · 内部结构归位与分层 |
| S9 / S9b–S9q | 性能与体积全套（见 [§2](#2-性能与体积口径权威出处)） |
| S10 / S10b / S10c | 测试 roadmap / 覆盖率 / 真 bug 修复 |
| S11 / S11b | 清理评估 / 清理落地记录 |
| [移植参考/](./移植参考/fast-qr-索引.md) | Rust fast_qr 语料（索引统辖） |

</details>

> **新增文档时**：请同时更新本文件与 [README 文档索引](../README.md#文档索引)；
> `bash scripts/docs-link-check.sh` 会校验相对链接是否存在（死链零容忍）。
