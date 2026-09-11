# MoonBit 项目目录设置 · 最佳实践

> 依据 MoonBit 官方文档（v0.10.11）整理，并结合本仓库的本地实证验证。
>
> 日期：2026-09-05　｜　工具链：`moon 0.1.20260827 (d0aaa07)`

---

## 一、官方权威依据

| 文档 | 链接 |
|------|------|
| MoonBit 构建系统教程（含「理解模块目录结构」） | <https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html> |
| 模块配置（`moon.mod`） | <https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html> |
| 包配置（`moon.pkg`） | <https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package.html> |

### 官方标准目录树（教程原文）

```
my_project
├── Agents.md
├── cmd
│   └── main
│       ├── main.mbt
│       └── moon.pkg
├── LICENSE
├── moon.mod
├── moon.pkg
├── my_project_test.mbt
├── my_project.mbt
├── README.mbt.md
└── README.md -> README.mbt.md
```

官方对各项的说明（原文摘录）：

- `moon.mod` 用于标识目录为 MoonBit 模块，包含模块名称、版本等元数据。
- `.` 和 `cmd/main` 目录是模块中的包。**每个包可以包含多个 `.mbt` 文件，
  但无论有多少个 `.mbt` 文件，它们都共享同一个 `moon.pkg` 文件。**
- `*_test.mbt` 是包中的独立测试文件，**用于黑盒测试，因此同一个包的私有成员不能直接访问**。
- `moon.pkg` 是包描述符，定义包的属性（是否 main 包、导入哪些包）。
  根包的 `moon.pkg` **可以是空的**，作用只是告诉构建系统这个文件夹是一个包。
- `README.mbt.md` 中 `mbt check` 代码块会由 `moon check` 和 `moon test` 检查运行。

> **官方树中不存在 `src/`** —— 这直接回答了本仓库「是否该有 `src/`」的疑问：不需要。

---

## 二、核心规则（官方文档 + 本地实证）

### 1. 包 = 目录；包名称由目录名决定，不可配置

> 包配置文档原文：「包名称不可配置；它由包的文件夹目录名称确定。」

推论：

- 拆分子包时按功能建目录（`fib/`、`encoding/`、`reedsolomon/`…），目录名即包名。
- 目录内的 `.mbt` **文件名不必与包名相同**。官方示例中 `fib` 包包含
  `slow.mbt` + `fast.mbt`，并没有 `fib.mbt`。
  官方标准库 `moonbitlang/core` 里 `array/array.mbt` 与主文件同名只是**它的风格惯例**，
  并非强制要求。

### 2. 一个包一个 `moon.pkg`，与 `.mbt` 数量无关

多个 `.mbt` 共享同一个 `moon.pkg`。不要每个源文件配一个 `moon.pkg`。

### 3. 测试文件的两种后缀

| 后缀 | 类型 | 可见范围 |
|------|------|---------|
| `_test.mbt` | 黑盒（包**外**） | 仅 `pub` 公共定义；私有成员**不可**访问 |
| `_wbtest.mbt` | 白盒（包**内**） | 私有函数与内部实现可直接访问 |

此外还支持**内联测试块**：

```moonbit
test {
  inspect(fib_slow(0))
}
```

官方说明：「内联测试块在非测试编译模式（`moon build` 和 `moon run`）中被丢弃，
因此它们不会导致生成的代码大小膨胀。」

**本地实证**（wasm-gc release，`cmd/main` 当前骨架产物；与
[wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) §5.1 的 440 B 一致）：

```
含内联 test{} 块产物: 440 B
移除内联 test{} 产物: 440 B
```

体积完全相同，官方说法得到验证。**建议把贴近实现的单元断言写成内联块**，
既保持在源码附近，又不影响产物体积。

### 4. 快照测试

```moonbit
inspect(value)                    // 首次运行后
inspect(value, content="...")     // moon test --update 自动填充
```

执行 `moon test --update` 自动写入期望值。适合输出结构复杂的用例。

### 5. 依赖在包级声明，且**声明后必须使用**

```toml
import {
  "username/my_project" @lib,
}
pkgtype(kind: "executable")
```

**实证**：声明 `@lib` 但未实际使用 →

```text
Warning: [0029] Unused package alias 'lib'
Warning: [0029] Unused package 'tryandrun/bb'
Failed with 2 warnings, 2 errors.
```

`unused_package` 默认启用（warn id=29），配合 `--deny-warn` 会直接失败。
**因此不要「提前」声明尚未用到的依赖。**

针对测试包还可用限定形式单独声明依赖：

```toml
import { "path/to/pkg" @p, } for "test"     // 仅黑盒测试包
import { "path/to/pkg" @p, } for "wbtest"   // 仅白盒测试包
```

`test-import-all`（默认 `true`）控制是否自动导入被测包的公共定义。

### 6. 包类型 `pkgtype`

| 值 | 用途 |
|----|------|
| `library` | **默认值**，普通库包 |
| `executable` | 含 `moon run` 入口（取代旧 `is-main: true`） |
| `foreign_library` | 对外输出供宿主链接的库（取代旧 `link: true`） |

三者互斥，不可同时声明。

### 7. 后端配置的三个层次

| 配置 | 位置 | 作用 |
|------|------|------|
| `--target` | 命令行 | 选择当前命令使用的后端 |
| `preferred_target` | `moon.mod` | 为 `moon` 与语言服务器选择**默认**后端 |
| `supported_targets` | `moon.mod` / `moon.pkg` | 声明打算支持哪些后端 |

`supported_targets` 使用**目标集合语法**（不是数组）：

```toml
supported_targets = "js"                 # 单个后端
supported_targets = "+js+wasm-gc"        # 显式指定一组
supported_targets = "+all-js"            # 除 js 外的所有后端
```

**实证（模块与包取交集）**：

| 模块级 | 包级 | 生效后端 |
|--------|------|---------|
| `+wasm+wasm-gc+js` | 未设 | wasm / wasm-gc / js 均 OK |
| `+wasm+wasm-gc+js` | `js` | 仅 js OK（wasm / wasm-gc 被跳过） |

符合文档「实际生效的后端集合就是它们的交集」。

> 注意：`moon check` 对不支持所选后端的包是**跳过**而非失败，
> 所以命令仍可能返回 0。CI 中若需严格校验，应显式指定 `--target` 并配合 `--deny-warn`。

**条件编译**（`targets`）与 `supported_targets` 分工不同：
`targets` 的最小单元是**文件**，用于按后端包含/排除个别文件；
`supported_targets` 是包级/模块级**元数据**。

```toml
options(
  targets: {
    "only_js.mbt": ["js"],
    "all_wasm.mbt": ["wasm", "wasm-gc"],
    "not_js.mbt": ["not", "js"],
  }
)
```

### 8. `core` 子包建议显式导入

文档提醒：「大多数 core 包在这里仍按普通包处理……请将对应的
`moonbitlang/core/...` 包加入 `import`，以避免 `core_package_not_imported` 警告。」

`prelude` 是例外，默认可用，无需导入。

### 9. 格式化与接口快照

- `moon fmt`：就地格式化，**含 `moon.mod` / `moon.pkg`**；
  也可把旧 `moon.pkg.json` 迁移为新 `moon.pkg`。
- `moon info`：生成 `.mbti` 对外接口快照。若 `.mbti` 无变化，
  说明改动未影响对外可见接口，通常属安全重构。
- 两者都应纳入收尾流程：

```bash
moon fmt && moon info && moon check && moon test
```

### 10. 其它官方建议

| 项 | 说明 |
|----|------|
| 生成文件排除格式化 | `formatter(ignore: ["generated.mbt"])` |
| 警告控制 | `warnings = "-unused_value+missing_doc"`；CI 用 `--deny-warn` 将告警升级为失败 |
| 导出函数给宿主 | 优先用 `#export_name("name")`，优于各后端 `link.exports` 配置 |
| 弃用代码 | 官方 `AGENTS.md` 建议放各目录的 `deprecated.mbt` |
| 代码组织 | 块风格，块以 `///|` 分隔，块间顺序无关 |
| 预构建步骤 | `rule(...)` + `dev_build(...)`；注意作为依赖被使用时**不会**触发（安全设计），故生成物需提交入库 |

---

## 三、本仓库对照与整改

> 布局演进（2026-09-05，**方案 3**）：仓库已改为「模块根不建包、库包在 `lib/`」的 core 形态，
> 与下方按 `moon new` 根包形态的对照存在差异；落地形态以
> [moonbit-实现布局与文件职责](./moonbit-实现布局与文件职责.md) 为准。下表 3.1 中凡与
> 该形态冲突的行已在说明处标注。

### 3.1 符合项

| 项 | 本仓库 | 判定 |
|----|--------|:---:|
| 无 `src/` | 库源码在 `lib/`（方案 3，非模块根） | 符合（无 `src/`） |
| 根包 `moon.pkg` | **无**——模块根只放元数据 | 偏离（方案 3，见 §3.3） |
| CLI 在 `cmd/main/` + `pkgtype(kind: "executable")` | 存在 | 符合 |
| 黑盒测试 `_test.mbt` | `lib/fast_qr_moonbit_test.mbt`（`@lib`） | 符合 |
| 白盒测试 `_wbtest.mbt` | `lib/fast_qr_moonbit_wbtest.mbt` | 符合 |
| 库主文件命名 | `lib/fast_qr_moonbit.mbt`（文件名沿用模块名） | 符合 |
| README 入口（真实文件） | `README.md`（`moon.mod` 的 `readme` 指向它） | 偏离（见 §3.3） |
| `supported_targets` 用集合语法 | `"+wasm-gc"`（`js`、`wasm`(WASI) 已移除） | 符合 |
| 未使用的依赖不提前声明 | `cmd/main/moon.pkg` 仅注释记录 | 符合 |

### 3.2 整改记录

两轮整改（2026-09-05）合并如下：

| 动作 | 依据 | 说明 |
|------|------|------|
| 新增 `README.md -> README.mbt.md` 符号链接（后已撤销，见 §3.3） | 官方布局含此链接 | 让 GitHub/GitLab 正常渲染首页；git 以 `mode 120000` 跟踪 |
| `preferred_target` 改为 `wasm-gc` | 实测：release 产物 440 B vs wasm 的 2598 B（-83%）；微基准 45 ms vs 60 ms（快 33%）；宿主仅需 1 个 `spectest.print_char` 回调 | 让 `moon check/build/run/test` 与 IDE 默认走最优后端；`wasm`(WASI) 后端后已移除，不再产出兼容产物 |
| `agents.md` → `AGENTS.md` | 官方 `moon new` 输出 `AGENTS.md` | `git mv` 保留历史；曾建 `agents.md -> AGENTS.md` 兼容链接（后已撤销，见 §3.3） |
| 新增 `.githooks/pre-commit` + `README.md` | 官方布局含此目录 | 执行 `moon fmt --check` + `moon check`（比官方仅 `moon check` 更严）；未装 `moon` 时自动跳过；启用由开发者自设 `core.hooksPath`，仓库不代设 |
| CI 补 `fmt-check` 与 `build-and-run` 阶段 | 防止格式与多后端回归腐化 | `check`/`test` 加 `--deny-warn`；`build-and-run` 遍历 `wasm-gc`/`wasm`/`js` 做 release 构建+运行+测试；**不含 native**（镜像缺 C 编译器） |

> `wasm`(WASI) 后端已移除，原「改回 `"wasm"`」的回退方式不再适用；当前 `preferred_target` 与 `supported_targets` 均为 `wasm-gc`。

### 3.3 已知差异（记录在案，暂不变更）

| 项 | 官方 | 本仓库 | 说明 |
|----|------|--------|------|
| 代理指南文件名 | `AGENTS.md` | `AGENTS.md` | **已对齐**：原小写 `agents.md` 于 2026-09-05 重命名为 `AGENTS.md`；曾建 `agents.md` 兼容符号链接（后撤销，仓库现不再保留该链接） |
| README 入口 | `README.mbt.md` + `README.md -> README.mbt.md` 符号链接（官方 `moon new` 布局） | `README.md`（单一真实文件） | **有意偏离**：撤销官方双文件+符号链接布局，避免两份内容需手动同步（符号链接在 Windows 开发环境还需管理员/开发者模式）；Git/平台渲染首页一致；`moon.mod` 的 `readme` 指向 `README.md` |
| `.githooks/` | 有（含 `pre-commit`） | 有 | **已补齐**：`pre-commit` 执行 `moon fmt --check` + `moon check`（比官方的仅 `moon check` 更严）；启用需开发者自行执行 `git config core.hooksPath .githooks`（本仓库不代设本地配置） |
| `.github/workflows/` | 有（copilot-setup-steps） | 无 | 本仓库 CI 在 `.cnb.yml`，无需 GitHub Actions |
| 模块形态 | `moon new` 单库：模块根即根包（`moon.pkg` + `<模块名>.mbt`） | **方案 3**：模块根不建包，库包在 `lib/`（`.../lib`），实现子包在 `lib/internal/` | **有意偏离**（对齐 core）：模块根只放元数据，目录更干净；导入路径变 `.../lib`，构建需显式给包名；见 [moonbit-实现布局与文件职责](./moonbit-实现布局与文件职责.md) |

> 关于符号链接：本仓库目前已**无符号链接** —— README 与 `agents.md` 的官方符号链接
> 布局均已撤销，相关文件均为单一真实文件（见上表 README 入口与代理指南文件名两行）。
> 若未来在 Windows 开发环境重建符号链接，教程注明需管理员权限或启用开发者模式。

---

## 四、落地为本仓库的操作清单

实现 QR 功能时按此执行：

1. **库 API** 写在 `lib/fast_qr_moonbit.mbt`（可按需拆多个 `.mbt`，共享 `lib/moon.pkg`）；
   实现子包放 `lib/internal/`。
2. **公共 API** 加 `///` 文档注释；可选开启 `missing_doc` 告警（core 已启用）。
3. **黑盒测试** `lib/fast_qr_moonbit_test.mbt`：用 `@lib` 引用，只测公共行为。
4. **白盒测试** `lib/fast_qr_moonbit_wbtest.mbt`：直接调用私有 helper。
5. **贴近实现的断言**优先写成源码内联 `test { }` 块（不影响产物体积）。
6. **CLI** 在 `cmd/main/`，调用库时在 `cmd/main/moon.pkg` 声明
   `import { "tryandrun/fast_qr_moonbit/lib" @lib }` —— 与首次实际调用同一批改动，勿提前加。
7. **若需拆子包**：在 `lib/` 内按功能建目录（如 `lib/internal/reedsolomon/`），加 `moon.pkg`，
   目录名即包名；**不要建 `src/`**。
8. **收尾**：`moon fmt && moon info && moon check && moon test`；
   三后端回归：`for t in wasm-gc wasm js; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done`。

---

## 五、参考

- [moonbit-实现布局与文件职责.md](./moonbit-实现布局与文件职责.md) — 本仓库布局检查过程与实证记录
- [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) — 后端选型与产物分析
- [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) — 工具链安装与构建系统
- 官方构建系统教程：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
- 官方包配置：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package.html>
