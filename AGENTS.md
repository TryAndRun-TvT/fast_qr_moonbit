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

- **模块根只放元数据**（`moon.mod` / `README.md` / `docs/` 等），**模块根不是包**
  （无根 `moon.pkg`）；库包统一放 `lib/`，实现细节藏 `lib/internal/`。
- 包按目录组织，每个目录一个 `moon.pkg`。
- 库入口文件放 `lib/`：`lib/fast_qr_moonbit.mbt`（文件名可任取，沿用模块名便于识别）；
  公共枚举/类型文件（ecl/version/mode/mask/qr/helpers 等）与入口同放 `lib/`。
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
    "tryandrun/fast_qr_moonbit/lib" @lib,
  }
  ```

- **声明后必须使用**：若声明了 `@lib` 却未实际使用，会触发 `unused_package` 告警
  并导致 `moon check` 失败。骨架阶段若无 API 可调用，**不要提前声明**。

### 3. 后端与构建

- 模块声明 `supported_targets = "+wasm+wasm-gc+js"`，默认 `preferred_target = "wasm-gc"`。
- 主推 **`wasm-gc`**（实测体积比 `wasm` 小 83%、计算微基准快约 33%、宿主接入成本最低）；
  `wasm` 作 WASI 兼容兜底，`js` 用于 npm / 浏览器。
- 需要兼容产物时显式指定包与后端：`moon build cmd/main --target wasm --release`
  （默认命令走 `wasm-gc`；模块根无包，构建需显式给包名）。
- **`native` 后端需系统 C 编译器**（`cc` / `gcc` / `clang`）。当前环境缺失，
  在修复前**不得**把 native 阶段写进 CI 必选流程。
- 代码块以 `///|` 分隔块风格组织，块间顺序无关。

### 4. 收尾检查

每次改动后执行：

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon info && moon check --deny-warn && moon test
# 多后端回归（release，显式构建 lib 与 cmd/main）
for t in wasm-gc wasm js; do moon build lib --target $t --release; moon build cmd/main --target $t --release; moon test --target $t; done
```

> CI 会执行 `moon fmt --check`、`moon check --deny-warn` 与三后端 release 回归，
> 本地先跑一遍可避免推送后失败。可选启用本地钩子：
> `git config core.hooksPath .githooks`（属个人本地配置，仓库不代设）。

- `moon fmt` 会就地格式化（含 `moon.mod` / `moon.pkg`），提交前务必执行。
- `moon info` 生成的 `*.mbti` 是包的对外接口快照：若 `.mbti` 无变化，
  说明改动未影响对外可见接口，通常属安全重构。

---

## 三、文档管理

- 文档统一放 `docs/`，命名用连字符分隔的小写词段（kebab-case，允许中英混排，
  如 `wasm-编译与运行-结果分析.md`）。
- **单文档 ≤800 行**，超长应拆分。
- **死链零容忍**：文档中不得引用不存在的文件；新增文档须同步更新
  `README.md` 的「文档」索引表。
- **纯本地 / 私人配置调整**（如本地默认值改动）：只改代码/配置，**不生成、不更新项目文档**。

---

## 四、参考

- 项目文档索引见 [README.md](./README.md)「文档」表。
- MoonBit 技能库：<https://github.com/moonbitlang/skills>
- MoonBit 构建系统：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
