# MoonBit 实现布局与文件职责（方案 3：lib/ 库包）

> 依据 [项目基础框架-详细分析](./项目基础框架-详细分析.md)、
> [moonbit-重写-roadmap-详细分析](./moonbit-重写-roadmap-详细分析.md) 与
> `moonbitlang/core` 实仓布局（模块根只放元数据、库为 feature 子目录包），
> 并采纳「方案 3」：**取消模块根根包，库代码统一收入 `lib/` 子包**。
> 当前阶段：代码 = 注释骨架（无逻辑），供后续按 roadmap 填充真实实现。
>
> 日期：2026-09-05

---

## 1. 布局决策（方案 3）

1. **模块根不设包**：根目录只放元数据（`moon.mod`/`README.md`/`docs/`/CI 配置等），
   **无根 `moon.pkg`** —— 与 `moonbitlang/core` 同形态（core 模块根无任何包，库都是 feature 子目录）。
2. **库包在 `lib/`**：`lib/moon.pkg` + 公共文件（入口/枚举/容器）+ `lib/internal/` 实现子包；
   消费者通过 `import { "tryandrun/fast_qr_moonbit/lib" @lib }` 使用。
3. **无环依赖（MoonBit 实测禁止 import 环）**：
   - `lib`（未来实现到该步时）import `lib/internal/*`；
   - internal 永不反向 import `lib`；跨边界以**域序号（Int）**或本包类型传参；
   - 公共枚举（ECL/Version/Mode/Mask 等）只出现在 `lib/`（`.mbti` 对外契约）。
4. **测试放所属包目录内**：`lib/*_test.mbt`（黑盒，`@lib` 别名 = 目录名，自动可用）、
   `lib/*_wbtest.mbt`（白盒）、贴近实现的断言用源码内联 `test {}`。
5. **不提前声明 import**：依赖在实现到该步时、声明与使用同一批提交；骨架阶段 `moon.pkg` 留空。
6. **代码注释先行**：真实代码按 roadmap B1→B11 逐个替换注释骨架，每批一个提交。

> 与「单根包」/「模块根 internal」旧方案的差异：库入口 import 路径由
> `.../fast_qr_moonbit` 变为 `.../fast_qr_moonbit/lib`；构建/CI 需显式给包名。

## 2. 布局树

```
moon.mod / README.md / docs/ / AGENTS.md / .cnb.yml   # 模块根：仅元数据（无包）
├── lib/                          # 库包（公共，对外契约）
│   ├── moon.pkg
│   ├── fast_qr_moonbit.mbt       #   库入口 / 公共 API 组装
│   ├── ecl.mbt / version.mbt / mode.mbt / mask.mbt   # 公共枚举
│   ├── qr.mbt                    #   QRCode 容器 / 错误 / 构造入口
│   ├── helpers.mbt               #   终端输出扩展
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
| `fast_qr_moonbit.mbt` | 入口 / 公共 API 组装 | `src/lib.rs` | B8 | 注释骨架 |
| `ecl.mbt` | ECL 枚举 → 序号映射 | `src/ecl.rs` | B1 | 注释骨架 |
| `version.mbt` | Version 枚举 → 序号映射 | `src/version.rs` | B2 | 注释骨架 |
| `mode.mbt` | Mode 枚举 → 序号映射 | `src/encode.rs` | B7 | 注释骨架 |
| `mask.mbt` | Mask 枚举 → 序号映射 | `src/datamasking.rs` | B10 | 注释骨架 |
| `qr.mbt` | QRCode 容器 / 错误 / 构造入口 | `src/qr.rs` | B8 | 注释骨架 |
| `helpers.mbt` | 终端字符画 to_str/print | `src/helpers.rs` | B11 | 注释骨架 |

### 3.2 lib/internal 实现层（不依赖 lib）

| 子包 / 文件 | 职责 | 参考源 | roadmap | 依赖方向 | 状态 |
|------|------|--------|:---:|---------|:---:|
| `constants/hardcode.mbt` | 分组/格式信息/生成多项式常量表 | `src/hardcode.rs` | B3 | 叶节点 | 注释骨架 |
| `constants/capacity.mbt` | 容量/矩阵元数据表 | `src/version.rs` | B2 | 叶节点 | 注释骨架 |
| `bitstream/bitbuffer.mbt` | 大端序位流缓冲 | `src/compact.rs` | B6 | 叶节点 | 注释骨架 |
| `reedsolomon/reedsolomon.mbt` | GF(256) division + structure | `src/polynomials.rs` | B4 | → constants | 注释骨架 |
| `data_encoding/encode.mbt` | 三模式编码 + 自动回退 | `src/encode.rs` | B7 | → constants/bitstream | 注释骨架 |
| `matrix/module.mbt` | Module 位打包 | `src/module.rs` | B5 | 本包内 | 注释骨架 |
| `matrix/matrix.mbt` | 功能图案绘制（Format 先占位） | `src/default.rs` | B9 | 本包内 | 注释骨架 |
| `matrix/placement.mbt` | 数据放置 + 掩码择优 + 总装 | `src/placement.rs` | B9-B10 | 本包内 | 注释骨架 |
| `matrix/datamasking.mbt` | 8 种掩码 | `src/datamasking.rs` | B10 | 本包内 | 注释骨架 |
| `matrix/score.mbt` | 4 条评分规则 | `src/score.rs` | B10 | 本包内 | 注释骨架 |

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

- 已落地：`lib/` 公共注释骨架 + `lib/internal/` 五子包 + `cmd/main` 注释指向 `.../lib`。
- 构建命令（模块根无包，须显式给包名）：`moon check --deny-warn`（全模块）、
  `moon test`、`moon build lib/cmd/main --release`、`moon run cmd/main`。
- 执行顺序：roadmap §4.3「B1→B11」，落点即上表文件；每批一个提交；收尾沿用 AGENTS §二.4。

## 7. 与 moonbitlang/core 对照

core 实证（`main @ 452eb70`）：模块根无包；feature 包（如 `random/`）= 目录包 +
`internal/random_source`（不 import 父包）+ 包内测试 + `README.mbt.md`。
本仓库 `lib/` = core 的 feature 包目录，`lib/internal/*` = 其 internal —— **形态一致**。

## 8. 参考

- [moonbit-重写-roadmap-详细分析.md](./moonbit-重写-roadmap-详细分析.md) — roadmap、B1-B11 与里程碑
- [项目基础框架-详细分析.md](./项目基础框架-详细分析.md) — 目标包架构、模块映射、移植语义
- [core-仓库布局参考与目标架构.md](./core-仓库布局参考与目标架构.md) — internal/ 目标树依据
- [README.md](../README.md) — 仓库文档索引与代码放置约定
