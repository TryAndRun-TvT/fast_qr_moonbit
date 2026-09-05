# Wasm 编译与运行 · 结果分析

> 本文记录把 `fast_qr_moonbit` 当前代码（骨架阶段）编译为 WebAssembly 并运行的全过程、
> 产物结构分析、多后端对比数据，以及由此得出的结论与后续建议。
>
> 环境日期：2026-09-05　｜　工具链：`moon 0.1.20260827 (d0aaa07)`

---

## 一、目标与范围

| 项 | 内容 |
|----|------|
| 目标 | 验证当前代码可稳定编译为 wasm 并运行；量化各后端产物特征；为后续 QR 实现选定后端 |
| 对象 | 当前骨架代码（库 `fast_qr_moonbit.mbt` 仅含文档注释，CLI 仅 `println` 一行，测试 1 个冒烟用例） |
| 范围 | `moon check` / `build` / `run` / `test` 跨后端验证、wasm 二进制结构解析、宿主可移植性验证、计算负载微基准 |
| 不在范围 | QR 算法本身的正确性（尚未实现） |

---

## 二、环境信息

| 组件 | 版本 / 状态 |
|------|------------|
| OS | Linux x86_64 |
| `moon` | `0.1.20260827 (d0aaa07 2026-08-27)` |
| `moonc` | `v0.10.11+6ff76a5f9 (2026-08-28)` |
| `moonrun` | `0.1.20260827`（wasm 官方运行时） |
| `moon-wasm-opt` | `wasm-opt version 125` |
| `tcc`（moon 自带） | `~/.moon/bin/internal/tcc` |
| Node | `v22.23.1`（`PATH` 中 `which node` 不可见，实际位于 `/usr/local/bin/node`） |
| C 编译器 | **缺失**（`cl` / `cc` / `gcc` / `clang` 均无） |
| Python | `3.12.14`（用于解析 wasm 二进制，仅分析用途） |

> **分析当时**的 `moon.mod` 配置：`preferred_target = "wasm"`，未声明 `supported_targets`
> （默认支持全部后端）。现均已变更 —— `preferred_target = "wasm-gc"`、
> `supported_targets = "+wasm+wasm-gc+js"`（见 §7.1）。
> Feature flags：`rr_moon_mod, rr_moon_pkg`（新版 TOML 配置格式）。

---

## 三、编译与运行全过程

### 3.1 校验与构建

```bash
moon check --target wasm   # Finished. moon: ran 4 tasks, now up to date
moon build --target wasm   # Finished. moon: ran 2 tasks, now up to date
```

产物落在 `_build/wasm/{debug,release}/build/cmd/main/`（`main.core` → `main.wasm`）。

### 3.2 运行

```bash
$ moon run cmd/main --target wasm
fast_qr_moonbit - MoonBit QR Code Generator

$ moon test --target wasm
Total tests: 1, passed: 1, failed: 0.
```

`moon run` 使用官方 `moonrun` 运行时执行 `_start`，`--release` 模式输出一致。

> 注：§3.2/§3.3 的测试数为**当时骨架**的记录（仅 1 个黑盒冒烟）。补齐白盒测试文件
> `fast_qr_moonbit_wbtest.mbt` 后，`moon test` 现为 2 个冒烟测试
> （见 [代码布局检查与整理.md](./代码布局检查与整理.md) §四）。

### 3.3 各后端校验结果

| 后端 | `moon check` | `moon run` | `moon test` |
|------|:---:|:---:|:---:|
| `wasm` | OK | OK | 1 passed |
| `wasm-gc` | OK | OK | 1 passed |
| `js` | OK | OK | — |
| `native` | — | **失败**（缺 C 编译器，见 §6.1） | — |

---

## 四、Wasm 产物结构分析

使用自写的段解析器（`LEB128` 逐段解析）对产物做静态分析。

### 4.1 CLI 骨架产物

| 指标 | wasm debug | wasm release | wasm-gc debug | wasm-gc release |
|------|-----------:|-------------:|--------------:|----------------:|
| 体积（B） | 4748 | 2598 | **804** | **440** |
| 函数数量 | 27 | 16 | 5 | — |
| code 段（B） | 2968 | 2186 | 119 | — |
| data 段（B） | 112 | 112 | 89 | — |
| 导入 | `wasi_snapshot_preview1.fd_write` | 同左 | `spectest.print_char` | 同左 |
| 导出 | `memory`, `_start` | 同左 | `_start` | 同左 |

### 4.2 关键结论

1. **`wasm` 后端依赖 WASI，且必须导出 `memory`**
   运行时通过线性内存 + `fd_write` 完成输出；`code` 段占总体积 60% 以上，主体是
   线性内存版的 MoonBit 运行时（分配器 / 字符串 / GC 相关例程），与业务代码量无关。
2. **`wasm-gc` 后端只依赖一个 `spectest.print_char` 导入，且不导出 memory**
   数据和对象全部交给宿主 GC 管理，因此不需要自带运行时支撑代码，
   体积比 `wasm` 后端小一个数量级（骨架场景 440 B vs 2598 B，**-83%**）。
3. **`--release` 对 `wasm` 后端收益显著**（4748 → 2598 B，**-45%**），
   主要来自函数内联与死代码消除（函数数 27 → 16）；对 `wasm-gc` 同样有效（804 → 440 B）。
4. **产物附带 `custom` 段（debug name / sourcemap）**，release 下 custom 段从 1404 B 降至 48 B。

### 4.3 宿主可移植性验证（不经过 `moonrun`）

| 运行方式 | 结果 | 说明 |
|---------|------|------|
| Node `node:wasi` + `wasi.start()` 直跑 `wasm` release 产物 | 通过，exit code 0 | 符合 WASI preview1 标准，可被任何 WASI 宿主（wasmtime / wasmer / node）加载 |
| 纯 `WebAssembly.instantiate` + 自制 `spectest.print_char` 直跑 `wasm-gc` 产物 | 通过，正确输出 | 宿主只需提供 1 个打印回调，可直接在浏览器 / 任意 WASI 无关的嵌入场景使用 |
| `wasm-gc` 在 Node 22 下无需实验标志 | 通过 | Node 22 默认启用 Wasm GC 提案 |

**结论**：两个 wasm 产物都不是「只能靠 moonrun 跑」的私有格式，具备真实可分发性；
其中 `wasm-gc` 的宿主集成成本最低（一个回调 + 无内存导出）。

---

## 五、多后端量化对比

### 5.1 产物体积（`cmd/main`，骨架）

| 后端 | debug | release |
|------|------:|--------:|
| `wasm` | 4748 B | 2598 B |
| `wasm-gc` | 804 B | 440 B |
| `js` | 293 B | — |

### 5.2 计算性能微基准

当前骨架只有一行 `println`，无法反映 QR 负载特征。因此在 `/tmp/bench`
（独立模块，不入库）构造了贴近 QR 生成的计算负载：

- **GF(256) 伽罗华域乘法**（Reed-Solomon 纠错的基石，位运算密集）
- **对数/指数表构造** + **45×45 模块矩阵填充 × 1200 轮**（约合反复生成版本 5 量级的二维码）

| 后端 | 产物体积 | 3 次耗时（ms） | 最优（ms） | 相对 `wasm` |
|------|--------:|---------------|----------:|------------:|
| `wasm` | 5985 B | 318 / 60 / 81 | **60** | 1.00× |
| `wasm-gc` | 2190 B | 47 / 47 / 45 | **45** | **1.33× 更快** |
| `js` | 2891 B | 78 / 122 / 100 | **78** | 0.77× |

三后端输出完全一致（`bench_result=78074400`），构成一次朴素的**跨后端结果互证**：
同一份源码在不同后端得到同一结果，说明编译产物语义一致。

> 说明：耗时含运行时启动开销，量级仅供选型参考，非严格 bench；
> `wasm` 首次 318 ms 为冷启动抖动，取多次最小值比较。

### 5.3 选型结论

| 维度 | 建议 |
|------|------|
| 主推后端 | **`wasm-gc`**：体积最小（CLI 骨架 release 为 `wasm` 的 **1/5.9**；计算密集 bench 为 **1/2.7**）、性能最优（bench 快约 33%）、宿主集成最简单 |
| 兼容性兜底 | 保留 `wasm`（WASI preview1）用于旧宿主；`js` 作为 npm/浏览器直出通道 |
| `native` | 仅当 CI/部署镜像安装了 C 工具链时启用，用于 CLI 与基准测试 |

---

## 六、发现的问题与风险

### 6.1 `native` 后端在本环境不可用（环境限制）

```text
Error: Failed to set C compiler when compiling tryandrun/fast_qr_moonbit/cmd/main@0.1.0
  new native backend requires a C compiler/linker driver; install clang/cc or set MOON_CC
  no system C compiler found; tried cl, cc, gcc, clang
```

尝试用 moon 自带 tcc 兜底（`MOON_CC=~/.moon/bin/internal/tcc`）仍失败：

```text
tcc: error: library 'c' / 'crtn.o' not found
tcc: error: undefined symbol 'putchar' 'malloc' 'memcpy' ...
```

根因是系统缺少 libc 开发文件（无 `libc.a` / `crt*.o`）。解决方式：
`apt-get install -y build-essential`（或 `libc6-dev`），或显式指定 `MOON_CC`。
**在修复前，任何依赖 native 后端的 CI 阶段都会失败。**

### 6.2 测试文件注释与实际实现不一致

`fast_qr_moonbit_test.mbt` 原注释称「**包内**黑盒测试」，表述自相矛盾：
`_test.mbt` 是**包外**黑盒测试，`_wbtest.mbt` 才是包内白盒测试。

> 已修正（见 `docs/代码布局检查与整理.md`）：注释改为准确的黑盒/白盒说明，
> 并补齐缺失的 `fast_qr_moonbit_wbtest.mbt`。

### 6.3 `cmd/main/moon.pkg` 尚未建立对根包的依赖

当前 `main` 未调用库函数，故可编译。一旦 CLI 开始调用库 API，需补：

```toml
import {
  "tryandrun/fast_qr_moonbit" @lib,
}
pkgtype(kind: "executable")
```

**修正与补充**（实证结论）：提前声明但暂未使用是**不可行**的——
实测会触发 `unused_package` 告警并导致 `moon check` 失败：

```text
Warning: [0029] Unused package 'tryandrun/bb'
Warning: [0029] Unused package alias 'lib'
Failed with 2 warnings, 2 errors.
```

因此正确做法是**等到 CLI 真正调用库 API 时再声明**，
骨架阶段仅在 `moon.pkg` 中以注释形式记录待启用内容（当前已如此处理）。

### 6.4 CI 未覆盖产物构建与多后端校验（**已修复**）

> 现状：`.cnb.yml` 已补 `fmt-check` 与 `build-and-run` 阶段，`check`/`test` 也已加 `--deny-warn`。
> 当前流水线为：setup → `moon fmt --check` → `moon check --deny-warn` → `moon test`
> → 遍历 `wasm-gc`/`wasm`/`js` 做 `--release` 构建+运行+测试。下方为原始问题描述与建议。

问题原描述：push 流水线只执行 `moon check` + `moon test`（走默认 `preferred_target = wasm`），
未验证 `moon build`、未做 release 产物与 `wasm-gc` 回归。建议补充：

```yaml
- name: build-wasm
  script: |
    export PATH="$HOME/.moon/bin:$PATH"
    moon build --target wasm --release
    moon build --target wasm-gc --release
    moon run cmd/main --target wasm-gc --release
```

> 注意：CI 镜像若未预装 C 编译器，切勿加入 `native` 阶段（见 §6.1）。

### 6.5 其它

- `moon info` 会生成 `pkg.generated.mbti` / `cmd/main/pkg.generated.mbti`（构建产物）。
  本次已将 `*.mbti` 追加进 `.gitignore`，避免误入库。
- `moon.mod` 未声明 `supported_targets` —— **已修复**，现为
  `supported_targets = "+wasm+wasm-gc+js"`（按实际支持情况显式收窄，`native` 因缺 C 编译器不纳入）。

---

## 七、结论与下一步

### 7.1 结论

1. **当前骨架代码可以稳定编译为 wasm 并运行**：`wasm` / `wasm-gc` / `js` 三后端
   `check` / `build` / `run` / `test` 全绿，输出与预期一致。
2. **产物具备真实可分发性**：`wasm` 符合 WASI preview1，可被 node / wasmtime 等标准宿主加载；
   `wasm-gc` 只需宿主提供一个 `spectest.print_char` 回调。
3. **`wasm-gc` 综合最优**：体积 **-83%**（CLI 骨架 release：440 B vs `wasm` 的 2598 B）、
   bench 性能 +33%、宿主接入成本最低，作为本库面向 Web 的主推后端。
   `preferred_target` **已切换为 `wasm-gc`**（本节初版写「待实现 QR 后评估」，现已落地）。

   > 勘误：初版此处写的是「-63%」，那是 **bench** 模块（5985 → 2190 B）的缩减比例，
   > 被误标成「wasm release」。CLI 骨架的正确数值是 **-83%**（2598 → 440 B），与 §4.2 一致。
4. **`native` 后端当前为环境短板**，需装 C 工具链后才可用，不应纳入 CI 必选阶段。

### 7.2 下一步建议（按优先级）

| 优先级 | 事项 | 状态 |
|:---:|------|:---:|
| P0 | 实现 QR 核心数据结构与公共 API，并让 `cmd/main` 真正调用（补 `moon.pkg` 的 `import`） | 待办 |
| P0 | 修正测试文件注释（§6.2） | **已完成** |
| P0 | 测试从 `assert_true(true)` 升级为真实断言 | 待办（依赖上一条公共 API） |
| P1 | CI 增加 release 构建 + `wasm-gc` 运行阶段（§6.4） | **已完成**（`fmt-check` + `build-and-run`） |
| P1 | `moon.mod` 显式声明 `supported_targets`（§6.5） | **已完成**（`+wasm+wasm-gc+js`） |
| P1 | `preferred_target` 切换为 `wasm-gc`（§7.1.3） | **已完成** |
| P2 | 实现后重跑 §5.2 微基准（改用真实 QR 生成路径），复核后端选型 | 待办 |
| P2 | 评估产物以 npm 包形式分发（`js`）与 WASI CLI 分发（`wasm`）的双通道 | 待办 |

---

## 八、复现命令清单

```bash
export PATH="$HOME/.moon/bin:$PATH"

# 校验 / 构建 / 运行 / 测试（wasm）
moon check --target wasm
moon build --target wasm && moon build --target wasm --release
moon run  cmd/main --target wasm
moon test --target wasm

# wasm-gc
moon build --target wasm-gc --release
moon run  cmd/main --target wasm-gc --release
moon test --target wasm-gc

# js
moon run cmd/main --target js

# 产物位置
ls -l _build/wasm/release/build/cmd/main/main.wasm
ls -l _build/wasm-gc/release/build/cmd/main/main.wasm
ls -l _build/js/debug/build/cmd/main/main.js

# 宿主直跑（不经 moonrun）
node --input-type=module -e "
  import { WASI } from 'node:wasi'; import { readFileSync } from 'node:fs';
  const wasi = new WASI({ version:'preview1', args:[], env:{}, preopens:{} });
  const inst = new WebAssembly.Instance(
    new WebAssembly.Module(readFileSync('_build/wasm/release/build/cmd/main/main.wasm')),
    wasi.getImportObject());
  wasi.start(inst);
"
```

---

## 九、相关文档

- [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) — 工具链安装与构建系统
- [repo-初始化配置说明.md](./repo-初始化配置说明.md) — 仓库初始化与 CI 配置
- [README.md](../README.md) — 项目入口与快速开始

官方链接：

- MoonBit 构建系统教程：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>
- Moon 命令参考：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/commands.html>
