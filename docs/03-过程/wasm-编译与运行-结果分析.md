# Wasm 编译与运行 · 结果分析

> **状态**：已失效　｜　日期：2026-09-05　｜　索引：[docs/README.md](../README.md) §7
> 并入：现行后端产物与体积口径见 [S9i](../02-证据/S9i-纯库调用体积探针与库实际体积.md) /
> [S9g](../02-证据/S9g-本项目wasm产物体积-确认与修正.md)；后端选型见 [AGENTS.md](../../AGENTS.md) §二.3

> ⚠️ **本文所述前提已不存在**（不是「过时」，是「不成立」）：
> ① 分析对象是**骨架阶段**代码（库仅文档注释、CLI 仅一行 `println`、测试 1 个冒烟用例，QR **尚未实现**）；
> ② 当时 `moon.mod` 为 `preferred_target = "wasm"`、默认支持全部后端；
> ③ `js` 与 `wasm`(WASI) 后端**均已按项目决策移除**，仓库现只有 `wasm-gc`。
>
> **不得引用本文为现行口径。** 本文只保留两处**仍然有效**的结论（§1–§2），
> 其余（骨架产物体积、`println` 级微基准、CI 建议、下一步清单）已无审计价值，就地删除。
> 要复跑现行体积/性能，用 `bash scripts/bench-size.sh` / `bash scripts/bench-host.sh`。

---

## 1. 仍然有效的结论（两条）

### 1.1 `native` 后端在本环境不可用（环境限制，非项目缺陷）

```text
Error: Failed to set C compiler when compiling TryAndRun-TvT/fast_qr_moonbit/cmd/main@0.1.0
  new native backend requires a C compiler/linker driver; install clang/cc or set MOON_CC
  no system C compiler found; tried cl, cc, gcc, clang
```

用 moon 自带 tcc 兜底（`MOON_CC=~/.moon/bin/internal/tcc`）仍失败（缺 `libc.a` / `crt*.o`）。
根因是系统缺 libc 开发文件；`apt-get install -y build-essential` 可解。
**在修复前，任何依赖 `native` 的门禁阶段都会失败**——这条至今成立，故 `native` 未纳入 CI（[AGENTS.md](../../AGENTS.md) §二.3）。

### 1.2 「提前声明未使用的 import」不可行（实测证据）

骨架阶段曾想在 `cmd/main/moon.pkg` 预声明 `@lib`；实测**触发器告警并失败**：

```text
Warning: [0029] Unused package 'tryandrun/bb'
Warning: [0029] Unused package alias 'lib'
Failed with 2 warnings, 2 errors.
```

正确做法 = **等到真正调用时才声明**。这条是「AGENTS.md §二.2『声明后必须使用』」的实测依据，
且至今有效（骨架阶段仅在 `moon.pkg` 注释里记录待启用内容）。

---

## 2. 结论去向

| 原内容 | 现状 |
|--------|------|
| 三后端选型结论（`wasm-gc` 综合最优） | 已落地（`preferred_target = "wasm-gc"`；`js`/`wasm` 已移除） |
| 骨架阶段产物体积（`wasm-gc` release 440 B 等） | **已作废**：那是「只有一行 `println`」的体积，**与当前实现无关** |
| `/tmp/bench` 的 `println` 级微基准（45 ms 等） | **已作废**：不反映 QR 负载；现行口径见 [S9p](../02-证据/S9p-宿主调用面性能口径-JS向wasm传参.md) |
| 产物可移植性验证（WASI / `spectest.print_char`） | 结论仍成立（`wasm-gc` 宿主只需 1 个回调），已并入 [S9i](../02-证据/S9i-纯库调用体积探针与库实际体积.md) |
| CI 建议 / P0–P2 下一步清单 | **已作废**：`push` 流水线已于 2026-09-14 移除，门禁改由 `scripts/gates.sh` 承担 |

---

## 3. 参考

- [项目基础框架-详细分析.md](项目基础框架-详细分析.md) §多后端选型（立项期基线）
- [moonbit-工具链与构建-setup-分析.md](../01-规格/moonbit-工具链与构建-setup-分析.md) — 工具链安装与构建系统
- 现行体积口径：[S9i](../02-证据/S9i-纯库调用体积探针与库实际体积.md) · 复跑 `bash scripts/bench-size.sh`
