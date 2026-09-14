# MoonBit 实现布局与文件职责（方案 3：lib/ 库包）

> 依据 [项目基础框架-详细分析](./项目基础框架-详细分析.md)、
> [moonbit-重写-roadmap-详细分析](./moonbit-重写-roadmap-详细分析.md) 与
> `moonbitlang/core` 实仓布局（模块根只放元数据、库为 feature 子目录包），
> 并采纳「方案 3」：**取消模块根根包，库代码统一收入 `lib/` 子包**。
> 当前阶段：**B1→B11 全部落地、S1–S11 收口完成**（测试 146 全绿；仅 `wasm-gc` 单后端）。
> 本文的布局/职责结论仍然有效，但 §3 的「状态」列与 §6 的落地描述已按**当前真实状态**刷新
> （2026-09-14，[S11b](./S11b-清理落地记录-v3-v5.md) §13「过期注释/口径巡检」）。
>
> 日期：2026-09-05（布局决策）　｜　状态刷新：2026-09-14

---

## 1. 布局决策（方案 3）

1. **模块根不放库代码**：根目录只放元数据（`moon.mod`/`README.md`/`docs/`/CI 配置等），
   库都是 `lib/` 下的子包 —— 与 `moonbitlang/core` 同形态。
   **唯一例外是根 `moon.pkg`（空包）**：2026-09-14 起作为 **README 文档测试宿主**——
   README 的 `mbt check` 示例要被 `moon check`/`moon test` 编译运行，而模块根的 `.md`
   **只有归属到某个包才会被扫描**，故根必须存在 `moon.pkg`。该包不写实现、不导出 API
   （`boundary` 仍由 `lib/` 承担），并显式 `warnings = "-29"`（`@lib` 只在文档测试里用，
   静态分析看不见）。
   **链接方向（2026-09-14 v4 回正）**：`README.md` 是**实体正文**，`README.mbt.md` 是指向它的
   **符号链接**（文档测试只认文件名恰为 `README.mbt.md` 的 markdown；反向做则 `README.md`
   在平台/blob/raw/不解析链接的宿主上只剩 13 字节存根，落地页劣化——见 §八 v4）。
2. **库包在 `lib/`**：`lib/moon.pkg` + 公共文件（入口/枚举/容器）+ `lib/internal/` 实现子包；
   消费者通过 `import { "TryAndRun-TvT/fast_qr_moonbit/lib" @lib }` 使用。
3. **无环依赖（MoonBit 实测禁止 import 环）**：
   - `lib` import `lib/internal/*`（已落地）；
   - internal 永不反向 import `lib`；跨边界以**域序号（Int）**或本包类型传参；
   - 公共枚举（ECL/Version/Mode/Mask 等）只出现在 `lib/`（`.mbti` 对外契约）。
4. **测试放所属包目录内**：`lib/*_test.mbt`（黑盒，`@lib` 别名 = 目录名，自动可用）、
   `lib/*_wbtest.mbt`（白盒）、贴近实现的断言用源码内联 `test {}`。
5. **不提前声明 import**：依赖在实现到该步时、声明与使用同一批提交；骨架阶段 `moon.pkg` 留空。
6. **代码注释先行（历史约定）**：B1→B11 曾按批次逐个把注释骨架替换为真实实现，每批一个提交；
   该过程已于 S1–S7 完成，现无注释骨架文件。

> 与「单根包」/「模块根 internal」旧方案的差异：库入口 import 路径由
> `.../fast_qr_moonbit` 变为 `.../fast_qr_moonbit/lib`；构建/CI 需显式给包名。
>
> **v4 更新（2026-09-14，[S11b §12](./S11b-清理落地记录-v3-v5.md)）**：原 `lib/fast_qr_moonbit.mbt`
> （入口注释文件）与 `lib/qr_output.mbt`（薄委托文件）已删/合并——MoonBit 同包共享命名空间，
> **公共 API 总览的权威载体是 README + 本文档**，不再在源码目录保留纯注释文件。

## 2. 布局树

```
moon.mod / README.md / docs/ / AGENTS.md / .cnb.yml  # 模块根：元数据
moon.pkg                         #   根空包：README 文档测试宿主（无实现、无导出）
├── lib/                          # 库包（公共，对外契约）
│   ├── moon.pkg
│   ├── ecl.mbt / version.mbt / mode.mbt / mask.mbt   # 公共枚举
│   ├── module.mbt                #   公共 Module/ModuleType（单字节位打包）
│   ├── qr.mbt                    #   QRCode 结果容器 / 错误 / 读写访问器
│   ├── qr_build.mbt              #   容量选择 + 编排入口（select_capacity/build_fixed/build）
│   ├── qr_builder.mbt            #   公共 QRBuilder 构造器
│   ├── helpers.mbt               #   终端画渲染 + QRCode::to_str/print（输出便捷）
│   ├── shape.mbt                 #   公共 Shape（SVG 形状枚举）
│   ├── svg.mbt                   #   公共 SvgBuilder（SVG 输出）
│   ├── fast_qr_moonbit_test.mbt  #   黑盒测试（@lib）
│   ├── fast_qr_moonbit_wbtest.mbt #  白盒测试
│   └── internal/                 # 实现子包（各带 moon.pkg；不反向依赖 lib）
│       ├── constants/            #   hardcode.mbt 常量表 + capacity.mbt 容量/元数据表
│       ├── bitstream/            #   bitbuffer.mbt 位流缓冲
│       ├── reedsolomon/          #   reedsolomon.mbt GF(256) 除法/交织
│       ├── data_encoding/        #   encode.mbt 三模式编码
│       └── matrix/               #   module / matrix / placement / datamasking / score
└── cmd/main/                     # CLI 可执行包（import ".../lib" @lib）
```

## 3. 文件职责

### 3.1 lib 公共层

| 文件 | 职责 | 参考源（/fast_qr） | roadmap | 状态 |
|------|------|--------------------|:---:|:---:|
| `ecl.mbt` | ECL 枚举 → 序号映射 | `src/ecl.rs` | B1 | 已实现 |
| `version.mbt` | Version 枚举 → 序号映射 | `src/version.rs` | B2 | 已实现 |
| `mode.mbt` | Mode 枚举 → 序号映射 | `src/encode.rs` | B7 | 已实现 |
| `mask.mbt` | Mask 枚举 → 序号映射 | `src/datamasking.rs` | B10 | 已实现 |
| `module.mbt` | 公共 `Module`/`ModuleType`（D1 上移呈现层） | `src/module.rs` | B5 | 已实现 |
| `qr.mbt` | QRCode 容器 / 错误 / 读写访问器（公共 API 总览见 [S11b §12](./S11b-清理落地记录-v3-v5.md)） | `src/qr.rs` | B8 | 已实现 |
| `qr_build.mbt` | 容量选择 + 编排（select_capacity/build_fixed/build） | `src/qr.rs`/`src/placement.rs` | B8/B10 | 已实现 |
| `qr_builder.mbt` | 公共 `QRBuilder` 构造器 | `src/qr.rs:200`/`lib.rs` | B8 | 已实现 |
| `helpers.mbt` | 终端字符画引擎 + `QRCode::to_str`/`print` 便捷方法 | `src/helpers.rs` | B11 | 已实现 |
| `shape.mbt` | 公共 `Shape`（SVG 形状枚举） | `convert/mod.rs` | B11 | 已实现 |
| `svg.mbt` | 公共 `SvgBuilder`（SVG 输出） | `convert/svg.rs` | B11 | 已实现 |

### 3.2 lib/internal 实现层（不依赖 lib）

| 子包 / 文件 | 职责 | 参考源 | roadmap | 依赖方向 | 状态 |
|------|------|--------|:---:|---------|:---:|
| `constants/hardcode.mbt` | 分组/格式信息/生成多项式常量表 | `src/hardcode.rs` | B3 | 叶节点 | 已实现 |
| `constants/capacity.mbt` | 容量/矩阵元数据表 | `src/version.rs` | B2 | 叶节点 | 已实现 |
| `bitstream/bitbuffer.mbt` | 大端序位流缓冲 | `src/compact.rs` | B6 | → constants（KEEP_LAST 自持） | 已实现 |
| `reedsolomon/reedsolomon.mbt` | GF(256) division + structure | `src/polynomials.rs` | B4 | → constants | 已实现 |
| `data_encoding/encode.mbt` | 三模式编码 + 自动回退 | `src/encode.rs` | B7 | → constants/bitstream | 已实现 |
| `matrix/module.mbt` | Module 位打包 | `src/module.rs` | B5 | 本包内 | 已实现 |
| `matrix/matrix.mbt` | 功能图案绘制（Format 先占位） | `src/default.rs` | B9 | 本包内 | 已实现 |
| `matrix/placement.mbt` | 数据放置 + 总装 | `src/placement.rs` | B9-B10 | 本包内 | 已实现 |
| `matrix/datamasking.mbt` | 8 种掩码 | `src/datamasking.rs` | B10 | 本包内 | 已实现 |
| `matrix/score.mbt` | 4 条评分规则 | `src/score.rs` | B10 | 本包内 | 已实现 |

## 4. 依赖图（实现时遵循）

```
lib(公共枚举/QRCode/组装)
  ├──> constants        （叶）
  ├──> bitstream        （叶）
  ├──> reedsolomon      （→ constants）
  ├──> data_encoding    （→ constants, bitstream）
  └──> matrix           （→ constants；包内 module→matrix→placement→datamasking→score）
cmd/main ──import──> lib
```

- 边界参数一律 `Int` 序号/本包类型；公共枚举只在 `lib`。
- `moon.pkg` 的 `import` 在使用方声明且**声明后必须使用**。

## 5. 测试规划

| 层 | 载体 | 覆盖 |
|----|------|------|
| 黑盒 | `lib/fast_qr_moonbit_test.mbt`（`@lib`） | 公共 API：构造/错误面/to_str |
| 白盒 | 各包 `*_wbtest.mbt`（包内） | 私有实现：位操作/掩码/评分/放置 |
| 内联 | 源码内 `test {}` | 贴近实现的断言 |
| 黄金/快照 | 期望值抄 `/fast_qr/src/tests/*.rs`；矩阵快照 JSON | 逐模块定位 + 端到端对齐 |

## 6. 落地状态与执行顺序

- 已落地：`lib/` 公共层（枚举/容器/编排/builder/输出）+ `lib/internal/` 五子包；`cmd/main`/`cmd/bench`/
  `cmd/qr-min` 均 `import ".../lib" @lib` 并真实调用。B1→B11 全部落地，无注释骨架文件。
- 构建命令（模块根无包，须显式给包名）：`moon check --deny-warn`（全模块）、
  `moon test`、`moon build lib/cmd/main --release`、`moon run cmd/main`。
- 执行顺序（历史）：roadmap §4.3「B1→B11」按批落地，每批一个提交；当前收尾沿用 AGENTS §二.4。

## 7. 与 moonbitlang/core 对照

core 实证（`main @ 452eb70`）：模块根无包；feature 包（如 `random/`）= 目录包 +
`internal/random_source`（不 import 父包）+ 包内测试 + `README.mbt.md`。
本仓库 `lib/` = core 的 feature 包目录，`lib/internal/*` = 其 internal —— **形态一致**。

## 8. 参考

- [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) — roadmap、B1-B11 与里程碑
- [项目基础框架-详细分析.md](./项目基础框架-详细分析.md) — 目标包架构、模块映射、移植语义
- [core-仓库布局参考与目标架构.md](./core-仓库布局参考与目标架构.md) — internal/ 目标树依据
- [README.md](../README.md) — 仓库文档索引与代码放置约定（`README.mbt.md` 为其符号链接）

---

## 附录：代码布局检查与整理记录

> 记录对 `fast_qr_moonbit` 代码放置位置的检查过程、结论与本次整理动作。
>
> 日期：2026-09-05　｜　工具链：`moon 0.1.20260827 (d0aaa07)`
>
> 布局演进：本记录基于当时的「模块根即根包」形态；此后仓库已改为**方案 3**
> （模块根不建包，库包在 `lib/`，实现子包在 `lib/internal/`），后续以
> [moonbit-实现布局与文件职责](./moonbit-实现布局与文件职责.md) 为准。

---

### 一、检查方法

不依靠记忆推断约定，而是**以官方生成器为基准做对照**：

```bash
moon new newref --user tryandrun --name ref
```

取官方生成的目录骨架作为参考标准，再逐项比对本仓库。

#### 官方参考布局（`moon new`）

```
moon.mod            # 模块配置
moon.pkg            # 根包描述（空文件）
<模块名>.mbt        # 库主文件
<模块名>_test.mbt   # 黑盒测试
<模块名>_wbtest.mbt # 白盒测试   ← 本仓库原缺失
cmd/main/main.mbt   # CLI 入口
cmd/main/moon.pkg   # pkgtype(kind: "executable")
AGENTS.md           # 项目代理指南
README.md           # README 实体正文（`mbt check` 代码块 = 文档测试）
README.mbt.md       # -> README.md（符号链接；文档测试只扫描此文件名）
LICENSE / .gitignore / .githooks/ / .github/
```

---

### 二、检查结果

#### 2.0 确认：MoonBit 没有 `src/` 约定

> 补充：此结论已由官方文档进一步确认，并整理为独立的
> [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md)。
> 官方教程「理解模块目录结构」给出的标准目录树中不含 `src/`。

其他语言（Rust / TypeScript / Go）普遍把源码放 `src/`，容易误用。三重证据确认 **MoonBit 不使用 `src/`**：

| # | 证据 | 结果 |
|:-:|------|------|
| 1 | `moon new` 官方生成器输出 | 无 `src/`；库主文件在**模块根目录**，CLI 在 `cmd/main/` |
| 2 | 官方标准库 `moonbitlang/core` 实际布局 | 无 `src/`；按**功能**建子目录（`array/` `bytes/` `builtin/` …），每目录一个 `moon.pkg` |
| 3 | 把 `.mbt` + `moon.pkg` 放进 `src/` 后 `moon check` | **通过** —— 说明 `src/` 只是普通目录，工具链并不特殊对待 |

结论：`src/` 技术上可行但**不合官方惯例**，不使用。

> 勘误：本表初版曾把「目录与主文件同名（如 `array/array.mbt`）」当作 core 的规则，
> 这是**错的**。官方示例中 `fib` 包只有 `slow.mbt` / `fast.mbt`，并无 `fib.mbt`；
> 目录内 `.mbt` 的文件名可自由命名，同名只是 core 的风格惯例。
> 详见 [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md) §二.1。

#### 2.1 位置判定

| 文件 / 目录 | 位置 | 判定 | 说明 |
|-------------|------|:---:|------|
| `moon.mod` | 根 | 正确 | 模块元数据 |
| `moon.pkg` | 根（空） | 正确 | 与官方一致；依赖留待按需声明 |
| `fast_qr_moonbit_test.mbt` | 根 | 位置正确 | 但**注释表述错误**（见 2.2） |
| `fast_qr_moonbit_wbtest.mbt` | — | **缺失** | 官方布局含白盒测试文件 |
| `cmd/main/main.mbt` | `cmd/main/` | 正确 | 与官方一致 |
| `cmd/main/moon.pkg` | `cmd/main/` | 位置正确 | 内容缺依赖声明（见 2.3） |
| `docs/` | 根 | 正确 | 本仓库特有，非 MoonBit 约定项 |
| `.cnb.yml` / `.codebuddy/` | 根 | 正确 | 本仓库特有基础设施 |
| `pkg.generated.mbti` | 根 / `cmd/main/` | **应清理** | `moon info` 构建产物 |

**结论：主体布局与官方一致，无需迁移目录。** 需要修正的是命名约定细节、
缺失的白盒测试文件，以及若干构建产物残留。

#### 2.2 测试文件语义错误（已修正）

原 `fast_qr_moonbit_test.mbt` 注释写「**包内**黑盒测试」——表述自相矛盾。

通过实测确认 MoonBit 的测试文件语义：

| 文件 | 运行位置 | 可访问范围 | 引用本包 |
|------|---------|-----------|---------|
| `*_test.mbt` | 包**外**（黑盒） | 仅 `pub` 导出的公共 API | `@<包名>` 别名**自动可用**，无需在 `moon.pkg` 声明 |
| `*_wbtest.mbt` | 包**内**（白盒） | 私有函数、内部实现 | 直接调用，无需导出 |

验证方式（`/tmp/bb` 实验模块）：

```moonbit
// bb.mbt
pub fn add(a : Int, b : Int) -> Int { a + b }
fn priv_helper() -> Int { 42 }

// bb_test.mbt —— 通过，证明包级别名自动可用
test "bb_no_import" { assert_eq(@bb.add(1, 2), 3) }

// bb_wbtest.mbt —— 通过，证明白盒可访问私有函数
test "wb_uses_priv" { assert_eq(priv_helper(), 42) }
```

`moon test` → `Total tests: 2, passed: 2`。

#### 2.3 依赖声明不能提前添加（实证）

考虑在 `cmd/main/moon.pkg` 中提前声明对根包的依赖，实测**失败**：

```text
Warning: [0029] Unused package 'tryandrun/bb'
Warning: [0029] Unused package alias 'lib'
Failed with 2 warnings, 2 errors.
Error: failed when checking project
```

**结论**：`moon.pkg` 中的 `import` 声明后必须使用，否则 `moon check` 失败。
因此骨架阶段（库尚无公共 API）**不能**提前声明依赖，
改为在文件中以注释记录待启用内容。

> 此项修正了 `docs/wasm-编译与运行-结果分析.md` §6.3 原先「必须补 import」的表述。

---

### 三、本次整理动作

#### 3.1 代码

| 动作 | 文件 | 内容 |
|------|------|------|
| 修正注释 | `fast_qr_moonbit_test.mbt` | 「包内黑盒」→ 准确的黑盒（包外）说明，补充包别名用法（当时为 `@fast_qr_moonbit`；方案 3 后改 `lib/` 内、别名 `@lib`） |
| 新增 | `fast_qr_moonbit_wbtest.mbt` | 补齐官方布局中的白盒测试文件 |
| 补充注释 | `cmd/main/moon.pkg` | 记录待启用的 `import` 写法与 `unused_package` 风险 |
| 新增配置 | `moon.mod` | `supported_targets = "+wasm+wasm-gc+js"`（后续已收敛为 `+wasm-gc`；`js`、`wasm`(WASI) 均已移除） |
| 格式化 | 全部 | 执行 `moon fmt`，`moon fmt --check` 通过 |

#### 3.2 配置与文档

| 动作 | 文件 | 内容 |
|------|------|------|
| 清理 | `.gitignore` | 移除与本仓库无关的 `/chathub-server/` 残留项；`*.mbti` 已在上次加入 |
| 重写 | `agents.md` | 从 Cloudflare/wrangler 专属内容适配为 MoonBit 项目约定；去除对不存在文件的引用 |
| 更新 | `README.mbt.md` | 新增「代码放置约定」章节；补全项目结构；修正后端表述（native 不可用） |
| 修正 | `docs/wasm-编译与运行-结果分析.md` | §6.2 / §6.3 补充实证结论；§7.2 待办表加状态列并标记已完成项 |
| 更新 | `docs/moonbit-工具链与构建-setup-分析.md` | 注意事项同步为「agents.md 已适配」 |
| 新增 | `docs/moonbit-实现布局与文件职责.md` | 本文档 |
| 新增 | `README.md` -> `README.mbt.md` 符号链接 | 官方布局含此链接；git 以 `mode 120000` 跟踪 |
| 新增 | `docs/moonbit-项目目录设置-最佳实践.md` | 依据官方文档整理的目录设置最佳实践 |

---

### 四、整理后验证

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt --check   # 通过
moon check         # Finished, 0 warnings 0 errors
moon test          # Total tests: 2, passed: 2, failed: 0
moon run cmd/main --target wasm-gc   # 正常输出（当时另有 wasm/js；现仅 wasm-gc）
```

测试数由 1 增至 2（黑盒 + 白盒）。

---

### 五、后续优化轮（2026-09-05）

依据 [moonbit-项目目录设置-最佳实践.md](./moonbit-项目目录设置-最佳实践.md) 执行的布局优化，详见其 §3.2。摘要：

| 动作 | 说明 |
|------|------|
| `preferred_target` → `wasm-gc` | 基于实测数据（体积 -83%、性能 +33%）切换默认后端 |
| `agents.md` → `AGENTS.md` | 对齐官方命名；曾建 `agents.md` 符号链接保持兼容（后撤销，见下行） |
| `agents.md` 符号链接 → 删除 | 与 README 一起去除符号链接化：仓库不再保留小写名兼容链接 |
| 新增 `.githooks/` | `pre-commit` 做 `moon fmt --check` + `moon check` |
| CI 补两阶段 | `fmt-check`（格式门禁）+ `build-and-run`（三后端 release 回归） |
| `README.mbt.md` + 符号链接 → 单一 `README.md` | （**2026-09-05**）撤销官方「`README.mbt.md` + `README.md` 符号链接」布局，改用单一真实文件；`moon.mod` 的 `readme` 指向 `README.md` |
| 单一 `README.md` → **恢复官方布局**（2026-09-14） | 见下「八、README 文档测试落地」：恢复 `README.mbt.md` + 符号链接，并新增根空 `moon.pkg` 作宿主，使示例受 `moon test` 保护 |
| 符号链接方向 **回正**（2026-09-14 v4） | 见下「八、README 文档测试落地」末段：`README.md` 改回**实体正文**、`README.mbt.md` 改为指向它的符号链接；`moon.pkg` 宿主不变 |

优化后验证：`fmt --check` / `check --deny-warn` / `test` / 三后端 `build+run+test` 全绿。

### 六、遗留待办

| 优先级 | 事项 |
|:---:|------|
| ~~P0~~ | ~~实现 QR 公共 API；届时在 `cmd/main/moon.pkg` 启用 `import { ... /lib @lib }` 并让 CLI 调用~~ → **已完成**（S1–S7 落地，`cmd/main` 已调用库输出） |
| ~~P0~~ | ~~测试从 `assert_true(true)` 升级为真实断言~~ → **已完成**（S10 收口，146 + README 文档测试 1 = 147） |
| P1 | **README 示例纳入文档测试**（2026-09-14 已落地，见 §八）：改公共 API 须同步 README 示例 |
| P2 | `.github/workflows/` 尚缺：官方布局含此项 | **不采纳** —— 本仓库 CI 已在 `.cnb.yml`，无需 GitHub Actions |

---

### 七、参考

- [README.md](../README.md) — 代码放置约定与文档索引（`README.mbt.md` 为其符号链接）
- [wasm-编译与运行-结果分析.md](./wasm-编译与运行-结果分析.md) — 后端选型与产物分析
- [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) — 工具链与构建系统
- [moonbit-工具链与构建-setup-分析.md](./moonbit-工具链与构建-setup-分析.md) — 仓库初始化与 CI 配置
- MoonBit 构建系统：<https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/tutorial.html>

---

### 八、README 文档测试落地（2026-09-14）

**背景**：README 示例历来只能靠「人工复制到临时模块实测」（见
[README优化-冗余清理与最佳实践.md](./README优化-冗余清理与最佳实践.md) §3.1），
改公共 API 后**没有任何门禁能发现 README 过期**。

**做法**（对齐官方 `moon new` 模板与 `moonbitlang/core` 惯例）：

| 动作 | 内容 |
|------|------|
| 恢复 README 文档测试布局 | 正文实体 `README.md` + 符号链接 `README.mbt.md`（**v4 回正**，见下表；v3 曾反向做，落地页劣化） |
| 示例改为文档测试 | README 的「快速开始」示例写进 ```mbt check``` 块（test `readme_quick_start`），由 `moon check`/`moon test` 编译并运行 |
| 新增根空包 `moon.pkg` | **关键前提**：模块根的 `.md` 只有归属到某个包才被扫描；该包不写实现、不导出 API，`warnings = "-29"` 关掉 `unused_package` |

**实测口径**（`moon 0.1.20260904`，本仓库实跑）：

```bash
moon check --deny-warn      # 通过
moon test --target wasm-gc  # 147 通过（146 原有 + 1 README 文档测试）
moon test --outline | grep README
#   1. TryAndRun-TvT/fast_qr_moonbit README.mbt.md:174 index=0 name="readme_quick_start"
```

**负向对照**（证明该门禁真的生效）：把文档测试断言从 `assert_eq(q.size(), 25)` 改成 `99`：

```text
[TryAndRun-TvT/fast_qr_moonbit] test README.mbt.md:174 ("readme_quick_start") failed: ... `25 != 99`
Total tests: 147, passed: 146, failed: 1.
```

**与「模块根无包」的关系**：本仓库曾把「根目录零 `moon.pkg`」当作方案 3 的标志，
但实测表明**根空包不影响任何架构主张**——`boundary` 与依赖方向仍全在 `lib/`；
根包只是一个「文档测试宿主」。故 §1 第 1 条已据此修订为「根不放**库代码**」而非「根无包」。

#### v4 回正：符号链接方向（2026-09-14）

v3 把 `README.md` 做成指向 `README.mbt.md` 的符号链接（模仿 `moon new` 模板），实测**造成了落地页劣化**：

- `git ls-files -s`：`README.md` = `mode 120000`，blob 内容是**字符串** `README.mbt.md`（**13 字节**）；
- **CNB blob / raw 视图**打开 `README.md` 只渲染出那一行 `README.mbt.md`（不是正文）；
- 任何**不解析符号链接**的宿主（zip 解包、Windows 检出、部分平台解析链路）同样只得到存根；
- `moon.mod` 的 `readme = "README.md"` 指向的是存根，而非正文。

**回正做法**：方向反过来——`README.md` 存**实体正文**、`README.mbt.md` 作**符号链接**。

| 事实 | 实测 |
|------|------|
| 文档测试只扫**文件名恰为 `README.mbt.md`** 的 markdown | 普通 `README.md` 的 `mbt check` 块**不被扫描**（`moon test --outline` 只见 "no test entry"） |
| 反向（`README.md` 实体 + `README.mbt.md` 链接）仍能被扫描 | `moon test --target wasm-gc --outline` → `README.mbt.md:176 readme_quick_start` ✅ |
| 平台读取 `README.md` 得到正文 | 实体文件；`moon package` 归档中 `README.md` 与 `README.mbt.md` **均**为 35 KB 正文 |

即：**「正文实体 = `README.md`」+「符号链接 = `README.mbt.md`」同时满足平台渲染与文档测试**，
是本仓库的最终布局（与 `moon new` 模板只差链接方向，取舍理由如上）。
