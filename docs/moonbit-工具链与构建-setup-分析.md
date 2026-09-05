# MoonBit 工具链与构建 Setup 详细分析

> 本文档基于官方文档
> 《MoonBit 构建系统教程》(https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html)、
> 《Moon 命令参考》(.../moon/commands.html) 及官方安装脚本
> `https://cli.moonbitlang.cn/install/unix.sh` 整理汇总，供本仓库
> `fast_qr_moonbit` 后续安装/构建/CI 集成时参考。

## 一、工具链概览

### 1. Moon 构建系统

`moon` 是 MoonBit 语言的构建系统（基于 `n2`），支持**并行 + 增量**构建，
并通过 [mooncakes.io](https://mooncakes.io) 管理和构建第三方包。

主要组成：

| 组成 | 说明 |
|------|------|
| `moon` 二进制 | 核心 CLI，位于 `~/.moon/bin/moon` |
| `moonx` | `moon` 的符号链接（`ln -sfn moon bin/moonx`），兼容入口 |
| `core` 标准库 | 以源码压缩包下载后由 `moon` 现场 `bundle` 生成 |
| `internal/tcc` | 内嵌的 C 编译器，用于 native 后端与原生编译 |
| `.mbti` / `_build` | 公共接口文件 / 增量构建产物目录 |

### 2. 核心配置文件

| 文件 | 作用 |
|------|------|
| `moon.mod` | 标识目录为 MoonBit **模块**，含名称、版本、readme、license、`preferred_target`/`supported_targets` 等元数据 |
| `moon.pkg` | 标识目录为一个**包**的包描述符（新版 TOML 格式；旧项目为遗留 `moon.pkg.json`） |
| `*_test.mbt` | 包**外**黑盒测试文件，构建系统自动为其新建测试包；只能访问 `pub` 公共定义 |
| `*_wbtest.mbt` | 包**内**白盒测试文件，可直接访问私有定义（本表初版漏记，实测确认） |
| `README.mbt.md` | README 文件，其中 `mbt check` 代码块会被 `moon check`/`moon test` 校验执行 |

`moon.pkg` 关键指令（新版格式）示例：

```toml
# 根目录 moon.pkg：可为空，仅告知构建系统该目录是一个包

# 可执行入口包 cmd/main/moon.pkg
import {
  "username/my_project" @lib,
}
pkgtype(kind: "executable")
```

- `pkgtype(kind: "executable")`：标记含 `moon run` 入口的 main 包。
- `import { "路径" @别名 }`：在**包级**声明依赖并给导入别名，代码中用 `@别名.xxx` 引用。

### 3. 目标后端

三组配置项（分工不同）：

| 配置 | 作用 |
|------|------|
| 命令行 `--target` | 选择当前命令使用哪个后端 |
| `moon.mod` 中 `preferred_target` | 为 `moon` 与语言服务器选择**默认**后端 |
| `supported_targets` | 声明模块/包打算支持哪些后端 |

后端取值：`wasm`、`wasm-gc`、`js`、`native`、`llvm`、`all`；
`supported_targets` 使用目标集合语法，如 `js`、`+js+wasm-gc`、`+all-js`。

以 native 为主的 CLI 项目典型配置：

```toml
preferred_target = "native"
supported_targets = "native"
```

若只有部分文件与后端相关，则让模块/包元数据保持宽泛，并在 `moon.pkg`
(或遗留 `moon.pkg.json`) 中用 `targets` 按后端选择文件。

## 二、安装 / Setup 流程分析

官方安装脚本：`https://cli.moonbitlang.cn/install/unix.sh`
执行：`curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash`

### 1. 脚本执行关键步骤（逐段解析）

| 阶段 | 脚本行为 |
|------|----------|
| **平台识别** | `uname -ms` 映射到 `linux-x86_64` / `linux-aarch64` / `darwin-aarch64`；不支持则报错退出 |
| **版本解析** | 参数/环境变量 `MOONBIT_INSTALL_VERSION` → 默认 `latest`；设 `MOONBIT_INSTALL_DEV` 则目标追加 `-dev` |
| **下载地址** | CLI 服务 `https://cli.moonbitlang.cn`：`/binaries/<ver>/moonbit-<target>.tar.gz` 与 `/cores/core-<ver>.tar.gz` |
| **安装目录** | 默认 `~/.moon`（可用 `MOON_HOME` 覆盖），`bin` 为二进制目录 |
| **下载 & 解压** | `curl --fail --location --progress-bar` 下载 `moon` 二进制包，清空并解压至 `~/.moon` |
| **链接 & 授权** | `ln -sfn moon moonx`；对 `bin/*` 及 `internal/tcc` 全部 `chmod +x` |
| **core 处理** | 下载 `core` 源码包解压至 `~/.moon/lib`，随后**现场 `bundle`**（`moon -C lib/core bundle ...`）生成默认/native(llvm nightly)/wasm-gc 产物 |
| **PATH 写入** | 检测当前 shell（fish/zsh/bash），把 `~/.moon/bin` 追加进对应 rc 文件并提示 source 刷新 |

> 可复现要点：脚本自带**卸载清理**（`rm -rf ~/.moon/lib ~/.moon/include`），
> 每次安装会重建 core；`curl` 失败/解压失败/缺平台均立即 `error` 退出，可据此判定 CI 阶段是否成功。

### 2. 关键环境变量与入口

| 项 | 说明 |
|----|------|
| `MOON_HOME` | 覆盖安装根目录（默认 `~/.moon`） |
| `MOONBIT_INSTALL_VERSION` | 指定安装版本（默认 `latest`） |
| `MOONBIT_INSTALL_DEV` | 非空则安装 dev 版 |
| `~/.moon/bin/moon` | 主 CLI，需保证在 `PATH` |
| `moon help` / `moon upgrade` | 查看用法 / 升级工具链（`moon upgrade --force` 强制、`--dev` 装 dev） |

### 3. CI / 无交互 setup 建议

- 上述 unix.sh 在无 TTY（CI）环境下 `Color`/`-t` 分支自动关闭，可非交互执行。
- 推荐固定版本安装（避免 `latest` 漂移导致 CI 不可复现）：

```bash
# 固定版本安装（moonbit 后端二进制下载）——示例
export MOONBIT_INSTALL_VERSION=<具体版本>
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"

# 依赖安装与常规校验
moon install          # 安装模块依赖（锁定同步 mooncakes 索引）
moon check            # 仅检查不产出对象（含 README.mbt.md 的 mbt check 块）
moon test             # 全项目测试，扫描并运行所有测试
moon build            # 构建当前包（可 --target、--release）
```

- 常用 moon 子命令速查：`new` `build` `check` `run` `test` `clean` `fmt` `doc`
  `info`(生成 .mbti) `bench` `add` `remove` `install` `tree` `update`
  `coverage` `upgrade` `shell-completion` `version` 等。

## 三、实际 Setup 验证

在 Linux x86_64 环境执行官方安装脚本 `unix.sh`，实测结果：

| 项目 | 结果 |
|------|------|
| 平台识别 | `Linux x86_64` → `linux-x86_64`，匹配成功 |
| 工具链版本 | `moon 0.1.20260827 (d0aaa07 2026-08-27)` |
| 安装目录 | `~/.moon`（默认） |
| core bundle | 成功，`ran 324 tasks`，含 wasm / wasm-gc 等产物 |
| PATH 写入 | bash 类型自动追加 `~/.moon/bin` 至 `~/.bashrc` |
| 无 TTY 支持 | 自动去色，可非交互执行，适合 CI |

**验证通过**。MoonBit 工具链可在 Linux x86_64 上正常安装并运行
`moon version`、`moon run`、`moon check`、`moon test` 等命令。

## 四、本仓库构建集成落地

已完成以下落地工作：

### 1. MoonBit 项目骨架初始化

> 下面是**初始化当时**落地的结构；后续演进见下方「当前状态」。

仓库根目录新增 MoonBit 项目结构：

```
├── moon.mod                      # 模块配置
├── moon.pkg                      # 根包描述
├── fast_qr_moonbit.mbt           # 库代码（骨架）
├── fast_qr_moonbit_test.mbt      # 库测试
├── cmd/main/                     # CLI 可执行入口
│   ├── main.mbt
│   └── moon.pkg
└── README.mbt.md                 # MoonBit README（含 mbt check 代码块）
```

初始化时的配置：`preferred_target = "wasm"`，未设 `supported_targets`（默认支持所有后端）；
根包测试含 `assert_true(true)` 冒烟用例。

**当前状态（后续演进后）**：

- `preferred_target` 已改为 **`wasm-gc`**（依据见
  [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md)）。
- 已补 `supported_targets = "+wasm+wasm-gc+js"`。
- 已补 `fast_qr_moonbit_wbtest.mbt`（白盒测试，上表 §一.2 初版漏记）。
- 已补 `docs/`、`AGENTS.md`（由小写 `agents.md` 重命名对齐官方命名，无兼容符号链接）、`.githooks/`。
- README 入口已改为单一真实 `README.md`（撤销官方 `README.mbt.md` + `README.md`
  符号链接布局；`moon.mod` 的 `readme` 指向 `README.md`，见 README「项目结构」）。
- 布局检查与整改过程见 [代码布局检查与整理.md](./代码布局检查与整理.md)。

### 2. `.cnb.yml` CI 流水线集成

在 `$` 分支下配置了两类事件：

- **`vscode`（云原生开发）**：初始化时安装 MoonBit 工具链，开发者可直接使用 `moon` 命令。
- **`push`（代码推送 CI）**：工具链 setup → `moon fmt --check` → `moon check --deny-warn`
  → `moon test` → 多后端 `build-and-run` 回归。

各阶段说明：

| 阶段 | 命令 | 作用 |
|------|------|------|
| `fmt-check` | `moon fmt --check` | 格式门禁（`moon fmt` 会格式化 `moon.mod` / `moon.pkg` / 所有 `.mbt`） |
| `check` | `moon check --deny-warn` | 把告警（如 `unused_package`）升级为失败 |
| `test` | `moon test` | 全项目测试 |
| `build-and-run` | 遍历 `wasm-gc` / `wasm` / `js` 做 `--release` 构建、运行、测试 | 多后端回归 |

> **不要加 `native` 阶段**：需系统 C 编译器，本镜像未安装，加入必然失败
> （见 [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) §6.1）。

CI 无 TTY 环境下 setup 脚本自动去色，可非交互执行。

### 3. 其它

- `.gitignore` 忽略 MoonBit 构建产物：`/_build/`、`/*.wasm`、`/*.js`、`*.mbti`，
  以及工具产生的 `.Trash-*/`（避免被 `git add -A` 误提交）。
- `LICENSE` 采用 Apache-2.0（与 `moon.mod` 中 license 字段一致）。

## 五、官方链接

- MoonBit 下载 / 校验：https://www.moonbitlang.cn/download/
- MoonBit 构建系统教程：https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html
- Moon 命令参考：https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/commands.html
- mooncakes.io 包管理：https://mooncakes.io
