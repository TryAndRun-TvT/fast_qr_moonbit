# core 仓库布局参考与本项目目标架构

> **状态**：历史　｜　日期：2026-09-05　｜　索引：[docs/README-导航与索引.md](README-导航与索引.md) §7　｜　并入：布局结论已并入 [moonbit-实现布局与文件职责](moonbit-实现布局与文件职责.md)

> 依据对官方标准库 `moonbitlang/core`（下称 **core**）实际布局的逐项研究，
> 结合本仓库当前骨架阶段的真实状态，给出 **借鉴而非照搬** 的目标架构设计
> 与分阶段落地路线。
>
> 研究日期：2026-09-05　｜　参考版本：`moonbitlang/core@main`（commit 452eb70）
> 参考仓库：<https://github.com/moonbitlang/core>

---

## 〇、研究结论（一句话）

core 最值得借鉴的三点：**包 = 功能目录**（每目录一个 `moon.pkg`）、
**`internal/` 隐藏实现细节**（对外只暴露高层公共包）、
**文档下沉到包内 `README.mbt.md` 且用可执行的 `mbt check` 代码块自我校验**。
但其巨型多包子目录树对当前仍是骨架的本仓库**不宜照搬**——过早建空包会破坏
`moon check`（无 `.mbt` 或声明未用依赖都会失败），应在实现时按路线逐步落地。

---

## 一、core 布局要点（研究摘录）

### 1.1 根级文件

```
moon.mod            # 模块名/版本/readme/repository/license/keywords/warnings
README.md           # 仓库入口，含「架构一瞥」依赖关系图 + mooncakes 文档链接
AGENTS.md           # 代理硬性约定（块风格、deprecated.mbt、moon info/fmt/test 流程）
LICENSE / NOTICE / CHANGELOG.md / CONTRIBUTING.md
.github/ .githooks/ .devcontainer/ .vscode/
bench/ test/        # 跨包基准与通用测试基座
```

> `moon.mod` 的 `readme = "README.md"` 直接指向真实文件（本仓库现亦采用单一真实
> `README.md`，不沿用官方 `README.mbt.md` + 符号链接布局，见 README「项目结构」）。

### 1.2 包组织（核心模式）

- **包 = 功能目录**，每个目录一个 `moon.pkg`；`moon.pkg` 的 `import` 声明该包
  依赖，`for "test"` 声明仅供测试的依赖。
- **`internal/` 私有实现**：对外不可见的内部子包放在 `internal/` 下，
  供模块内部高层包复用。例：
  - `random/`（公共）→ `random/internal/random_source`（内部实现，仅上层依赖）
  - `internal/strconv`、`internal/regex_engine`、`internal/edit_distance` 等
- 一个包的 `.mbt` 常按职责拆多文件，共享同一 `moon.pkg`：
  例如 `encoding/hex` = `encode.mbt` + `decode.mbt` + `extends.mbt` +
  `encode_test.mbt` + `decode_test.mbt` + 若干 `*_wbtest.mbt`。
- **`extends.mbt`**：集中放 trait 方法提升（`pub extend`）的扩展块。
- **`deprecated.mbt`**：本目录的弃用代码统一放此文件（多个目录都有）。

### 1.3 测试文件分型

| 文件 | 类型 | 说明 |
|------|------|------|
| `*_test.mbt` | 黑盒（包外） | 只访问 `pub` API |
| `*_wbtest.mbt` | 白盒（包内） | 访问私有实现 |
| `*_bench_test.mbt` | 基准 | 与 `bench/` 配合做性能回归 |
| `*_quickcheck_test.mbt` / `quickcheck/` | 性质测试 | 随机输入验证性质 |

`_test.mbt` 中声明的测试夹具建议标 `priv`，避免 `implicit_impl_as_method`
误触发而被迫写 `pub extend` 样板。

### 1.4 每包一份 `README.mbt.md`

63+ 个包目录各有 `README.mbt.md`，用可执行的 `mbt check` 代码块做 API 示例
（会被 `moon check`/`moon test` 校验，防文档与代码脱节）。例如 `random/README.mbt.md`
直接给出 `@random.Rand::new()` 的用法与快照断言。

### 1.5 文档即代码、接口快照

- `moon info` 生成每包 `pkg.generated.mbti` 接口快照；`.mbti` 无变化 → 安全重构。
- `moon fmt && moon info && moon test` 为收尾流程；`deprecated` 用
  `#deprecated(..)` + `#doc(hidden)` 标注。
- core 的 `moon.mod` 开 `warnings = "+…+missing_doc+…"`，把缺文档告警也纳入，
  驱动公共 API 全带文档注释。

---

## 二、借鉴原则（照抄会出错的地方）

core 布局是「数十个互相依赖的功能包子包」+「跨包基准/性质测试」的大仓库形态。
本仓库是**单一目标库**（二维码生成），骨架阶段更接近 `bool/`、`option/` 这类
单包叶子模块，而非 core 的顶层多包树。因此：

| core 做法 | 本仓库是否采用 | 理由 |
|-----------|:---:|------|
| 按功能拆目录子包 | ✅ 目标态 | 实现 QR 到一定复杂度后值得拆（见 §四） |
| `internal/` 藏内部实现 | ✅ 目标态 | 对外只暴露顶层公共包，隐藏矩阵/位流等内部层 |
| 每包 `README.mbt.md` | ✅ 目标态 | 代码示例可执行自校验 |
| 顶层多包树 | ❌ 不采用 | 本仓库一个库，无 multi-crate 需求；避免过早建空包 |
| `bench/` / `quickcheck/` 顶层基座 | ⏳ 后置 | 有真实 QR 算法后可再评估，暂不引入 |
| `extends.mbt` trait 提升块 | ⏳ 后置 | 涉及具体 trait 设计，非布局任务 |

---

## 三、当前骨架布局（维持，不做空包化）

当前布局与 `moon new` 官方骨架一致，且 `moon check --deny-warn` / `moon test`
全绿，**无需迁移目录**。QR 公共 API 尚未实现，此时为「未来子包」建空目录将：

- 空目录 `moon.pkg` 若无 `.mbt` 内容无意义；若放入仅声明未用依赖又会触发
  `unused_package` 告警使 `moon check` 失败。
- 违背 `AGENTS.md`「依赖声明后必须使用」「不提前声明」约定。

因此骨架阶段正确做法是把目标架构**记录在案**（见 §四），实现时按路线逐步落地，
而不是现在就把目录铺开。

---

## 四、目标包架构（借鉴 core，逐步落地）

> 落地更新（2026-09-05，方案 3）：本仓库已进一步采用 core 的「模块根不建包」形态——
> 库包收口在 `lib/`（公共 API），实现子包在 `lib/internal/`；本节目标树中「根公共包/
> 模块根包」即 `lib/` 包。权威落地版见
> [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md)。

实现 QR 功能时，建议在 `lib/` 公共包之下按 core 的 `internal/` 模式
补充实现子包。以「公开编码入口（`encode`/QR 数据结构）在公共包，
编码细节下沉 `lib/internal/`」为骨架：

```
lib/                              # 公共包：对外 API（QRCode / encode 等）
├── qr.mbt / helpers.mbt 等        #   公共类型与入口（按职责分文件，不设同名入口注释文件）
├── version.mbt                  #   版本/纠错等级/掩码等公共枚举与常量
├── encode.mbt                   #   公共编码入口：bytes/str → 码矩阵
├── *_test.mbt / *_wbtest.mbt    #   黑盒/白盒测试（公共行为）
└── internal/                    # 内部实现（对模块外不可见）
    ├── matrix/                  #   最终矩阵（取模图形 + 掩码应用）等
    ├── reedsolomon/             #   Reed-Solomon 纠错码（可选再拆）
    ├── bitstream/               #   数据位流封装（可选）
    └── data_encoding/           #   ECI/数字/字母数字/字节/汉字 模式编码（可选）
```

> 说明：
> - `internal/` 下子包各自带 `moon.pkg`，仅被模块内其它包依赖；模块外的用户
>   只能通过根包公共 API 触达，接口面更干净——这正是 core `random` 的形态。
> - 根公共包建议**只放面向调用者的类型/函数**，把纯实现细节留在 `internal/`，
>   从而把 `.mbti` 对外接口快照约束到最小、稳定。
> - 子包 `.mbt` 文件可自由命名（`encode.mbt`/`decode.mbt`/`matrix.mbt`…），
>   不必与目录同名；共享各自目录的 `moon.pkg`。
> - 每个功能子包建议配一份 `README.mbt.md`，示例用 `mbt check` 代码块自校验。

### 何时才拆包（落地判据）

建议**先全部实现在根包内**（一个 `moon.pkg`，多 `.mbt` 文件），直到出现下列
信号之一再拆 `internal/`：

1. 根包 `.mbt` 文件过多、彼此耦合成度明显分层（如编码 vs 矩阵 vs 纠错）；
2. 需要把某块内部实现独立测试且不便走公共 API；
3. 公共 API 出现只想对内部暴露、不想进 `.mbti` 的类型。

早拆的代价（文件间移动、依赖重连、`.mbti` 变动）高于晚拆的收益；core 的
`internal/` 是为「对外隐藏」而非「凑目录」而设。

---

## 五、落地清单（供实现时对照）

- [ ] P0 先在根包实现最小可用 QR 编码（单包、多 `.mbt`），补真实测试替换
      `assert_true(true)`。
- [ ] P0 让 `cmd/main` 声明 `import { "TryAndRun-TvT/fast_qr_moonbit/lib" @lib }`
      并真正调用库 API（首次实际调用时才加，勿提前）。
- [ ] P1 当出现 §四「何时才拆包」任一信号时，按 §四 目标树拆 `internal/` 子包，
      每个目录带 `moon.pkg` 与 `README.mbt.md`。
- [ ] P1 弃用接口统一放各目录 `deprecated.mbt`，用 `#deprecated` + `#doc(hidden)`。
- [ ] P1 公共 API 全带 `///` 文档；可选在 `moon.mod` 打开
      `warnings = "+missing_doc+…"`（仿 core）驱动文档完备。
- [ ] P2 引入基准/性质测试（`*_bench_test.mbt` / quickcheck）时再评估顶层
      `bench/` 基座，避免现在空建。

> 优先级标注与 [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) §六 一致。

---

## 六、参考

- [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md) —
  `moon new` 官方目录树与包/测试约定（本仓库既有依据）
- [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) — 本仓库布局整理与遗留待办
- [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) — 后端选型与产物
- moonbitlang/core 布局实证：<https://github.com/moonbitlang/core>
